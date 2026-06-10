import { type Address } from "viem";

export const DIEM_TOKEN = "0xf4d97f2da56e8c3098f3a8d538db630a2606a024" as Address;
export const USDC_BASE = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913" as Address;

// Base mainnet v2 relay contracts.
export const SDIEM_ADDRESS = (process.env.NEXT_PUBLIC_SDIEM_ADDRESS ??
  "0x8065228a8156590A8BFca30678394e9db91f80Ee") as Address;
export const CSDIEM_ADDRESS = (process.env.NEXT_PUBLIC_CSDIEM_ADDRESS ??
  "0x78B8726929911044748374178CB2D417A54319e5") as Address;

export const DIEM_DECIMALS = 18;
export const USDC_DECIMALS = 6;
