// SPDX-License-Identifier: MIT
pragma solidity 0.8.31;

import {ERC20, ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract CashGames is ERC20, ERC20Burnable {
    constructor(
        string memory name,
        string memory symbol,
        address stakingRewards,
        address privateSale,
        address uniswapLiquidity,
        address levelUpRewards,
        address teamVesting,
        address teamVesting1,
        address dedicatedWallet
    ) ERC20(name, symbol) {
        _mint(stakingRewards, 50_000_000 * 10 ** 18); // 50%    House Pool Staking Rewards
        _mint(privateSale, 10_000_000 * 10 ** 18); // 10%    Private Sale
        _mint(uniswapLiquidity, 10_000_000 * 10 ** 18); // 10%    Uniswap Liquidity
        _mint(levelUpRewards, 5_000_000 * 10 ** 18); // 5%     Level Up Rewards
        _mint(teamVesting, 23_400_000 * 10 ** 18); // 23.4%  Team Vesting
        _mint(teamVesting1, 1_500_000 * 10 ** 18); // 1.5%   Team Vesting1
        _mint(dedicatedWallet, 100_000 * 10 ** 18); // 0.1%   Dedicated Wallet
    }
}
