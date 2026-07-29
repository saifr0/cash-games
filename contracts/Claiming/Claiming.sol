// SPDX-License-Identifier: MIT

pragma solidity 0.8.31;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IClaiming} from "./interfaces/IClaiming.sol";
import {InvalidAddress, InvalidAmount, InvalidAssignment, InvalidArrayLength} from "./shared/Errors.sol";
import {_revert} from "./shared/Globals.sol";

/**
 * @title Claiming.
 * @author Rain Team.
 * @notice Allows USDC tokens to be claimed after an unstake request has been requested.
 */
contract Claiming is IClaiming, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    /* ========================== STATE VARIABLES ========================== */

    /// @inheritdoc IClaiming
    IERC20 public ASSET;

    /// @dev Seven days time in seconds.
    uint256 private constant _SEVEN_DAYS_TIME = 1 minutes; // TODO: change to 7 days for production

    /// @inheritdoc IClaiming
    uint256 public totalRequests;

    /// @inheritdoc IClaiming
    address public reservoir;

    /// @inheritdoc IClaiming
    mapping(bytes32 key => Request request) public requests;

    /// @dev Unique key with respect to a unique request index.
    EnumerableSet.Bytes32Set private _requestKeys;

    /* ========================== CONSTRUCTOR ========================== */

    /**
     * @dev Initializes an immutable state variable variable.
     * @param initialOwner_ Address to which ownership will be initially granted.
     * @param asset_ Address of the asset.
     */
    constructor(address initialOwner_, IERC20 asset_) Ownable(initialOwner_) {
        if (address(asset_) == address(0)) {
            _revert(InvalidAddress.selector);
        }

        ASSET = asset_;
    }

    /* ========================== FUNCTIONS ========================== */

    /**
     * @inheritdoc IClaiming
     */
    function setRequest(address claimer, uint256 amount) external nonReentrant {
        if (msg.sender != reservoir) {
            _revert(ClaimingUnauthorizedAccount.selector);
        }

        if (claimer == address(0)) {
            _revert(InvalidAddress.selector);
        }

        if (amount == 0) {
            _revert(InvalidAmount.selector);
        }

        uint256 index = totalRequests++;
        bytes32 key = _generateKey(claimer, index);
        _requestKeys.add(key);
        uint256 claimRequestTime = block.timestamp + _SEVEN_DAYS_TIME;
        requests[key] = Request({
            amount: amount,
            claimRequestTime: claimRequestTime
        });

        emit RequestSet({
            claimer: claimer,
            index: index,
            amount: amount,
            claimRequestTime: claimRequestTime
        });
    }

    /**
     * @inheritdoc IClaiming
     */
    function claimRequest(uint256 index) external nonReentrant {
        ASSET.safeTransfer(msg.sender, _claimRequest(index));

        emit RequestClaimed({claimer: msg.sender, index: index});
    }

    /**
     * @inheritdoc IClaiming
     */
    function claimMultipleRequests(
        uint256[] calldata indexes
    ) external nonReentrant {
        uint256 indexesLength = indexes.length;

        if (indexesLength == 0) {
            _revert(InvalidArrayLength.selector);
        }

        uint256 totalRequestAmount;

        for (uint256 i; i < indexesLength; ++i) {
            totalRequestAmount += _claimRequest(indexes[i]);
        }

        ASSET.safeTransfer(msg.sender, totalRequestAmount);

        emit MultipleRequestsClaimed({claimer: msg.sender, indexes: indexes});
    }

    /**
     * @inheritdoc IClaiming
     */
    function updateReservoir(address newReservoir) external onlyOwner {
        if (address(newReservoir) == address(0)) {
            _revert(InvalidAddress.selector);
        }

        if (address(newReservoir) == reservoir) {
            _revert(InvalidAssignment.selector);
        }

        reservoir = newReservoir;
    }

    /**
     * @inheritdoc IClaiming
     */
    function getRequest(
        uint256 index
    ) external view returns (uint256, uint256) {
        Request memory request = requests[_requestKeys.at(index)];
        return (request.amount, request.claimRequestTime);
    }

    /**
     * @inheritdoc IClaiming
     */
    function getRequestKey(uint256 index) external view returns (bytes32) {
        return _requestKeys.at(index);
    }

    /**
     * @dev Implements logic for a completed claim request. DOES NOT transfer
     * claimable USDC tokens.
     * @return requestAmount Amount of USDC tokens in the claim request that
     * need to be processed.
     */
    function _claimRequest(uint256 index) private returns (uint256) {
        bytes32 key = _generateKey(msg.sender, index);
        Request memory request = requests[key];

        if (request.amount == 0) {
            _revert(InvalidClaimRequest.selector);
        }

        if (block.timestamp < request.claimRequestTime) {
            _revert(ClaimRequestTimeNotReached.selector);
        }

        _requestKeys.remove(key);
        delete requests[key];

        return request.amount;
    }

    /**
     * @notice Creates a unique key pertaining to the caller and the given
     * unique request index.
     * @param claimer Claimer who's tokens are being held.
     * @param index Request index to get the key for.
     * @return key Key that is present for the given request index.
     */
    function _generateKey(
        address claimer,
        uint256 index
    ) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(claimer, index));
    }

    function rescueAssets(uint256 amount) external onlyOwner {
        ASSET.safeTransfer(msg.sender, amount);
    }

    function updateAssets(IERC20 newAsset) external onlyOwner {
        ASSET = newAsset;
    }
}
