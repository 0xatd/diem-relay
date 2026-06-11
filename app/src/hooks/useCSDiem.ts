"use client";

import { useReadContracts, useAccount } from "wagmi";
import { parseUnits, zeroAddress, type Abi } from "viem";
import { CSDIEM_ADDRESS, DIEM_DECIMALS } from "@/config/contracts";
import { csDiemAbi, csDiemV2Abi } from "@/config/abis";
import { useContracts } from "./useContracts";

const ONE_SHARE = parseUnits("1", DIEM_DECIMALS);

// See useSDiem.ts for the rationale on this type-erased contract-call cast.
type AnyCall = never;
const c = (x: unknown) => x as AnyCall;

// v1 csDIEM was deployed at a known address; the constant has historically
// guarded the UI from showing the wrap tab against zeroAddress. v2 always
// has an address (we ship deployed addresses in config), so this is just a
// v1 safety net.
export const isCSDiemDeployed = CSDIEM_ADDRESS !== zeroAddress;

export function useCSDiem() {
  const { address } = useAccount();
  const { csdiem, isV2 } = useContracts();
  const user = address ?? zeroAddress;

  const abi: Abi = isV2
    ? (csDiemV2Abi as unknown as Abi)
    : (csDiemAbi as unknown as Abi);

  // v1 csDIEM uses an async requestRedeem → 24h → completeRedeem flow with
  // dedicated `redemptionRequests` / `canCompleteRedeem` views. v2 csDIEM is
  // a canonical ERC-4626 with synchronous `redeem` — no pending state exists
  // on-chain.
  const v1Reads = isV2
    ? []
    : [
        c({ address: csdiem, abi, functionName: "redemptionRequests", args: [user] }),
        c({ address: csdiem, abi, functionName: "canCompleteRedeem", args: [user] }),
        c({ address: csdiem, abi, functionName: "WITHDRAWAL_DELAY" }),
      ];

  const { data, isLoading, refetch } = useReadContracts({
    contracts: [
      c({ address: csdiem, abi, functionName: "totalAssets" }),
      c({ address: csdiem, abi, functionName: "totalSupply" }),
      c({ address: csdiem, abi, functionName: "convertToAssets", args: [ONE_SHARE] }),
      c({ address: csdiem, abi, functionName: "paused" }),
      c({ address: csdiem, abi, functionName: "balanceOf", args: [user] }),
      ...v1Reads,
    ],
    query: { enabled: isV2 || isCSDiemDeployed, refetchInterval: 15_000 },
  });

  const get = <T,>(index: number): T | undefined =>
    data?.[index]?.status === "success"
      ? (data[index].result as T)
      : undefined;

  const userShares = address ? (get<bigint>(4) ?? 0n) : 0n;
  const sharePrice = get<bigint>(2) ?? ONE_SHARE;

  // userShares × sharePrice gives the DIEM-denominated value of the user's
  // position (sharePrice = DIEM per 1 csDIEM share, both 18-decimal scaled).
  const userAssetsValue =
    userShares > 0n ? (userShares * sharePrice) / ONE_SHARE : 0n;

  // v1-only fields. On v2 the wrap tab takes a sync path and never reads
  // these.
  const redemption = isV2
    ? ([0n, 0n, 0n] as const)
    : (get<readonly [bigint, bigint, bigint]>(5) ?? ([0n, 0n, 0n] as const));
  const canCompleteRedeem = isV2 ? false : (get<boolean>(6) ?? false);
  const withdrawalDelay = isV2 ? 0n : (get<bigint>(7) ?? 0n);

  return {
    deployed: isV2 ? true : isCSDiemDeployed,
    totalAssets: get<bigint>(0) ?? 0n,
    totalSupply: get<bigint>(1) ?? 0n,
    sharePrice,
    paused: get<boolean>(3) ?? false,
    userShares,
    userAssetsValue,
    pendingRedemption: {
      assets: redemption[0],
      shares: redemption[1],
      requestedAt: redemption[2],
    },
    canCompleteRedeem,
    withdrawalDelay,
    isV2,
    isLoading,
    refetch,
  };
}
