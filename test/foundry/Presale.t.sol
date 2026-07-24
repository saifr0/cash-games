// SPDX-License-Identifier: MIT
pragma solidity 0.8.31;

import {Test, console} from "forge-std/Test.sol";
import {Presale} from "../../contracts/Presale.sol";
import {CashGames} from "../../contracts/CashGames.sol";
import {MockERC20} from "../../contracts/MockERC20.sol";

// ─────────────────────────────────────────────
// Mock Chainlink feed — configurable price & timestamps
// ─────────────────────────────────────────────
contract MockAggregator {
    int256  public price;
    uint256 public updatedAt;
    uint80  public roundId;

    constructor(int256 _price) {
        price     = _price;
        updatedAt = block.timestamp;
        roundId   = 1;
    }

    function setPrice(int256 _price) external {
        price     = _price;
        updatedAt = block.timestamp;
        roundId++;
    }

    function setUpdatedAt(uint256 _updatedAt) external { updatedAt = _updatedAt; }
    function setRoundId(uint80 _roundId)       external { roundId   = _roundId;   }

    function latestRoundData()
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (roundId, price, 1, updatedAt, roundId);
    }
}

// ─────────────────────────────────────────────
// Base fixture
// ─────────────────────────────────────────────
contract PresaleBase is Test {
    Presale        internal presale;
    CashGames      internal cash;
    MockERC20      internal usdc;
    MockERC20      internal usdt;
    MockAggregator internal ethFeed;
    MockAggregator internal usdcFeed;
    MockAggregator internal usdtFeed;

    address internal owner         = makeAddr("owner");
    address internal presaleWallet = makeAddr("presaleWallet");
    address internal fundsWallet   = makeAddr("fundsWallet");
    address internal buyer         = makeAddr("buyer");

    int256  internal constant ETH_PRICE   = 2_000e8;   // $2 000 (8-dec Chainlink)
    int256  internal constant USDC_PRICE  = 1e8;        // $1.00  (8-dec Chainlink)
    int256  internal constant USDT_PRICE  = 1e8;        // $1.00  (8-dec Chainlink)
    uint256 internal constant TOKEN_PRICE = 50_000;     // $0.05  (6-dec USD)
    uint256 internal constant PRESALE_SUPPLY = 10_000_000e18;

    function setUp() public virtual {
        ethFeed  = new MockAggregator(ETH_PRICE);
        usdcFeed = new MockAggregator(USDC_PRICE);
        usdtFeed = new MockAggregator(USDT_PRICE);

        cash = new CashGames(
            "$CASH", "$CASH",
            address(1), address(2), presaleWallet, address(3), address(4), address(5), address(6)
        );

        usdc = new MockERC20("USD Coin",   "USDC", 6);
        usdt = new MockERC20("Tether USD", "USDT", 6);

        presale = new Presale(
            address(cash),
            address(usdc),
            address(usdt),
            address(ethFeed),
            address(usdcFeed),
            address(usdtFeed),
            presaleWallet,
            fundsWallet,
            TOKEN_PRICE,
            owner
        );

        vm.prank(presaleWallet);
        cash.approve(address(presale), PRESALE_SUPPLY);

        usdc.mint(buyer, 1_000_000e6);
        usdt.mint(buyer, 1_000_000e6);
    }

    // ── helpers ──────────────────────────────

    function _buyUSDC(address user, uint256 amount) internal {
        vm.startPrank(user);
        usdc.approve(address(presale), amount);
        presale.buyWithToken(address(usdc), amount);
        vm.stopPrank();
    }

    function _buyUSDT(address user, uint256 amount) internal {
        vm.startPrank(user);
        usdt.approve(address(presale), amount);
        presale.buyWithToken(address(usdt), amount);
        vm.stopPrank();
    }

    function _expectedTokens(uint256 stableAmount) internal pure returns (uint256) {
        return ((stableAmount * uint256(USDC_PRICE)) / 1e8 * 1e18) / TOKEN_PRICE;
    }

    function _expectedTokensFromETH(uint256 ethAmount) internal pure returns (uint256) {
        return ((ethAmount * uint256(ETH_PRICE)) / 1e20 * 1e18) / TOKEN_PRICE;
    }
}

// ═════════════════════════════════════════════
// UNIT TESTS
// ═════════════════════════════════════════════
contract PresaleUnitTest is PresaleBase {

    // ── constructor ───────────────────────────

    function test_constructor_setsState() public view {
        assertEq(address(presale.saleToken()),  address(cash));
        assertEq(address(presale.usdc()),       address(usdc));
        assertEq(address(presale.usdt()),       address(usdt));
        assertEq(presale.presaleWallet(),       presaleWallet);
        assertEq(presale.fundsWallet(),         fundsWallet);
        assertEq(presale.tokenPrice(),          TOKEN_PRICE);
        assertEq(presale.owner(),               owner);
    }

    function test_constructor_revertsZeroAddress() public {
        vm.expectRevert(Presale.ZeroAddress.selector);
        new Presale(address(0), address(usdc), address(usdt), address(ethFeed), address(usdcFeed), address(usdtFeed), presaleWallet, fundsWallet, TOKEN_PRICE, owner);

        vm.expectRevert(Presale.ZeroAddress.selector);
        new Presale(address(cash), address(0), address(usdt), address(ethFeed), address(usdcFeed), address(usdtFeed), presaleWallet, fundsWallet, TOKEN_PRICE, owner);

        vm.expectRevert(Presale.ZeroAddress.selector);
        new Presale(address(cash), address(usdc), address(0), address(ethFeed), address(usdcFeed), address(usdtFeed), presaleWallet, fundsWallet, TOKEN_PRICE, owner);

        vm.expectRevert(Presale.ZeroAddress.selector);
        new Presale(address(cash), address(usdc), address(usdt), address(0), address(usdcFeed), address(usdtFeed), presaleWallet, fundsWallet, TOKEN_PRICE, owner);

        vm.expectRevert(Presale.ZeroAddress.selector);
        new Presale(address(cash), address(usdc), address(usdt), address(ethFeed), address(0), address(usdtFeed), presaleWallet, fundsWallet, TOKEN_PRICE, owner);

        vm.expectRevert(Presale.ZeroAddress.selector);
        new Presale(address(cash), address(usdc), address(usdt), address(ethFeed), address(usdcFeed), address(0), presaleWallet, fundsWallet, TOKEN_PRICE, owner);
    }

    function test_constructor_revertsPriceTooLow() public {
        uint256 minPrice = presale.MIN_TOKEN_PRICE();
        vm.expectRevert(Presale.PriceTooLow.selector);
        new Presale(address(cash), address(usdc), address(usdt), address(ethFeed), address(usdcFeed), address(usdtFeed), presaleWallet, fundsWallet, minPrice - 1, owner);
    }

    function test_constructor_revertsPriceTooHigh() public {
        uint256 maxPrice = presale.MAX_TOKEN_PRICE();
        vm.expectRevert(Presale.PriceTooHigh.selector);
        new Presale(address(cash), address(usdc), address(usdt), address(ethFeed), address(usdcFeed), address(usdtFeed), presaleWallet, fundsWallet, maxPrice + 1, owner);
    }

    function test_constructor_revertsSaleTokenEqualsUSDC() public {
        vm.expectRevert(Presale.UnsupportedToken.selector);
        new Presale(address(usdc), address(usdc), address(usdt), address(ethFeed), address(usdcFeed), address(usdtFeed), presaleWallet, fundsWallet, TOKEN_PRICE, owner);
    }

    function test_constructor_revertsSaleTokenEqualsUSDT() public {
        vm.expectRevert(Presale.UnsupportedToken.selector);
        new Presale(address(usdt), address(usdc), address(usdt), address(ethFeed), address(usdcFeed), address(usdtFeed), presaleWallet, fundsWallet, TOKEN_PRICE, owner);
    }

    function test_constructor_revertsPresaleWalletIsContract() public {
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        vm.expectRevert(Presale.ZeroAddress.selector);
        new Presale(address(cash), address(usdc), address(usdt), address(ethFeed), address(usdcFeed), address(usdtFeed), predicted, fundsWallet, TOKEN_PRICE, owner);
    }

    // ── buyWithToken — USDC ───────────────────

    function test_buyWithUSDC_transfersTokens() public {
        uint256 amount   = 100e6;
        uint256 expected = _expectedTokens(amount);
        _buyUSDC(buyer, amount);
        assertEq(cash.balanceOf(buyer), expected);
    }

    function test_buyWithUSDC_forwardsPayment() public {
        uint256 amount = 200e6;
        uint256 before = usdc.balanceOf(fundsWallet);
        _buyUSDC(buyer, amount);
        assertEq(usdc.balanceOf(fundsWallet), before + amount);
    }

    function test_buyWithUSDC_updatesAccounting() public {
        uint256 amount = 500e6;
        uint256 usdVal = (amount * uint256(USDC_PRICE)) / 1e8;
        uint256 tokens = (usdVal * 1e18) / TOKEN_PRICE;
        _buyUSDC(buyer, amount);
        assertEq(presale.totalRaisedUSD(),  usdVal);
        assertEq(presale.totalTokensSold(), tokens);
    }

    function test_buyWithUSDC_emitsEvent() public {
        uint256 amount = 50e6;
        uint256 usdVal = (amount * uint256(USDC_PRICE)) / 1e8;
        uint256 tokens = (usdVal * 1e18) / TOKEN_PRICE;

        vm.startPrank(buyer);
        usdc.approve(address(presale), amount);
        vm.expectEmit(true, true, false, true);
        emit Presale.TokensPurchased(buyer, address(usdc), amount, 0, usdVal, tokens);
        presale.buyWithToken(address(usdc), amount);
        vm.stopPrank();
    }

    // ── buyWithToken — USDT ───────────────────

    function test_buyWithUSDT_transfersTokens() public {
        uint256 amount   = 100e6;
        uint256 expected = _expectedTokens(amount);
        _buyUSDT(buyer, amount);
        assertEq(cash.balanceOf(buyer), expected);
    }

    function test_buyWithUSDT_forwardsPayment() public {
        uint256 amount = 300e6;
        uint256 before = usdt.balanceOf(fundsWallet);
        _buyUSDT(buyer, amount);
        assertEq(usdt.balanceOf(fundsWallet), before + amount);
    }

    function test_buyWithUSDT_usesUSDTPriceFeed() public {
        usdtFeed.setPrice(0.98e8);
        uint256 amount       = 1000e6;
        uint256 usdVal       = (amount * 0.98e8) / 1e8;
        uint256 tokensExpect = (usdVal * 1e18) / TOKEN_PRICE;
        _buyUSDT(buyer, amount);
        assertEq(cash.balanceOf(buyer), tokensExpect);
    }

    function test_buyWithUSDT_independentFromUSDCFeed() public {
        // Moving the USDC feed must NOT affect USDT pricing.
        usdcFeed.setPrice(0.95e8);
        uint256 amount       = 1000e6;
        uint256 usdVal       = (amount * uint256(USDT_PRICE)) / 1e8; // still uses USDT feed ($1)
        uint256 tokensExpect = (usdVal * 1e18) / TOKEN_PRICE;
        _buyUSDT(buyer, amount);
        assertEq(cash.balanceOf(buyer), tokensExpect);
    }

    function test_buyWithUSDT_emitsEvent() public {
        uint256 amount = 50e6;
        uint256 usdVal = (amount * uint256(USDC_PRICE)) / 1e8;
        uint256 tokens = (usdVal * 1e18) / TOKEN_PRICE;

        vm.startPrank(buyer);
        usdt.approve(address(presale), amount);
        vm.expectEmit(true, true, false, true);
        emit Presale.TokensPurchased(buyer, address(usdt), amount, 0, usdVal, tokens);
        presale.buyWithToken(address(usdt), amount);
        vm.stopPrank();
    }

    // ── buyWithToken — error cases ────────────

    function test_buyWithToken_revertsUnsupportedToken() public {
        MockERC20 rando = new MockERC20("X", "X", 6);
        rando.mint(buyer, 1000e6);
        vm.startPrank(buyer);
        rando.approve(address(presale), 100e6);
        vm.expectRevert(Presale.UnsupportedToken.selector);
        presale.buyWithToken(address(rando), 100e6);
        vm.stopPrank();
    }

    function test_buyWithToken_revertsZeroAmount() public {
        vm.startPrank(buyer);
        vm.expectRevert(Presale.ZeroAmount.selector);
        presale.buyWithToken(address(usdc), 0);
        vm.stopPrank();
    }

    function test_buyWithToken_revertsWhenPaused() public {
        vm.prank(owner);
        presale.pause();
        vm.startPrank(buyer);
        usdc.approve(address(presale), 100e6);
        vm.expectRevert();
        presale.buyWithToken(address(usdc), 100e6);
        vm.stopPrank();
    }

    function test_buyWithToken_revertsCapExceeded() public {
        uint256 minPrice = presale.MIN_TOKEN_PRICE(); // cache before prank consumes the call
        vm.prank(owner);
        presale.setTokenPrice(minPrice);

        vm.startPrank(buyer);
        usdc.approve(address(presale), 1_000_000e6);
        vm.expectRevert(Presale.PresaleCapExceeded.selector);
        presale.buyWithToken(address(usdc), 1_000_000e6);
        vm.stopPrank();
    }

    // With MIN/MAX_TOKEN_PRICE bounds, any non-zero 6-dec stablecoin amount always produces
    // at least 1 token unit (18-dec). The tokens==0 guard in buyWithToken/buyWithETH is
    // defense-in-depth for future constant changes — it is provably unreachable today.
    // This test confirms the worst-case price produces non-zero tokens for the minimum buy.
    function test_buyWithToken_minimumPurchaseAlwaysProducesTokens() public {
        uint256 maxPrice = presale.MAX_TOKEN_PRICE(); // $1 000 per token
        vm.prank(owner);
        presale.setTokenPrice(maxPrice);

        usdc.mint(buyer, 1e6);
        vm.startPrank(buyer);
        usdc.approve(address(presale), 1e6);
        presale.buyWithToken(address(usdc), 1e6); // must succeed and produce > 0 tokens
        vm.stopPrank();

        assertGt(cash.balanceOf(buyer), 0);
    }

    // ── buyWithETH ────────────────────────────

    function test_buyWithETH_transfersTokens() public {
        uint256 ethAmount = 1 ether;
        uint256 expected  = _expectedTokensFromETH(ethAmount);
        vm.deal(buyer, ethAmount);
        vm.prank(buyer);
        presale.buyWithETH{value: ethAmount}();
        assertEq(cash.balanceOf(buyer), expected);
    }

    function test_buyWithETH_forwardsETH() public {
        uint256 ethAmount = 0.5 ether;
        vm.deal(buyer, ethAmount);
        uint256 before = fundsWallet.balance;
        vm.prank(buyer);
        presale.buyWithETH{value: ethAmount}();
        assertEq(fundsWallet.balance, before + ethAmount);
    }

    function test_buyWithETH_updatesAccounting() public {
        uint256 ethAmount = 2 ether;
        uint256 usdVal    = (ethAmount * uint256(ETH_PRICE)) / 1e20;
        uint256 tokens    = (usdVal * 1e18) / TOKEN_PRICE;
        vm.deal(buyer, ethAmount);
        vm.prank(buyer);
        presale.buyWithETH{value: ethAmount}();
        assertEq(presale.totalRaisedETH(),  ethAmount);
        assertEq(presale.totalRaisedUSD(),  usdVal);
        assertEq(presale.totalTokensSold(), tokens);
    }

    function test_buyWithETH_emitsEvent() public {
        uint256 ethAmount = 1 ether;
        uint256 usdVal    = (ethAmount * uint256(ETH_PRICE)) / 1e20;
        uint256 tokens    = (usdVal * 1e18) / TOKEN_PRICE;
        vm.deal(buyer, ethAmount);
        vm.prank(buyer);
        vm.expectEmit(true, true, false, true);
        emit Presale.TokensPurchased(buyer, address(0), ethAmount, ethAmount, usdVal, tokens);
        presale.buyWithETH{value: ethAmount}();
    }

    function test_buyWithETH_revertsZeroAmount() public {
        vm.expectRevert(Presale.ZeroAmount.selector);
        presale.buyWithETH{value: 0}();
    }

    function test_buyWithETH_revertsWhenPaused() public {
        vm.prank(owner);
        presale.pause();
        vm.deal(buyer, 1 ether);
        vm.expectRevert();
        vm.prank(buyer);
        presale.buyWithETH{value: 1 ether}();
    }

    function test_receive_revertsAccidentalETH() public {
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        (bool ok, bytes memory data) = address(presale).call{value: 1 ether}("");
        assertFalse(ok);
        assertEq(bytes4(data), Presale.AccidentalETHSend.selector);
    }

    // ── stale / invalid feed ──────────────────

    function test_buyWithETH_revertsOnStaleFeed() public {
        vm.warp(block.timestamp + 2 days);
        ethFeed.setUpdatedAt(block.timestamp - 2 hours); // > 1h heartbeat
        vm.deal(buyer, 1 ether);
        vm.expectRevert(Presale.StalePriceFeed.selector);
        vm.prank(buyer);
        presale.buyWithETH{value: 1 ether}();
    }

    function test_buyWithToken_revertsOnStaleFeed_USDC() public {
        vm.warp(block.timestamp + 2 days);
        usdcFeed.setUpdatedAt(block.timestamp - 26 hours); // > 25h default
        vm.startPrank(buyer);
        usdc.approve(address(presale), 100e6);
        vm.expectRevert(Presale.StalePriceFeed.selector);
        presale.buyWithToken(address(usdc), 100e6);
        vm.stopPrank();
    }

    function test_buyWithToken_revertsOnStaleFeed_USDT() public {
        vm.warp(block.timestamp + 2 days);
        usdtFeed.setUpdatedAt(block.timestamp - 26 hours); // > 25h default
        vm.startPrank(buyer);
        usdt.approve(address(presale), 100e6);
        vm.expectRevert(Presale.StalePriceFeed.selector);
        presale.buyWithToken(address(usdt), 100e6);
        vm.stopPrank();
    }

    function test_buyWithETH_revertsOnFutureTimestamp() public {
        ethFeed.setUpdatedAt(block.timestamp + 1 hours);
        vm.deal(buyer, 1 ether);
        vm.expectRevert(Presale.StalePriceFeed.selector);
        vm.prank(buyer);
        presale.buyWithETH{value: 1 ether}();
    }

    function test_buyWithToken_revertsOnFutureTimestamp() public {
        usdcFeed.setUpdatedAt(block.timestamp + 1 hours);
        vm.startPrank(buyer);
        usdc.approve(address(presale), 100e6);
        vm.expectRevert(Presale.StalePriceFeed.selector);
        presale.buyWithToken(address(usdc), 100e6);
        vm.stopPrank();
    }

    function test_buyWithETH_revertsOnInvalidPrice() public {
        ethFeed.setPrice(0);
        vm.deal(buyer, 1 ether);
        vm.expectRevert(Presale.InvalidChainlinkPrice.selector);
        vm.prank(buyer);
        presale.buyWithETH{value: 1 ether}();
    }

    function test_buyWithToken_revertsOnNegativePrice() public {
        usdcFeed.setPrice(-1);
        vm.startPrank(buyer);
        usdc.approve(address(presale), 100e6);
        vm.expectRevert(Presale.InvalidChainlinkPrice.selector);
        presale.buyWithToken(address(usdc), 100e6);
        vm.stopPrank();
    }

    // ── view helpers ──────────────────────────

    function test_previewBuyWithETH_matchesBuy() public {
        uint256 ethAmount = 1 ether;
        uint256 preview   = presale.previewBuyWithETH(ethAmount);
        vm.deal(buyer, ethAmount);
        vm.prank(buyer);
        presale.buyWithETH{value: ethAmount}();
        assertEq(cash.balanceOf(buyer), preview);
    }

    function test_previewBuyWithToken_USDC_matchesBuy() public {
        uint256 amount  = 100e6;
        uint256 preview = presale.previewBuyWithToken(address(usdc), amount);
        _buyUSDC(buyer, amount);
        assertEq(cash.balanceOf(buyer), preview);
    }

    function test_previewBuyWithToken_USDT_matchesBuy() public {
        uint256 amount  = 100e6;
        uint256 preview = presale.previewBuyWithToken(address(usdt), amount);
        _buyUSDT(buyer, amount);
        assertEq(cash.balanceOf(buyer), preview);
    }

    function test_previewBuyWithToken_revertsUnsupported() public {
        vm.expectRevert(Presale.UnsupportedToken.selector);
        presale.previewBuyWithToken(address(0xdead), 100e6);
    }

    function test_getETHPrice_returnsCorrectPrice() public view {
        assertEq(presale.getETHPrice(), uint256(ETH_PRICE));
    }

    function test_getUSDCPrice_returnsCorrectPrice() public view {
        assertEq(presale.getUSDCPrice(), uint256(USDC_PRICE));
    }

    // ── owner functions ───────────────────────

    function test_setTokenPrice_withinBounds() public {
        vm.prank(owner);
        presale.setTokenPrice(100_000);
        assertEq(presale.tokenPrice(), 100_000);
    }

    function test_setTokenPrice_revertsTooLow() public {
        uint256 minPrice = presale.MIN_TOKEN_PRICE();
        vm.prank(owner);
        vm.expectRevert(Presale.PriceTooLow.selector);
        presale.setTokenPrice(minPrice - 1);
    }

    function test_setTokenPrice_revertsTooHigh() public {
        uint256 maxPrice = presale.MAX_TOKEN_PRICE();
        vm.prank(owner);
        vm.expectRevert(Presale.PriceTooHigh.selector);
        presale.setTokenPrice(maxPrice + 1);
    }

    function test_setTokenPrice_revertsNonOwner() public {
        vm.expectRevert();
        presale.setTokenPrice(100_000);
    }

    function test_setTokenPrice_emitsEvent() public {
        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit Presale.TokenPriceUpdated(TOKEN_PRICE, 200_000);
        presale.setTokenPrice(200_000);
    }

    function test_setPriceFeedStaleness_withinBounds() public {
        vm.prank(owner);
        presale.setPriceFeedStaleness(2 hours);
        assertEq(presale.priceFeedStaleness(), 2 hours);
    }

    function test_setPriceFeedStaleness_revertsZero() public {
        vm.prank(owner);
        vm.expectRevert(Presale.InvalidStaleness.selector);
        presale.setPriceFeedStaleness(0);
    }

    function test_setPriceFeedStaleness_revertsTooHigh() public {
        uint256 maxS = presale.MAX_STALENESS();
        vm.prank(owner);
        vm.expectRevert(Presale.InvalidStaleness.selector);
        presale.setPriceFeedStaleness(maxS + 1);
    }

    function test_setStablecoinFeedStaleness_withinBounds() public {
        vm.prank(owner);
        presale.setStablecoinFeedStaleness(48 hours);
        assertEq(presale.stablecoinFeedStaleness(), 48 hours);
    }

    function test_setStablecoinFeedStaleness_revertsZero() public {
        vm.prank(owner);
        vm.expectRevert(Presale.InvalidStaleness.selector);
        presale.setStablecoinFeedStaleness(0);
    }

    function test_setStablecoinFeedStaleness_revertsTooHigh() public {
        uint256 maxS = presale.MAX_STALENESS();
        vm.prank(owner);
        vm.expectRevert(Presale.InvalidStaleness.selector);
        presale.setStablecoinFeedStaleness(maxS + 1);
    }

    function test_setPresaleWallet() public {
        address newWallet = makeAddr("newPresale");
        vm.prank(owner);
        presale.setPresaleWallet(newWallet);
        assertEq(presale.presaleWallet(), newWallet);
    }

    function test_setPresaleWallet_revertsZero() public {
        vm.prank(owner);
        vm.expectRevert(Presale.ZeroAddress.selector);
        presale.setPresaleWallet(address(0));
    }

    function test_setPresaleWallet_revertsContractSelf() public {
        vm.prank(owner);
        vm.expectRevert(Presale.ZeroAddress.selector);
        presale.setPresaleWallet(address(presale));
    }

    function test_setFundsWallet() public {
        address newWallet = makeAddr("newFunds");
        vm.prank(owner);
        presale.setFundsWallet(newWallet);
        assertEq(presale.fundsWallet(), newWallet);
    }

    function test_setFundsWallet_revertsZero() public {
        vm.prank(owner);
        vm.expectRevert(Presale.ZeroAddress.selector);
        presale.setFundsWallet(address(0));
    }

    function test_pauseUnpause() public {
        vm.prank(owner);
        presale.pause();
        assertTrue(presale.paused());
        vm.prank(owner);
        presale.unpause();
        assertFalse(presale.paused());
    }

    function test_pause_revertsNonOwner() public {
        vm.expectRevert();
        presale.pause();
    }

    // ── cumulative / multi-buyer ──────────────

    function test_multiplePurchases_accumulateCorrectly() public {
        address buyer2 = makeAddr("buyer2");
        usdt.mint(buyer2, 500e6);

        _buyUSDC(buyer,  200e6);
        _buyUSDT(buyer2, 300e6);

        uint256 usd1 = (200e6 * uint256(USDC_PRICE)) / 1e8;
        uint256 usd2 = (300e6 * uint256(USDC_PRICE)) / 1e8;
        assertEq(presale.totalRaisedUSD(), usd1 + usd2);
    }
}

// ═════════════════════════════════════════════
// FUZZ TESTS
// ═════════════════════════════════════════════
contract PresaleFuzzTest is PresaleBase {

    // ── buyWithToken fuzz ─────────────────────

    function testFuzz_buyWithUSDC(uint256 amount) public {
        amount = bound(amount, 1e6, 200_000e6);
        usdc.mint(buyer, amount);

        uint256 usdVal         = (amount * uint256(USDC_PRICE)) / 1e8;
        uint256 expectedTokens = (usdVal * 1e18) / TOKEN_PRICE;

        _buyUSDC(buyer, amount);

        assertEq(cash.balanceOf(buyer),     expectedTokens);
        assertEq(presale.totalRaisedUSD(),  usdVal);
        assertEq(presale.totalTokensSold(), expectedTokens);
    }

    function testFuzz_buyWithUSDT(uint256 amount) public {
        amount = bound(amount, 1e6, 200_000e6);
        usdt.mint(buyer, amount);

        uint256 usdVal         = (amount * uint256(USDC_PRICE)) / 1e8;
        uint256 expectedTokens = (usdVal * 1e18) / TOKEN_PRICE;

        _buyUSDT(buyer, amount);
        assertEq(cash.balanceOf(buyer), expectedTokens);
    }

    function testFuzz_buyWithETH(uint256 ethAmount) public {
        ethAmount = bound(ethAmount, 0.001 ether, 200 ether);
        vm.deal(buyer, ethAmount);
        vm.prank(buyer);
        presale.buyWithETH{value: ethAmount}();

        uint256 usdVal         = (ethAmount * uint256(ETH_PRICE)) / 1e20;
        uint256 expectedTokens = (usdVal * 1e18) / TOKEN_PRICE;

        assertEq(cash.balanceOf(buyer),    expectedTokens);
        assertEq(presale.totalRaisedETH(), ethAmount);
    }

    // ── price feed fuzz ───────────────────────

    function testFuzz_usdcPriceVariations(int256 price, uint256 amount) public {
        price  = int256(bound(uint256(price), 0.90e8, 1.10e8));
        amount = bound(amount, 1e6, 100_000e6);

        usdcFeed.setPrice(price);
        usdc.mint(buyer, amount);

        uint256 usdVal         = (amount * uint256(price)) / 1e8;
        uint256 expectedTokens = (usdVal * 1e18) / TOKEN_PRICE;

        if (presale.totalTokensSold() + expectedTokens > presale.MAX_TOKENS()) return;

        _buyUSDC(buyer, amount);
        assertEq(cash.balanceOf(buyer), expectedTokens);
    }

    function testFuzz_usdtPriceVariations(int256 price, uint256 amount) public {
        price  = int256(bound(uint256(price), 0.90e8, 1.10e8));
        amount = bound(amount, 1e6, 100_000e6);

        usdtFeed.setPrice(price);
        usdt.mint(buyer, amount);

        uint256 usdVal         = (amount * uint256(price)) / 1e8;
        uint256 expectedTokens = (usdVal * 1e18) / TOKEN_PRICE;

        if (presale.totalTokensSold() + expectedTokens > presale.MAX_TOKENS()) return;

        _buyUSDT(buyer, amount);
        assertEq(cash.balanceOf(buyer), expectedTokens);
    }

    function testFuzz_ethPriceVariations(int256 price, uint256 ethAmount) public {
        price     = int256(bound(uint256(price), 500e8, 10_000e8));
        ethAmount = bound(ethAmount, 0.001 ether, 10 ether);

        ethFeed.setPrice(price);

        uint256 usdVal         = (ethAmount * uint256(price)) / 1e20;
        uint256 expectedTokens = (usdVal * 1e18) / TOKEN_PRICE;

        if (presale.totalTokensSold() + expectedTokens > presale.MAX_TOKENS()) return;

        vm.deal(buyer, ethAmount);
        vm.prank(buyer);
        presale.buyWithETH{value: ethAmount}();
        assertEq(cash.balanceOf(buyer), expectedTokens);
    }

    // ── tokenPrice fuzz ───────────────────────

    function testFuzz_tokenPriceVariations(uint256 newPrice, uint256 amount) public {
        newPrice = bound(newPrice, presale.MIN_TOKEN_PRICE(), presale.MAX_TOKEN_PRICE());
        amount   = bound(amount,   1e6, 10_000e6);

        vm.prank(owner);
        presale.setTokenPrice(newPrice);
        usdc.mint(buyer, amount);

        uint256 usdVal         = (amount * uint256(USDC_PRICE)) / 1e8;
        uint256 expectedTokens = (usdVal * 1e18) / newPrice;

        if (presale.totalTokensSold() + expectedTokens > presale.MAX_TOKENS()) return;
        if (expectedTokens == 0) return;

        _buyUSDC(buyer, amount);
        assertEq(cash.balanceOf(buyer), expectedTokens);
    }

    // ── accounting invariants ─────────────────

    function testFuzz_accountingInvariant(uint256 a, uint256 b) public {
        a = bound(a, 1e6, 50_000e6);
        b = bound(b, 1e6, 50_000e6);
        usdc.mint(buyer, a);
        usdt.mint(buyer, b);

        _buyUSDC(buyer, a);
        _buyUSDT(buyer, b);

        uint256 usdA = (a * uint256(USDC_PRICE)) / 1e8;
        uint256 usdB = (b * uint256(USDC_PRICE)) / 1e8;
        uint256 tokA = (usdA * 1e18) / TOKEN_PRICE;
        uint256 tokB = (usdB * 1e18) / TOKEN_PRICE;

        assertEq(presale.totalRaisedUSD(),  usdA + usdB);
        assertEq(presale.totalTokensSold(), tokA + tokB);
        assertEq(cash.balanceOf(buyer),     tokA + tokB);
    }

    // ── preview matches actual ─────────────────

    function testFuzz_previewMatchesBuyUSDC(uint256 amount) public {
        amount = bound(amount, 1e6, 100_000e6);
        usdc.mint(buyer, amount);
        uint256 preview = presale.previewBuyWithToken(address(usdc), amount);
        _buyUSDC(buyer, amount);
        assertEq(cash.balanceOf(buyer), preview);
    }

    function testFuzz_previewMatchesBuyUSDT(uint256 amount) public {
        amount = bound(amount, 1e6, 100_000e6);
        usdt.mint(buyer, amount);
        uint256 preview = presale.previewBuyWithToken(address(usdt), amount);
        _buyUSDT(buyer, amount);
        assertEq(cash.balanceOf(buyer), preview);
    }

    function testFuzz_previewMatchesBuyETH(uint256 ethAmount) public {
        ethAmount = bound(ethAmount, 0.001 ether, 100 ether);
        vm.deal(buyer, ethAmount);
        uint256 preview = presale.previewBuyWithETH(ethAmount);
        vm.prank(buyer);
        presale.buyWithETH{value: ethAmount}();
        assertEq(cash.balanceOf(buyer), preview);
    }

    // ── staleness bounds fuzz ─────────────────

    function testFuzz_stalenessSetterBounds(uint256 s) public {
        // Values within [1, MAX_STALENESS] must succeed.
        s = bound(s, 1, presale.MAX_STALENESS());
        vm.startPrank(owner);
        presale.setPriceFeedStaleness(s);
        presale.setStablecoinFeedStaleness(s);
        vm.stopPrank();
        assertEq(presale.priceFeedStaleness(),       s);
        assertEq(presale.stablecoinFeedStaleness(),  s);
    }

    // ── price bounds fuzz ─────────────────────

    function testFuzz_tokenPriceBounds(uint256 p) public {
        p = bound(p, presale.MIN_TOKEN_PRICE(), presale.MAX_TOKEN_PRICE());
        vm.prank(owner);
        presale.setTokenPrice(p);
        assertEq(presale.tokenPrice(), p);
    }
}
