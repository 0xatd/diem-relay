// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC20, IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IcsDIEM} from "./interfaces/IcsDIEM.sol";
import {IDIEMStaking} from "./interfaces/IDIEMStaking.sol";

/**
 * @title csDIEM — Compounding Staked DIEM
 * @notice ERC-4626 vault: deposit DIEM → receive csDIEM shares.
 *
 * Anyone can call `donate()` to add DIEM rewards to the vault. This
 * increases `totalAssets()`, pushing the share price up.
 *
 * Venice forward-staking: all deposited DIEM is immediately
 * forward-staked on Venice for compute credits ($1/day per staked DIEM).
 *
 * Redemptions use a request/complete pattern with a 24h delay,
 * matching Venice's unstake cooldown. Standard ERC-4626 withdraw()
 * and redeem() are disabled — use requestRedeem()/completeRedeem().
 *
 * Venice management (claimFromVenice, redeployExcess) is fully
 * permissionless — anyone can call when conditions are met.
 *
 * `totalAssets()` is overridden to include forward-staked + pending
 * DIEM minus pending redemptions, ensuring the share price correctly
 * reflects all assets under management.
 *
 * Because csDIEM is a standard ERC-20 with a monotonically increasing
 * exchange rate, it composes with Pendle (PT/YT), Morpho, Silo, and
 * any protocol that accepts yield-bearing tokens.
 *
 * Security features:
 *   - OZ ERC-4626 with virtual shares/assets (inflation attack mitigation)
 *   - Two-step admin transfer
 *   - Emergency pause (deposits gated; redemption requests always allowed)
 *   - Operator role separation
 *   - Token recovery for accidental sends
 *   - 24h async withdrawal matching Venice cooldown
 */
contract csDIEM is ERC4626, IcsDIEM {
    using SafeERC20 for IERC20;

    // ── Constants ────────────────────────────────────────────────────────

    uint256 public constant override WITHDRAWAL_DELAY = 24 hours;

    // ── Immutables ──────────────────────────────────────────────────────

    /// @notice The DIEM token contract (which has staking built-in).
    IDIEMStaking public immutable diemStaking;

    // ── State — roles ───────────────────────────────────────────────────

    address public override admin;
    address public override pendingAdmin;
    address public override operator;
    bool public override paused;

    // ── State — redemptions ─────────────────────────────────────────────

    uint256 public override totalPendingRedemptions;
    uint256 public override totalPendingNotInitiated;
    mapping(address => RedemptionRequest) private _redemptionRequests;

    // ── Modifiers ───────────────────────────────────────────────────────

    modifier onlyAdmin() {
        require(msg.sender == admin, "csDIEM: not admin");
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
        // DIEM token contract has staking built-in — same address
        diemStaking = IDIEMStaking(address(_diem));
    }

    // ── ERC-4626 overrides ─────────────────────────────────────────────

    /**
     * @notice Total DIEM assets under management.
     * @dev liquid + veniceStaked + venicePending - totalPendingRedemptions
     *
     *      Subtracting pending redemptions is critical: those shares have
     *      already been burned, so their DIEM is owed to redeemers and must
     *      not inflate the share price for remaining holders.
     */
    function totalAssets() public view override(ERC4626, IERC4626) returns (uint256) {
        (uint256 staked,, uint256 pending) = diemStaking.stakedInfos(address(this));
        uint256 gross = IERC20(asset()).balanceOf(address(this)) + staked + pending;
        // Pending redemptions are owed to users, not part of vault value
        return gross > totalPendingRedemptions ? gross - totalPendingRedemptions : 0;
    }

    /// @dev Gate deposits behind pause. Forward DIEM to Venice after deposit.
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal override whenNotPaused {
        super._deposit(caller, receiver, assets, shares);

        // Forward deposited DIEM to Venice immediately
        diemStaking.stake(assets);
    }

    /**
     * @dev Disable standard ERC-4626 withdrawals.
     *      Users must use requestRedeem()/completeRedeem() instead.
     */
    function _withdraw(
        address,
        address,
        address,
        uint256,
        uint256
    ) internal pure override {
        revert("csDIEM: use requestRedeem");
    }

    /// @notice Always returns 0 — standard ERC-4626 withdrawals are disabled.
    /// @dev Users must use requestRedeem()/completeRedeem() instead.
    function maxWithdraw(address) public pure override(ERC4626, IERC4626) returns (uint256) {
        return 0;
    }

    /// @notice Always returns 0 — standard ERC-4626 redemptions are disabled.
    /// @dev Users must use requestRedeem()/completeRedeem() instead.
    function maxRedeem(address) public pure override(ERC4626, IERC4626) returns (uint256) {
        return 0;
    }

    /// @dev Use 1e6 offset for inflation attack protection.
    /// With 18-decimal DIEM, this means the vault effectively operates at
    /// 24 decimal precision internally, making donation attacks cost ~1e6
    /// DIEM to steal 1 wei of value — economically infeasible.
    function _decimalsOffset() internal pure override returns (uint8) {
        return 6;
    }

    // ── Views ───────────────────────────────────────────────────────────

    /// @inheritdoc IcsDIEM
    function redemptionRequests(address account)
        external
        view
        override
        returns (uint256 assets, uint256 requestedAt)
    {
        RedemptionRequest storage req = _redemptionRequests[account];
        return (req.assets, req.requestedAt);
    }

    /// @inheritdoc IcsDIEM
    function canCompleteRedeem(address account) external view override returns (bool) {
        RedemptionRequest storage req = _redemptionRequests[account];
        if (req.assets == 0) return false;
        if (block.timestamp < req.requestedAt + WITHDRAWAL_DELAY) return false;
        uint256 liquid = IERC20(asset()).balanceOf(address(this));
        (,uint256 cooldownEnd, uint256 pending) = diemStaking.stakedInfos(address(this));
        if (pending > 0 && block.timestamp >= cooldownEnd) {
            liquid += pending;
        }
        return liquid >= req.assets;
    }

    /// @inheritdoc IcsDIEM
    function veniceCooldownEnd() external view override returns (uint256) {
        (, uint256 cooldownEnd,) = diemStaking.stakedInfos(address(this));
        return cooldownEnd;
    }

    // ── Async Redemption ────────────────────────────────────────────────

    /**
     * @notice Request redemption of csDIEM shares. Burns shares, starts 24h delay.
     * @dev Burns shares at current exchange rate, records DIEM amount owed.
     *      Initiates Venice unstake for the DIEM amount.
     *      If user has an existing pending redemption, amounts accumulate
     *      and the timer resets.
     * @param shares Number of csDIEM shares to redeem.
     * @return assets DIEM amount that will be claimable after delay.
     */
    function requestRedeem(uint256 shares) external override returns (uint256 assets) {
        require(shares > 0, "csDIEM: zero shares");
        require(balanceOf(msg.sender) >= shares, "csDIEM: insufficient shares");

        // Calculate DIEM owed at current exchange rate BEFORE burning
        assets = previewRedeem(shares);
        require(assets > 0, "csDIEM: zero assets");

        // Effects — burn shares
        _burn(msg.sender, shares);

        // Track pending redemption
        RedemptionRequest storage req = _redemptionRequests[msg.sender];
        req.assets += assets;
        req.requestedAt = block.timestamp;
        totalPendingRedemptions += assets;
        totalPendingNotInitiated += assets;

        emit RedemptionRequested(msg.sender, shares, assets);

        // Auto-initiate Venice unstake if possible
        _tryInitiateVeniceUnstake();
    }

    /**
     * @notice Complete redemption after 24h delay.
     * @dev Auto-claims from Venice if cooldown has matured but hasn't
     *      been claimed yet. Only reverts if Venice cooldown is still active.
     */
    function completeRedeem() external override {
        RedemptionRequest storage req = _redemptionRequests[msg.sender];
        uint256 assets = req.assets;
        require(assets > 0, "csDIEM: no pending redemption");
        require(
            block.timestamp >= req.requestedAt + WITHDRAWAL_DELAY,
            "csDIEM: withdrawal delay not met"
        );

        // Auto-claim from Venice if matured but not yet claimed
        uint256 liquid = IERC20(asset()).balanceOf(address(this));
        if (liquid < assets) {
            (,, uint256 pending) = diemStaking.stakedInfos(address(this));
            if (pending > 0) {
                diemStaking.unstake();
                liquid = IERC20(asset()).balanceOf(address(this));
            }
        }
        require(liquid >= assets, "csDIEM: Venice cooldown not finished");

        // Effects
        req.assets = 0;
        req.requestedAt = 0;
        totalPendingRedemptions -= assets;

        // Interaction
        IERC20(asset()).safeTransfer(msg.sender, assets);

        emit RedemptionCompleted(msg.sender, assets);
    }

    /**
     * @notice Cancel a pending redemption. Mints new shares at current rate.
     * @dev Re-mints shares for the pending DIEM amount at the current exchange
     *      rate. The user may receive fewer shares than they originally burned
     *      if the share price increased since their request (due to donations).
     */
    function cancelRedeem() external override {
        RedemptionRequest storage req = _redemptionRequests[msg.sender];
        uint256 assets = req.assets;
        require(assets > 0, "csDIEM: no pending redemption");

        // Effects
        req.assets = 0;
        req.requestedAt = 0;
        totalPendingRedemptions -= assets;

        // Re-mint shares at current exchange rate
        uint256 shares = previewDeposit(assets);
        _mint(msg.sender, shares);

        emit RedemptionCancelled(msg.sender, assets, shares);
    }

    // ── Permissionless ──────────────────────────────────────────────────

    /**
     * @notice Donate DIEM rewards to the vault, increasing share price.
     * @dev Anyone can call. Donor must have approved this contract.
     *      The donated DIEM increases `totalAssets()` without minting
     *      new shares, so existing share prices go up.
     *      Inflation attack mitigated by _decimalsOffset=6.
     * @param amount Amount of DIEM to donate.
     */
    function donate(uint256 amount) external override {
        require(amount > 0, "csDIEM: zero amount");

        // Effects — event before external calls
        emit RewardDonated(msg.sender, amount);

        // Interactions — pull DIEM then forward to Venice
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), amount);
        diemStaking.stake(amount);
    }

    /**
     * @notice Claim matured DIEM from Venice. Anyone can call.
     * @dev Calls diemStaking.unstake() which transfers all pending
     *      DIEM back after cooldown. Reverts if cooldown hasn't expired.
     */
    function claimFromVenice() external override {
        (,, uint256 pending) = diemStaking.stakedInfos(address(this));
        require(pending > 0, "csDIEM: nothing pending on Venice");

        // Effects — event before external call
        emit VeniceClaimed(msg.sender, pending);

        // Interaction
        diemStaking.unstake();
    }

    /**
     * @notice Batch-send accumulated redemption amounts to Venice. Anyone can call.
     * @dev Claims matured cooldown first (M-01 fix) to prevent re-locking.
     *      Reverts if Venice cooldown is still active or nothing to initiate.
     */
    function initiateVeniceUnstake() external override {
        require(totalPendingNotInitiated > 0, "csDIEM: nothing to initiate");
        _tryInitiateVeniceUnstake();
    }

    /**
     * @dev Internal: attempt to initiate Venice unstake for all pending amounts.
     *      - If matured pending exists, claims it first (M-01 fix).
     *      - If cooldown is active, silently returns (no revert for auto-calls).
     */
    function _tryInitiateVeniceUnstake() internal {
        uint256 amount = totalPendingNotInitiated;
        if (amount == 0) return;

        (, uint256 cooldownEnd, uint256 pending) = diemStaking.stakedInfos(address(this));

        if (pending > 0) {
            if (block.timestamp >= cooldownEnd) {
                // M-01 fix: claim matured cooldown before initiating new one
                diemStaking.unstake();
            } else {
                // Cooldown still active — can't initiate, return silently
                return;
            }
        }

        // Effects
        totalPendingNotInitiated = 0;
        emit VeniceUnstakeInitiated(msg.sender, amount);

        // Interaction
        diemStaking.initiateUnstake(amount);
    }

    /**
     * @notice Redeploy excess liquid DIEM to Venice. Anyone can call.
     * @dev Any liquid DIEM beyond what's needed for pending redemptions
     *      is excess and should be earning Venice compute credits.
     */
    function redeployExcess() external override {
        uint256 liquid = IERC20(asset()).balanceOf(address(this));
        require(liquid > totalPendingRedemptions, "csDIEM: no excess to redeploy");

        uint256 excess = liquid - totalPendingRedemptions;

        // Effects — event before external call
        emit ExcessRedeployed(msg.sender, excess);

        // Interaction — forward excess to Venice
        diemStaking.stake(excess);
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
