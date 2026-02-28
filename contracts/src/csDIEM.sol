// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20, IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IcsDIEM} from "./interfaces/IcsDIEM.sol";

/**
 * @title csDIEM — Compounding Staked DIEM
 * @notice ERC-4626 vault: deposit DIEM → receive csDIEM shares.
 *
 * An off-chain operator sells Venice AI compute credits, swaps USDC → DIEM,
 * and calls `donate()` to add DIEM rewards to the vault. This increases
 * `totalAssets()`, pushing the share price up.
 *
 * Because csDIEM is a standard ERC-20 with a monotonically increasing
 * exchange rate, it composes with Pendle (PT/YT), Morpho, Silo, and
 * any protocol that accepts yield-bearing tokens.
 *
 * Security features:
 *   - OZ ERC-4626 with virtual shares/assets (inflation attack mitigation)
 *   - Two-step admin transfer
 *   - Emergency pause (deposits gated; withdrawals always allowed)
 *   - Operator role separation
 *   - Token recovery for accidental sends
 */
contract csDIEM is ERC4626, IcsDIEM {
    using SafeERC20 for IERC20;

    // ── State — roles ───────────────────────────────────────────────────

    address public override admin;
    address public override pendingAdmin;
    address public override operator;
    bool public override paused;

    // ── Modifiers ───────────────────────────────────────────────────────

    modifier onlyAdmin() {
        require(msg.sender == admin, "csDIEM: not admin");
        _;
    }

    modifier onlyOperator() {
        require(msg.sender == operator, "csDIEM: not operator");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "csDIEM: paused");
        _;
    }

    // ── Constructor ─────────────────────────────────────────────────────

    constructor(
        IERC20 _diem,
        address _admin,
        address _operator
    )
        ERC20("Compounding Staked DIEM", "csDIEM")
        ERC4626(IERC20(_diem))
    {
        require(_admin != address(0), "csDIEM: zero admin");
        require(_operator != address(0), "csDIEM: zero operator");

        admin = _admin;
        operator = _operator;
    }

    // ── ERC-4626 overrides ─────────────────────────────────────────────

    /// @dev Gate deposits behind pause. Withdrawals always allowed.
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal override whenNotPaused {
        super._deposit(caller, receiver, assets, shares);
    }

    /// @dev Use 1e6 offset for inflation attack protection.
    /// With 18-decimal DIEM, this means the vault effectively operates at
    /// 24 decimal precision internally, making donation attacks cost ~1e6
    /// DIEM to steal 1 wei of value — economically infeasible.
    function _decimalsOffset() internal pure override returns (uint8) {
        return 6;
    }

    // ── Operator — donate rewards ──────────────────────────────────────

    /**
     * @notice Donate DIEM rewards to the vault, increasing share price.
     * @dev Operator must have approved this contract for `amount` DIEM.
     *      The donated DIEM increases `totalAssets()` without minting
     *      new shares, so existing share prices go up.
     * @param amount Amount of DIEM to donate.
     */
    function donate(uint256 amount) external override onlyOperator {
        require(amount > 0, "csDIEM: zero amount");

        // Pull DIEM from operator — increases totalAssets() for all holders
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), amount);

        emit RewardDonated(msg.sender, amount);
    }

    // ── Admin ──────────────────────────────────────────────────────────

    function pause() external override onlyAdmin {
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external override onlyAdmin {
        paused = false;
        emit Unpaused(msg.sender);
    }

    function setOperator(address newOperator) external override onlyAdmin {
        require(newOperator != address(0), "csDIEM: zero operator");
        address oldOperator = operator;
        operator = newOperator;
        emit OperatorChanged(oldOperator, newOperator);
    }

    /// @notice Start two-step admin transfer.
    function transferAdmin(address newAdmin) external override onlyAdmin {
        require(newAdmin != address(0), "csDIEM: zero admin");
        pendingAdmin = newAdmin;
        emit AdminTransferStarted(admin, newAdmin);
    }

    /// @notice Pending admin accepts the role.
    function acceptAdmin() external override {
        require(msg.sender == pendingAdmin, "csDIEM: not pending admin");
        address oldAdmin = admin;
        admin = msg.sender;
        pendingAdmin = address(0);
        emit AdminTransferred(oldAdmin, msg.sender);
    }

    /// @notice Recover tokens accidentally sent to the vault.
    /// @dev Cannot recover the underlying DIEM to protect depositors.
    function recoverERC20(
        address token,
        address to,
        uint256 amount
    ) external override onlyAdmin {
        require(token != asset(), "csDIEM: cannot recover underlying");
        require(to != address(0), "csDIEM: zero to");
        IERC20(token).safeTransfer(to, amount);
        emit TokenRecovered(token, to, amount);
    }
}
