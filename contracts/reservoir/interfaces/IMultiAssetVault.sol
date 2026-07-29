// SPDX-License-Identifier: MIT

pragma solidity 0.8.31;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IMultiAssetVault.
 * @author Rain Team.
 * @dev Interface for the multi asset vault abstract contract.
 */
interface IMultiAssetVault {
    /* ========================== EVENTS ========================== */

    event Deposit(address indexed sender, IERC20 asset, address receiver, uint256 assets, uint256 shares);
    event Withdraw(address indexed sender, IERC20 asset, address receiver, uint256 assets, uint256 shares);
    event UpdateAsset(address asset, bool state);

    /* ========================== ERRORS ========================== */

    error AssetNotRegistered();
    error ExceededMaxDeposit();
    error ExceededMaxMint();
    error ExceededMaxWithdraw();
    error ExceededMaxRedeem();

    /* ========================== FUNCTIONS ========================== */

    function isAsset(IERC20 asset) external view returns (bool);
    function decimals(IERC20 asset) external view returns (uint8);
    function totalSupply(IERC20 asset) external view returns (uint256);
    function balanceOf(IERC20 asset, address owner) external view returns (uint256);

    function deposit(IERC20 asset, uint256 assets, address receiver) external returns (uint256);
    function mint(IERC20 asset, uint256 shares, address receiver) external returns (uint256);
    function withdraw(IERC20 asset, uint256 assets, address receiver) external returns (uint256);
    function redeem(IERC20 asset, uint256 shares, address receiver) external returns (uint256);

    function totalAssets(IERC20 asset) external view returns (uint256);
    function convertToShares(IERC20 asset, uint256 assets) external view returns (uint256);
    function convertToAssets(IERC20 asset, uint256 shares) external view returns (uint256);

    function maxDeposit(address) external view returns (uint256);
    function maxMint(address) external view returns (uint256);
    function maxWithdraw(IERC20 asset, address owner) external view returns (uint256);
    function maxRedeem(IERC20 asset, address owner) external view returns (uint256);

    function previewDeposit(IERC20 asset, uint256 assets) external view returns (uint256);
    function previewMint(IERC20 asset, uint256 shares) external view returns (uint256);
    function previewWithdraw(IERC20 asset, uint256 assets) external view returns (uint256);
    function previewRedeem(IERC20 asset, uint256 shares) external view returns (uint256);
}
