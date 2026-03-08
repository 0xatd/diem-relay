// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {csDIEM} from "../src/csDIEM.sol";
import {IcsDIEM} from "../src/interfaces/IcsDIEM.sol";
import {MockDIEMStaking} from "./mocks/MockDIEMStaking.sol";

contract csDIEMTest is Test {
    csDIEM public vault;
    MockDIEMStaking public diem;

    address admin = makeAddr("admin");
    address operator = makeAddr("operator");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint256 constant INITIAL_BALANCE = 1000e18;
    uint256 constant DEPOSIT_AMOUNT = 100e18;
    uint256 constant DONATION_AMOUNT = 10e18;

    function setUp() public {
        diem = new MockDIEMStaking();
        vault = new csDIEM(IERC20(address(diem)), admin, operator);

        // Fund users
        diem.mint(alice, INITIAL_BALANCE);
        diem.mint(bob, INITIAL_BALANCE);
        diem.mint(operator, INITIAL_BALANCE);

        // Approvals
        vm.prank(alice);
        diem.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        diem.approve(address(vault), type(uint256).max);
        vm.prank(operator);
        diem.approve(address(vault), type(uint256).max);
    }

    // ── Constructor ─────────────────────────────────────────────────────

    function test_constructor() public view {
        assertEq(vault.name(), "Compounding Staked DIEM");
        assertEq(vault.symbol(), "csDIEM");
        assertEq(vault.decimals(), 24); // 18 + 6 offset
        assertEq(vault.asset(), address(diem));
        assertEq(vault.admin(), admin);
        assertEq(vault.operator(), operator);
        assertFalse(vault.paused());
    }

    function test_constructor_revert_zeroAdmin() public {
        vm.expectRevert("csDIEM: zero admin");
        new csDIEM(IERC20(address(diem)), address(0), operator);
    }

    function test_constructor_revert_zeroOperator() public {
        vm.expectRevert("csDIEM: zero operator");
        new csDIEM(IERC20(address(diem)), admin, address(0));
    }

    // ── Deposit / Withdraw (ERC-4626) ──────────────────────────────────

    function test_deposit() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(DEPOSIT_AMOUNT, alice);

        assertGt(shares, 0);
        assertEq(vault.balanceOf(alice), shares);
        assertEq(vault.totalAssets(), DEPOSIT_AMOUNT);
        assertEq(diem.balanceOf(address(vault)), DEPOSIT_AMOUNT);
    }

    function test_withdraw() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        uint256 assets = vault.redeem(shares, alice, alice);

        // OZ virtual shares/assets may cause 1 wei rounding
        assertApproxEqAbs(assets, DEPOSIT_AMOUNT, 1);
        assertEq(vault.balanceOf(alice), 0);
    }

    function test_mint() public {
        // Preview how many assets for a given share amount
        uint256 sharesToMint = 50e24; // 50 shares (24 decimals)
        uint256 assetsNeeded = vault.previewMint(sharesToMint);

        vm.prank(alice);
        uint256 assets = vault.mint(sharesToMint, alice);

        assertEq(assets, assetsNeeded);
        assertEq(vault.balanceOf(alice), sharesToMint);
    }

    // ── Donate (operator) ──────────────────────────────────────────────

    function test_donate_increasesSharePrice() public {
        // Alice deposits 100 DIEM
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        uint256 sharesBefore = vault.balanceOf(alice);
        uint256 assetsBefore = vault.convertToAssets(sharesBefore);

        // Operator donates 10 DIEM
        vm.prank(operator);
        vault.donate(DONATION_AMOUNT);

        uint256 assetsAfter = vault.convertToAssets(sharesBefore);

        // Same shares, more assets
        assertGt(assetsAfter, assetsBefore);
        // Share price increased by ~10%
        assertApproxEqAbs(assetsAfter, DEPOSIT_AMOUNT + DONATION_AMOUNT, 1);
    }

    function test_donate_emitsEvent() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        vm.expectEmit(true, false, false, true);
        emit IcsDIEM.RewardDonated(operator, DONATION_AMOUNT);

        vm.prank(operator);
        vault.donate(DONATION_AMOUNT);
    }

    function test_donate_revert_notOperator() public {
        vm.expectRevert("csDIEM: not operator");
        vm.prank(alice);
        vault.donate(DONATION_AMOUNT);
    }

    function test_donate_revert_zeroAmount() public {
        vm.expectRevert("csDIEM: zero amount");
        vm.prank(operator);
        vault.donate(0);
    }

    function test_donate_multipleStakers_fairDistribution() public {
        // Alice deposits 100 DIEM
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        // Bob deposits 100 DIEM
        vm.prank(bob);
        vault.deposit(DEPOSIT_AMOUNT, bob);

        // Operator donates 10 DIEM
        vm.prank(operator);
        vault.donate(DONATION_AMOUNT);

        // Each staker should get ~5 DIEM of value increase
        uint256 aliceAssets = vault.convertToAssets(vault.balanceOf(alice));
        uint256 bobAssets = vault.convertToAssets(vault.balanceOf(bob));

        // Equal deposits → equal share of donation
        assertApproxEqAbs(aliceAssets, DEPOSIT_AMOUNT + DONATION_AMOUNT / 2, 1);
        assertApproxEqAbs(bobAssets, DEPOSIT_AMOUNT + DONATION_AMOUNT / 2, 1);
    }

    function test_donate_lateDepositor_noFreebies() public {
        // Alice deposits before donation
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        // Operator donates 10 DIEM
        vm.prank(operator);
        vault.donate(DONATION_AMOUNT);

        // Bob deposits AFTER donation — he gets fewer shares per DIEM
        vm.prank(bob);
        vault.deposit(DEPOSIT_AMOUNT, bob);

        uint256 aliceShares = vault.balanceOf(alice);
        uint256 bobShares = vault.balanceOf(bob);

        // Alice has more shares for the same deposit because she was there before donation
        assertGt(aliceShares, bobShares);

        // Alice's assets > Bob's assets (Alice captured the donation)
        uint256 aliceAssets = vault.convertToAssets(aliceShares);
        uint256 bobAssets = vault.convertToAssets(bobShares);
        assertGt(aliceAssets, bobAssets);

        // Bob gets ~100 DIEM back (his deposit), Alice gets ~110 (deposit + donation)
        assertApproxEqAbs(bobAssets, DEPOSIT_AMOUNT, 1);
        assertApproxEqAbs(aliceAssets, DEPOSIT_AMOUNT + DONATION_AMOUNT, 1);
    }

    // ── Share price monotonicity ───────────────────────────────────────

    function test_sharePriceNeverDecreases() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        uint256 priceBefore = vault.convertToAssets(1e24);

        // Donate
        vm.prank(operator);
        vault.donate(DONATION_AMOUNT);

        uint256 priceAfter = vault.convertToAssets(1e24);
        assertGe(priceAfter, priceBefore);

        // Partial withdraw by alice
        uint256 halfShares = vault.balanceOf(alice) / 2;
        vm.prank(alice);
        vault.redeem(halfShares, alice, alice);

        uint256 priceAfterWithdraw = vault.convertToAssets(1e24);
        assertGe(priceAfterWithdraw, priceBefore);
    }

    // ── Pause ──────────────────────────────────────────────────────────

    function test_pause_blocksDeposit() public {
        vm.prank(admin);
        vault.pause();

        vm.expectRevert("csDIEM: paused");
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);
    }

    function test_pause_blocksMint() public {
        vm.prank(admin);
        vault.pause();

        vm.expectRevert("csDIEM: paused");
        vm.prank(alice);
        vault.mint(1e24, alice);
    }

    function test_pause_allowsWithdraw() public {
        // Deposit first
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        // Pause
        vm.prank(admin);
        vault.pause();

        // Withdraw still works
        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        uint256 assets = vault.redeem(shares, alice, alice);
        assertApproxEqAbs(assets, DEPOSIT_AMOUNT, 1);
    }

    function test_pause_allowsRedeem() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        vm.prank(admin);
        vault.pause();

        uint256 withdrawable = vault.maxWithdraw(alice);
        vm.prank(alice);
        vault.withdraw(withdrawable, alice, alice);
        // No revert = success
    }

    function test_pause_revert_notAdmin() public {
        vm.expectRevert("csDIEM: not admin");
        vm.prank(alice);
        vault.pause();
    }

    function test_unpause() public {
        vm.prank(admin);
        vault.pause();
        assertTrue(vault.paused());

        vm.prank(admin);
        vault.unpause();
        assertFalse(vault.paused());

        // Deposit works again
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);
        assertGt(vault.balanceOf(alice), 0);
    }

    // ── Admin transfer (two-step) ──────────────────────────────────────

    function test_transferAdmin_twoStep() public {
        vm.prank(admin);
        vault.transferAdmin(alice);

        // Still admin until accepted
        assertEq(vault.admin(), admin);
        assertEq(vault.pendingAdmin(), alice);

        // Random address can't accept
        vm.expectRevert("csDIEM: not pending admin");
        vm.prank(bob);
        vault.acceptAdmin();

        // Alice accepts
        vm.prank(alice);
        vault.acceptAdmin();

        assertEq(vault.admin(), alice);
        assertEq(vault.pendingAdmin(), address(0));
    }

    function test_transferAdmin_revert_zeroAddress() public {
        vm.expectRevert("csDIEM: zero admin");
        vm.prank(admin);
        vault.transferAdmin(address(0));
    }

    function test_transferAdmin_revert_notAdmin() public {
        vm.expectRevert("csDIEM: not admin");
        vm.prank(alice);
        vault.transferAdmin(bob);
    }

    function test_transferAdmin_emitsEvents() public {
        vm.expectEmit(true, true, false, false);
        emit IcsDIEM.AdminTransferStarted(admin, alice);

        vm.prank(admin);
        vault.transferAdmin(alice);

        vm.expectEmit(true, true, false, false);
        emit IcsDIEM.AdminTransferred(admin, alice);

        vm.prank(alice);
        vault.acceptAdmin();
    }

    // ── Operator management ────────────────────────────────────────────

    function test_setOperator() public {
        vm.prank(admin);
        vault.setOperator(alice);

        assertEq(vault.operator(), alice);
    }

    function test_setOperator_revert_zeroAddress() public {
        vm.expectRevert("csDIEM: zero operator");
        vm.prank(admin);
        vault.setOperator(address(0));
    }

    function test_setOperator_revert_notAdmin() public {
        vm.expectRevert("csDIEM: not admin");
        vm.prank(alice);
        vault.setOperator(bob);
    }

    function test_setOperator_emitsEvent() public {
        vm.expectEmit(true, true, false, false);
        emit IcsDIEM.OperatorChanged(operator, alice);

        vm.prank(admin);
        vault.setOperator(alice);
    }

    // ── Token recovery ─────────────────────────────────────────────────

    function test_recoverERC20() public {
        // Accidentally send some random token to vault
        ERC20Mock randomToken = new ERC20Mock();
        randomToken.mint(address(vault), 500e18);

        vm.prank(admin);
        vault.recoverERC20(address(randomToken), admin, 500e18);

        assertEq(randomToken.balanceOf(admin), 500e18);
        assertEq(randomToken.balanceOf(address(vault)), 0);
    }

    function test_recoverERC20_revert_cannotRecoverUnderlying() public {
        vm.expectRevert("csDIEM: cannot recover underlying");
        vm.prank(admin);
        vault.recoverERC20(address(diem), admin, 1e18);
    }

    function test_recoverERC20_revert_zeroTo() public {
        ERC20Mock randomToken = new ERC20Mock();
        vm.expectRevert("csDIEM: zero to");
        vm.prank(admin);
        vault.recoverERC20(address(randomToken), address(0), 1e18);
    }

    function test_recoverERC20_revert_notAdmin() public {
        vm.expectRevert("csDIEM: not admin");
        vm.prank(alice);
        vault.recoverERC20(address(diem), alice, 1e18);
    }

    function test_recoverERC20_emitsEvent() public {
        ERC20Mock randomToken = new ERC20Mock();
        randomToken.mint(address(vault), 100e18);

        vm.expectEmit(true, true, false, true);
        emit IcsDIEM.TokenRecovered(address(randomToken), admin, 100e18);

        vm.prank(admin);
        vault.recoverERC20(address(randomToken), admin, 100e18);
    }

    // ── Venice forward-staking ──────────────────────────────────────────

    function test_deployToVenice_success() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        uint256 deployAmount = 90e18;
        vm.expectEmit(false, false, false, true);
        emit IcsDIEM.DeployedToVenice(deployAmount);

        vm.prank(operator);
        vault.deployToVenice(deployAmount);

        assertEq(vault.liquidBuffer(), 10e18);
        assertEq(vault.forwardStaked(), 90e18);
        assertEq(vault.pendingUnstake(), 0);
        // totalAssets unchanged (liquidBuffer + forwardStaked = 100)
        assertEq(vault.totalAssets(), DEPOSIT_AMOUNT);
    }

    function test_deployToVenice_revertsZero() public {
        vm.prank(operator);
        vm.expectRevert("csDIEM: zero amount");
        vault.deployToVenice(0);
    }

    function test_deployToVenice_revertsNotOperator() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        vm.prank(alice);
        vm.expectRevert("csDIEM: not operator");
        vault.deployToVenice(10e18);
    }

    function test_deployToVenice_revertsInsufficientBuffer() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        vm.prank(operator);
        vm.expectRevert("csDIEM: insufficient buffer");
        vault.deployToVenice(DEPOSIT_AMOUNT + 1);
    }

    function test_deployToVenice_revertsBufferFloor() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        // Buffer floor = 5% of totalAssets = 5e18
        // Deploying 96 leaves only 4 (below floor)
        vm.prank(operator);
        vm.expectRevert("csDIEM: would breach buffer floor");
        vault.deployToVenice(96e18);
    }

    function test_deployToVenice_maxDeployRespectsFloor() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        // Max deploy = 100 - 5% = 95
        vm.prank(operator);
        vault.deployToVenice(95e18);

        assertEq(vault.liquidBuffer(), 5e18);
        assertEq(vault.forwardStaked(), 95e18);
        assertEq(vault.totalAssets(), DEPOSIT_AMOUNT);
    }

    function test_deployToVenice_totalAssetsUnchanged() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        uint256 totalBefore = vault.totalAssets();
        uint256 sharesBefore = vault.balanceOf(alice);
        uint256 assetValueBefore = vault.convertToAssets(sharesBefore);

        vm.prank(operator);
        vault.deployToVenice(90e18);

        // totalAssets unchanged — share price preserved
        assertEq(vault.totalAssets(), totalBefore);
        assertEq(vault.convertToAssets(sharesBefore), assetValueBefore);
    }

    function test_initiateBufferReplenish_success() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        vm.prank(operator);
        vault.deployToVenice(90e18);

        vm.expectEmit(false, false, false, true);
        emit IcsDIEM.BufferReplenishInitiated(50e18);

        vm.prank(operator);
        vault.initiateBufferReplenish(50e18);

        assertEq(vault.forwardStaked(), 40e18);
        assertEq(vault.pendingUnstake(), 50e18);
        // totalAssets still 100 (10 buffer + 40 staked + 50 pending)
        assertEq(vault.totalAssets(), DEPOSIT_AMOUNT);
    }

    function test_initiateBufferReplenish_revertsZero() public {
        vm.prank(operator);
        vm.expectRevert("csDIEM: zero amount");
        vault.initiateBufferReplenish(0);
    }

    function test_initiateBufferReplenish_revertsNotOperator() public {
        vm.prank(alice);
        vm.expectRevert("csDIEM: not operator");
        vault.initiateBufferReplenish(10e18);
    }

    function test_completeBufferReplenish_success() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        vm.prank(operator);
        vault.deployToVenice(90e18);

        vm.prank(operator);
        vault.initiateBufferReplenish(50e18);

        // Warp past cooldown
        vm.warp(block.timestamp + 24 hours);

        vm.prank(operator);
        vault.completeBufferReplenish();

        assertEq(vault.liquidBuffer(), 60e18);
        assertEq(vault.forwardStaked(), 40e18);
        assertEq(vault.pendingUnstake(), 0);
        assertEq(vault.totalAssets(), DEPOSIT_AMOUNT);
    }

    function test_completeBufferReplenish_revertsDuringCooldown() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        vm.prank(operator);
        vault.deployToVenice(90e18);

        vm.prank(operator);
        vault.initiateBufferReplenish(50e18);

        // Don't warp — cooldown active
        vm.prank(operator);
        vm.expectRevert("MockDIEM: cooldown active");
        vault.completeBufferReplenish();
    }

    function test_completeBufferReplenish_revertsNotOperator() public {
        vm.prank(alice);
        vm.expectRevert("csDIEM: not operator");
        vault.completeBufferReplenish();
    }

    function test_withdraw_revertsBufferInsufficient() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        // Deploy 90 to Venice
        vm.prank(operator);
        vault.deployToVenice(90e18);

        // Alice tries to withdraw more than buffer
        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        vm.expectRevert("csDIEM: buffer insufficient");
        vault.redeem(shares, alice, alice); // tries to redeem all ~100 DIEM but only 10 in buffer
    }

    function test_withdraw_succeedsWithinBuffer() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        vm.prank(operator);
        vault.deployToVenice(90e18);

        // Alice can withdraw assets up to buffer (10 DIEM)
        vm.prank(alice);
        vault.withdraw(10e18, alice, alice);

        // Check she received the DIEM
        assertEq(diem.balanceOf(alice), INITIAL_BALANCE - DEPOSIT_AMOUNT + 10e18);
    }

    function test_views_liquidBuffer_forwardStaked_pendingUnstake() public {
        // Initial: all zero
        assertEq(vault.liquidBuffer(), 0);
        assertEq(vault.forwardStaked(), 0);
        assertEq(vault.pendingUnstake(), 0);

        // After deposit
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);
        assertEq(vault.liquidBuffer(), DEPOSIT_AMOUNT);

        // After deploying
        vm.prank(operator);
        vault.deployToVenice(80e18);
        assertEq(vault.liquidBuffer(), 20e18);
        assertEq(vault.forwardStaked(), 80e18);

        // After initiating replenish
        vm.prank(operator);
        vault.initiateBufferReplenish(30e18);
        assertEq(vault.forwardStaked(), 50e18);
        assertEq(vault.pendingUnstake(), 30e18);

        // After completing replenish
        vm.warp(block.timestamp + 24 hours);
        vm.prank(operator);
        vault.completeBufferReplenish();
        assertEq(vault.liquidBuffer(), 50e18);
        assertEq(vault.forwardStaked(), 50e18);
        assertEq(vault.pendingUnstake(), 0);
    }

    function test_fullVeniceFlow_sharePricePreserved() public {
        // 1. Alice deposits
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);
        uint256 sharesAlice = vault.balanceOf(alice);

        // 2. Operator donates (share price up)
        vm.prank(operator);
        vault.donate(DONATION_AMOUNT);

        uint256 priceAfterDonation = vault.convertToAssets(1e24);

        // 3. Deploy to Venice
        vm.prank(operator);
        vault.deployToVenice(95e18); // deploy most of 110 DIEM

        // Share price unchanged by deploy
        assertEq(vault.convertToAssets(1e24), priceAfterDonation);

        // 4. Initiate and complete replenish
        vm.prank(operator);
        vault.initiateBufferReplenish(95e18);
        vm.warp(block.timestamp + 24 hours);
        vm.prank(operator);
        vault.completeBufferReplenish();

        // Share price still preserved
        assertEq(vault.convertToAssets(1e24), priceAfterDonation);

        // 5. Alice redeems all
        vm.prank(alice);
        uint256 assets = vault.redeem(sharesAlice, alice, alice);

        // Alice gets deposit + donation (minus rounding)
        assertApproxEqAbs(assets, DEPOSIT_AMOUNT + DONATION_AMOUNT, 1);
    }

    // ── Fuzz tests ─────────────────────────────────────────────────────

    function testFuzz_depositWithdrawRoundTrip(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_BALANCE);

        vm.prank(alice);
        uint256 shares = vault.deposit(amount, alice);

        vm.prank(alice);
        uint256 assetsBack = vault.redeem(shares, alice, alice);

        // OZ ERC-4626 rounds in favor of the vault — user may lose 1 wei
        assertApproxEqAbs(assetsBack, amount, 1);
        assertLe(assetsBack, amount); // Never more than deposited
    }

    function testFuzz_donationIncreasesSharePrice(
        uint256 depositAmount,
        uint256 donationAmount
    ) public {
        depositAmount = bound(depositAmount, 1e18, INITIAL_BALANCE);
        donationAmount = bound(donationAmount, 1e15, INITIAL_BALANCE);

        // Alice deposits
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 sharesBefore = vault.balanceOf(alice);
        uint256 priceBefore = vault.convertToAssets(1e24);

        // Operator donates
        vm.prank(operator);
        vault.donate(donationAmount);

        uint256 priceAfter = vault.convertToAssets(1e24);

        // Share price must not decrease
        assertGe(priceAfter, priceBefore);

        // Alice's shares are worth deposit + donation (within rounding)
        // OZ virtual shares with 1e6 offset cause rounding proportional to magnitude
        uint256 aliceAssets = vault.convertToAssets(sharesBefore);
        uint256 total = depositAmount + donationAmount;
        uint256 tolerance = total / 1e15 + 10; // ~0.0001% + 10 wei
        assertApproxEqAbs(aliceAssets, total, tolerance);
    }

    function testFuzz_twoDepositors_fairSplit(
        uint256 aliceDeposit,
        uint256 bobDeposit,
        uint256 donationAmount
    ) public {
        aliceDeposit = bound(aliceDeposit, 1e18, INITIAL_BALANCE / 2);
        bobDeposit = bound(bobDeposit, 1e18, INITIAL_BALANCE / 2);
        donationAmount = bound(donationAmount, 1e18, INITIAL_BALANCE);

        vm.prank(alice);
        vault.deposit(aliceDeposit, alice);

        vm.prank(bob);
        vault.deposit(bobDeposit, bob);

        vm.prank(operator);
        vault.donate(donationAmount);

        uint256 aliceAssets = vault.convertToAssets(vault.balanceOf(alice));
        uint256 bobAssets = vault.convertToAssets(vault.balanceOf(bob));

        uint256 totalDeposited = aliceDeposit + bobDeposit;

        // Each gets proportional share of donation
        uint256 aliceExpected = aliceDeposit + (donationAmount * aliceDeposit) / totalDeposited;
        uint256 bobExpected = bobDeposit + (donationAmount * bobDeposit) / totalDeposited;

        // Tolerance: OZ virtual shares + integer division, proportional to total value
        uint256 totalValue = totalDeposited + donationAmount;
        uint256 tolerance = totalValue / 1e15 + 10;
        assertApproxEqAbs(aliceAssets, aliceExpected, tolerance);
        assertApproxEqAbs(bobAssets, bobExpected, tolerance);
    }

    function testFuzz_deployToVenice_preservesTotalAssets(
        uint256 depositAmount,
        uint256 deployAmount
    ) public {
        depositAmount = bound(depositAmount, 10e18, INITIAL_BALANCE);

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        // Max deployable respecting 5% floor of totalAssets
        uint256 totalAssetsVal = vault.totalAssets();
        uint256 floor = (totalAssetsVal * 500) / 10000;
        uint256 maxDeploy = depositAmount - floor;
        deployAmount = bound(deployAmount, 1, maxDeploy);

        uint256 totalBefore = vault.totalAssets();

        vm.prank(operator);
        vault.deployToVenice(deployAmount);

        // totalAssets unchanged
        assertEq(vault.totalAssets(), totalBefore);

        // Conservation: liquidBuffer + forwardStaked == totalAssets
        assertEq(
            vault.liquidBuffer() + vault.forwardStaked(),
            vault.totalAssets()
        );
    }
}
