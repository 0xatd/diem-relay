import { type Address } from "viem";

export const DIEM_TOKEN = "0xf4d97f2da56e8c3098f3a8d538db630a2606a024" as Address;
export const USDC_BASE = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913" as Address;

// v1 (live, exit-only after migration window) ─────────────────────────────
// Override via NEXT_PUBLIC_SDIEM_ADDRESS / NEXT_PUBLIC_CSDIEM_ADDRESS.
export const SDIEM_ADDRESS = (process.env.NEXT_PUBLIC_SDIEM_ADDRESS ??
  "0xdbF05AF4fdAA518AC9c4dc5aA49399b8dd0B4be2") as Address;
export const CSDIEM_ADDRESS = (process.env.NEXT_PUBLIC_CSDIEM_ADDRESS ??
  "0x4899f5fBA1bf43C8Bea483bE6342e55Bc16e045a") as Address;

// v2 (live, deployed 2026-05-21) ──────────────────────────────────────────
// sDIEM v2: transferable ERC-20 + EIP-2612 permit, Synthetix rewards on _update.
// csDIEM v2: canonical ERC-4626 wrapper over sDIEM v2 (asset() = sDIEM v2),
// synchronous redeem, maxRedeem == balanceOf, depositDIEM zap for raw DIEM.
// Override via NEXT_PUBLIC_SDIEM_V2_ADDRESS / NEXT_PUBLIC_CSDIEM_V2_ADDRESS.
export const SDIEM_V2_ADDRESS = (process.env.NEXT_PUBLIC_SDIEM_V2_ADDRESS ??
  "0x8065228a8156590A8BFca30678394e9db91f80Ee") as Address;
export const CSDIEM_V2_ADDRESS = (process.env.NEXT_PUBLIC_CSDIEM_V2_ADDRESS ??
  "0x78B8726929911044748374178CB2D417A54319e5") as Address;

// Migration helper — the version new users land on. Migrating LPs still
// need v1 addresses for the requestWithdraw → 24h → completeWithdraw exit.
export const DEFAULT_VERSION: "v1" | "v2" = "v2";

export const DIEM_DECIMALS = 18;
export const USDC_DECIMALS = 6;
