// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IClaiming.
 * @author Rain Team.
 * @notice Interface for the Claiming contract.
 */
interface IClaiming {
    /* ========================== EVENTS ========================== */

    event RequestSet(address indexed claimer, uint256 index, uint256 amount, uint256 claimRequestTime);
    event RequestClaimed(address indexed claimer, uint256 index);
    event MultipleRequestsClaimed(address indexed claimer, uint256[] indexes);
    event UpdateReservoir(address indexed newReservoir, address indexed oldReservoir);

    /* ========================== ERRORS ========================== */

    error ClaimingUnauthorizedAccount();
    error ClaimRequestTimeNotReached();
    error InvalidClaimRequest();

    /* ========================== STRUCTS ========================== */

    struct Request {
        uint256 amount;
        /// @dev Time after which the claim request will be complete.
        uint256 claimRequestTime;
    }

    /* ========================== FUNCTIONS ========================== */

    /**
     * @notice Set a request to claim tokens being withdrawn from the Reservoir.
     *         Only the Reservoir can call this function.
     * @param claimer  Address whose tokens are being held.
     * @param amount   Amount of tokens being held.
     */
    function setRequest(address claimer, uint256 amount) external;

    /**
     * @notice Claim tokens following the completion of a claim request.
     * @param index  Claimer's index to claim request against.
     */
    function claimRequest(uint256 index) external;

    /**
     * @notice Claim tokens for multiple request indexes.
     * @param indexes  List of claimer's indexes to claim requests against.
     */
    function claimMultipleRequests(uint256[] calldata indexes) external;

    /**
     * @notice Updates the reservoir contract address.
     * @param newReservoir  Address of the new reservoir contract.
     */
    function updateReservoir(address newReservoir) external;

    /// @notice Address of the asset this claiming contract manages.
    function ASSET() external view returns (IERC20);

    /// @notice Total number of request keys currently assigned.
    function totalRequests() external view returns (uint256);

    /// @notice Address of the reservoir contract.
    function reservoir() external view returns (address);

    /// @dev Returns a claimer's request by its unique key.
    function requests(bytes32 key) external view returns (uint256, uint256);

    /**
     * @notice Returns the request at the given index for msg.sender.
     * @param index  Request index.
     * @return amount            Amount of tokens requested.
     * @return claimRequestTime  Time after which tokens become claimable.
     */
    function getRequest(uint256 index) external view returns (uint256, uint256);

    /**
     * @notice Returns the unique key for the given request index of msg.sender.
     * @param index  Request index.
     * @return key  Unique key for that request.
     */
    function getRequestKey(uint256 index) external view returns (bytes32);
}
