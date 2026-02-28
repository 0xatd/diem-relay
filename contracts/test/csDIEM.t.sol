// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {csDIEM} from "../src/csDIEM.sol";
import {IcsDIEM} from "../src/interfaces/IcsDIEM.sol";

contract csDIEMTest is Test {
    csDIEM public vault;
    ERC20Mock public diem;

    address admin = makeAddr("admin");
    address operator = makeAddr("operator");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint256 constant INITIAL_BALANCE = 1000e18;
    uint256 constant DEPOSIT_AMOUNT = 100e18;
    uint256 constant DONATION_AMOUNT = 10e18;

    function setUp() public {
        diem = new ERC20Mock();
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
}
