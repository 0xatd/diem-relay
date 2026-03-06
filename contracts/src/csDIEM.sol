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
 * An off-chain operator sells Venice AI compute credits, swaps USDC → DIEM,
 * and calls `donate()` to add DIEM rewards to the vault. This increases
 * `totalAssets()`, pushing the share price up.
 *
 * Venice forward-staking: deposited DIEM is forward-staked on the DIEM
 * token contract to earn Venice compute credits ($1/day per staked DIEM).
 * A liquid buffer (target 10%) is maintained for instant withdrawals.
 *
 * `totalAssets()` is overridden to include forward-staked + pending DIEM,
 * ensuring the share price correctly reflects all assets under management
 * regardless of how much is deployed to Venice.
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
 *   - Buffer floor enforcement on Venice deployment
 */
contract csDIEM is ERC4626, IcsDIEM {
    using SafeERC20 for IERC20;

    // ── Constants ────────────────────────────────────────────────────────

    /// @notice Buffer target: 10% of total deposits kept liquid.
    uint256 public constant BUFFER_TARGET_BPS = 1000;

    /// @notice Buffer floor: below 5%, operator should replenish.
    uint256 public constant BUFFER_FLOOR_BPS = 500;

    uint256 private constant BPS = 10000;

    // ── Immutables ──────────────────────────────────────────────────────

    /// @notice The DIEM token contract (which has staking built-in).
    IDIEMStaking public immutable diemStaking;

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
        // DIEM token contract has staking built-in — same address
        diemStaking = IDIEMStaking(address(_diem));
    }

    // ── ERC-4626 overrides ─────────────────────────────────────────────

    /**
     * @notice Total DIEM assets under management.
     * @dev Includes liquid buffer + forward-staked + pending unstake.
     *      This ensures share price stays accurate when DIEM is deployed
     *      to Venice staking. Without this override, deploying DIEM to
     *      Venice would collapse the share price.
     */
    function totalAssets() public view override(ERC4626, IERC4626) returns (uint256) {
        (uint256 staked,, uint256 pending) = diemStaking.stakedInfos(address(this));
        return IERC20(asset()).balanceOf(address(this)) + staked + pending;
    }

    /// @dev Gate deposits behind pause. Withdrawals always allowed.
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal override whenNotPaused {
        super._deposit(caller, receiver, assets, shares);
    }

    /**
     * @dev Gate withdrawals to liquid buffer.
     *      If a user tries to withdraw more than the buffer holds,
     *      the tx reverts. The operator must replenish the buffer
     *      from Venice staking first.
     */
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal override {
        require(
            IERC20(asset()).balanceOf(address(this)) >= assets,
            "csDIEM: buffer insufficient"
        );
        super._withdraw(caller, receiver, owner, assets, shares);
    }

    /// @dev Use 1e6 offset for inflation attack protection.
    /// With 18-decimal DIEM, this means the vault effectively operates at
    /// 24 decimal precision internally, making donation attacks cost ~1e6
    /// DIEM to steal 1 wei of value — economically infeasible.
    function _decimalsOffset() internal pure override returns (uint8) {
        return 6;
    }

    // ── Views — buffer ────────────────────────────────────────────────

    /// @inheritdoc IcsDIEM
    function liquidBuffer() public view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }

    /// @inheritdoc IcsDIEM
    function forwardStaked() public view override returns (uint256) {
        (uint256 staked,,) = diemStaking.stakedInfos(address(this));
        return staked;
    }

    /// @inheritdoc IcsDIEM
    function pendingUnstake() public view override returns (uint256) {
        (,, uint256 pending) = diemStaking.stakedInfos(address(this));
        return pending;
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

    // ── Operator — Venice forward-staking ──────────────────────────────

    /**
     * @notice Deploy idle DIEM from liquid buffer to Venice staking.
     * @dev Calls DIEM.stake() which does an internal balance transfer.
     *      Enforces buffer floor to ensure withdrawal liquidity.
     *      totalAssets() remains unchanged because forwardStaked increases
     *      by the same amount liquidBuffer decreases.
     * @param amount Amount of DIEM to forward-stake.
     */
    function deployToVenice(uint256 amount) external override onlyOperator {
        require(amount > 0, "csDIEM: zero amount");

        uint256 currentBuffer = IERC20(asset()).balanceOf(address(this));
        require(currentBuffer >= amount, "csDIEM: insufficient buffer");

        // Enforce buffer floor relative to total assets
        uint256 totalAssetsValue = totalAssets();
        if (totalAssetsValue > 0) {
            uint256 bufferAfter = currentBuffer - amount;
            require(
                bufferAfter >= (totalAssetsValue * BUFFER_FLOOR_BPS) / BPS,
                "csDIEM: would breach buffer floor"
            );
        }

        // Interaction — stake on DIEM contract
        diemStaking.stake(amount);

        emit DeployedToVenice(amount);
    }

    /**
     * @notice Start unstaking DIEM from Venice to replenish buffer.
     * @dev Initiates the 24h cooldown on the DIEM contract.
     *      Warning: calling again while pending resets the cooldown timer.
     * @param amount Amount of DIEM to unstake from Venice.
     */
    function initiateBufferReplenish(uint256 amount) external override onlyOperator {
        require(amount > 0, "csDIEM: zero amount");

        // Interaction — initiate unstake on DIEM contract
        diemStaking.initiateUnstake(amount);

        emit BufferReplenishInitiated(amount);
    }

    /**
     * @notice Complete buffer replenishment after Venice cooldown expires.
     * @dev Calls DIEM.unstake() which transfers pendingUnstakeAmount back.
     */
    function completeBufferReplenish() external override onlyOperator {
        // Interaction — complete unstake on DIEM contract
        diemStaking.unstake();

        emit BufferReplenishCompleted(IERC20(asset()).balanceOf(address(this)));
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
