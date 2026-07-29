// SPDX-License-Identifier: MIT
pragma solidity 0.8.31;

import {Test, console} from "forge-std/Test.sol";
import {TeamVesting} from "../../contracts/TeamVesting.sol";
import {MockERC20} from "../../contracts/MockERC20.sol";

// ─────────────────────────────────────────────────────────────────────────────
// Base fixture
//   1. Deploy TeamVesting  (token + pool wired in constructor)
//   2. Mint tokens directly to vesting contract
// ─────────────────────────────────────────────────────────────────────────────
contract VestingBase is Test {
    TeamVesting internal vesting;
    MockERC20   internal token;

    address internal owner    = makeAddr("owner");
    address internal pool     = makeAddr("pool");    // dummy EOA — depositWithSlippage is mocked
    address internal claiming = makeAddr("claiming"); // dummy EOA — not called in constructor

    uint256 internal constant ALLOCATION = 23_500_000 * 1e18;
    uint256 internal constant CLIFF      = 3 * 365 days;
    uint256 internal constant MONTHS     = 24;
    uint256 internal constant MONTH      = 30 days;

    function setUp() public virtual {
        token = new MockERC20("CashGames", "CASH", 18);

        // Predict the vesting address so we can approve before deploying.
        address predictedVesting = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        token.mint(address(this), ALLOCATION);
        token.approve(predictedVesting, ALLOCATION);

        // Pool is an EOA in unit tests; mock depositWithSlippage so tokens stay in TeamVesting.
        vm.mockCall(
            pool,
            abi.encodeWithSignature("depositWithSlippage(address,uint256,address,uint256)"),
            abi.encode(uint256(0))
        );

        vesting = new TeamVesting(owner, address(token), pool, claiming, CLIFF, MONTH, ALLOCATION);
    }

    function _warpMonths(uint256 n) internal {
        vm.warp(vesting.vestingStart() + n * MONTH);
    }

    function _claim() internal returns (uint256) {
        uint256 before = token.balanceOf(owner);
        vm.prank(owner);
        vesting.claim();
        return token.balanceOf(owner) - before;
    }
}

// =============================================================================
// UNIT TESTS
// =============================================================================
contract TeamVestingUnitTest is VestingBase {

    // ── constructor ───────────────────────────────────────────────────────────

    function test_constructor_setsVestingStart() public view {
        assertEq(vesting.vestingStart(), block.timestamp + CLIFF);
    }

    function test_constructor_setsTotalAllocation() public view {
        assertEq(vesting.totalAllocation(), ALLOCATION);
    }

    function test_constructor_setsMonthlyAmount() public view {
        assertEq(vesting.monthlyAmount(), ALLOCATION / MONTHS);
    }

    function test_constructor_setsToken() public view {
        assertEq(address(vesting.token()), address(token));
    }

    function test_constructor_setsPool() public view {
        assertEq(address(vesting.pool()), pool);
    }

    function test_constructor_revertsZeroToken() public {
        vm.expectRevert(TeamVesting.ZeroAddress.selector);
        new TeamVesting(owner, address(0), pool, claiming, CLIFF, MONTH, ALLOCATION);
    }

    function test_constructor_revertsZeroPool() public {
        vm.expectRevert(TeamVesting.ZeroAddress.selector);
        new TeamVesting(owner, address(token), address(0), claiming, CLIFF, MONTH, ALLOCATION);
    }

    function test_constructor_revertsZeroClaiming() public {
        vm.expectRevert(TeamVesting.ZeroAddress.selector);
        new TeamVesting(owner, address(token), pool, address(0), CLIFF, MONTH, ALLOCATION);
    }

    function test_constructor_revertsZeroAllocation() public {
        vm.expectRevert(TeamVesting.ZeroAmount.selector);
        new TeamVesting(owner, address(token), pool, claiming, CLIFF, MONTH, 0);
    }

    // ── claim — pre-conditions ────────────────────────────────────────────────

    function test_claim_revertsVestingNotStarted() public {
        vm.expectRevert(TeamVesting.VestingNotStarted.selector);
        vm.prank(owner);
        vesting.claim();
    }

    function test_claim_revertsNothingToClaim_exactlyAtVestingStart() public {
        vm.warp(vesting.vestingStart());
        vm.expectRevert(TeamVesting.NothingToClaim.selector);
        vm.prank(owner);
        vesting.claim();
    }

    function test_claim_revertsNonOwner() public {
        _warpMonths(1);
        vm.expectRevert();
        vesting.claim(); // no prank — caller is address(this)
    }

    // ── double-claim protection ───────────────────────────────────────────────

    function test_claim_revertsOnDoubleClaim_sameMonth() public {
        _warpMonths(1);
        vm.prank(owner); vesting.claim();
        vm.expectRevert(TeamVesting.NothingToClaim.selector);
        vm.prank(owner); vesting.claim();
    }

    function test_claim_revertsOnDoubleClaim_middleOfSchedule() public {
        _warpMonths(5);
        vm.prank(owner); vesting.claim();
        vm.expectRevert(TeamVesting.NothingToClaim.selector);
        vm.prank(owner); vesting.claim();
    }

    function test_claim_revertsOnDoubleClaim_afterFullVesting() public {
        _warpMonths(MONTHS);
        vm.prank(owner); vesting.claim();
        vm.expectRevert(TeamVesting.NothingToClaim.selector);
        vm.prank(owner); vesting.claim();
    }

    // ── equal monthly amounts ─────────────────────────────────────────────────

    function test_claim_month1_exactMonthlyAmount() public {
        _warpMonths(1);
        assertEq(_claim(), ALLOCATION / MONTHS);
    }

    function test_claim_everyMonthHasSameAmount_months1to23() public {
        uint256 expected = ALLOCATION / MONTHS;
        for (uint256 m = 1; m <= 23; m++) {
            _warpMonths(m);
            assertEq(_claim(), expected);
        }
    }

    function test_claim_month24_drainsContractToZero() public {
        for (uint256 m = 1; m <= 23; m++) {
            _warpMonths(m);
            _claim();
        }
        _warpMonths(24);
        _claim();
        assertEq(token.balanceOf(address(vesting)), 0);
    }

    function test_claim_allMonths_sumEqualsAllocation() public {
        uint256 total;
        for (uint256 m = 1; m <= MONTHS; m++) {
            _warpMonths(m);
            total += _claim();
        }
        assertEq(total, ALLOCATION);
    }

    // ── missed months / catch-up ──────────────────────────────────────────────

    function test_claim_skipped3Months_getsAllAtOnce() public {
        _warpMonths(3);
        assertEq(_claim(), 3 * (ALLOCATION / MONTHS));
        assertEq(vesting.monthsClaimed(), 3);
    }

    function test_claim_skippedAllMonths_drainsFull() public {
        _warpMonths(MONTHS + 5);
        assertEq(_claim(), ALLOCATION);
        assertEq(token.balanceOf(address(vesting)), 0);
    }

    function test_claim_irregularCatchUp_sumEqualsAllocation() public {
        uint256 total;
        _warpMonths(3);      total += _claim();
        _warpMonths(7);      total += _claim();
        _warpMonths(MONTHS); total += _claim();
        assertEq(total, ALLOCATION);
        assertEq(token.balanceOf(address(vesting)), 0);
    }

    // ── monthsClaimed tracking ────────────────────────────────────────────────

    function test_monthsClaimed_incrementsCorrectly() public {
        _warpMonths(1);      vm.prank(owner); vesting.claim();
        assertEq(vesting.monthsClaimed(), 1);
        _warpMonths(5);      vm.prank(owner); vesting.claim();
        assertEq(vesting.monthsClaimed(), 5);
        _warpMonths(MONTHS); vm.prank(owner); vesting.claim();
        assertEq(vesting.monthsClaimed(), MONTHS);
    }

    // ── claim event ───────────────────────────────────────────────────────────

    function test_claim_emitsCorrectEvent() public {
        _warpMonths(2);
        uint256 expected = 2 * (ALLOCATION / MONTHS);
        vm.expectEmit(true, false, false, true);
        emit TeamVesting.Claimed(owner, expected, 2);
        vm.prank(owner);
        vesting.claim();
    }

    // ── views ─────────────────────────────────────────────────────────────────

    function test_vestedMonths_zeroBeforeCliff()        public view { assertEq(vesting.vestedMonths(), 0); }
    function test_vestedMonths_zeroAtExactCliffStart()  public { vm.warp(vesting.vestingStart()); assertEq(vesting.vestedMonths(), 0); }
    function test_vestedMonths_oneAfterOneMonth()       public { _warpMonths(1); assertEq(vesting.vestedMonths(), 1); }
    function test_vestedMonths_capsAt24()               public { _warpMonths(MONTHS + 10); assertEq(vesting.vestedMonths(), MONTHS); }

    function test_claimable_zeroBeforeCliff()           public view { assertEq(vesting.claimable(), 0); }
    function test_claimable_oneMonthAmount()            public { _warpMonths(1); assertEq(vesting.claimable(), ALLOCATION / MONTHS); }
    function test_claimable_zeroAfterClaim()            public { _warpMonths(1); _claim(); assertEq(vesting.claimable(), 0); }
    function test_claimable_accumulatesSkippedMonths()  public { _warpMonths(5); assertEq(vesting.claimable(), 5 * (ALLOCATION / MONTHS)); }

    function test_locked_fullAllocationBeforeAnyCliff() public view { assertEq(vesting.locked(), ALLOCATION); }
    function test_locked_decreasesAfterClaim()          public { _warpMonths(1); _claim(); assertEq(vesting.locked(), ALLOCATION - ALLOCATION / MONTHS); }
    function test_locked_zeroAfterAllClaimed()          public { _warpMonths(MONTHS); _claim(); assertEq(vesting.locked(), 0); }
}

// =============================================================================
// FUZZ TESTS
// =============================================================================
contract TeamVestingFuzzTest is Test {
    MockERC20 internal token;

    address internal owner    = makeAddr("owner");
    address internal pool     = makeAddr("pool");
    address internal claiming = makeAddr("claiming");

    uint256 internal constant CLIFF  = 3 * 365 days;
    uint256 internal constant MONTH  = 30 days;
    uint256 internal constant MONTHS = 24;

    function setUp() public {
        token = new MockERC20("CashGames", "CASH", 18);
    }

    function _deploy(uint256 alloc) internal returns (TeamVesting v) {
        address predictedAddr = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        token.mint(address(this), alloc);
        token.approve(predictedAddr, alloc);

        vm.mockCall(
            pool,
            abi.encodeWithSignature("depositWithSlippage(address,uint256,address,uint256)"),
            abi.encode(uint256(0))
        );

        v = new TeamVesting(owner, address(token), pool, claiming, CLIFF, MONTH, alloc);
    }

    function _warpMonths(TeamVesting v, uint256 n) internal {
        vm.warp(v.vestingStart() + n * MONTH);
    }

    function _claim(TeamVesting v) internal returns (uint256) {
        uint256 before = token.balanceOf(owner);
        vm.prank(owner);
        v.claim();
        return token.balanceOf(owner) - before;
    }

    function testFuzz_allMonthsSum_equalsAllocation(uint256 alloc) public {
        alloc = bound(alloc, MONTHS, 1_000_000_000 * 1e18);
        TeamVesting v = _deploy(alloc);
        uint256 total;
        for (uint256 m = 1; m <= MONTHS; m++) {
            _warpMonths(v, m);
            total += _claim(v);
        }
        assertEq(total, alloc);
        assertEq(token.balanceOf(address(v)), 0);
    }

    function testFuzz_months1to23_equalAmounts(uint256 alloc) public {
        alloc = bound(alloc, MONTHS, 1_000_000_000 * 1e18);
        TeamVesting v = _deploy(alloc);
        uint256 expected = alloc / MONTHS;
        for (uint256 m = 1; m <= 23; m++) {
            _warpMonths(v, m);
            assertEq(_claim(v), expected);
        }
    }

    function testFuzz_singleClaim_afterFullVesting(uint256 alloc) public {
        alloc = bound(alloc, MONTHS, 1_000_000_000 * 1e18);
        TeamVesting v = _deploy(alloc);
        _warpMonths(v, MONTHS + 3);
        assertEq(_claim(v), alloc);
        assertEq(token.balanceOf(address(v)), 0);
    }

    function testFuzz_irregularClaims_sumEqualsAllocation(uint256 alloc, uint256 bp1, uint256 bp2) public {
        alloc = bound(alloc, MONTHS, 1_000_000_000 * 1e18);
        bp1   = bound(bp1, 1, MONTHS - 2);
        bp2   = bound(bp2, bp1 + 1, MONTHS - 1);
        TeamVesting v = _deploy(alloc);
        uint256 total;
        _warpMonths(v, bp1);    total += _claim(v);
        _warpMonths(v, bp2);    total += _claim(v);
        _warpMonths(v, MONTHS); total += _claim(v);
        assertEq(total, alloc);
        assertEq(token.balanceOf(address(v)), 0);
    }

    function testFuzz_noDoubleClaim(uint256 alloc, uint256 claimAtMonth) public {
        alloc        = bound(alloc, MONTHS, 1_000_000_000 * 1e18);
        claimAtMonth = bound(claimAtMonth, 1, MONTHS);
        TeamVesting v = _deploy(alloc);
        _warpMonths(v, claimAtMonth);
        vm.prank(owner); v.claim();
        vm.expectRevert(TeamVesting.NothingToClaim.selector);
        vm.prank(owner); v.claim();
    }

    function testFuzz_claimableMatchesClaim(uint256 alloc, uint256 claimAtMonth) public {
        alloc        = bound(alloc, MONTHS, 1_000_000_000 * 1e18);
        claimAtMonth = bound(claimAtMonth, 1, MONTHS);
        TeamVesting v = _deploy(alloc);
        _warpMonths(v, claimAtMonth);
        assertEq(v.claimable(), _claim(v));
    }
}
