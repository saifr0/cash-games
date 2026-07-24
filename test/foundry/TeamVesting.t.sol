// SPDX-License-Identifier: MIT
pragma solidity 0.8.31;

import {Test, console} from "forge-std/Test.sol";
import {TeamVesting} from "../../contracts/TeamVesting.sol";
import {MockERC20} from "../../contracts/MockERC20.sol";

// ─────────────────────────────────────────────────────────────────────────────
// Base fixture  (mirrors real deploy order)
//   1. Deploy TeamVesting  (no token yet)
//   2. Mint tokens directly to vesting contract  (simulates CashGames mint)
//   3. Call setToken()
// ─────────────────────────────────────────────────────────────────────────────
contract VestingBase is Test {
    TeamVesting internal vesting;
    MockERC20   internal token;

    address internal owner       = makeAddr("owner");
    address internal beneficiary = makeAddr("beneficiary");

    uint256 internal constant ALLOCATION = 23_500_000 * 1e18;
    uint256 internal constant CLIFF      = 3 * 365 days;
    uint256 internal constant MONTHS     = 24;
    uint256 internal constant MONTH      = 30 days;

    function setUp() public virtual {
        // Step 1 — deploy vesting (token unknown)
        vesting = new TeamVesting(beneficiary, owner, CLIFF, MONTH, ALLOCATION);

        // Step 2 — mint tokens directly to vesting (simulates CashGames constructor)
        token = new MockERC20("CashGames", "CASH", 18);
        token.mint(address(vesting), ALLOCATION);

        // Step 3 — wire token address
        vm.prank(owner);
        vesting.setToken(address(token));
    }

    function _warpMonths(uint256 n) internal {
        vm.warp(vesting.vestingStart() + n * MONTH);
    }

    function _claim() internal returns (uint256) {
        uint256 before = token.balanceOf(beneficiary);
        vm.prank(beneficiary);
        vesting.claim();
        return token.balanceOf(beneficiary) - before;
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

    function test_constructor_setsBeneficiary() public view {
        assertEq(vesting.beneficiary(), beneficiary);
    }

    function test_constructor_setsTotalAllocation() public view {
        assertEq(vesting.totalAllocation(), ALLOCATION);
    }

    function test_constructor_setsMonthlyAmount() public view {
        assertEq(vesting.monthlyAmount(), ALLOCATION / MONTHS);
    }

    function test_constructor_revertsZeroBeneficiary() public {
        vm.expectRevert(TeamVesting.ZeroAddress.selector);
        new TeamVesting(address(0), owner, CLIFF, MONTH, ALLOCATION);
    }

    function test_constructor_revertsZeroAllocation() public {
        vm.expectRevert(TeamVesting.ZeroAmount.selector);
        new TeamVesting(beneficiary, owner, CLIFF, MONTH, 0);
    }

    // ── setToken ──────────────────────────────────────────────────────────────

    function test_setToken_setsAddress() public view {
        assertEq(address(vesting.token()), address(token));
    }

    function test_setToken_emitsEvent() public {
        TeamVesting v = new TeamVesting(beneficiary, owner, CLIFF, MONTH, ALLOCATION);
        vm.expectEmit(true, false, false, false);
        emit TeamVesting.TokenSet(address(token));
        vm.prank(owner);
        v.setToken(address(token));
    }

    function test_setToken_revertsSecondCall() public {
        vm.prank(owner);
        vm.expectRevert(TeamVesting.TokenAlreadySet.selector);
        vesting.setToken(address(token));
    }

    function test_setToken_revertsZeroAddress() public {
        TeamVesting v = new TeamVesting(beneficiary, owner, CLIFF, MONTH, ALLOCATION);
        vm.prank(owner);
        vm.expectRevert(TeamVesting.ZeroAddress.selector);
        v.setToken(address(0));
    }

    function test_setToken_revertsNonOwner() public {
        TeamVesting v = new TeamVesting(beneficiary, owner, CLIFF, MONTH, ALLOCATION);
        vm.expectRevert();
        v.setToken(address(token));
    }

    // ── claim — pre-conditions ────────────────────────────────────────────────

    function test_claim_revertsTokenNotSet() public {
        TeamVesting v = new TeamVesting(beneficiary, owner, CLIFF, MONTH, ALLOCATION);
        vm.warp(v.vestingStart() + MONTH);
        vm.expectRevert(TeamVesting.TokenNotSet.selector);
        vm.prank(beneficiary);
        v.claim();
    }

    function test_claim_revertsVestingNotStarted() public {
        vm.expectRevert(TeamVesting.VestingNotStarted.selector);
        vm.prank(beneficiary);
        vesting.claim();
    }

    function test_claim_revertsNothingToClaim_exactlyAtVestingStart() public {
        vm.warp(vesting.vestingStart());
        vm.expectRevert(TeamVesting.NothingToClaim.selector);
        vm.prank(beneficiary);
        vesting.claim();
    }

    // ── double-claim protection ───────────────────────────────────────────────

    function test_claim_revertsOnDoubleClaim_sameMonth() public {
        _warpMonths(1);
        vm.prank(beneficiary); vesting.claim();
        vm.expectRevert(TeamVesting.NothingToClaim.selector);
        vm.prank(beneficiary); vesting.claim();
    }

    function test_claim_revertsOnDoubleClaim_middleOfSchedule() public {
        _warpMonths(5);
        vm.prank(beneficiary); vesting.claim();
        vm.expectRevert(TeamVesting.NothingToClaim.selector);
        vm.prank(beneficiary); vesting.claim();
    }

    function test_claim_revertsOnDoubleClaim_afterFullVesting() public {
        _warpMonths(MONTHS);
        vm.prank(beneficiary); vesting.claim();
        vm.expectRevert(TeamVesting.NothingToClaim.selector);
        vm.prank(beneficiary); vesting.claim();
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
        _warpMonths(1);      vm.prank(beneficiary); vesting.claim();
        assertEq(vesting.monthsClaimed(), 1);
        _warpMonths(5);      vm.prank(beneficiary); vesting.claim();
        assertEq(vesting.monthsClaimed(), 5);
        _warpMonths(MONTHS); vm.prank(beneficiary); vesting.claim();
        assertEq(vesting.monthsClaimed(), MONTHS);
    }

    // ── claim event ───────────────────────────────────────────────────────────

    function test_claim_emitsCorrectEvent() public {
        _warpMonths(2);
        uint256 expected = 2 * (ALLOCATION / MONTHS);
        vm.expectEmit(true, false, false, true);
        emit TeamVesting.Claimed(beneficiary, expected, 2);
        vm.prank(beneficiary);
        vesting.claim();
    }

    // ── setBeneficiary ────────────────────────────────────────────────────────

    function test_setBeneficiary_updatesAddress() public {
        address newBen = makeAddr("newBen");
        vm.prank(owner);
        vesting.setBeneficiary(newBen);
        assertEq(vesting.beneficiary(), newBen);
    }

    function test_setBeneficiary_revertsZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(TeamVesting.ZeroAddress.selector);
        vesting.setBeneficiary(address(0));
    }

    function test_setBeneficiary_revertsNonOwner() public {
        vm.expectRevert();
        vesting.setBeneficiary(makeAddr("x"));
    }

    function test_setBeneficiary_newBeneficiaryReceivesNextClaim() public {
        address newBen = makeAddr("newBen");
        vm.prank(owner);
        vesting.setBeneficiary(newBen);
        _warpMonths(1);
        vm.prank(newBen);
        vesting.claim();
        assertEq(token.balanceOf(newBen),      ALLOCATION / MONTHS);
        assertEq(token.balanceOf(beneficiary), 0);
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

    address internal owner       = makeAddr("owner");
    address internal beneficiary = makeAddr("beneficiary");

    uint256 internal constant CLIFF  = 3 * 365 days;
    uint256 internal constant MONTH  = 30 days;
    uint256 internal constant MONTHS = 24;

    function setUp() public {
        token = new MockERC20("CashGames", "CASH", 18);
    }

    function _deploy(uint256 alloc) internal returns (TeamVesting v) {
        v = new TeamVesting(beneficiary, owner, CLIFF, MONTH, alloc);
        token.mint(address(v), alloc);
        vm.prank(owner);
        v.setToken(address(token));
    }

    function _warpMonths(TeamVesting v, uint256 n) internal {
        vm.warp(v.vestingStart() + n * MONTH);
    }

    function _claim(TeamVesting v) internal returns (uint256) {
        uint256 before = token.balanceOf(beneficiary);
        vm.prank(beneficiary);
        v.claim();
        return token.balanceOf(beneficiary) - before;
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
        vm.prank(beneficiary); v.claim();
        vm.expectRevert(TeamVesting.NothingToClaim.selector);
        vm.prank(beneficiary); v.claim();
    }

    function testFuzz_claimableMatchesClaim(uint256 alloc, uint256 claimAtMonth) public {
        alloc        = bound(alloc, MONTHS, 1_000_000_000 * 1e18);
        claimAtMonth = bound(claimAtMonth, 1, MONTHS);
        TeamVesting v = _deploy(alloc);
        _warpMonths(v, claimAtMonth);
        assertEq(v.claimable(), _claim(v));
    }
}
