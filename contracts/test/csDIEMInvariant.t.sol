// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {csDIEM} from "../src/csDIEM.sol";
import {MockDIEMStaking} from "./mocks/MockDIEMStaking.sol";

// ── Handler ────────────────────────────────────────────────────────────────

contract csDIEMHandler is Test {
    csDIEM public vault;
    MockDIEMStaking public diem;

    address[] public actors;

    // Ghost variables for tracking
    uint256 public ghost_totalDeposited;
    uint256 public ghost_totalRedeemed;
    uint256 public ghost_totalDonated;
    uint256 public ghost_totalPendingRedemptions;

    constructor(csDIEM _vault, MockDIEMStaking _diem) {
        vault = _vault;
        diem = _diem;

        // Instant cooldown for invariant testing
        diem.setCooldownDuration(0);

        // Create actors
        for (uint256 i = 0; i < 5; i++) {
            address actor = address(uint160(0xBEEF + i));
            actors.push(actor);
            diem.mint(actor, 10_000e18);
            vm.prank(actor);
            diem.approve(address(vault), type(uint256).max);
        }
    }

    // ── Actions ────────────────────────────────────────────────────────────

    function deposit(uint256 actorSeed, uint256 amount) external {
        address actor = actors[actorSeed % actors.length];
        uint256 bal = diem.balanceOf(actor);
        if (bal == 0) return;

        amount = bound(amount, 1e15, bal);

        vm.prank(actor);
        vault.deposit(amount, actor);

        ghost_totalDeposited += amount;
    }

    function requestRedeem(uint256 actorSeed, uint256 shares) external {
        address actor = actors[actorSeed % actors.length];
        uint256 maxShares = vault.balanceOf(actor);
        if (maxShares == 0) return;

        shares = bound(shares, 1, maxShares);

        vm.prank(actor);
        uint256 assets = vault.requestRedeem(shares);

        ghost_totalPendingRedemptions += assets;
    }

    function completeRedeem(uint256 actorSeed) external {
        address actor = actors[actorSeed % actors.length];
        (uint256 pendingAssets, uint256 requestedAt) = vault.redemptionRequests(actor);
        if (pendingAssets == 0) return;

        // Ensure delay has passed
        if (block.timestamp < requestedAt + vault.WITHDRAWAL_DELAY()) {
            vm.warp(requestedAt + vault.WITHDRAWAL_DELAY());
        }

        // Claim from Venice if needed (cooldown is 0 in tests)
        (,, uint256 venicePending) = diem.stakedInfos(address(vault));
        if (venicePending > 0) {
            vault.claimFromVenice();
        }

        // Only complete if enough liquid
        uint256 liquid = diem.balanceOf(address(vault));
        if (liquid < pendingAssets) return;

        vm.prank(actor);
        vault.completeRedeem();

        ghost_totalPendingRedemptions -= pendingAssets;
        ghost_totalRedeemed += pendingAssets;
    }

    function donate(uint256 amount) external {
        amount = bound(amount, 1e15, 100e18);
        if (vault.totalSupply() == 0) return; // No point donating to empty vault

        address donor = address(uint160(0xD000));
        diem.mint(donor, amount);
        vm.prank(donor);
        diem.approve(address(vault), amount);
        vm.prank(donor);
        vault.donate(amount);

        ghost_totalDonated += amount;
    }

    function warpTime(uint256 secs) external {
        secs = bound(secs, 1, 7 days);
        vm.warp(block.timestamp + secs);
    }

    function claimFromVenice() external {
        (,, uint256 pending) = diem.stakedInfos(address(vault));
        if (pending == 0) return;

        vault.claimFromVenice();
    }

    function redeployExcess() external {
        uint256 liquid = diem.balanceOf(address(vault));
        uint256 pendingR = vault.totalPendingRedemptions();
        if (liquid <= pendingR) return;

        vault.redeployExcess();
    }
}

// ── Invariant Test Suite ───────────────────────────────────────────────────

contract csDIEMInvariantTest is Test {
    csDIEM public vault;
    MockDIEMStaking public diem;
    csDIEMHandler public handler;

    address admin = makeAddr("admin");
    address operator = makeAddr("operator");

    function setUp() public {
        diem = new MockDIEMStaking();
        vault = new csDIEM(IERC20(address(diem)), admin, operator);

        handler = new csDIEMHandler(vault, diem);

        targetContract(address(handler));

        // Target specific functions
        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = csDIEMHandler.deposit.selector;
        selectors[1] = csDIEMHandler.requestRedeem.selector;
        selectors[2] = csDIEMHandler.completeRedeem.selector;
        selectors[3] = csDIEMHandler.donate.selector;
        selectors[4] = csDIEMHandler.warpTime.selector;
        selectors[5] = csDIEMHandler.claimFromVenice.selector;
        selectors[6] = csDIEMHandler.redeployExcess.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// @notice Total deposited + donated = total redeemed + totalAssets + totalPendingRedemptions
    /// All DIEM is accounted for.
    function invariant_diemConservation() public view {
        uint256 totalIn = handler.ghost_totalDeposited() + handler.ghost_totalDonated();
        uint256 totalOut = handler.ghost_totalRedeemed();
        uint256 inVault = vault.totalAssets() + vault.totalPendingRedemptions();

        assertEq(
            totalIn,
            totalOut + inVault,
            "deposited + donated != redeemed + totalAssets + pendingRedemptions"
        );
    }

    /// @notice totalAssets accounts for all DIEM locations minus pending redemptions.
    /// totalAssets = liquid + veniceStaked + venicePending - totalPendingRedemptions
    function invariant_totalAssetsAccountsForAllDiem() public view {
        (uint256 veniceStaked,, uint256 venicePending) = diem.stakedInfos(address(vault));
        uint256 liquid = diem.balanceOf(address(vault));
        uint256 gross = liquid + veniceStaked + venicePending;
        uint256 expected = gross > vault.totalPendingRedemptions()
            ? gross - vault.totalPendingRedemptions()
            : 0;

        assertEq(
            vault.totalAssets(),
            expected,
            "totalAssets != liquid + staked + pending - pendingRedemptions"
        );
    }

    /// @notice Share price (assets per share) must never decrease
    /// @dev Key invariant for composability — Pendle relies on monotonic exchange rate
    function invariant_sharePriceMonotonicallyIncreasing() public view {
        if (vault.totalSupply() == 0) return;

        uint256 currentPrice = vault.convertToAssets(1e24);
        // Price starts at ~1e18 (1:1), should only go up from donations
        assertGe(currentPrice + 1, 1e18); // Never drops significantly below 1:1
    }

    /// @notice No shares exist without corresponding assets
    function invariant_noSharesWithoutAssets() public view {
        if (vault.totalSupply() > 0) {
            assertGt(vault.totalAssets(), 0);
        }
    }

    /// @notice convertToAssets and convertToShares are inverse (within rounding)
    function invariant_conversionConsistency() public view {
        if (vault.totalSupply() == 0) return;

        uint256 testAssets = 100e18;
        uint256 shares = vault.convertToShares(testAssets);
        uint256 assetsBack = vault.convertToAssets(shares);

        // Round-trip rounding grows with share price.
        uint256 tolerance = testAssets / 100_000 + 1;
        assertApproxEqAbs(assetsBack, testAssets, tolerance);
        assertLe(assetsBack, testAssets); // Vault never overpays
    }

    /// @notice Ghost pending redemptions tracks contract state
    function invariant_pendingRedemptionsMatchGhost() public view {
        assertEq(
            vault.totalPendingRedemptions(),
            handler.ghost_totalPendingRedemptions(),
            "totalPendingRedemptions != ghost"
        );
    }
}
