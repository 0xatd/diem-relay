/**
 * DIEM Relay — Permissionless Keeper Bot
 *
 * Calls gas-only permissionless functions on sDIEM, csDIEM, and RevenueSplitter:
 *   1. claimFromVenice()  — claim matured DIEM from Venice (sDIEM + csDIEM)
 *   2. redeployExcess()   — restake idle DIEM to Venice (sDIEM + csDIEM)
 *   3. distribute()       — split USDC revenue to sDIEM and csDIEM
 *
 * No special role needed — the operator wallet just provides gas.
 *
 * Env:
 *   SDIEM_ADDRESS       - sDIEM contract address (optional)
 *   CSDIEM_ADDRESS      - csDIEM contract address (optional)
 *   SPLITTER_ADDRESS    - RevenueSplitter contract address (optional)
 *   DIEM_ADDRESS        - DIEM token address (default: Base DIEM)
 *   RPC_URL             - Base JSON-RPC URL (required)
 *   OPERATOR_KEY        - Wallet private key (required, gas-only)
 *   POLL_INTERVAL_S     - Seconds between cycles (default: 300 = 5 min)
 *
 * Usage: bun run operator
 */

import {
  createPublicClient,
  createWalletClient,
  http,
  formatUnits,
  type PublicClient,
  type WalletClient,
  type Address,
} from "viem";
import { base } from "viem/chains";
import { privateKeyToAccount } from "viem/accounts";

// ── Config ──────────────────────────────────────────────────────────────

const SDIEM_ADDRESS = process.env.SDIEM_ADDRESS as Address | undefined;
const CSDIEM_ADDRESS = process.env.CSDIEM_ADDRESS as Address | undefined;
const SPLITTER_ADDRESS = process.env.SPLITTER_ADDRESS as Address | undefined;
const DIEM_ADDRESS = (process.env.DIEM_ADDRESS ?? "0xF4d97F2da56e8c3098f3a8D538DB630A2606a024") as Address;
const RPC_URL = process.env.RPC_URL ?? "";
const OPERATOR_KEY = process.env.OPERATOR_KEY ?? "";
const POLL_INTERVAL_S = Number(process.env.POLL_INTERVAL_S ?? "300");

// ── Validation ──────────────────────────────────────────────────────────

if (!SDIEM_ADDRESS && !CSDIEM_ADDRESS && !SPLITTER_ADDRESS) {
  console.error("Error: At least one of SDIEM_ADDRESS, CSDIEM_ADDRESS, or SPLITTER_ADDRESS required");
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

// ── ABIs (minimal — only what we read/write) ─────────────────────────────

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
  {
    name: "balanceOf",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ type: "uint256" }],
  },
] as const;

const STAKING_COMMON_ABI = [
  { name: "paused", type: "function", stateMutability: "view", inputs: [], outputs: [{ type: "bool" }] },
  { name: "totalPendingWithdrawals", type: "function", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { name: "totalPendingRedemptions", type: "function", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { name: "totalStaked", type: "function", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { name: "totalAssets", type: "function", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { name: "totalSupply", type: "function", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { name: "rewardRate", type: "function", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { name: "periodFinish", type: "function", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { name: "claimFromVenice", type: "function", stateMutability: "nonpayable", inputs: [], outputs: [] },
  { name: "redeployExcess", type: "function", stateMutability: "nonpayable", inputs: [], outputs: [] },
] as const;

const SPLITTER_ABI = [
  { name: "pendingRevenue", type: "function", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { name: "minDistribution", type: "function", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { name: "sdiemBps", type: "function", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { name: "paused", type: "function", stateMutability: "view", inputs: [], outputs: [{ type: "bool" }] },
  { name: "distribute", type: "function", stateMutability: "nonpayable", inputs: [], outputs: [] },
] as const;

// ── Helpers ─────────────────────────────────────────────────────────────

const dim = (s: string) => `\x1b[2m${s}\x1b[0m`;
const bold = (s: string) => `\x1b[1m${s}\x1b[0m`;
const green = (s: string) => `\x1b[32m${s}\x1b[0m`;
const yellow = (s: string) => `\x1b[33m${s}\x1b[0m`;
const red = (s: string) => `\x1b[31m${s}\x1b[0m`;

function fmtDiem(amount: bigint): string {
  return formatUnits(amount, 18);
}

function fmtUsdc(amount: bigint): string {
  return formatUnits(amount, 6);
}

function fmtTime(seconds: number): string {
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  return `${h}h${m}m`;
}

// ── Venice state for a staking contract ─────────────────────────────────

interface VeniceState {
  stakedAmount: bigint;
  cooldownEnd: bigint;
  pendingUnstake: bigint;
  liquidBalance: bigint;
}

async function readVeniceState(client: PublicClient, contractAddress: Address): Promise<VeniceState> {
  const [[stakedAmount, cooldownEnd, pendingUnstake], liquidBalance] = await Promise.all([
    client.readContract({
      address: DIEM_ADDRESS,
      abi: DIEM_STAKING_ABI,
      functionName: "stakedInfos",
      args: [contractAddress],
    }) as Promise<[bigint, bigint, bigint]>,
    client.readContract({
      address: DIEM_ADDRESS,
      abi: DIEM_STAKING_ABI,
      functionName: "balanceOf",
      args: [contractAddress],
    }) as Promise<bigint>,
  ]);

  return { stakedAmount, cooldownEnd, pendingUnstake, liquidBalance };
}

// ── sDIEM cycle ─────────────────────────────────────────────────────────

async function cycleSDiem(
  client: PublicClient,
  wallet: WalletClient,
  account: Address,
  address: Address
): Promise<void> {
  const [paused, totalStaked, totalPendingWithdrawals, rewardRate, periodFinish] = await Promise.all([
    client.readContract({ address, abi: STAKING_COMMON_ABI, functionName: "paused" }) as Promise<boolean>,
    client.readContract({ address, abi: STAKING_COMMON_ABI, functionName: "totalStaked" }) as Promise<bigint>,
    client.readContract({ address, abi: STAKING_COMMON_ABI, functionName: "totalPendingWithdrawals" }) as Promise<bigint>,
    client.readContract({ address, abi: STAKING_COMMON_ABI, functionName: "rewardRate" }) as Promise<bigint>,
    client.readContract({ address, abi: STAKING_COMMON_ABI, functionName: "periodFinish" }) as Promise<bigint>,
  ]);

  if (paused) {
    console.log(`  sDIEM: ${red("PAUSED")}`);
    return;
  }

  const venice = await readVeniceState(client, address);
  const now = BigInt(Math.floor(Date.now() / 1000));
  const rewardActive = periodFinish > now;

  console.log(
    `  sDIEM: staked=${fmtDiem(totalStaked)} liquid=${fmtDiem(venice.liquidBalance)} venice=${fmtDiem(venice.stakedAmount)} pending_w=${fmtDiem(totalPendingWithdrawals)} rewards=${rewardActive ? green("active") : dim("ended")}`
  );

  // 1. Claim from Venice if cooldown expired and there's pending unstake
  if (venice.pendingUnstake > 0n) {
    if (now >= venice.cooldownEnd) {
      console.log(`  sDIEM: ${green(`Claiming ${fmtDiem(venice.pendingUnstake)} DIEM from Venice`)}`);
      try {
        const hash = await wallet.writeContract({
          address,
          abi: STAKING_COMMON_ABI,
          functionName: "claimFromVenice",
          chain: base,
          account,
        });
        console.log(`  sDIEM: ${dim(`tx: ${hash}`)}`);
      } catch (err: any) {
        console.error(`  sDIEM: ${red(`claimFromVenice failed: ${err.message}`)}`);
      }
    } else {
      const remaining = Number(venice.cooldownEnd - now);
      console.log(`  sDIEM: ${dim(`Venice cooldown — ${fmtDiem(venice.pendingUnstake)} pending, ${fmtTime(remaining)} remaining`)}`);
    }
  }

  // 2. Redeploy excess liquid DIEM to Venice
  const excess = venice.liquidBalance > totalPendingWithdrawals
    ? venice.liquidBalance - totalPendingWithdrawals
    : 0n;

  if (excess > 0n && venice.pendingUnstake === 0n) {
    console.log(`  sDIEM: ${green(`Redeploying ${fmtDiem(excess)} excess DIEM to Venice`)}`);
    try {
      const hash = await wallet.writeContract({
        address,
        abi: STAKING_COMMON_ABI,
        functionName: "redeployExcess",
        chain: base,
        account,
      });
      console.log(`  sDIEM: ${dim(`tx: ${hash}`)}`);
    } catch (err: any) {
      console.error(`  sDIEM: ${red(`redeployExcess failed: ${err.message}`)}`);
    }
  }
}

// ── csDIEM cycle ────────────────────────────────────────────────────────

async function cycleCsDiem(
  client: PublicClient,
  wallet: WalletClient,
  account: Address,
  address: Address
): Promise<void> {
  const [paused, totalAssets, totalSupply, totalPendingRedemptions] = await Promise.all([
    client.readContract({ address, abi: STAKING_COMMON_ABI, functionName: "paused" }) as Promise<boolean>,
    client.readContract({ address, abi: STAKING_COMMON_ABI, functionName: "totalAssets" }) as Promise<bigint>,
    client.readContract({ address, abi: STAKING_COMMON_ABI, functionName: "totalSupply" }) as Promise<bigint>,
    client.readContract({ address, abi: STAKING_COMMON_ABI, functionName: "totalPendingRedemptions" }) as Promise<bigint>,
  ]);

  if (paused) {
    console.log(`  csDIEM: ${red("PAUSED")}`);
    return;
  }

  const venice = await readVeniceState(client, address);
  const now = BigInt(Math.floor(Date.now() / 1000));
  const sharePrice = totalSupply > 0n ? (totalAssets * 10n ** 18n) / totalSupply : 10n ** 18n;

  console.log(
    `  csDIEM: assets=${fmtDiem(totalAssets)} shares=${fmtDiem(totalSupply)} price=${fmtDiem(sharePrice)} liquid=${fmtDiem(venice.liquidBalance)} venice=${fmtDiem(venice.stakedAmount)} pending_r=${fmtDiem(totalPendingRedemptions)}`
  );

  // 1. Claim from Venice if cooldown expired and there's pending unstake
  if (venice.pendingUnstake > 0n) {
    if (now >= venice.cooldownEnd) {
      console.log(`  csDIEM: ${green(`Claiming ${fmtDiem(venice.pendingUnstake)} DIEM from Venice`)}`);
      try {
        const hash = await wallet.writeContract({
          address,
          abi: STAKING_COMMON_ABI,
          functionName: "claimFromVenice",
          chain: base,
          account,
        });
        console.log(`  csDIEM: ${dim(`tx: ${hash}`)}`);
      } catch (err: any) {
        console.error(`  csDIEM: ${red(`claimFromVenice failed: ${err.message}`)}`);
      }
    } else {
      const remaining = Number(venice.cooldownEnd - now);
      console.log(`  csDIEM: ${dim(`Venice cooldown — ${fmtDiem(venice.pendingUnstake)} pending, ${fmtTime(remaining)} remaining`)}`);
    }
  }

  // 2. Redeploy excess liquid DIEM to Venice
  const excess = venice.liquidBalance > totalPendingRedemptions
    ? venice.liquidBalance - totalPendingRedemptions
    : 0n;

  if (excess > 0n && venice.pendingUnstake === 0n) {
    console.log(`  csDIEM: ${green(`Redeploying ${fmtDiem(excess)} excess DIEM to Venice`)}`);
    try {
      const hash = await wallet.writeContract({
        address,
        abi: STAKING_COMMON_ABI,
        functionName: "redeployExcess",
        chain: base,
        account,
      });
      console.log(`  csDIEM: ${dim(`tx: ${hash}`)}`);
    } catch (err: any) {
      console.error(`  csDIEM: ${red(`redeployExcess failed: ${err.message}`)}`);
    }
  }
}

// ── RevenueSplitter cycle ────────────────────────────────────────────────

async function cycleSplitter(
  client: PublicClient,
  wallet: WalletClient,
  account: Address,
  address: Address
): Promise<void> {
  const [pending, minDist, sdiemBps, paused] = await Promise.all([
    client.readContract({ address, abi: SPLITTER_ABI, functionName: "pendingRevenue" }) as Promise<bigint>,
    client.readContract({ address, abi: SPLITTER_ABI, functionName: "minDistribution" }) as Promise<bigint>,
    client.readContract({ address, abi: SPLITTER_ABI, functionName: "sdiemBps" }) as Promise<bigint>,
    client.readContract({ address, abi: SPLITTER_ABI, functionName: "paused" }) as Promise<boolean>,
  ]);

  if (paused) {
    console.log(`  Splitter: ${red("PAUSED")}`);
    return;
  }

  const csdiemPct = (10_000n - sdiemBps) * 100n / 10_000n;
  const sdiemPct = sdiemBps * 100n / 10_000n;

  console.log(
    `  Splitter: pending=${fmtUsdc(pending)} USDC (min=${fmtUsdc(minDist)}) split=${Number(sdiemPct)}% sDIEM / ${Number(csdiemPct)}% csDIEM`
  );

  if (pending >= minDist) {
    console.log(`  Splitter: ${green(`Distributing ${fmtUsdc(pending)} USDC`)}`);
    try {
      const hash = await wallet.writeContract({
        address,
        abi: SPLITTER_ABI,
        functionName: "distribute",
        chain: base,
        account,
      });
      console.log(`  Splitter: ${dim(`tx: ${hash}`)}`);
    } catch (err: any) {
      console.error(`  Splitter: ${red(`distribute failed: ${err.message}`)}`);
    }
  }
}

// ── Main cycle ──────────────────────────────────────────────────────────

async function runCycle(
  client: PublicClient,
  wallet: WalletClient,
  account: Address
): Promise<void> {
  const timestamp = new Date().toISOString().slice(11, 19);
  console.log(`\n  ── Cycle ${timestamp} ──`);

  if (SDIEM_ADDRESS) {
    try {
      await cycleSDiem(client, wallet, account, SDIEM_ADDRESS);
    } catch (err: any) {
      console.error(`  sDIEM: ${red(`error: ${err.message}`)}`);
    }
  }

  if (CSDIEM_ADDRESS) {
    try {
      await cycleCsDiem(client, wallet, account, CSDIEM_ADDRESS);
    } catch (err: any) {
      console.error(`  csDIEM: ${red(`error: ${err.message}`)}`);
    }
  }

  if (SPLITTER_ADDRESS) {
    try {
      await cycleSplitter(client, wallet, account, SPLITTER_ADDRESS);
    } catch (err: any) {
      console.error(`  Splitter: ${red(`error: ${err.message}`)}`);
    }
  }
}

// ── Main ────────────────────────────────────────────────────────────────

async function main() {
  const account = privateKeyToAccount(OPERATOR_KEY as `0x${string}`);

  console.log(`\n  ${bold("DIEM Relay — Permissionless Keeper")}`);
  console.log(dim(`  Wallet:    ${account.address}`));
  if (SDIEM_ADDRESS) console.log(dim(`  sDIEM:     ${SDIEM_ADDRESS}`));
  if (CSDIEM_ADDRESS) console.log(dim(`  csDIEM:    ${CSDIEM_ADDRESS}`));
  if (SPLITTER_ADDRESS) console.log(dim(`  Splitter:  ${SPLITTER_ADDRESS}`));
  console.log(dim(`  DIEM:      ${DIEM_ADDRESS}`));
  console.log(dim(`  Interval:  ${POLL_INTERVAL_S}s`));

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

  console.log(dim(`\n  Keeper running. Ctrl+C to stop.\n`));

  process.on("SIGINT", () => {
    console.log(dim("\n  Stopping keeper..."));
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
