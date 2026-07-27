// SPDX-License-Identifier: MIT
pragma solidity 0.8.31;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Presale} from "../../contracts/Presale.sol";

/// @notice Fork tests against the live Presale on Arbitrum One.
///         No mocks — uses real USDT, real Chainlink feeds, real $CASH.
///         The buyer wallet is created locally and funded with real USDT storage via `deal`.
///
/// Run:
///   forge test --match-contract PresaleForkTest --fork-url $URL_ARB -v
///   or set URL_ARB in .env and run:
///   forge test --match-contract PresaleForkTest -v
contract PresaleForkTest is Test {

    // ── Live Arbitrum One addresses ────────────────────────────────────────────
    address constant PRESALE_ADDR = 0x57Ef7807DB93237227027FEa273F150C0d643CE1;
    address constant USDT_ADDR    = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;

    Presale presale = Presale(payable(PRESALE_ADDR));
    IERC20  usdt    = IERC20(USDT_ADDR);

    // Resolved from the live contract in setUp — not hardcoded
    IERC20  saleToken;
    address presaleWallet;
    address fundsWallet;

    address buyer  = makeAddr("buyer");
    address buyer2 = makeAddr("buyer2");

    function setUp() public {
        vm.createSelectFork(vm.envString("URL_ARB"));

        // Read all critical addresses from the live contract
        saleToken     = presale.saleToken();
        presaleWallet = presale.presaleWallet();
        fundsWallet   = presale.fundsWallet();

        // The presale wallet needs: sufficient saleToken balance + approval to this Presale.
        // We deal the full 10M cap and grant unlimited allowance so tests are self-contained.
        deal(address(saleToken), presaleWallet, presale.MAX_TOKENS());
        vm.prank(presaleWallet);
        saleToken.approve(address(presale), type(uint256).max);
    }

    // ── helpers ────────────────────────────────────────────────────────────────

    function _dealUSDT(address to, uint256 amount) internal {
        deal(USDT_ADDR, to, amount);
    }

    function _buy(address user, uint256 amount) internal {
        vm.startPrank(user);
        usdt.approve(address(presale), amount);
        presale.buyWithToken(USDT_ADDR, amount);
        vm.stopPrank();
    }

    // ── sanity: read live state ────────────────────────────────────────────────

    function test_fork_liveState() public view {
        console.log("saleToken              :", address(saleToken));
        console.log("presaleWallet          :", presaleWallet);
        console.log("fundsWallet            :", fundsWallet);
        console.log("tokenPrice             :", presale.tokenPrice());
        console.log("stablecoinFeedStaleness:", presale.stablecoinFeedStaleness());
        console.log("totalTokensSold        :", presale.totalTokensSold());

        assertEq(address(presale.usdt()), USDT_ADDR);
        assertGt(presale.tokenPrice(), 0);
        assertFalse(presale.paused());
    }

    // ── buy: tokens received ──────────────────────────────────────────────────

    function test_fork_buyWithUSDT_receivesTokens() public {
        uint256 amount  = 100e6; // 100 USDT
        uint256 preview = presale.previewBuyWithToken(USDT_ADDR, amount);

        _dealUSDT(buyer, amount);
        _buy(buyer, amount);

        assertGt(saleToken.balanceOf(buyer), 0);
        assertEq(saleToken.balanceOf(buyer), preview);
    }

    // ── buy: USDT routed to fundsWallet ──────────────────────────────────────

    function test_fork_buyWithUSDT_transfersToFundsWallet() public {
        uint256 amount = 500e6; // 500 USDT
        uint256 before = usdt.balanceOf(fundsWallet);

        _dealUSDT(buyer, amount);
        _buy(buyer, amount);

        assertEq(usdt.balanceOf(fundsWallet), before + amount);
        assertEq(usdt.balanceOf(buyer), 0);
    }

    // ── buy: accounting incremented ───────────────────────────────────────────

    function test_fork_buyWithUSDT_updatesAccounting() public {
        uint256 amount       = 1_000e6; // 1 000 USDT
        uint256 soldBefore   = presale.totalTokensSold();
        uint256 raisedBefore = presale.totalRaisedUSD();
        uint256 preview      = presale.previewBuyWithToken(USDT_ADDR, amount);

        _dealUSDT(buyer, amount);
        _buy(buyer, amount);

        assertEq(presale.totalTokensSold(), soldBefore + preview);
        assertGt(presale.totalRaisedUSD(),  raisedBefore);
    }

    // ── buy: preview matches actual ───────────────────────────────────────────

    function test_fork_previewMatchesBuy() public {
        uint256 amount  = 250e6;
        uint256 preview = presale.previewBuyWithToken(USDT_ADDR, amount);

        _dealUSDT(buyer, amount);
        _buy(buyer, amount);

        assertEq(saleToken.balanceOf(buyer), preview);
    }

    // ── buy: multiple independent buyers ─────────────────────────────────────

    function test_fork_buyWithUSDT_multipleUsers() public {
        uint256 amt1 = 200e6;
        uint256 amt2 = 300e6;

        uint256 preview1 = presale.previewBuyWithToken(USDT_ADDR, amt1);
        uint256 preview2 = presale.previewBuyWithToken(USDT_ADDR, amt2);

        _dealUSDT(buyer,  amt1);
        _dealUSDT(buyer2, amt2);

        _buy(buyer,  amt1);
        _buy(buyer2, amt2);

        assertEq(saleToken.balanceOf(buyer),  preview1);
        assertEq(saleToken.balanceOf(buyer2), preview2);
        assertEq(presale.totalTokensSold(), preview1 + preview2);
    }

    // ── buy: same buyer purchases twice ───────────────────────────────────────

    function test_fork_buyWithUSDT_twiceSameUser() public {
        uint256 amt1 = 100e6;
        uint256 amt2 = 200e6;

        uint256 preview1 = presale.previewBuyWithToken(USDT_ADDR, amt1);

        _dealUSDT(buyer, amt1 + amt2);

        _buy(buyer, amt1);
        assertEq(saleToken.balanceOf(buyer), preview1);

        uint256 preview2 = presale.previewBuyWithToken(USDT_ADDR, amt2);
        _buy(buyer, amt2);
        assertEq(saleToken.balanceOf(buyer), preview1 + preview2);
    }

    // ── allowance guard ───────────────────────────────────────────────────────

    /// If presaleWallet revokes allowance mid-sale, every subsequent purchase fails.
    function test_fork_revertsWhenPresaleWalletRevokesAllowance() public {
        // Revoke the allowance setUp granted
        vm.prank(presaleWallet);
        saleToken.approve(address(presale), 0);

        _dealUSDT(buyer, 100e6);
        vm.startPrank(buyer);
        usdt.approve(address(presale), 100e6);
        vm.expectRevert(); // ERC20InsufficientAllowance
        presale.buyWithToken(USDT_ADDR, 100e6);
        vm.stopPrank();
    }

    /// After allowance is restored, purchases work again.
    function test_fork_worksAfterAllowanceRestored() public {
        // Revoke then restore
        vm.startPrank(presaleWallet);
        saleToken.approve(address(presale), 0);
        saleToken.approve(address(presale), type(uint256).max);
        vm.stopPrank();

        uint256 amount  = 100e6;
        uint256 preview = presale.previewBuyWithToken(USDT_ADDR, amount);

        _dealUSDT(buyer, amount);
        _buy(buyer, amount);

        assertEq(saleToken.balanceOf(buyer), preview);
    }

    // ── reverts ───────────────────────────────────────────────────────────────

    function test_fork_revertsZeroAmount() public {
        vm.prank(buyer);
        vm.expectRevert(Presale.ZeroAmount.selector);
        presale.buyWithToken(USDT_ADDR, 0);
    }

    function test_fork_revertsUnsupportedToken() public {
        vm.prank(buyer);
        vm.expectRevert(Presale.UnsupportedToken.selector);
        presale.buyWithToken(address(0xdead), 100e6);
    }

    function test_fork_revertsWithoutApproval() public {
        _dealUSDT(buyer, 100e6);
        vm.prank(buyer);
        vm.expectRevert();
        presale.buyWithToken(USDT_ADDR, 100e6);
    }

    function test_fork_revertsInsufficientBalance() public {
        // buyer has 0 USDT but approves
        vm.startPrank(buyer);
        usdt.approve(address(presale), 100e6);
        vm.expectRevert();
        presale.buyWithToken(USDT_ADDR, 100e6);
        vm.stopPrank();
    }

    // ── ETH purchases ─────────────────────────────────────────────────────────

    function test_fork_buyWithETH_receivesTokens() public {
        uint256 ethAmount = 0.1 ether;
        uint256 preview   = presale.previewBuyWithETH(ethAmount);

        vm.deal(buyer, ethAmount);
        vm.prank(buyer);
        presale.buyWithETH{value: ethAmount}();

        assertGt(saleToken.balanceOf(buyer), 0);
        assertEq(saleToken.balanceOf(buyer), preview);
    }

    function test_fork_buyWithETH_forwardsETHToFundsWallet() public {
        uint256 ethAmount = 0.5 ether;
        uint256 before    = fundsWallet.balance;

        vm.deal(buyer, ethAmount);
        vm.prank(buyer);
        presale.buyWithETH{value: ethAmount}();

        assertEq(fundsWallet.balance, before + ethAmount);
        assertEq(buyer.balance, 0);
    }

    function test_fork_buyWithETH_updatesAccounting() public {
        uint256 ethAmount    = 1 ether;
        uint256 soldBefore   = presale.totalTokensSold();
        uint256 raisedBefore = presale.totalRaisedETH();
        uint256 preview      = presale.previewBuyWithETH(ethAmount);

        vm.deal(buyer, ethAmount);
        vm.prank(buyer);
        presale.buyWithETH{value: ethAmount}();

        assertEq(presale.totalTokensSold(), soldBefore + preview);
        assertEq(presale.totalRaisedETH(),  raisedBefore + ethAmount);
    }

    function test_fork_buyWithETH_previewMatchesBuy() public {
        uint256 ethAmount = 0.25 ether;
        uint256 preview   = presale.previewBuyWithETH(ethAmount);

        vm.deal(buyer, ethAmount);
        vm.prank(buyer);
        presale.buyWithETH{value: ethAmount}();

        assertEq(saleToken.balanceOf(buyer), preview);
    }

    function test_fork_buyWithETH_revertsZeroValue() public {
        vm.prank(buyer);
        vm.expectRevert(Presale.ZeroAmount.selector);
        presale.buyWithETH{value: 0}();
    }

    function test_fork_buyWithETH_revertsAccidentalSend() public {
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        (bool ok, bytes memory data) = address(presale).call{value: 1 ether}("");
        assertFalse(ok);
        assertEq(bytes4(data), Presale.AccidentalETHSend.selector);
    }

    function testFuzz_fork_buyWithETH(uint256 ethAmount) public {
        // 0.001 ETH – 10 ETH, stays inside the cap
        ethAmount = bound(ethAmount, 0.001 ether, 10 ether);

        uint256 preview = presale.previewBuyWithETH(ethAmount);
        if (presale.totalTokensSold() + preview > presale.MAX_TOKENS()) return;

        vm.deal(buyer, ethAmount);
        vm.prank(buyer);
        presale.buyWithETH{value: ethAmount}();

        assertEq(saleToken.balanceOf(buyer), preview);
    }

    // ── $0.01 token price ─────────────────────────────────────────────────────
    // tokenPrice = 10_000  (6-decimal USD → $0.01 per token)
    // Formula:  tokens = (usdValue * 1e18) / tokenPrice
    //   100 USDT  → $100 USD  → 100e6 * 1e18 / 10_000  = 10,000  tokens
    //   1000 USDT → $1000 USD → 1000e6 * 1e18 / 10_000 = 100,000 tokens

    uint256 constant PRICE_001 = 10_000; // $0.01

    modifier atOneCentPrice() {
        vm.prank(presale.owner());
        presale.setTokenPrice(PRICE_001);
        _;
    }

    function test_fork_price001_100USDT_givesCorrectTokens() public atOneCentPrice {
        uint256 amount = 100e6; // 100 USDT

        // Mirror the contract's own formula using the live feed price
        uint256 usdtPrice = presale.getUSDTPrice();                    // 8-dec Chainlink
        uint256 usdValue  = (amount * usdtPrice) / 1e8;               // 6-dec USD
        uint256 expected  = (usdValue * 1e18) / PRICE_001;            // 18-dec tokens

        console.log("USDT/USD price (8-dec):", usdtPrice);
        console.log("USD value   (6-dec)   :", usdValue);
        console.log("Expected tokens       :", expected);

        uint256 preview = presale.previewBuyWithToken(USDT_ADDR, amount);
        assertEq(preview, expected, "preview mismatch");

        _dealUSDT(buyer, amount);
        _buy(buyer, amount);

        assertEq(saleToken.balanceOf(buyer), expected, "balance mismatch");
    }

    function test_fork_price001_1000USDT_givesCorrectTokens() public atOneCentPrice {
        uint256 amount = 1_000e6; // 1,000 USDT

        uint256 usdtPrice = presale.getUSDTPrice();
        uint256 usdValue  = (amount * usdtPrice) / 1e8;
        uint256 expected  = (usdValue * 1e18) / PRICE_001;

        console.log("USDT/USD price (8-dec):", usdtPrice);
        console.log("USD value   (6-dec)   :", usdValue);
        console.log("Expected tokens       :", expected);

        uint256 preview = presale.previewBuyWithToken(USDT_ADDR, amount);
        assertEq(preview, expected, "preview mismatch");

        _dealUSDT(buyer, amount);
        _buy(buyer, amount);

        assertEq(saleToken.balanceOf(buyer), expected, "balance mismatch");
    }

    function test_fork_price001_ETH_correctTokens() public atOneCentPrice {
        uint256 ethAmount = 1 ether;

        // Use the live ETH/USD feed price to compute expected tokens
        uint256 ethPrice  = presale.getETHPrice();                    // 8-dec
        uint256 usdValue  = (ethAmount * ethPrice) / 1e20;           // 6-dec USD
        uint256 expected  = (usdValue * 1e18) / PRICE_001;           // 18-dec tokens

        console.log("ETH/USD price (8-dec) :", ethPrice);
        console.log("USD value   (6-dec)   :", usdValue);
        console.log("Expected tokens       :", expected);

        uint256 preview = presale.previewBuyWithETH(ethAmount);
        assertEq(preview, expected, "preview mismatch");

        vm.deal(buyer, ethAmount);
        vm.prank(buyer);
        presale.buyWithETH{value: ethAmount}();

        assertEq(saleToken.balanceOf(buyer), expected, "balance mismatch");
    }

    function test_fork_price001_previewAlwaysMatchesBuy() public atOneCentPrice {
        uint256 amount  = 500e6; // 500 USDT → 50,000 tokens
        uint256 preview = presale.previewBuyWithToken(USDT_ADDR, amount);

        _dealUSDT(buyer, amount);
        _buy(buyer, amount);

        assertEq(saleToken.balanceOf(buyer), preview);
    }

    // ── decimal conversion audit ──────────────────────────────────────────────
    //
    // Full pipeline:
    //   Step 1  USDT (6-dec)  ×  USDT/USD price (8-dec)  /  1e8  =  USD value (6-dec)
    //   Step 2  USD value (6-dec)  ×  1e18  /  tokenPrice (6-dec)  =  tokens (18-dec)
    //
    // Why the divisors work:
    //   Step 1: price is in units of [USD_8dec / USDT_6dec], so
    //           USDT_6dec × USD_8dec / USDT_6dec = USD_8dec; divide by 1e8 → USD_6dec  ✓
    //   Step 2: USD_6dec × 1e18 / USD_6dec = dimensionless × 1e18 = tokens_18dec       ✓

    function test_fork_decimalConversion_step1_usdtToUSD() public view {
        uint256 usdtPrice = presale.getUSDTPrice(); // 8-dec from Chainlink

        // 100 USDT (6-dec) → USD value (6-dec)
        uint256 amount   = 100e6;
        uint256 usdValue = (amount * usdtPrice) / 1e8;

        // Manual sanity: usdValue should be close to 100_000_000 ($100 in 6-dec)
        // At $0.9991 feed price: 100e6 * 99910000 / 1e8 = 99910000 ≈ $99.91
        console.log("USDT/USD price (8-dec)     :", usdtPrice);
        console.log("100 USDT usdValue (6-dec)  :", usdValue);
        console.log("100 USDT usdValue whole $   :", usdValue / 1e6);
        console.log("100 USDT usdValue cents     :", (usdValue % 1e6) / 1e4);

        // The result must equal (amount * usdtPrice) / 1e8 — no rounding beyond truncation
        assertEq(usdValue, (amount * usdtPrice) / 1e8);

        // usdValue must be within 0.5% of the nominal $100 (feed peg is tight)
        uint256 nominal = 100e6; // $100 in 6-dec
        assertGt(usdValue, nominal * 995 / 1000, "usdValue too low (>0.5% depeg)");
        assertLt(usdValue, nominal * 1005 / 1000, "usdValue too high (>0.5% depeg)");
    }

    function test_fork_decimalConversion_step2_usdToTokens() public view {
        uint256 tp = presale.tokenPrice(); // 6-dec

        // $100 USD (6-dec) at current token price
        uint256 usdValue = 100e6;
        uint256 tokens   = (usdValue * 1e18) / tp;

        console.log("tokenPrice (6-dec)     :", tp);
        console.log("$100 USD -> tokens (18-dec):", tokens);

        // Manual: at $0.05/token → 100 / 0.05 = 2,000 tokens
        //         at $0.01/token → 100 / 0.01 = 10,000 tokens
        // Verify dimension: tokens must be in 18-dec (>= 1e18 for $1 USD at any sane price)
        assertEq(tokens, (usdValue * 1e18) / tp);
        assertGt(tokens, 0);

        // Inverse check: tokens × tokenPrice / 1e18 should recover usdValue (within truncation)
        uint256 recovered = (tokens * tp) / 1e18;
        // recovered ≤ usdValue (truncation only ever removes, never adds)
        assertLe(recovered, usdValue);
        // truncation loss is at most (tokenPrice - 1) in the smallest 6-dec unit
        assertGe(recovered, usdValue - (tp - 1) / 1e18 - 1);
    }

    function test_fork_decimalConversion_fullPipeline_multipleAmounts() public view {
        uint256 usdtPrice = presale.getUSDTPrice();
        uint256 tp        = presale.tokenPrice();

        uint256[5] memory amounts = [
            uint256(1e6),       //       1 USDT
            uint256(10e6),      //      10 USDT
            uint256(100e6),     //     100 USDT
            uint256(1_000e6),   //   1,000 USDT
            uint256(10_000e6)   //  10,000 USDT
        ];

        console.log("USDT/USD price (8-dec):", usdtPrice);
        console.log("tokenPrice    (6-dec) :", tp);
        console.log("---");

        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 amount   = amounts[i];
            uint256 usdValue = (amount * usdtPrice) / 1e8;   // Step 1
            uint256 tokens   = (usdValue * 1e18) / tp;       // Step 2
            uint256 preview  = presale.previewBuyWithToken(USDT_ADDR, amount);

            console.log("USDT in (6-dec) :", amount);
            console.log("  usdValue      :", usdValue);
            console.log("  tokens        :", tokens);

            // Contract must produce the identical result
            assertEq(preview, tokens, "preview != manual for this amount");

            // Step 1 precision: truncation loss < 1 micro-USD per unit of USDT input
            uint256 lossStep1 = amount - ((usdValue * 1e8) / usdtPrice);
            assertLt(lossStep1, 2, "step-1 truncation exceeds 1 micro-USDT");

            // Step 2 precision: recovering USD from tokens loses at most (tokenPrice-1) dust
            uint256 recoveredUSD = (tokens * tp) / 1e18;
            assertLe(recoveredUSD, usdValue);
            assertGe(recoveredUSD + tp / 1e18 + 1, usdValue, "step-2 truncation too large");
        }
    }

    function test_fork_decimalConversion_contractOutputMatchesManual() public {
        uint256 usdtPrice = presale.getUSDTPrice();
        uint256 tp        = presale.tokenPrice();
        uint256 amount    = 123_456_789; // arbitrary non-round USDT amount (6-dec)

        // Manual pipeline — same as the contract's internal functions
        uint256 usdValue       = (amount * usdtPrice) / 1e8;
        uint256 expectedTokens = (usdValue * 1e18) / tp;

        uint256 preview = presale.previewBuyWithToken(USDT_ADDR, amount);
        assertEq(preview, expectedTokens, "preview != manual");

        deal(address(saleToken), presaleWallet, presale.MAX_TOKENS());
        _dealUSDT(buyer, amount);
        _buy(buyer, amount);

        assertEq(saleToken.balanceOf(buyer), expectedTokens, "balance != manual");
    }

    // ── fuzz USDT ─────────────────────────────────────────────────────────────

    function testFuzz_fork_buyWithUSDT(uint256 amount) public {
        // 1 USDT minimum, 50k USDT upper — stays well inside the 10M token cap
        amount = bound(amount, 1e6, 50_000e6);

        uint256 preview = presale.previewBuyWithToken(USDT_ADDR, amount);
        if (presale.totalTokensSold() + preview > presale.MAX_TOKENS()) return;

        _dealUSDT(buyer, amount);
        _buy(buyer, amount);

        assertEq(saleToken.balanceOf(buyer), preview);
    }
}
