// SPDX-License-Identifier: MIT
pragma solidity 0.8.31;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

import {IClaiming} from "./Claiming/interfaces/IClaiming.sol";

/// @notice Game pool interface — ERC4626-style vault with slippage guards.
interface IGamePool {
    /// @dev Deposits `assets` of `asset` token into the pool and mints shares to `receiver`.
    ///      Reverts if shares minted < `minSharesOut`.
    function depositWithSlippage(
        IERC20 asset,
        uint256 assets,
        address receiver,
        uint256 minSharesOut
    ) external returns (uint256 shares);

    /// @dev Withdraws `assets` of `asset` token from the pool to `receiver`.
    ///      Reverts if shares burned > `maxSharesIn`.
    function withdrawWithSlippage(
        IERC20 asset,
        uint256 assets,
        address receiver,
        uint256 maxSharesIn
    ) external returns (uint256 shares);

    function maxWithdraw(
        IERC20 asset,
        address owner
    ) external view returns (uint256);
}

/// @notice Linear monthly vesting — owner claims tokens directly.
///
/// Deploy order:
///   1. Deploy TeamVesting.
///   2. token.approve(vestingAddress, totalAllocation).
///   3. Call depositToPool() — pulls tokens from caller and deposits into Reservoir.
///
/// Post-cliff lifecycle:
///   1. withdraw()                 — after cliff elapses, initiates Reservoir → Claiming redemption.
///   2. (wait Claiming cooldown)
///   3. claimFromClaiming(index)   — pulls tokens from Claiming into this contract.
///   4. claim()                    — callable monthly; sends each tranche to owner.
contract TeamVesting is Ownable2Step {
    using SafeERC20 for IERC20;

    // ── Errors ───────────────────────────────────────────────────────────────
    error ZeroAddress();
    error ZeroAmount();
    error VestingNotStarted();
    error NothingToClaim();
    error TokensNotReady();
    error AlreadyDeposited();

    // ── Events ───────────────────────────────────────────────────────────────
    event Claimed(
        address indexed recipient,
        uint256 amount,
        uint256 monthsPaid
    );
    event Deposited(address indexed pool, uint256 amount);
    event Withdrawn(address indexed pool, uint256 amount);
    event ClaimedFromClaiming(uint256 amount);

    // ── Constants ────────────────────────────────────────────────────────────
    uint256 public constant VESTING_MONTHS = 24;

    // ── Immutables ───────────────────────────────────────────────────────────
    uint256 public immutable MONTH_DURATION;
    uint256 public immutable vestingStart;
    uint256 public totalAllocation;
    uint256 public monthlyAmount;

    // ── State ────────────────────────────────────────────────────────────────
    IERC20 public immutable token;
    IGamePool public immutable pool;
    IClaiming public immutable claiming;
    uint256 public monthsClaimed; // slices paid out [0, VESTING_MONTHS]
    bool public tokensReady; // true after claimFromClaiming() succeeds
    bool public depositedToPool; // true after depositToPool() is called once

    // ─────────────────────────────────────────────────────────────────────────
    // Construction
    // ─────────────────────────────────────────────────────────────────────────

    constructor(
        address _owner,
        address _token,
        address _pool,
        address _claiming,
        uint256 _cliffDuration,
        uint256 _monthDuration,
        uint256 _totalAllocation
    ) Ownable(_owner) {
        if (_token == address(0)) revert ZeroAddress();
        if (_pool == address(0)) revert ZeroAddress();
        if (_claiming == address(0)) revert ZeroAddress();
        if (_totalAllocation == 0) revert ZeroAmount();

        token = IERC20(_token);
        pool = IGamePool(_pool);
        claiming = IClaiming(_claiming);
        MONTH_DURATION = _monthDuration;
        vestingStart = block.timestamp + _cliffDuration;
        totalAllocation = _totalAllocation;
        monthlyAmount = _totalAllocation / VESTING_MONTHS;
    }

    /// @notice Pull the allocation from the caller and deposit it into the pool.
    ///         Must be called once after deployment. Caller must have approved
    ///         this contract for totalAllocation tokens beforehand.
    ///         Owner only. One-time — reverts if called again.
    function depositToPool() external onlyOwner {
        if (depositedToPool) revert AlreadyDeposited();
        depositedToPool = true;
        token.safeTransferFrom(msg.sender, address(this), totalAllocation);
        token.forceApprove(address(pool), totalAllocation);
        pool.depositWithSlippage(token, totalAllocation, address(this), 0);
        emit Deposited(address(pool), totalAllocation);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Owner actions
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Claim all unlocked tokens to the owner wallet.
    ///         Missed months accumulate — one call catches everything up.
    ///         The final claim drains the full contract balance.
    function claim() external onlyOwner {
        if (!tokensReady) revert TokensNotReady();
        if (block.timestamp < vestingStart) revert VestingNotStarted();

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
        token.safeTransfer(owner(), amount);
        emit Claimed(owner(), amount, unpaid);
    }

    /// @notice Withdraw `amount` tokens from the pool back into this contract.
    ///         Owner only. Only callable AFTER the cliff has elapsed so tokens
    ///         are available for monthly claims.
    ///         maxSharesIn = type(uint256).max: no upper bound on shares burned.
    function withdraw() external onlyOwner {
        if (block.timestamp < vestingStart) revert VestingNotStarted();
        totalAllocation = pool.maxWithdraw(token, address(this));

        pool.withdrawWithSlippage(
            token,
            totalAllocation,
            address(this),
            type(uint256).max
        );

        emit Withdrawn(address(pool), totalAllocation);
    }

    /// @notice After the Claiming cooldown elapses, pull tokens back into this
    ///         contract so they are available for monthly claim().
    ///         Owner only. Tokens land here because TeamVesting is the registered
    ///         claimer in the Claiming contract.
    function claimFromClaiming(uint256 index) external onlyOwner {
        claiming.claimRequest(index);
        uint256 received = token.balanceOf(address(this));
        totalAllocation = received;
        monthlyAmount = received / VESTING_MONTHS;
        tokensReady = true;
        emit ClaimedFromClaiming(received);
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
        uint256 months = elapsed / MONTH_DURATION;
        return months > VESTING_MONTHS ? VESTING_MONTHS : months;
    }
}
