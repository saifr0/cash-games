// SPDX-License-Identifier: MIT

pragma solidity 0.8.31;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IMultiAssetVault } from "./IMultiAssetVault.sol";

interface IReservoir is IMultiAssetVault {
    /* ========================== TYPES ========================== */

    enum AbsorptionCause {
        FEE,
        RETURN
    }

    /* ========================== EVENTS ========================== */

    event Absorb(IERC20 asset, uint256 assets, AbsorptionCause cause);
    event Disburse(IERC20 asset, uint256 assets, address indexed winner);
    event UpdateClaim(address newClaimingAddress, address oldClaiming);

    /* ========================== ERRORS ========================== */

    error InsufficientTotalAssets();
    error Slippage();

    /* ========================== FUNCTIONS ========================== */

    function depositWithSlippage(
        IERC20 asset,
        uint256 assets,
        address receiver,
        uint256 minSharesOut
    ) external returns (uint256 shares);

    function mintWithSlippage(
        IERC20 asset,
        uint256 shares,
        address receiver,
        uint256 maxAssetsIn
    ) external returns (uint256 assets);

    function withdrawWithSlippage(
        IERC20 asset,
        uint256 assets,
        address receiver,
        uint256 maxSharesIn
    ) external returns (uint256 shares);

    function redeemWithSlippage(
        IERC20 asset,
        uint256 shares,
        address receiver,
        uint256 minAssetsOut
    ) external returns (uint256 assets);

    function absorb(IERC20 asset, uint256 assets, AbsorptionCause cause) external;
    function disburse(IERC20 asset, uint256 assets, address winner) external;
    function claiming() external view returns (address);
}
