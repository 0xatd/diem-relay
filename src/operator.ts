/**
 * DIEM Relay — Venice Forward-Staking Operator
 *
 * Manages the Venice forward-staking lifecycle for sDIEM and csDIEM:
 *   1. Deploy excess buffer to Venice (DIEM.stake via contracts)
 *   2. Initiate buffer replenish when below floor (24h cooldown)
 *   3. Complete pending replenishes after cooldown expires
 *   4. Distribute rewards: notifyRewardAmount (sDIEM) / donate (csDIEM)
 *
 * Runs as a periodic cron loop. Each cycle reads on-chain state and
 * executes the appropriate operator actions.
 *
 * Env:
 *   SDIEM_ADDRESS    - sDIEM contract address (required)
 *   CSDIEM_ADDRESS   - csDIEM contract address (required)
 *   DIEM_ADDRESS     - DIEM token address (default: Base DIEM)
 *   USDC_ADDRESS     - USDC address (default: Base USDC)
 *   RPC_URL          - Base JSON-RPC URL (required)
 *   OPERATOR_KEY     - Operator wallet private key (required)
 *   POLL_INTERVAL_S  - Seconds between cycles (default: 300 = 5 min)
 *
 * Usage: bun run operator
 */

import {
  createPublicClient,
  createWalletClient,
  http,
  formatUnits,
  parseUnits,
  type PublicClient,
  type WalletClient,
  type Address,
} from "viem";
import { base } from "viem/chains";
import { privateKeyToAccount } from "viem/accounts";

// ── Config ──────────────────────────────────────────────────────────────

const SDIEM_ADDRESS = process.env.SDIEM_ADDRESS as Address | undefined;
const CSDIEM_ADDRESS = process.env.CSDIEM_ADDRESS as Address | undefined;
const DIEM_ADDRESS = (process.env.DIEM_ADDRESS ?? "0xF4d97F2da56e8c3098f3a8D538DB630A2606a024") as Address;
const USDC_ADDRESS = (process.env.USDC_ADDRESS ?? "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913") as Address;
const RPC_URL = process.env.RPC_URL ?? "";
const OPERATOR_KEY = process.env.OPERATOR_KEY ?? "";
const POLL_INTERVAL_S = Number(process.env.POLL_INTERVAL_S ?? "300");

const DIEM_DECIMALS = 18;
const USDC_DECIMALS = 6;
const BPS = 10_000n;

// ── Validation ──────────────────────────────────────────────────────────

if (!SDIEM_ADDRESS && !CSDIEM_ADDRESS) {
  console.error("Error: At least one of SDIEM_ADDRESS or CSDIEM_ADDRESS required");
  process.exit(1);
}
if (!RPC_URL) {
  console.error("Error: RPC_URL env is required");
  process.exit(1);
}
if (!OPERATOR_KEY) {
  console.error("Error: OPERATOR_KEY env is required");
  process.exit(1);
}

// ── ABIs (only what we need) ────────────────────────────────────────────

const STAKING_READ_ABI = [
  {
    name: "totalStaked",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint256" }],
  },
  {
    name: "liquidBuffer",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint256" }],
  },
  {
    name: "forwardStaked",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint256" }],
  },
  {
    name: "pendingUnstake",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint256" }],
  },
  {
    name: "paused",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "bool" }],
  },
  {
    name: "BUFFER_TARGET_BPS",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint256" }],
  },
  {
    name: "BUFFER_FLOOR_BPS",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint256" }],
  },
] as const;

// sDIEM-specific reads
const SDIEM_READ_ABI = [
  ...STAKING_READ_ABI,
  {
    name: "periodFinish",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint256" }],
  },
  {
    name: "rewardRate",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint256" }],
  },
] as const;

// csDIEM-specific reads
const CSDIEM_READ_ABI = [
  ...STAKING_READ_ABI,
  {
    name: "totalAssets",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint256" }],
  },
  {
    name: "totalSupply",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint256" }],
  },
] as const;

// Write ABIs
const OPERATOR_WRITE_ABI = [
  {
    name: "deployToVenice",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [{ name: "amount", type: "uint256" }],
    outputs: [],
  },
  {
    name: "initiateBufferReplenish",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [{ name: "amount", type: "uint256" }],
    outputs: [],
  },
  {
    name: "completeBufferReplenish",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [],
    outputs: [],
  },
] as const;

const SDIEM_NOTIFY_ABI = [
  {
    name: "notifyRewardAmount",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [{ name: "reward", type: "uint256" }],
    outputs: [],
  },
] as const;

const CSDIEM_DONATE_ABI = [
  {
    name: "donate",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [{ name: "amount", type: "uint256" }],
    outputs: [],
  },
] as const;

// DIEM staking reads (to check cooldown status)
const DIEM_STAKING_ABI = [
  {
    name: "stakedInfos",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "account", type: "address" }],
    outputs: [
      { name: "stakedAmount", type: "uint256" },
      { name: "cooldownEndTimestamp", type: "uint256" },
      { name: "pendingUnstakeAmount", type: "uint256" },
    ],
  },
] as const;

// ── Types ───────────────────────────────────────────────────────────────

interface VaultState {
  totalStaked: bigint;
  liquidBuffer: bigint;
  forwardStaked: bigint;
  pendingUnstake: bigint;
  paused: boolean;
  bufferTargetBps: bigint;
  bufferFloorBps: bigint;
  // DIEM staking cooldown info for this contract
  cooldownEndTimestamp: bigint;
}

// ── Helpers ─────────────────────────────────────────────────────────────

const dim = (s: string) => `\x1b[2m${s}\x1b[0m`;
const bold = (s: string) => `\x1b[1m${s}\x1b[0m`;
const green = (s: string) => `\x1b[32m${s}\x1b[0m`;
const yellow = (s: string) => `\x1b[33m${s}\x1b[0m`;
const red = (s: string) => `\x1b[31m${s}\x1b[0m`;

function fmtDiem(amount: bigint): string {
  return formatUnits(amount, DIEM_DECIMALS);
}

function bufferRatioBps(buffer: bigint, total: bigint): bigint {
  if (total === 0n) return BPS;
  return (buffer * BPS) / total;
}

// ── Read state ──────────────────────────────────────────────────────────

async function readVaultState(
  client: PublicClient,
  address: Address,
  abi: readonly any[]
): Promise<VaultState> {
  const [totalStaked, liquidBuffer, forwardStaked, pendingUnstake, paused, bufferTargetBps, bufferFloorBps] =
    await Promise.all([
      client.readContract({ address, abi, functionName: "totalStaked" }) as Promise<bigint>,
      client.readContract({ address, abi, functionName: "liquidBuffer" }) as Promise<bigint>,
      client.readContract({ address, abi, functionName: "forwardStaked" }) as Promise<bigint>,
      client.readContract({ address, abi, functionName: "pendingUnstake" }) as Promise<bigint>,
      client.readContract({ address, abi, functionName: "paused" }) as Promise<boolean>,
      client.readContract({ address, abi, functionName: "BUFFER_TARGET_BPS" }) as Promise<bigint>,
      client.readContract({ address, abi, functionName: "BUFFER_FLOOR_BPS" }) as Promise<bigint>,
    ]);

  // Read cooldown info from DIEM staking contract
  const [, cooldownEndTimestamp] = (await client.readContract({
    address: DIEM_ADDRESS,
    abi: DIEM_STAKING_ABI,
    functionName: "stakedInfos",
    args: [address],
  })) as [bigint, bigint, bigint];

  return {
    totalStaked,
    liquidBuffer,
    forwardStaked,
    pendingUnstake,
    paused,
    bufferTargetBps,
    bufferFloorBps,
    cooldownEndTimestamp,
  };
}

// ── Action: Deploy excess buffer to Venice ─────────────────────────────

async function maybeDeployToVenice(
  label: string,
  address: Address,
  state: VaultState,
  wallet: WalletClient,
  account: Address
): Promise<void> {
  if (state.paused) return;
  if (state.totalStaked === 0n) return;

  const currentRatio = bufferRatioBps(state.liquidBuffer, state.totalStaked);
  if (currentRatio <= state.bufferTargetBps) return;

  // Deploy excess: buffer - (totalStaked * targetBps / BPS)
  const targetBuffer = (state.totalStaked * state.bufferTargetBps) / BPS;
  const excess = state.liquidBuffer - targetBuffer;

  if (excess <= 0n) return;

  console.log(
    `  ${label}: Buffer ${fmtDiem(state.liquidBuffer)} (${Number(currentRatio) / 100}%) > target ${Number(state.bufferTargetBps) / 100}%`
  );
  console.log(`  ${label}: ${green(`Deploying ${fmtDiem(excess)} DIEM to Venice`)}`);

  try {
    const hash = await wallet.writeContract({
      address,
      abi: OPERATOR_WRITE_ABI,
      functionName: "deployToVenice",
      args: [excess],
      chain: base,
      account,
    });
    console.log(`  ${label}: ${dim(`tx: ${hash}`)}`);
  } catch (err: any) {
    console.error(`  ${label}: ${red(`deployToVenice failed: ${err.message}`)}`);
  }
}

// ── Action: Initiate buffer replenish when below floor ─────────────────

async function maybeInitiateReplenish(
  label: string,
  address: Address,
  state: VaultState,
  wallet: WalletClient,
  account: Address
): Promise<void> {
  if (state.paused) return;
  if (state.totalStaked === 0n) return;
  if (state.forwardStaked === 0n) return;
  // Don't initiate if already pending
  if (state.pendingUnstake > 0n) return;

  const currentRatio = bufferRatioBps(state.liquidBuffer, state.totalStaked);
  if (currentRatio >= state.bufferFloorBps) return;

  // Replenish to target: (totalStaked * targetBps / BPS) - buffer
  const targetBuffer = (state.totalStaked * state.bufferTargetBps) / BPS;
  let replenishAmount = targetBuffer - state.liquidBuffer;

  // Cap to what's available on Venice
  if (replenishAmount > state.forwardStaked) {
    replenishAmount = state.forwardStaked;
  }

  if (replenishAmount <= 0n) return;

  console.log(
    `  ${label}: Buffer ${fmtDiem(state.liquidBuffer)} (${Number(currentRatio) / 100}%) < floor ${Number(state.bufferFloorBps) / 100}%`
  );
  console.log(`  ${label}: ${yellow(`Initiating replenish of ${fmtDiem(replenishAmount)} DIEM (24h cooldown)`)}`);

  try {
    const hash = await wallet.writeContract({
      address,
      abi: OPERATOR_WRITE_ABI,
      functionName: "initiateBufferReplenish",
      args: [replenishAmount],
      chain: base,
      account,
    });
    console.log(`  ${label}: ${dim(`tx: ${hash}`)}`);
  } catch (err: any) {
    console.error(`  ${label}: ${red(`initiateBufferReplenish failed: ${err.message}`)}`);
  }
}

// ── Action: Complete pending replenish after cooldown ───────────────────

async function maybeCompleteReplenish(
  label: string,
  address: Address,
  state: VaultState,
  wallet: WalletClient,
  account: Address
): Promise<void> {
  if (state.pendingUnstake === 0n) return;

  const now = BigInt(Math.floor(Date.now() / 1000));
  if (now < state.cooldownEndTimestamp) {
    const remaining = Number(state.cooldownEndTimestamp - now);
    const hours = Math.floor(remaining / 3600);
    const mins = Math.floor((remaining % 3600) / 60);
    console.log(
      `  ${label}: ${dim(`Cooldown active — ${fmtDiem(state.pendingUnstake)} DIEM pending, ${hours}h${mins}m remaining`)}`
    );
    return;
  }

  console.log(`  ${label}: ${green(`Completing replenish of ${fmtDiem(state.pendingUnstake)} DIEM`)}`);

  try {
    const hash = await wallet.writeContract({
      address,
      abi: OPERATOR_WRITE_ABI,
      functionName: "completeBufferReplenish",
      chain: base,
      account,
    });
    console.log(`  ${label}: ${dim(`tx: ${hash}`)}`);
  } catch (err: any) {
    console.error(`  ${label}: ${red(`completeBufferReplenish failed: ${err.message}`)}`);
  }
}

// ── Cycle ───────────────────────────────────────────────────────────────

async function runCycle(
  client: PublicClient,
  wallet: WalletClient,
  account: Address
): Promise<void> {
  const timestamp = new Date().toISOString().slice(11, 19);
  console.log(`\n  ── Cycle ${timestamp} ──`);

  // sDIEM
  if (SDIEM_ADDRESS) {
    try {
      const state = await readVaultState(client, SDIEM_ADDRESS, SDIEM_READ_ABI);

      if (state.paused) {
        console.log(`  sDIEM: ${red("PAUSED")}`);
      } else {
        const ratio = state.totalStaked > 0n ? bufferRatioBps(state.liquidBuffer, state.totalStaked) : BPS;
        console.log(
          `  sDIEM: staked=${fmtDiem(state.totalStaked)} buffer=${fmtDiem(state.liquidBuffer)} (${Number(ratio) / 100}%) venice=${fmtDiem(state.forwardStaked)} pending=${fmtDiem(state.pendingUnstake)}`
        );

        await maybeDeployToVenice("sDIEM", SDIEM_ADDRESS, state, wallet, account);
        await maybeInitiateReplenish("sDIEM", SDIEM_ADDRESS, state, wallet, account);
        await maybeCompleteReplenish("sDIEM", SDIEM_ADDRESS, state, wallet, account);
      }
    } catch (err: any) {
      console.error(`  sDIEM: ${red(`read error: ${err.message}`)}`);
    }
  }

  // csDIEM
  if (CSDIEM_ADDRESS) {
    try {
      const state = await readVaultState(client, CSDIEM_ADDRESS, CSDIEM_READ_ABI);

      if (state.paused) {
        console.log(`  csDIEM: ${red("PAUSED")}`);
      } else {
        const total = state.liquidBuffer + state.forwardStaked + state.pendingUnstake;
        const ratio = total > 0n ? bufferRatioBps(state.liquidBuffer, total) : BPS;
        console.log(
          `  csDIEM: assets=${fmtDiem(total)} buffer=${fmtDiem(state.liquidBuffer)} (${Number(ratio) / 100}%) venice=${fmtDiem(state.forwardStaked)} pending=${fmtDiem(state.pendingUnstake)}`
        );

        await maybeDeployToVenice("csDIEM", CSDIEM_ADDRESS, state, wallet, account);
        await maybeInitiateReplenish("csDIEM", CSDIEM_ADDRESS, state, wallet, account);
        await maybeCompleteReplenish("csDIEM", CSDIEM_ADDRESS, state, wallet, account);
      }
    } catch (err: any) {
      console.error(`  csDIEM: ${red(`read error: ${err.message}`)}`);
    }
  }
}

// ── Main ────────────────────────────────────────────────────────────────

async function main() {
  const account = privateKeyToAccount(OPERATOR_KEY as `0x${string}`);

  console.log(`\n  ${bold("DIEM Relay — Venice Operator")}`);
  console.log(dim(`  Operator: ${account.address}`));
  if (SDIEM_ADDRESS) console.log(dim(`  sDIEM:    ${SDIEM_ADDRESS}`));
  if (CSDIEM_ADDRESS) console.log(dim(`  csDIEM:   ${CSDIEM_ADDRESS}`));
  console.log(dim(`  DIEM:     ${DIEM_ADDRESS}`));
  console.log(dim(`  Interval: ${POLL_INTERVAL_S}s`));

  const client = createPublicClient({
    chain: base,
    transport: http(RPC_URL),
  }) as PublicClient;

  const wallet = createWalletClient({
    account,
    chain: base,
    transport: http(RPC_URL),
  });

  // Run first cycle immediately
  await runCycle(client, wallet, account.address);

  // Then run on interval
  const interval = setInterval(async () => {
    try {
      await runCycle(client, wallet, account.address);
    } catch (err: any) {
      console.error(`  ${red(`Cycle error: ${err.message}`)}`);
    }
  }, POLL_INTERVAL_S * 1000);

  console.log(dim(`\n  Operator running. Ctrl+C to stop.\n`));

  process.on("SIGINT", () => {
    console.log(dim("\n  Stopping operator..."));
    clearInterval(interval);
    process.exit(0);
  });

  process.on("SIGTERM", () => {
    clearInterval(interval);
    process.exit(0);
  });
}

main().catch((e) => {
  console.error(`Fatal: ${e.message}`);
  process.exit(1);
});
