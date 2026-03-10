// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/**
 * @title IcsDIEM
 * @notice Interface for Compounding Staked DIEM vault.
 *
 * ERC-4626 vault: deposit DIEM → receive csDIEM shares.
 * Anyone donates DIEM rewards → share price increases.
 * Composable with Pendle, Morpho, Silo, etc.
 *
 * All deposited DIEM is forward-staked on Venice for compute credits.
 * Redemptions require a 24h delay (matching Venice's unstake cooldown).
 * Standard ERC-4626 withdraw()/redeem() are disabled — use
 * requestRedeem()/completeRedeem() instead.
 *
 * Venice management (claimFromVenice, redeployExcess) is fully
 * permissionless — anyone can call when conditions are met.
 */
interface IcsDIEM is IERC4626 {
    // ── Structs ─────────────────────────────────────────────────────────────

    struct RedemptionRequest {
        uint256 assets; // DIEM amount owed
        uint256 requestedAt;
    }

    // ── Events ──────────────────────────────────────────────────────────────

    /// @notice Emitted when anyone donates DIEM rewards to the vault.
    event RewardDonated(address indexed donor, uint256 amount);

    /// @notice Emitted when a user requests share redemption.
    event RedemptionRequested(address indexed user, uint256 shares, uint256 assets);

    /// @notice Emitted when a user completes redemption after delay.
    event RedemptionCompleted(address indexed user, uint256 assets);

    /// @notice Emitted when admin pauses the vault.
    event Paused(address indexed by);

    /// @notice Emitted when admin unpauses the vault.
    event Unpaused(address indexed by);

    /// @notice Emitted when admin changes the operator.
    event OperatorChanged(address indexed oldOperator, address indexed newOperator);

    /// @notice Emitted when admin transfers admin role.
    event AdminTransferStarted(address indexed currentAdmin, address indexed pendingAdmin);

    /// @notice Emitted when pending admin accepts the role.
    event AdminTransferred(address indexed oldAdmin, address indexed newAdmin);

    /// @notice Emitted when admin recovers accidentally sent tokens.
    event TokenRecovered(address indexed token, address indexed to, uint256 amount);

    /// @notice Emitted when anyone claims matured DIEM from Venice.
    event VeniceClaimed(address indexed caller, uint256 amount);

    /// @notice Emitted when anyone redeploys excess liquid DIEM to Venice.
    event ExcessRedeployed(address indexed caller, uint256 amount);

    /// @notice Emitted when anyone batches pending unstakes to Venice.
    event VeniceUnstakeInitiated(address indexed caller, uint256 amount);

    // ── Views ───────────────────────────────────────────────────────────────

    function admin() external view returns (address);
    function pendingAdmin() external view returns (address);
    function operator() external view returns (address);
    function paused() external view returns (bool);

    /// @notice Total DIEM currently pending redemption across all users.
    function totalPendingRedemptions() external view returns (uint256);

    /// @notice DIEM redemption amounts not yet sent to Venice for unstaking.
    function totalPendingNotInitiated() external view returns (uint256);

    /// @notice Redemption request for a specific user.
    function redemptionRequests(address account) external view returns (uint256 assets, uint256 requestedAt);

    /// @notice Venice cooldown end timestamp for this contract.
    function veniceCooldownEnd() external view returns (uint256);

    /// @notice Delay before redemptions can be completed (matches Venice cooldown).
    function WITHDRAWAL_DELAY() external view returns (uint256);

    // ── Async Redemption ────────────────────────────────────────────────────

    /// @notice Request redemption of shares. Burns shares, starts 24h delay.
    /// @param shares Number of csDIEM shares to redeem.
    /// @return assets DIEM amount that will be claimable after delay.
    function requestRedeem(uint256 shares) external returns (uint256 assets);

    /// @notice Complete redemption after 24h delay + Venice cooldown.
    function completeRedeem() external;

    // ── Permissionless ──────────────────────────────────────────────────────

    /// @notice Donate DIEM rewards to the vault, increasing share price. Anyone can call.
    function donate(uint256 amount) external;

    /// @notice Claim matured DIEM from Venice. Anyone can call.
    function claimFromVenice() external;

    /// @notice Redeploy excess liquid DIEM (above pending redemptions) to Venice.
    function redeployExcess() external;

    /// @notice Batch-send accumulated redemption amounts to Venice. Anyone can call.
    /// @dev Calls diemStaking.initiateUnstake() once for all pending amounts,
    ///      minimizing cooldown resets.
    function initiateVeniceUnstake() external;

    // ── Admin ───────────────────────────────────────────────────────────────

    function pause() external;
    function unpause() external;
    function setOperator(address newOperator) external;
    function transferAdmin(address newAdmin) external;
    function acceptAdmin() external;

    /// @notice Recover tokens accidentally sent to the vault.
    /// @dev Cannot recover the underlying DIEM asset.
    function recoverERC20(address token, address to, uint256 amount) external;
}
