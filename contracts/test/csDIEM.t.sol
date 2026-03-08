// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
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
    address donor = makeAddr("donor");

    uint256 constant INITIAL_BALANCE = 1000e18;
    uint256 constant DEPOSIT_AMOUNT = 100e18;
    uint256 constant DONATION_AMOUNT = 10e18;

    function setUp() public {
        diem = new MockDIEMStaking();
        vault = new csDIEM(IERC20(address(diem)), admin, operator);

        // Fund users
        diem.mint(alice, INITIAL_BALANCE);
        diem.mint(bob, INITIAL_BALANCE);
        diem.mint(donor, INITIAL_BALANCE);

        // Approvals
        vm.prank(alice);
        diem.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        diem.approve(address(vault), type(uint256).max);
        vm.prank(donor);
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

    // ── Deposit (ERC-4626) ──────────────────────────────────────────────

    function test_deposit() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(DEPOSIT_AMOUNT, alice);

        assertGt(shares, 0);
        assertEq(vault.balanceOf(alice), shares);
        assertEq(vault.totalAssets(), DEPOSIT_AMOUNT);
        // DIEM forwarded to Venice — contract holds 0 liquid DIEM
        assertEq(diem.balanceOf(address(vault)), 0);
        // Verify Venice got it
        (uint256 staked,,) = diem.stakedInfos(address(vault));
        assertEq(staked, DEPOSIT_AMOUNT);
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

    // ── Standard withdraw/redeem DISABLED ────────────────────────────────

    function test_standardRedeem_reverts() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        // OZ ERC4626 checks maxRedeem (returns 0) before calling _withdraw
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC4626.ERC4626ExceededMaxRedeem.selector, alice, shares, 0
            )
        );
        vault.redeem(shares, alice, alice);
    }

    function test_standardWithdraw_reverts() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        vm.prank(alice);
        // OZ ERC4626 checks maxWithdraw (returns 0) before calling _withdraw
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC4626.ERC4626ExceededMaxWithdraw.selector, alice, 10e18, 0
            )
        );
        vault.withdraw(10e18, alice, alice);
    }

    function test_maxWithdraw_returnsZero() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        assertEq(vault.maxWithdraw(alice), 0);
    }

    function test_maxRedeem_returnsZero() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        assertEq(vault.maxRedeem(alice), 0);
    }

    // ── Request Redeem ──────────────────────────────────────────────────

    function test_requestRedeem_updatesState() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        uint256 shares = vault.balanceOf(alice);

        vm.prank(alice);
        uint256 assets = vault.requestRedeem(shares);

        assertGt(assets, 0);
        assertApproxEqAbs(assets, DEPOSIT_AMOUNT, 1);

        // Shares burned
        assertEq(vault.balanceOf(alice), 0);

        // Pending redemption tracked
        (uint256 pendingAssets, uint256 requestedAt) = vault.redemptionRequests(alice);
        assertEq(pendingAssets, assets);
        assertEq(requestedAt, block.timestamp);
        assertEq(vault.totalPendingRedemptions(), assets);
    }

    function test_requestRedeem_emitsEvent() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        uint256 shares = vault.balanceOf(alice);
        uint256 expectedAssets = vault.previewRedeem(shares);

        vm.expectEmit(true, false, false, true);
        emit IcsDIEM.RedemptionRequested(alice, shares, expectedAssets);

        vm.prank(alice);
        vault.requestRedeem(shares);
    }

    function test_requestRedeem_revertsZeroShares() public {
        vm.prank(alice);
        vm.expectRevert("csDIEM: zero shares");
        vault.requestRedeem(0);
    }

    function test_requestRedeem_revertsInsufficientShares() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        vm.expectRevert("csDIEM: insufficient shares");
        vault.requestRedeem(shares + 1);
    }

    function test_requestRedeem_partialAmount() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        uint256 halfShares = vault.balanceOf(alice) / 2;

        vm.prank(alice);
        uint256 assets = vault.requestRedeem(halfShares);

        assertGt(vault.balanceOf(alice), 0); // Still has remaining shares
        assertApproxEqAbs(assets, DEPOSIT_AMOUNT / 2, 1);
    }

    function test_requestRedeem_accumulates() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        uint256 totalShares = vault.balanceOf(alice);
        uint256 firstBatch = totalShares / 3;
        uint256 secondBatch = totalShares / 3;

        // First request
        vm.prank(alice);
        uint256 assets1 = vault.requestRedeem(firstBatch);

        // Second request — accumulates, resets timer
        vm.warp(block.timestamp + 12 hours);
        vm.prank(alice);
        uint256 assets2 = vault.requestRedeem(secondBatch);

        (uint256 pendingAssets, uint256 requestedAt) = vault.redemptionRequests(alice);
        assertEq(pendingAssets, assets1 + assets2);
        assertEq(requestedAt, block.timestamp); // Timer reset
    }

    function test_requestRedeem_allowedWhenPaused() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        vm.prank(admin);
        vault.pause();

        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        vault.requestRedeem(shares); // Must not revert

        (uint256 amount,) = vault.redemptionRequests(alice);
        assertGt(amount, 0);
    }

    function test_requestRedeem_initiatesVeniceUnstake() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        uint256 assets = vault.requestRedeem(shares);

        // Venice should have pending unstake
        (uint256 staked,, uint256 pending) = diem.stakedInfos(address(vault));
        assertEq(staked, 0);
        assertEq(pending, assets);
    }

    function test_requestRedeem_doesNotInflateSharePrice() public {
        // Alice and Bob both deposit
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);
        vm.prank(bob);
        vault.deposit(DEPOSIT_AMOUNT, bob);

        uint256 priceBefore = vault.convertToAssets(1e24);

        // Alice requests full redeem
        uint256 aliceShares = vault.balanceOf(alice);
        vm.prank(alice);
        vault.requestRedeem(aliceShares);

        // totalAssets subtracts pending redemptions — Bob's share price shouldn't change
        uint256 priceAfter = vault.convertToAssets(1e24);
        assertApproxEqAbs(priceAfter, priceBefore, 1);
    }

    // ── Complete Redeem ──────────────────────────────────────────────────

    function test_completeRedeem_success() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        uint256 assets = vault.requestRedeem(shares);

        // Warp past delay
        vm.warp(block.timestamp + 24 hours);

        // Claim from Venice
        vault.claimFromVenice();

        uint256 balBefore = diem.balanceOf(alice);
        vm.prank(alice);
        vault.completeRedeem();

        assertEq(diem.balanceOf(alice), balBefore + assets);
        (uint256 pendingAssets,) = vault.redemptionRequests(alice);
        assertEq(pendingAssets, 0);
        assertEq(vault.totalPendingRedemptions(), 0);
    }

    function test_completeRedeem_emitsEvent() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        uint256 assets = vault.requestRedeem(shares);

        vm.warp(block.timestamp + 24 hours);
        vault.claimFromVenice();

        vm.expectEmit(true, false, false, true);
        emit IcsDIEM.RedemptionCompleted(alice, assets);

        vm.prank(alice);
        vault.completeRedeem();
    }

    function test_completeRedeem_revertsNoRequest() public {
        vm.prank(alice);
        vm.expectRevert("csDIEM: no pending redemption");
        vault.completeRedeem();
    }

    function test_completeRedeem_revertsDelayNotMet() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        vault.requestRedeem(shares);

        // Only 12 hours
        vm.warp(block.timestamp + 12 hours);

        vm.prank(alice);
        vm.expectRevert("csDIEM: withdrawal delay not met");
        vault.completeRedeem();
    }

    function test_completeRedeem_revertsInsufficientLiquidity() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        vault.requestRedeem(shares);

        vm.warp(block.timestamp + 24 hours);

        // Don't claim from Venice
        vm.prank(alice);
        vm.expectRevert("csDIEM: claim from Venice first");
        vault.completeRedeem();
    }

    // ── Donate (permissionless) ─────────────────────────────────────────

    function test_donate_increasesSharePrice() public {
        // Alice deposits 100 DIEM
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        uint256 sharesBefore = vault.balanceOf(alice);
        uint256 assetsBefore = vault.convertToAssets(sharesBefore);

        // Anyone donates 10 DIEM
        vm.prank(donor);
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
        emit IcsDIEM.RewardDonated(donor, DONATION_AMOUNT);

        vm.prank(donor);
        vault.donate(DONATION_AMOUNT);
    }

    function test_donate_anyoneCanCall() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        // Alice can donate (not just operator)
        vm.prank(alice);
        vault.donate(1e18);

        // Bob can donate
        diem.mint(bob, 1e18);
        vm.prank(bob);
        vault.donate(1e18);

        // Random donor can donate
        vm.prank(donor);
        vault.donate(1e18);
    }

    function test_donate_revert_zeroAmount() public {
        vm.expectRevert("csDIEM: zero amount");
        vm.prank(donor);
        vault.donate(0);
    }

    function test_donate_multipleStakers_fairDistribution() public {
        // Alice deposits 100 DIEM
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        // Bob deposits 100 DIEM
        vm.prank(bob);
        vault.deposit(DEPOSIT_AMOUNT, bob);

        // Donor donates 10 DIEM
        vm.prank(donor);
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

        // Donor donates 10 DIEM
        vm.prank(donor);
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

    function test_donate_forwardsToVenice() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        vm.prank(donor);
        vault.donate(DONATION_AMOUNT);

        // Donated DIEM should be on Venice, not sitting liquid
        assertEq(diem.balanceOf(address(vault)), 0);
        (uint256 staked,,) = diem.stakedInfos(address(vault));
        assertEq(staked, DEPOSIT_AMOUNT + DONATION_AMOUNT);
    }

    // ── Share price monotonicity ────────────────────────────────────────

    function test_sharePriceNeverDecreases() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        uint256 priceBefore = vault.convertToAssets(1e24);

        // Donate
        vm.prank(donor);
        vault.donate(DONATION_AMOUNT);

        uint256 priceAfterDonation = vault.convertToAssets(1e24);
        assertGe(priceAfterDonation, priceBefore);

        // Partial requestRedeem by alice
        uint256 halfShares = vault.balanceOf(alice) / 2;
        vm.prank(alice);
        vault.requestRedeem(halfShares);

        uint256 priceAfterRedeem = vault.convertToAssets(1e24);
        // Share price should not decrease after requestRedeem
        // (totalPendingRedemptions offsets the burned shares)
        assertGe(priceAfterRedeem + 1, priceAfterDonation); // +1 for rounding
    }

    // ── Permissionless Venice Management ────────────────────────────────

    function test_claimFromVenice_success() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        // Request redeem to trigger initiateUnstake
        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        vault.requestRedeem(shares);

        vm.warp(block.timestamp + 24 hours);

        (,, uint256 pending) = diem.stakedInfos(address(vault));

        vm.expectEmit(true, false, false, true);
        emit IcsDIEM.VeniceClaimed(bob, pending);

        // Anyone can call
        vm.prank(bob);
        vault.claimFromVenice();

        assertGt(diem.balanceOf(address(vault)), 0);
    }

    function test_claimFromVenice_revertsNothingPending() public {
        vm.expectRevert("csDIEM: nothing pending on Venice");
        vault.claimFromVenice();
    }

    function test_redeployExcess_success() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        // Simulate excess liquid DIEM (e.g., someone accidentally sent DIEM to the vault)
        uint256 excessAmount = 50e18;
        diem.mint(address(vault), excessAmount);

        uint256 liquid = diem.balanceOf(address(vault));
        uint256 pending = vault.totalPendingRedemptions();
        assertEq(pending, 0);
        assertEq(liquid, excessAmount);

        vm.expectEmit(true, false, false, true);
        emit IcsDIEM.ExcessRedeployed(bob, excessAmount);

        vm.prank(bob); // Anyone can call
        vault.redeployExcess();

        assertEq(diem.balanceOf(address(vault)), 0);
    }

    function test_redeployExcess_revertsNoExcess() public {
        vm.expectRevert("csDIEM: no excess to redeploy");
        vault.redeployExcess();
    }

    // ── Pause ───────────────────────────────────────────────────────────

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

    function test_pause_allowsRequestRedeem() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        vm.prank(admin);
        vault.pause();

        // requestRedeem works even when paused
        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        vault.requestRedeem(shares);

        (uint256 amount,) = vault.redemptionRequests(alice);
        assertGt(amount, 0);
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

    // ── Views ───────────────────────────────────────────────────────────

    function test_views_redemptionRequests() public {
        (uint256 assets, uint256 requestedAt) = vault.redemptionRequests(alice);
        assertEq(assets, 0);
        assertEq(requestedAt, 0);
    }

    function test_views_veniceCooldownEnd() public {
        assertEq(vault.veniceCooldownEnd(), 0);

        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        vault.requestRedeem(shares);

        assertEq(vault.veniceCooldownEnd(), block.timestamp + 24 hours);
    }

    function test_views_WITHDRAWAL_DELAY() public view {
        assertEq(vault.WITHDRAWAL_DELAY(), 24 hours);
    }

    function test_totalAssets_includesVeniceStaked() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        // All DIEM is on Venice, but totalAssets still reflects the deposit
        assertEq(vault.totalAssets(), DEPOSIT_AMOUNT);
        assertEq(diem.balanceOf(address(vault)), 0); // No liquid DIEM
    }

    function test_totalAssets_excludesPendingRedemptions() public {
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        uint256 totalBefore = vault.totalAssets();

        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        uint256 assets = vault.requestRedeem(shares);

        // totalAssets should decrease by the pending redemption amount
        assertApproxEqAbs(vault.totalAssets(), totalBefore - assets, 1);
    }

    // ── Full Async Redemption Flow ──────────────────────────────────────

    function test_fullAsyncRedemptionFlow() public {
        // 1. Alice deposits
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        // 2. Donor donates (share price up)
        vm.prank(donor);
        vault.donate(DONATION_AMOUNT);

        // 3. Alice requests full redeem
        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        uint256 assets = vault.requestRedeem(shares);

        // Assets should be ~110 DIEM (deposit + donation)
        assertApproxEqAbs(assets, DEPOSIT_AMOUNT + DONATION_AMOUNT, 1);

        // 4. Wait for delay
        vm.warp(block.timestamp + 24 hours);

        // 5. Anyone claims from Venice
        vault.claimFromVenice();

        // 6. Alice completes redemption
        uint256 diemBefore = diem.balanceOf(alice);
        vm.prank(alice);
        vault.completeRedeem();

        assertApproxEqAbs(diem.balanceOf(alice) - diemBefore, DEPOSIT_AMOUNT + DONATION_AMOUNT, 1);
        assertEq(vault.totalPendingRedemptions(), 0);
    }

    function test_multiUserAsyncRedemption() public {
        // Alice and Bob deposit
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);
        vm.prank(bob);
        vault.deposit(DEPOSIT_AMOUNT, bob);

        // Both request full redeem
        uint256 aliceShares = vault.balanceOf(alice);
        vm.prank(alice);
        uint256 aliceAssets = vault.requestRedeem(aliceShares);

        uint256 bobShares = vault.balanceOf(bob);
        vm.prank(bob);
        uint256 bobAssets = vault.requestRedeem(bobShares);

        assertEq(vault.totalPendingRedemptions(), aliceAssets + bobAssets);

        // Wait and claim
        vm.warp(block.timestamp + 24 hours);
        vault.claimFromVenice();

        // Both complete
        vm.prank(alice);
        vault.completeRedeem();
        vm.prank(bob);
        vault.completeRedeem();

        assertEq(vault.totalPendingRedemptions(), 0);
        assertApproxEqAbs(diem.balanceOf(alice), INITIAL_BALANCE, 1);
        assertApproxEqAbs(diem.balanceOf(bob), INITIAL_BALANCE, 1);
    }

    // ── Fuzz tests ─────────────────────────────────────────────────────

    function testFuzz_depositRedeemRoundTrip(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_BALANCE);

        vm.prank(alice);
        uint256 shares = vault.deposit(amount, alice);

        vm.prank(alice);
        uint256 assetsBack = vault.requestRedeem(shares);

        // OZ ERC-4626 rounds in favor of the vault — user may lose 1 wei
        assertApproxEqAbs(assetsBack, amount, 1);
        assertLe(assetsBack, amount); // Never more than deposited

        // Complete the withdrawal
        vm.warp(block.timestamp + 24 hours);
        vault.claimFromVenice();
        vm.prank(alice);
        vault.completeRedeem();

        assertApproxEqAbs(diem.balanceOf(alice), INITIAL_BALANCE, 1);
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

        // Anyone donates
        diem.mint(donor, donationAmount);
        vm.prank(donor);
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

        diem.mint(donor, donationAmount);
        vm.prank(donor);
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
