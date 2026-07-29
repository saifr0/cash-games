// SPDX-License-Identifier: MIT

pragma solidity 0.8.31;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { IClaiming } from "./interfaces/IClaiming.sol";
import { IReservoir } from "./interfaces/IReservoir.sol";
import { _AUTHORITY_ROLE, _OWNER_ROLE } from "./shared/Constants.sol";
import { InvalidAddress, InvalidAmount, InvalidAssignment } from "./shared/Errors.sol";
import { _revert } from "./shared/Globals.sol";
import { MultiAssetVaultUpgradeable } from "./utils/MultiAssetVaultUpgradeable.sol";

/**
 * @title Reservoir.
 * @author Rain Team.
 * @notice Reservoir that holds the RainCasino's reserve.
 *
 * Proxy  : 0x921eF4f117460275eB8f54823282b9ef159F6815 (Arbitrum One)
 * Impl   : 0x4fba28fc4c4c7b7c6ac9129336e9305a8269ed2f (Arbitrum One)
 */
contract Reservoir is IReservoir, UUPSUpgradeable, MultiAssetVaultUpgradeable, AccessControlUpgradeable {
    using SafeERC20 for IERC20;

    /* ========================== ERC7201 STORAGE ========================== */

    /// @custom:storage-location erc7201:raincasino.storage.Reservoir
    struct ReservoirStorage {
        IClaiming _claiming;
        mapping(uint256 => mapping(IERC20 => uint256)) _dailyFeesCollected;
    }

    // keccak256(abi.encode(uint256(keccak256("raincasino.storage.Reservoir")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ReservoirStorageLocation =
        0xb8b5498b0dd8c9bfa7fbcc6688ff729ba511f7b015dc8a9b092fee3551a62000;

    function _getReservoirStorage() private pure returns (ReservoirStorage storage $) {
        assembly {
            $.slot := ReservoirStorageLocation
        }
    }

    function claiming() public view returns (address) {
        ReservoirStorage storage $ = _getReservoirStorage();
        return address($._claiming);
    }

    /* ========================== CONSTRUCTOR ========================== */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /* ========================== INITIALIZE ========================== */

    /**
     * @notice Initializes parent contracts and assigns roles.
     * @param assetsList_   List of accepted asset addresses.
     * @param initialOwner_ Address granted the owner role.
     * @param claiming_     Address of the withdrawal claiming contract.
     */
    function initialize(
        IERC20[] calldata assetsList_,
        address initialOwner_,
        address claiming_
    ) external initializer {
        __AccessControl_init();
        __MultiAssetVault_init(assetsList_);

        ReservoirStorage storage $ = _getReservoirStorage();

        _setRoleAdmin(_OWNER_ROLE, _OWNER_ROLE);
        _setRoleAdmin(_AUTHORITY_ROLE, _OWNER_ROLE);
        _grantRole(_OWNER_ROLE, initialOwner_);

        $._claiming = IClaiming(claiming_);
    }

    /* ========================== FUNCTIONS ========================== */

    function depositWithSlippage(
        IERC20 asset,
        uint256 assets,
        address receiver,
        uint256 minSharesOut
    ) external returns (uint256 shares) {
        shares = deposit(asset, assets, receiver);
        if (shares < minSharesOut) _revert(Slippage.selector);
        return shares;
    }

    function mintWithSlippage(
        IERC20 asset,
        uint256 shares,
        address receiver,
        uint256 maxAssetsIn
    ) external returns (uint256 assets) {
        assets = mint(asset, shares, receiver);
        if (assets > maxAssetsIn) _revert(Slippage.selector);
        return assets;
    }

    function withdrawWithSlippage(
        IERC20 asset,
        uint256 assets,
        address receiver,
        uint256 maxSharesIn
    ) external returns (uint256 shares) {
        shares = withdraw(asset, assets, receiver);
        if (shares > maxSharesIn) _revert(Slippage.selector);
        return shares;
    }

    function redeemWithSlippage(
        IERC20 asset,
        uint256 shares,
        address receiver,
        uint256 minAssetsOut
    ) external returns (uint256 assets) {
        assets = redeem(asset, shares, receiver);
        if (assets < minAssetsOut) _revert(Slippage.selector);
        return assets;
    }

    function absorb(
        IERC20 asset,
        uint256 assets,
        AbsorptionCause cause
    ) external validateAsset(asset) onlyRole(_AUTHORITY_ROLE) {
        ReservoirStorage storage $ = _getReservoirStorage();
        uint256 day = block.timestamp / 1 days;
        $._dailyFeesCollected[day][asset] += assets;
        emit Absorb({ asset: asset, assets: assets, cause: cause });
    }

    function disburse(
        IERC20 asset,
        uint256 assets,
        address winner
    ) external validateAsset(asset) onlyRole(_AUTHORITY_ROLE) {
        if (winner == address(0)) _revert(InvalidAddress.selector);
        if (assets == 0) _revert(InvalidAmount.selector);
        if (assets > totalAssets(asset)) _revert(InsufficientTotalAssets.selector);
        asset.safeTransfer(winner, assets);
        emit Disburse({ asset: asset, assets: assets, winner: winner });
    }

    /**
     * @dev Overrides withdraw to route assets through the Claiming contract.
     *      Tokens go to Claiming first; the receiver must then call claimRequest().
     */
    function _withdraw(IERC20 asset, address receiver, uint256 assets, uint256 shares) internal override {
        ReservoirStorage storage $ = _getReservoirStorage();
        super._withdraw(asset, address($._claiming), assets, shares);
        $._claiming.setRequest(receiver, assets);
    }

    function _authorizeUpgrade(address newImplementation) internal view override onlyRole(_OWNER_ROLE) {
        if (newImplementation == address(0)) _revert(InvalidAddress.selector);
    }

    function updateClaiming(address newClaimingAddress) external onlyRole(_OWNER_ROLE) {
        ReservoirStorage storage $ = _getReservoirStorage();
        if (address(newClaimingAddress) == address(0)) _revert(InvalidAddress.selector);
        if (address(newClaimingAddress) == address($._claiming)) _revert(InvalidAssignment.selector);
        emit UpdateClaim({ newClaimingAddress: address(newClaimingAddress), oldClaiming: address($._claiming) });
        $._claiming = IClaiming(newClaimingAddress);
    }

    function updateAsset(IERC20 asset, bool state) external onlyRole(_OWNER_ROLE) {
        if (address(asset) == address(0)) _revert(InvalidAddress.selector);
        _updateAsset(asset, state);
    }

    function dailyFeesCollected(IERC20 asset, uint256 day) external view returns (uint256) {
        ReservoirStorage storage $ = _getReservoirStorage();
        return $._dailyFeesCollected[day][asset];
    }
}
