// SPDX-License-Identifier: MIT

pragma solidity 0.8.31;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ContextUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";

import { IMultiAssetVault } from "../interfaces/IMultiAssetVault.sol";
import { InvalidAddress, InvalidArrayLength, InvalidAssignment } from "../shared/Errors.sol";
import { _revert } from "../shared/Globals.sol";

/**
 * @title MultiAssetVaultUpgradeable.
 * @author Rain Team.
 * @dev Multi asset vault based on ERC-4626. Supports multiple assets without tokenizing shares.
 */
abstract contract MultiAssetVaultUpgradeable is IMultiAssetVault, Initializable, ContextUpgradeable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /* ========================== ERC7201 STORAGE ========================== */

    /// @custom:storage-location erc7201:raincasino.storage.MultiAssetVault
    struct MultiAssetVaultStorage {
        mapping(IERC20 asset => bool isAsset) _isAsset;
        mapping(IERC20 asset => uint8 underlyingDecimals) _underlyingDecimals;
        mapping(IERC20 asset => uint256 totalSupply) _totalSupply;
        mapping(IERC20 asset => mapping(address owner => uint256 balance)) _balances;
    }

    // keccak256(abi.encode(uint256(keccak256("raincasino.storage.MultiAssetVault")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant MultiAssetVaultStorageLocation =
        0x39c309a110dd22495d81d1b2ab0e1847f4145957f48825546ead22a758749000;

    function _getMultiAssetVaultStorage() private pure returns (MultiAssetVaultStorage storage $) {
        assembly {
            $.slot := MultiAssetVaultStorageLocation
        }
    }

    function isAsset(IERC20 asset) public view virtual returns (bool) {
        MultiAssetVaultStorage storage $ = _getMultiAssetVaultStorage();
        return $._isAsset[asset];
    }

    function decimals(IERC20 asset) public view virtual returns (uint8) {
        MultiAssetVaultStorage storage $ = _getMultiAssetVaultStorage();
        return $._underlyingDecimals[asset] + _decimalsOffset();
    }

    function totalSupply(IERC20 asset) public view virtual returns (uint256) {
        MultiAssetVaultStorage storage $ = _getMultiAssetVaultStorage();
        return $._totalSupply[asset];
    }

    function balanceOf(IERC20 asset, address owner) public view virtual returns (uint256) {
        MultiAssetVaultStorage storage $ = _getMultiAssetVaultStorage();
        return $._balances[asset][owner];
    }

    /* ========================== MODIFIERS ========================== */

    modifier validateAsset(IERC20 asset) {
        _validateAsset(asset);
        _;
    }

    /* ========================== INIT ========================== */

    function __MultiAssetVault_init(IERC20[] calldata assetsList_) internal onlyInitializing {
        __MultiAssetVault_init_unchained(assetsList_);
    }

    function __MultiAssetVault_init_unchained(IERC20[] calldata assetsList_) internal onlyInitializing {
        uint256 len = assetsList_.length;
        if (len == 0) _revert(InvalidArrayLength.selector);
        for (uint256 i; i < len; ++i) {
            _updateAsset(assetsList_[i], true);
        }
    }

    /* ========================== FUNCTIONS ========================== */

    function deposit(IERC20 asset, uint256 assets, address receiver) public virtual returns (uint256) {
        if (assets > maxDeposit(receiver)) _revert(ExceededMaxDeposit.selector);
        uint256 shares = previewDeposit(asset, assets);
        _deposit(asset, receiver, assets, shares);
        return shares;
    }

    function mint(IERC20 asset, uint256 shares, address receiver) public virtual returns (uint256) {
        if (shares > maxMint(receiver)) _revert(ExceededMaxMint.selector);
        uint256 assets = previewMint(asset, shares);
        _deposit(asset, receiver, assets, shares);
        return assets;
    }

    function withdraw(IERC20 asset, uint256 assets, address receiver) public virtual returns (uint256) {
        if (assets > maxWithdraw(asset, _msgSender())) _revert(ExceededMaxWithdraw.selector);
        uint256 shares = previewWithdraw(asset, assets);
        _withdraw(asset, receiver, assets, shares);
        return shares;
    }

    function redeem(IERC20 asset, uint256 shares, address receiver) public virtual returns (uint256) {
        if (shares > maxRedeem(asset, _msgSender())) _revert(ExceededMaxRedeem.selector);
        uint256 assets = previewRedeem(asset, shares);
        _withdraw(asset, receiver, assets, shares);
        return assets;
    }

    function totalAssets(IERC20 asset) public view virtual returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function convertToShares(IERC20 asset, uint256 assets) public view virtual returns (uint256) {
        return _convertToShares(asset, assets, Math.Rounding.Floor);
    }

    function convertToAssets(IERC20 asset, uint256 shares) public view virtual returns (uint256) {
        return _convertToAssets(asset, shares, Math.Rounding.Floor);
    }

    function maxDeposit(address) public view virtual returns (uint256) { return type(uint256).max; }
    function maxMint(address) public view virtual returns (uint256) { return type(uint256).max; }

    function maxWithdraw(IERC20 asset, address owner) public view virtual returns (uint256) {
        return _convertToAssets(asset, balanceOf(asset, owner), Math.Rounding.Floor);
    }

    function maxRedeem(IERC20 asset, address owner) public view virtual returns (uint256) {
        return balanceOf(asset, owner);
    }

    function previewDeposit(IERC20 asset, uint256 assets) public view virtual returns (uint256) {
        return _convertToShares(asset, assets, Math.Rounding.Floor);
    }

    function previewMint(IERC20 asset, uint256 shares) public view virtual returns (uint256) {
        return _convertToAssets(asset, shares, Math.Rounding.Ceil);
    }

    function previewWithdraw(IERC20 asset, uint256 assets) public view virtual returns (uint256) {
        return _convertToShares(asset, assets, Math.Rounding.Ceil);
    }

    function previewRedeem(IERC20 asset, uint256 shares) public view virtual returns (uint256) {
        return _convertToAssets(asset, shares, Math.Rounding.Floor);
    }

    function _updateAsset(IERC20 asset, bool state) internal virtual {
        MultiAssetVaultStorage storage $ = _getMultiAssetVaultStorage();
        if (address(asset) == address(0)) _revert(InvalidAddress.selector);
        if (isAsset(asset) == state) _revert(InvalidAssignment.selector);
        (bool success, uint8 assetDecimals) = _tryGetAssetDecimals(asset);
        $._isAsset[asset] = state;
        $._underlyingDecimals[asset] = success ? assetDecimals : 18;
        emit UpdateAsset({ asset: address(asset), state: state });
    }

    function _deposit(IERC20 asset, address receiver, uint256 assets, uint256 shares) internal virtual {
        MultiAssetVaultStorage storage $ = _getMultiAssetVaultStorage();
        asset.safeTransferFrom(_msgSender(), address(this), assets);
        $._totalSupply[asset] += shares;
        $._balances[asset][receiver] += shares;
        emit Deposit(_msgSender(), asset, receiver, assets, shares);
    }

    function _withdraw(IERC20 asset, address receiver, uint256 assets, uint256 shares) internal virtual {
        MultiAssetVaultStorage storage $ = _getMultiAssetVaultStorage();
        $._totalSupply[asset] -= shares;
        $._balances[asset][_msgSender()] -= shares;
        asset.safeTransfer(receiver, assets);
        emit Withdraw(_msgSender(), asset, receiver, assets, shares);
    }

    function _convertToShares(
        IERC20 asset,
        uint256 assets,
        Math.Rounding rounding
    ) internal view virtual validateAsset(asset) returns (uint256) {
        return assets.mulDiv(totalSupply(asset) + 10 ** _decimalsOffset(), totalAssets(asset) + 1, rounding);
    }

    function _convertToAssets(
        IERC20 asset,
        uint256 shares,
        Math.Rounding rounding
    ) internal view virtual validateAsset(asset) returns (uint256) {
        return shares.mulDiv(totalAssets(asset) + 1, totalSupply(asset) + 10 ** _decimalsOffset(), rounding);
    }

    function _decimalsOffset() internal view virtual returns (uint8) { return 0; }

    function _tryGetAssetDecimals(IERC20 asset) private view returns (bool, uint8) {
        (bool success, bytes memory encodedDecimals) = address(asset).staticcall(
            abi.encodeCall(IERC20Metadata.decimals, ())
        );
        if (success && encodedDecimals.length >= 32) {
            uint256 returnedDecimals = abi.decode(encodedDecimals, (uint256));
            if (returnedDecimals <= type(uint8).max) {
                return (true, uint8(returnedDecimals));
            }
        }
        return (false, 0);
    }

    function _validateAsset(IERC20 asset) private view {
        if (!isAsset(asset)) _revert(AssetNotRegistered.selector);
    }

    function _seedShares(IERC20 asset, address receiver, uint256 shares) internal virtual {
        MultiAssetVaultStorage storage $ = _getMultiAssetVaultStorage();
        uint256 assets = totalAssets(asset);
        $._totalSupply[asset] = shares;
        $._balances[asset][receiver] = assets;
        emit Deposit(receiver, asset, receiver, assets, shares);
    }
}
