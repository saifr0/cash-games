// SPDX-License-Identifier: MIT
pragma solidity 0.8.31;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract CashGames is ERC20, ERC20Burnable {
    constructor(
        string memory name,
        string memory symbol,
        address houseWallet,
        address stakingRewards,
        address privateSale,
        address uniswapLiquidity,
        address levelUpRewards,
        address teamVesting,
        address dedicatedWallet
    ) ERC20(name, symbol) {
        _mint(houseWallet,      25_000_000 * 10 ** 18); // 25%    House / Company
        _mint(stakingRewards,   50_000_000 * 10 ** 18); // 50%    House Pool Staking Rewards
        _mint(privateSale,      10_000_000 * 10 ** 18); // 10%    Private Sale
        _mint(uniswapLiquidity, 10_000_000 * 10 ** 18); // 10%    Uniswap Liquidity
        _mint(levelUpRewards,    5_000_000 * 10 ** 18); // 5%     Level Up Rewards
        _mint(teamVesting,      23_400_000 * 10 ** 18); // 23.4%  Team Vesting
        _mint(dedicatedWallet,       100_000 * 10 ** 18); // 0.1%   Dedicated Wallet
    }
}
