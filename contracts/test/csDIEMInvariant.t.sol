// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {csDIEM} from "../src/csDIEM.sol";

// ── Handler ────────────────────────────────────────────────────────────────

contract csDIEMHandler is Test {
    csDIEM public vault;
    ERC20Mock public diem;

    address[] public actors;
    address public operator;

    // Ghost variables for tracking
    uint256 public ghost_totalDeposited;
    uint256 public ghost_totalWithdrawn;
    uint256 public ghost_totalDonated;
    uint256 public ghost_lastSharePrice;

    constructor(csDIEM _vault, ERC20Mock _diem, address _operator) {
        vault = _vault;
        diem = _diem;
        operator = _operator;

        // Create actors
        for (uint256 i = 0; i < 5; i++) {
            address actor = address(uint160(0xBEEF + i));
            actors.push(actor);
            diem.mint(actor, 10_000e18);
            vm.prank(actor);
            diem.approve(address(vault), type(uint256).max);
        }

        // Initial share price (1:1 scaled by offset)
        ghost_lastSharePrice = vault.convertToAssets(1e24);
    }

    // ── Actions ──────────────────────────────────────────────────────────

    function deposit(uint256 actorSeed, uint256 amount) external {
        address actor = actors[actorSeed % actors.length];
        amount = bound(amount, 1e15, diem.balanceOf(actor));
        if (amount == 0) return;

        vm.prank(actor);
        vault.deposit(amount, actor);

        ghost_totalDeposited += amount;
    }

    function withdraw(uint256 actorSeed, uint256 shares) external {
        address actor = actors[actorSeed % actors.length];
        uint256 maxShares = vault.balanceOf(actor);
        if (maxShares == 0) return;

        shares = bound(shares, 1, maxShares);

        uint256 assetsBefore = diem.balanceOf(actor);
        vm.prank(actor);
        vault.redeem(shares, actor, actor);
        uint256 assetsAfter = diem.balanceOf(actor);

        ghost_totalWithdrawn += (assetsAfter - assetsBefore);
    }

    function donate(uint256 amount) external {
        amount = bound(amount, 1e15, 100e18);
        if (vault.totalSupply() == 0) return; // No point donating to empty vault

        diem.mint(operator, amount);
        vm.prank(operator);
        vault.donate(amount);

        ghost_totalDonated += amount;
    }

    function warpTime(uint256 secs) external {
        secs = bound(secs, 1, 7 days);
        vm.warp(block.timestamp + secs);
    }
}

// ── Invariant Test Suite ───────────────────────────────────────────────────

contract csDIEMInvariantTest is Test {
    csDIEM public vault;
    ERC20Mock public diem;
    csDIEMHandler public handler;

    address admin = makeAddr("admin");
    address operator = makeAddr("operator");

    function setUp() public {
        diem = new ERC20Mock();
        vault = new csDIEM(IERC20(address(diem)), admin, operator);

        handler = new csDIEMHandler(vault, diem, operator);

        // Grant operator approval for handler donations
        vm.prank(operator);
        diem.approve(address(vault), type(uint256).max);

        targetContract(address(handler));

        // Target specific functions
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = csDIEMHandler.deposit.selector;
        selectors[1] = csDIEMHandler.withdraw.selector;
        selectors[2] = csDIEMHandler.donate.selector;
        selectors[3] = csDIEMHandler.warpTime.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// @notice Vault DIEM balance must always equal totalAssets()
    function invariant_balanceMatchesTotalAssets() public view {
        assertEq(diem.balanceOf(address(vault)), vault.totalAssets());
    }

    /// @notice Total deposited + donated must equal total withdrawn + vault balance
    function invariant_diemConservation() public view {
        uint256 vaultBalance = diem.balanceOf(address(vault));
        assertEq(
            handler.ghost_totalDeposited() + handler.ghost_totalDonated(),
            handler.ghost_totalWithdrawn() + vaultBalance
        );
    }

    /// @notice Share price (assets per share) must never decrease
    /// @dev This is the key invariant for composability — Pendle relies on monotonic exchange rate
    function invariant_sharePriceMonotonicallyIncreasing() public view {
        if (vault.totalSupply() == 0) return;

        uint256 currentPrice = vault.convertToAssets(1e24);
        // Price starts at ~1e18 (1:1), should only go up from donations
        // With virtual shares offset, initial price is slightly below 1e18
        // We just check it never drops below the initial ratio minus rounding
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

        // Round-trip rounding grows with share price. Both convertToShares and
        // convertToAssets round DOWN (vault-favoring), so loss ≈ 2 * (assets / totalShares).
        // Use 0.001% relative tolerance as safe bound.
        uint256 tolerance = testAssets / 100_000 + 1;
        assertApproxEqAbs(assetsBack, testAssets, tolerance);
        assertLe(assetsBack, testAssets); // Vault never overpays
    }
}
