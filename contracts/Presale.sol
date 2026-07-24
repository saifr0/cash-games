// SPDX-License-Identifier: MIT
pragma solidity 0.8.31;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

interface AggregatorV3Interface {
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

/// @notice Presale contract — sells CashGames tokens immediately for USDC, USDT, or ETH.
///         Tokens are pulled from `presaleWallet` (must approve this contract first).
///         All incoming funds are forwarded to `fundsWallet` at the time of purchase.
///         Each stablecoin has its own dedicated Chainlink price feed.
///
/// Arbitrum One addresses (pass to constructor):
///   USDC         0xaf88d065e77c8cC2239327C5EDb3A432268e5831
///   USDT         0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9
///   ETH/USD      0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612
///   USDC/USD     0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3
///   USDT/USD     0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7
///
/// On testnets without a USDT/USD feed, pass the USDC/USD address for both feed params.
contract Presale is Ownable2Step, Pausable, ReentrancyGuardTransient {
    using SafeERC20 for IERC20;
    using Address for address payable;

    // ─────────────────────────────────────────────
    // Custom errors
    // ─────────────────────────────────────────────

    error ZeroAddress();
    error ZeroAmount();
    error ZeroPrice();
    error PresaleCapExceeded();
    error StalePriceFeed();
    error InvalidChainlinkPrice();
    error AccidentalETHSend();
    error BelowMinimumPurchase();
    error UnsupportedToken();
    error InvalidStaleness();
    error PriceTooLow();
    error PriceTooHigh();

    // ─────────────────────────────────────────────
    // Constants
    // ─────────────────────────────────────────────

    uint256 public constant MAX_TOKENS = 10_000_000 * 1e18;

    /// Token price bounds (6-decimal USD).
    uint256 public constant MIN_TOKEN_PRICE =   1_000; // $0.001
    uint256 public constant MAX_TOKEN_PRICE = 1_000_000_000; // $1 000

    /// Maximum acceptable staleness for any Chainlink feed.
    uint256 public constant MAX_STALENESS = 7 days;

    // ─────────────────────────────────────────────
    // State
    // ─────────────────────────────────────────────

    IERC20 public immutable saleToken;
    IERC20 public immutable usdc;
    IERC20 public immutable usdt;

    AggregatorV3Interface public immutable ethPriceFeed;
    AggregatorV3Interface public immutable usdcPriceFeed;
    AggregatorV3Interface public immutable usdtPriceFeed;

    /// Wallet that holds the 10M presale allocation; must approve this contract.
    address public presaleWallet;

    /// Wallet that receives all purchase funds immediately.
    address public fundsWallet;

    /// Token price in USD with 6 decimal precision.
    /// Example: $0.05 per token → tokenPrice = 50_000
    uint256 public tokenPrice;

    uint256 public totalRaisedUSD; // 6-decimal USD
    uint256 public totalTokensSold; // 18-decimal tokens
    uint256 public totalRaisedETH; // wei

    /// ETH/USD feed heartbeat on mainnet is 1h.
    uint256 public priceFeedStaleness = 1 hours;

    /// USDC/USD feed on mainnet has a 24h heartbeat; 25h gives a 1h buffer.
    uint256 public stablecoinFeedStaleness = 25 hours;

    // ─────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────

    event TokensPurchased(
        address indexed buyer,
        address indexed paymentAsset,
        uint256 amountPaid, // stablecoin: 6-dec units; ETH: wei
        uint256 ethPaid, // non-zero only for ETH purchases (wei); 0 for stablecoins
        uint256 usdValue, // 6-decimal USD equivalent
        uint256 tokensBought
    );
    event TokenPriceUpdated(uint256 oldPrice, uint256 newPrice);
    event PriceFeedStalenessUpdated(uint256 oldStaleness, uint256 newStaleness);
    event StablecoinFeedStalenessUpdated(
        uint256 oldStaleness,
        uint256 newStaleness
    );
    event PresaleWalletUpdated(address oldWallet, address newWallet);
    event FundsWalletUpdated(address oldWallet, address newWallet);

    // ─────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────

    constructor(
        address _saleToken,
        address _usdc,
        address _usdt,
        address _ethPriceFeed,
        address _usdcPriceFeed,
        address _usdtPriceFeed,
        address _presaleWallet,
        address _fundsWallet,
        uint256 _tokenPrice,
        address _owner
    ) Ownable(_owner) {
        if (
            _saleToken == address(0) ||
            _usdc == address(0) ||
            _usdt == address(0) ||
            _ethPriceFeed == address(0) ||
            _usdcPriceFeed == address(0) ||
            _usdtPriceFeed == address(0) ||
            _presaleWallet == address(0) ||
            _fundsWallet == address(0)
        ) {
            revert ZeroAddress();
        }

        // Sale token must not be a payment token — would create a circular transfer.
        if (_saleToken == _usdc || _saleToken == _usdt) {
            revert UnsupportedToken();
        }

        // Presale wallet cannot be this contract — safeTransferFrom(this, …) would always fail.
        if (_presaleWallet == address(this)) {
            revert ZeroAddress();
        }

        saleToken = IERC20(_saleToken);
        usdc = IERC20(_usdc);
        usdt = IERC20(_usdt);
        ethPriceFeed = AggregatorV3Interface(_ethPriceFeed);
        usdcPriceFeed = AggregatorV3Interface(_usdcPriceFeed);
        usdtPriceFeed = AggregatorV3Interface(_usdtPriceFeed);
        presaleWallet = _presaleWallet;
        fundsWallet = _fundsWallet;
        tokenPrice = _tokenPrice;
    }

    // ─────────────────────────────────────────────
    // Purchase functions
    // ─────────────────────────────────────────────

    /// @param stablecoin  Address of USDC or USDT — the token to pay with.
    /// @param amount      Amount in 6-decimal stablecoin units.
    function buyWithToken(
        address stablecoin,
        uint256 amount
    ) external whenNotPaused nonReentrant {
        if (stablecoin != address(usdc) && stablecoin != address(usdt)) {
            revert UnsupportedToken();
        }

        if (amount == 0) {
            revert ZeroAmount();
        }

        uint256 usdValue = _stablecoinToUSD(stablecoin, amount);

        if (usdValue == 0) {
            revert BelowMinimumPurchase();
        }

        uint256 tokens = _tokensForUSD(usdValue);

        if (tokens == 0) {
            revert BelowMinimumPurchase();
        }

        _validateCap(tokens);

        // CEI: write all state before external calls.
        totalRaisedUSD += usdValue;
        totalTokensSold += tokens;
        emit TokensPurchased(
            msg.sender,
            stablecoin,
            amount,
            0,
            usdValue,
            tokens
        );

        IERC20(stablecoin).safeTransferFrom(msg.sender, fundsWallet, amount);
        saleToken.safeTransferFrom(presaleWallet, msg.sender, tokens);
    }

    function buyWithETH() external payable whenNotPaused nonReentrant {
        if (msg.value == 0) {
            revert ZeroAmount();
        }

        uint256 usdValue = _ethToUSD(msg.value);

        if (usdValue == 0) {
            revert BelowMinimumPurchase();
        }

        uint256 tokens = _tokensForUSD(usdValue);

        if (tokens == 0) {
            revert BelowMinimumPurchase();
        }

        _validateCap(tokens);

        payable(fundsWallet).sendValue(msg.value);

        // CEI: write all state before external calls.
        totalRaisedETH += msg.value;
        totalRaisedUSD += usdValue;
        totalTokensSold += tokens;
        emit TokensPurchased(
            msg.sender,
            address(0),
            msg.value,
            msg.value,
            usdValue,
            tokens
        );

        saleToken.safeTransferFrom(presaleWallet, msg.sender, tokens);
    }

    /// Reject plain ETH sends so funds are never accidentally locked.
    receive() external payable {
        revert AccidentalETHSend();
    }

    // ─────────────────────────────────────────────
    // View helpers
    // ─────────────────────────────────────────────

    /// Returns how many sale tokens `ethAmount` (wei) would buy at the current price.
    function previewBuyWithETH(
        uint256 ethAmount
    ) external view returns (uint256 tokens) {
        return _tokensForUSD(_ethToUSD(ethAmount));
    }

    /// Returns how many sale tokens `amount` of `stablecoin` would buy at the current price.
    function previewBuyWithToken(
        address stablecoin,
        uint256 amount
    ) external view returns (uint256 tokens) {
        if (stablecoin != address(usdc) && stablecoin != address(usdt)) {
            revert UnsupportedToken();
        }

        return _tokensForUSD(_stablecoinToUSD(stablecoin, amount));
    }

    /// Latest validated ETH/USD price (8-decimal Chainlink format).
    function getETHPrice() public view returns (uint256) {
        return _validateFeed(ethPriceFeed, priceFeedStaleness);
    }

    /// Latest validated USDC/USD price (8-decimal Chainlink format).
    function getUSDCPrice() public view returns (uint256) {
        return _validateFeed(usdcPriceFeed, stablecoinFeedStaleness);
    }

    /// Latest validated USDT/USD price (8-decimal Chainlink format).
    function getUSDTPrice() public view returns (uint256) {
        return _validateFeed(usdtPriceFeed, stablecoinFeedStaleness);
    }

    // ─────────────────────────────────────────────
    // Owner functions
    // ─────────────────────────────────────────────

    function setPriceFeedStaleness(uint256 newStaleness) external onlyOwner {
        if (newStaleness == 0 || newStaleness > MAX_STALENESS)
            revert InvalidStaleness();
        emit PriceFeedStalenessUpdated(priceFeedStaleness, newStaleness);
        priceFeedStaleness = newStaleness;
    }

    function setStablecoinFeedStaleness(
        uint256 newStaleness
    ) external onlyOwner {
        if (newStaleness == 0 || newStaleness > MAX_STALENESS)
            revert InvalidStaleness();
        emit StablecoinFeedStalenessUpdated(
            stablecoinFeedStaleness,
            newStaleness
        );
        stablecoinFeedStaleness = newStaleness;
    }

    function setTokenPrice(uint256 newPrice) external onlyOwner {
        if (newPrice < MIN_TOKEN_PRICE) revert PriceTooLow();
        if (newPrice > MAX_TOKEN_PRICE) revert PriceTooHigh();
        emit TokenPriceUpdated(tokenPrice, newPrice);
        tokenPrice = newPrice;
    }


    function setPresaleWallet(address newWallet) external onlyOwner {
        if (newWallet == address(0) || newWallet == address(this)) {
            revert ZeroAddress();
        }
        emit PresaleWalletUpdated(presaleWallet, newWallet);
        presaleWallet = newWallet;
    }

    function setFundsWallet(address newWallet) external onlyOwner {
        if (newWallet == address(0)) {
            revert ZeroAddress();
        }
        emit FundsWalletUpdated(fundsWallet, newWallet);
        fundsWallet = newWallet;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ─────────────────────────────────────────────
    // Internal helpers
    // ─────────────────────────────────────────────

    /// Reads and validates a Chainlink feed, returns the price (8 dec).
    function _validateFeed(
        AggregatorV3Interface feed,
        uint256 staleness
    ) internal view returns (uint256) {
        (
            uint80 roundId,
            int256 price,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        if (price <= 0) revert InvalidChainlinkPrice();
        if (startedAt == 0) revert InvalidChainlinkPrice();
        if (answeredInRound < roundId) revert StalePriceFeed();

        // Guard against feeds returning a future timestamp, which would underflow in 0.8+.
        if (
            updatedAt > block.timestamp ||
            block.timestamp - updatedAt > staleness
        ) {
            revert StalePriceFeed();
        }

        return uint256(price);
    }

    /// ethAmount (18 dec) × ETH/USD price (8 dec) / 1e20 = USD value (6 dec)
    function _ethToUSD(uint256 ethAmount) internal view returns (uint256) {
        return (ethAmount * getETHPrice()) / 1e20;
    }

    /// amount (6 dec) × stablecoin/USD price (8 dec) / 1e8 = USD value (6 dec)
    function _stablecoinToUSD(
        address stablecoin,
        uint256 amount
    ) internal view returns (uint256) {
        uint256 price = stablecoin == address(usdc)
            ? getUSDCPrice()
            : getUSDTPrice();
        return (amount * price) / 1e8;
    }

    /// usdAmount (6 dec) × 1e18 / tokenPrice (6 dec) = tokens (18 dec)
    function _tokensForUSD(uint256 usdAmount) internal view returns (uint256) {
        return (usdAmount * 1e18) / tokenPrice;
    }

    function _validateCap(uint256 tokens) internal view {
        if (totalTokensSold + tokens > MAX_TOKENS) {
            revert PresaleCapExceeded();
        }
    }
}
