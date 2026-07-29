// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IClaiming.
 * @author Rain Team.
 * @notice Interface for the Claiming contract.
 */
interface IClaiming {
    /* ========================== EVENTS ========================== */

    /**
     * @dev Emitted when a claim request has been set.
     */
    event RequestSet(
        address indexed claimer,
        uint256 index,
        uint256 amount,
        uint256 claimRequestTime
    );

    /**
     * @dev Emitted when a claim request has been claimed.
     */
    event RequestClaimed(address indexed claimer, uint256 index);

    /**
     * @dev Emitted when multiple claim requests have been claimed.
     */
    event MultipleRequestsClaimed(address indexed claimer, uint256[] indexes);

    /**
     * @dev Emitted when the reservoir contract is changed.
     * @param newReservoir Address of the new reservoir contract.
     * @param oldReservoir Address of the old reservoir contract.
     */
    event UpdateReservoir(
        address indexed newReservoir,
        address indexed oldReservoir
    );

    /* ========================== ERRORS ========================== */

    /**
     * @dev Indicates an error when the caller is not authorized.
     */
    error ClaimingUnauthorizedAccount();

    /**
     * @dev Indicates an error related to claimer's claim request when the claim request time has not yet passed.
     */
    error ClaimRequestTimeNotReached();

    /**
     * @dev Indicates an error related to claimer's claim request when the amount of tokens in the request is `0`.
     */
    error InvalidClaimRequest();

    /* ========================== STRUCTS ========================== */

    struct Request {
        uint256 amount;
        /// @dev Time after which the claim request will be complete.
        uint256 claimRequestTime;
    }

    /* ========================== FUNCTIONS ========================== */

    /**
     * @notice Set a request to claim USDT tokens being unstaked from the Staking
     * contract. Only `staking` can call this function.
     * @param claimer Claimer who's USDT tokens are being held.
     * @param amount Amount of USDT tokens being unstaked.
     */
    function setRequest(address claimer, uint256 amount) external;

    /**
     * @notice Claim USDT tokens following the completion of a claim request.
     * @param index Claimer's index to claim request against.
     */
    function claimRequest(uint256 index) external;

    /**
     * @notice Claim USDT tokens following the completion of multiple claim
     * requests.
     * @param indexes List of claimer's indexes to claim requests against.
     */
    function claimMultipleRequests(uint256[] calldata indexes) external;

    /**
     * @notice Updates the reservoir contract.
     * @dev Can only be called by the owner.
     * @param newReservoir Address of the new reservoir contract.
     */
    function updateReservoir(address newReservoir) external;

    /**
     * @notice Address of the asset.
     */
    function ASSET() external view returns (IERC20);

    /**
     * @notice Number of request keys currently assigned.
     */
    function totalRequests() external view returns (uint256);

    /**
     * @notice Address of the reservoir contract.
     */
    function reservoir() external view returns (address);

    /**
     * @dev Claimer's claim request with respect to a unique key.
     */
    function requests(bytes32 key) external view returns (uint256, uint256);

    /**
     * @notice Gives the request pertaining to the given unique request index.
     * @param index Request index to get the key for.
     * @return amount Amount of USDT tokens requested.
     * @return claimRequestTime Time after which requested USDT tokens will be
     * claimable.
     */
    function getRequest(uint256 index) external view returns (uint256, uint256);

    /**
     * @notice Gives a unique key pertaining to the given unique request index.
     * @param index Request index to get the key for.
     * @return key Key that is present for the given request index.
     */
    function getRequestKey(uint256 index) external view returns (bytes32);
}
