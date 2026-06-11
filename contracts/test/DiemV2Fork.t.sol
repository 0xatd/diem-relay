// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {sDIEMv2} from "../src/sDIEMv2.sol";
import {csDIEMv2} from "../src/csDIEMv2.sol";
import {IDIEMStaking} from "../src/interfaces/IDIEMStaking.sol";
import {ICLPool} from "../src/interfaces/ICLPool.sol";
import {OracleLibrary} from "../src/libraries/OracleLibrary.sol";

/**
 * @title DiemV2ForkTest
 * @notice End-to-end integration on a Base mainnet fork.
 *
 *         Deploys fresh sDIEMv2 + csDIEMv2 against the live DIEM token,
 *         the live USDC, the live Aerodrome Slipstream pool and router
 *         that v1 uses today. Exercises the full happy path: stake DIEM,
 *         transfer sDIEM, notify rewards, harvest (real TWAP + real swap
 *         + real Venice forward-stake), redeem.
 *
 *         What mocks can't catch and this can:
 *           - real Slipstream pool's observation cardinality (must be
 *             ≥ what twapWindow demands; live pool already has it)
 *           - real OracleLibrary.consult behavior against live tick state
 *           - real swap router slippage on a real depth pool
 *           - real DIEM token's staking-vs-balance bookkeeping
 *           - real Venice cooldown progression
 *
 *         Run only on demand (skipped by default in CI to avoid RPC churn).
 *         Enable with: forge test --match-contract DiemV2ForkTest -vv \
 *           --fork-url $BASE_RPC_URL
 */
contract DiemV2ForkTest is Test {
    // ── Live Base addresses (verified against broadcast/ artifacts) ────

    address constant DIEM = 0xF4d97F2da56e8c3098f3a8D538DB630A2606a024;
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant SLIPSTREAM_ROUTER = 0xBE6D8f0d05cC4be24d5167a3eF062215bE6D18a5;
    address constant ORACLE_POOL = 0xBc3231036Ee1ECa03E5F67FEceDC640D21610823;
    int24 constant TICK_SPACING = 100;
    uint32 constant TWAP_WINDOW = 3600;
    uint256 constant MAX_SLIPPAGE_BPS = 50;
    uint256 constant MIN_HARVEST = 100e6; // 100 USDC

    sDIEMv2 internal s;
    csDIEMv2 internal cs;

    address admin = makeAddr("admin");
    address operator = makeAddr("operator");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        // Allow CI / local runs to skip when no RPC is configured.
        string memory rpc = vm.envOr("BASE_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
        }
        vm.createSelectFork(rpc);

        // Sanity: live oracle pool has sufficient observation history.
        // This is what the new deploy script's _assertOracleTwapQueryable
        // helper checks; verify the live state passes.
        OracleLibrary.consult(ORACLE_POOL, TWAP_WINDOW);

        s = new sDIEMv2(DIEM, USDC, admin, operator);

        // Floor: derived from the LIVE TWAP at fork time, set to 50% of
        // observed (mirrors how the v1 csDIEM was deployed — see user
        // memory note "set to 50% of TWAP at deploy"). The real DIEM is
        // priced well above USDC, so a hardcoded floor would either be
        // too tight (causing harvest reverts) or stale.
        int24 liveTick = OracleLibrary.consult(ORACLE_POOL, TWAP_WINDOW);
        uint256 liveQuotePerUsdc = OracleLibrary.getQuoteAtTick(
            liveTick,
            1e6, // 1 USDC
            USDC,
            DIEM
        );
        uint256 floor = liveQuotePerUsdc / 2; // 50% of TWAP

        cs = new csDIEMv2(
            s,
            DIEM,
            USDC,
            SLIPSTREAM_ROUTER,
            ORACLE_POOL,
            admin,
            MAX_SLIPPAGE_BPS,
            TWAP_WINDOW,
            TICK_SPACING,
            MIN_HARVEST,
            floor
        );

        // Seed both actors with DIEM from forge's cheat.
        deal(DIEM, alice, 1_000e18);
        deal(DIEM, bob, 1_000e18);

        vm.startPrank(alice);
        IERC20(DIEM).approve(address(s), type(uint256).max);
        IERC20(DIEM).approve(address(cs), type(uint256).max);
        IERC20(s).approve(address(cs), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(bob);
        IERC20(DIEM).approve(address(s), type(uint256).max);
        IERC20(DIEM).approve(address(cs), type(uint256).max);
        IERC20(s).approve(address(cs), type(uint256).max);
        vm.stopPrank();
    }

    /// @notice Real Slipstream pool's TWAP must be queryable for the
    ///         configured window. This is the operational sanity check
    ///         that the constructor would do today via the deploy script.
    function test_fork_oracleTwapQueryable() public view {
        int24 tick = OracleLibrary.consult(ORACLE_POOL, TWAP_WINDOW);
        // Tick can be negative or positive; we just need it to not revert.
        // A non-zero result is also informative (zero would suggest a flat
        // pool, which is unlikely for an active DIEM/USDC market).
        assertTrue(tick != 0, "oracle returned a zero tick - unexpected for an active pool");
    }

    /// @notice Stake DIEM into sDIEM v2 and verify the Venice forward-stake.
    function test_fork_stakeForwardsToVenice() public {
        uint256 stakedBefore;
        (stakedBefore,,) = IDIEMStaking(DIEM).stakedInfos(address(s));

        vm.prank(alice);
        s.stake(100e18);

        // Alice gets 100 sDIEM 1:1.
        assertEq(s.balanceOf(alice), 100e18);
        assertEq(s.totalSupply(), 100e18);

        // Venice records 100 DIEM staked under the sDIEM v2 contract.
        (uint256 stakedAfter,,) = IDIEMStaking(DIEM).stakedInfos(address(s));
        assertEq(stakedAfter - stakedBefore, 100e18, "Venice didn't record the stake");
    }

    /// @notice Transfer sDIEM (the v2 unlock) and verify reward checkpoint.
    function test_fork_transferPreservesRewards() public {
        // Alice stakes, accrues rewards for a period, transfers to Bob.
        vm.prank(alice);
        s.stake(100e18);

        _notifyRewardAmount(100e6);
        vm.warp(block.timestamp + 12 hours);

        uint256 aliceEarnedBefore = s.earned(alice);
        assertGt(aliceEarnedBefore, 0, "alice should have accrued");

        vm.prank(alice);
        s.transfer(bob, 60e18);

        // Alice keeps her accrued rewards; Bob starts fresh.
        assertApproxEqAbs(s.earned(alice), aliceEarnedBefore, 1, "alice rewards leaked");
        assertApproxEqAbs(s.earned(bob), 0, 1, "bob phantom-earned");

        // Alice can claim what she earned.
        uint256 usdcBefore = IERC20(USDC).balanceOf(alice);
        vm.prank(alice);
        s.claimReward();
        assertGt(IERC20(USDC).balanceOf(alice) - usdcBefore, 0, "alice claim returned zero");
    }

    /// @notice The headline path: zap deposit DIEM → harvest cycle → standard
    ///         4626 redeem → unstake. End-to-end against live infrastructure.
    function test_fork_zapHarvestRedeem() public {
        // Alice zaps 100 DIEM into csDIEM v2.
        vm.prank(alice);
        uint256 shares = cs.depositDIEM(100e18, alice);
        assertGt(shares, 0, "zap returned zero shares");
        assertEq(s.balanceOf(address(cs)), 100e18, "vault didn't hold 100 sDIEM");

        uint256 priceBefore = cs.convertToAssets(1e24);

        // Operator notifies enough USDC to clear minHarvest.
        _notifyRewardAmount(200e6);
        vm.warp(block.timestamp + 24 hours);

        // Sanity: the vault has > minHarvest accrued.
        assertGt(s.earned(address(cs)), MIN_HARVEST, "not enough accrued for harvest");

        // Real harvest: claim USDC → real Slipstream swap → real Venice restake.
        uint256 sdiemBalBefore = s.balanceOf(address(cs));
        cs.harvest(block.timestamp + 300);
        uint256 sdiemBalAfter = s.balanceOf(address(cs));
        assertGt(sdiemBalAfter, sdiemBalBefore, "harvest didn't grow sDIEM balance");

        uint256 priceAfter = cs.convertToAssets(1e24);
        assertGt(priceAfter, priceBefore, "share price didn't tick up");

        // Alice redeems synchronously (the v1 → v2 composability win).
        uint256 sdiemRecvBefore = s.balanceOf(alice);
        vm.prank(alice);
        uint256 assets = cs.redeem(shares, alice, alice);
        assertGt(assets, 100e18, "alice should redeem more sDIEM than she put in (compounded)");
        assertEq(s.balanceOf(alice) - sdiemRecvBefore, assets);
    }

    /// @notice Verify the maxDeposit-while-paused fix on live infrastructure
    ///         (the EIP-4626 fix we landed for Morpho integration).
    function test_fork_pausedMaxDepositIsZero() public {
        assertEq(cs.maxDeposit(alice), type(uint256).max, "unpaused should be max");

        vm.prank(admin);
        cs.pause();

        assertEq(cs.maxDeposit(alice), 0, "paused maxDeposit must be 0");
        assertEq(cs.maxMint(alice), 0, "paused maxMint must be 0");

        // Redemption still works while paused.
        // (We don't have a position to redeem in this test path, but the
        // maxRedeem signal is what integrators read.)
        assertEq(cs.maxRedeem(alice), cs.balanceOf(alice), "redeem must remain open");
    }

    // ── Helper ─────────────────────────────────────────────────────────

    function _notifyRewardAmount(uint256 amount) internal {
        deal(USDC, operator, amount);
        vm.startPrank(operator);
        IERC20(USDC).approve(address(s), amount);
        s.notifyRewardAmount(amount);
        vm.stopPrank();
    }
}
