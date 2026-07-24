// SPDX-License-Identifier: MIT
pragma solidity 0.8.31;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @notice Game pool interface — implemented by the external pool contract.
interface IGamePool {
    /// @dev Pulls `amount` tokens from msg.sender into the pool.
    function deposit(uint256 amount) external;
    /// @dev Pushes `amount` tokens from the pool back to msg.sender.
    function withdraw(uint256 amount) external;
}

/// @notice Linear monthly vesting for a single beneficiary.
///
/// Deploy order:
///   1. Deploy TeamVesting  (token unknown yet)
///   2. Deploy CashGames    (pass vesting address → tokens minted directly here)
///   3. Call setToken()     (wire the token address in; one-time, owner only)
///   4. Call setPool()      (wire the game pool address; owner only, updatable)
///   5. Cliff elapses → beneficiary calls claim(), deposit(), or withdraw()
///
/// Pool flow:
///   deposit()        — sends vested tokens to pool instead of to beneficiary wallet
///   withdraw(amount) — pulls tokens back from pool into this contract
///   collectReturned()— sweeps any tokens sitting in this contract (returned from pool)
///                      to the beneficiary wallet
contract TeamVesting is Ownable2Step {
    using SafeERC20 for IERC20;

    // ── Errors ───────────────────────────────────────────────────────────────
    error ZeroAddress();
    error ZeroAmount();
    error TokenAlreadySet();
    error TokenNotSet();
    error PoolNotSet();
    error Unauthorized();
    error VestingNotStarted();
    error NothingToClaim();

    // ── Events ───────────────────────────────────────────────────────────────
    event TokenSet(address indexed token);
    event PoolSet(address indexed pool);
    event Claimed(address indexed beneficiary, uint256 amount, uint256 monthsPaid);
    event Deposited(address indexed pool, uint256 amount, uint256 monthsPaid);
    event Withdrawn(address indexed pool, uint256 amount);
    event ReturnedCollected(address indexed beneficiary, uint256 amount);
    event BeneficiaryUpdated(address indexed oldBeneficiary, address indexed newBeneficiary);

    // ── Constants ────────────────────────────────────────────────────────────
    uint256 public constant VESTING_MONTHS = 24;

    // ── Immutables ───────────────────────────────────────────────────────────
    uint256 public immutable CLIFF_DURATION;
    uint256 public immutable MONTH_DURATION;
    uint256 public immutable vestingStart;
    uint256 public immutable totalAllocation;
    uint256 public immutable monthlyAmount;

    // ── State ────────────────────────────────────────────────────────────────
    IERC20    public token;         // set once via setToken()
    IGamePool public pool;          // set via setPool() (updatable by owner)
    address   public beneficiary;
    uint256   public monthsClaimed; // slices paid out or deposited [0, VESTING_MONTHS]

    // ─────────────────────────────────────────────────────────────────────────
    // Construction
    // ─────────────────────────────────────────────────────────────────────────

    constructor(
        address _beneficiary,
        address _owner,
        uint256 _cliffDuration,
        uint256 _monthDuration,
        uint256 _totalAllocation
    ) Ownable(_owner) {
        if (_beneficiary     == address(0)) revert ZeroAddress();
        if (_totalAllocation == 0)          revert ZeroAmount();

        beneficiary     = _beneficiary;
        CLIFF_DURATION  = _cliffDuration;
        MONTH_DURATION  = _monthDuration;
        vestingStart    = block.timestamp + _cliffDuration;
        totalAllocation = _totalAllocation;
        monthlyAmount   = _totalAllocation / VESTING_MONTHS;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Owner actions
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Wire in the CashGames token address. One-time, owner only.
    function setToken(address _token) external onlyOwner {
        if (address(token) != address(0)) revert TokenAlreadySet();
        if (_token          == address(0)) revert ZeroAddress();
        token = IERC20(_token);
        emit TokenSet(_token);
    }

    /// @notice Set (or update) the game pool contract address. Owner only.
    function setPool(address _pool) external onlyOwner {
        if (_pool == address(0)) revert ZeroAddress();
        pool = IGamePool(_pool);
        emit PoolSet(_pool);
    }

    /// @notice Replace the beneficiary wallet. Owner only.
    function setBeneficiary(address _beneficiary) external onlyOwner {
        if (_beneficiary == address(0)) revert ZeroAddress();
        emit BeneficiaryUpdated(beneficiary, _beneficiary);
        beneficiary = _beneficiary;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Beneficiary actions
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Claim all unlocked tokens directly to the beneficiary wallet.
    ///         Missed months accumulate — one call catches everything up.
    ///         The final claim drains the full contract balance.
    function claim() external {
        if (address(token)   == address(0)) revert TokenNotSet();
        if (block.timestamp  <  vestingStart) revert VestingNotStarted();
        if (msg.sender       != beneficiary)  revert Unauthorized();

        uint256 vested = _vestedMonths();
        uint256 unpaid = vested - monthsClaimed;
        if (unpaid == 0) revert NothingToClaim();

        uint256 amount;
        if (monthsClaimed + unpaid >= VESTING_MONTHS) {
            amount = token.balanceOf(address(this));
        } else {
            amount = unpaid * monthlyAmount;
        }

        monthsClaimed += unpaid;
        token.safeTransfer(beneficiary, amount);
        emit Claimed(beneficiary, amount, unpaid);
    }

    /// @notice Deposit unlocked tokens into the game pool instead of claiming to wallet.
    ///         Behaves identically to claim() but routes tokens to the pool contract.
    ///         monthsClaimed advances so the same months cannot be claimed twice.
    function deposit() external {
        if (address(token)   == address(0)) revert TokenNotSet();
        if (address(pool)    == address(0)) revert PoolNotSet();
        if (block.timestamp  <  vestingStart) revert VestingNotStarted();
        if (msg.sender       != beneficiary)  revert Unauthorized();

        uint256 vested = _vestedMonths();
        uint256 unpaid = vested - monthsClaimed;
        if (unpaid == 0) revert NothingToClaim();

        uint256 amount;
        if (monthsClaimed + unpaid >= VESTING_MONTHS) {
            amount = token.balanceOf(address(this));
        } else {
            amount = unpaid * monthlyAmount;
        }

        monthsClaimed += unpaid;
        token.forceApprove(address(pool), amount);
        pool.deposit(amount);
        emit Deposited(address(pool), amount, unpaid);
    }

    /// @notice Withdraw `amount` tokens from the pool back into this contract.
    ///         After withdrawal the tokens sit here; call collectReturned() to
    ///         move them to the beneficiary wallet.
    function withdraw(uint256 amount) external {
        if (address(pool) == address(0)) revert PoolNotSet();
        if (msg.sender    != beneficiary)  revert Unauthorized();
        if (amount        == 0)            revert ZeroAmount();

        pool.withdraw(amount);
        emit Withdrawn(address(pool), amount);
    }

    /// @notice Sweep tokens that have been returned from the pool (sitting in
    ///         this contract) directly to the beneficiary wallet.
    function collectReturned() external {
        if (address(token) == address(0)) revert TokenNotSet();
        if (msg.sender     != beneficiary)  revert Unauthorized();

        uint256 balance = token.balanceOf(address(this));
        if (balance == 0) revert NothingToClaim();

        token.safeTransfer(beneficiary, balance);
        emit ReturnedCollected(beneficiary, balance);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Views
    // ─────────────────────────────────────────────────────────────────────────

    function vestedMonths() external view returns (uint256) {
        return _vestedMonths();
    }

    function claimable() external view returns (uint256) {
        uint256 vested = _vestedMonths();
        uint256 unpaid = vested - monthsClaimed;
        if (unpaid == 0) return 0;

        if (monthsClaimed + unpaid >= VESTING_MONTHS) {
            return totalAllocation - (monthsClaimed * monthlyAmount);
        }
        return unpaid * monthlyAmount;
    }

    function locked() external view returns (uint256) {
        if (monthsClaimed >= VESTING_MONTHS) return 0;
        return totalAllocation - (monthsClaimed * monthlyAmount);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internal
    // ─────────────────────────────────────────────────────────────────────────

    function _vestedMonths() internal view returns (uint256) {
        if (block.timestamp < vestingStart) return 0;
        uint256 elapsed = block.timestamp - vestingStart;
        uint256 months  = elapsed / MONTH_DURATION;
        return months > VESTING_MONTHS ? VESTING_MONTHS : months;
    }
}
