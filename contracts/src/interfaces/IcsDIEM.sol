// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/**
 * @title IcsDIEM
 * @notice Interface for the Compounding Staked DIEM vault.
 *
 * ERC-4626 vault: deposit DIEM → receive csDIEM shares.
 * Operator donates DIEM rewards → share price increases.
 * Composable with Pendle, Morpho, Silo, etc.
 *
 * Venice forward-staking: operator deploys deposited DIEM to Venice
 * staking for compute credits. A liquid buffer is maintained for
 * instant withdrawals.
 */
interface IcsDIEM is IERC4626 {
    // ── Events ────────────────────────────────────────────────────────────

    /// @notice Emitted when operator donates DIEM rewards to the vault.
    event RewardDonated(address indexed operator, uint256 amount);

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

    /// @notice Emitted when operator deploys DIEM from buffer to Venice staking.
    event DeployedToVenice(uint256 amount);

    /// @notice Emitted when operator initiates buffer replenishment from Venice.
    event BufferReplenishInitiated(uint256 amount);

    /// @notice Emitted when operator completes buffer replenishment after cooldown.
    event BufferReplenishCompleted(uint256 newBufferBalance);

    // ── Views ─────────────────────────────────────────────────────────────

    function admin() external view returns (address);

    function pendingAdmin() external view returns (address);

    function operator() external view returns (address);

    function paused() external view returns (bool);

    /// @notice Liquid DIEM available for instant withdrawals.
    function liquidBuffer() external view returns (uint256);

    /// @notice DIEM currently forward-staked on Venice via DIEM contract.
    function forwardStaked() external view returns (uint256);

    /// @notice DIEM in cooldown, pending unstake from Venice.
    function pendingUnstake() external view returns (uint256);

    // ── Operator ──────────────────────────────────────────────────────────

    /// @notice Donate DIEM rewards to the vault, increasing share price.
    /// @param amount Amount of DIEM to donate.
    function donate(uint256 amount) external;

    /// @notice Deploy idle DIEM from buffer to Venice staking.
    function deployToVenice(uint256 amount) external;

    /// @notice Start unstaking DIEM from Venice to replenish buffer.
    function initiateBufferReplenish(uint256 amount) external;

    /// @notice Complete buffer replenishment after Venice cooldown expires.
    function completeBufferReplenish() external;

    // ── Admin ─────────────────────────────────────────────────────────────

    function pause() external;

    function unpause() external;

    function setOperator(address newOperator) external;

    function transferAdmin(address newAdmin) external;

    function acceptAdmin() external;

    /// @notice Recover tokens accidentally sent to the vault.
    /// @dev Cannot recover the underlying DIEM asset.
    function recoverERC20(address token, address to, uint256 amount) external;
}
