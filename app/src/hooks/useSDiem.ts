"use client";

import { useReadContracts, useAccount } from "wagmi";
import { zeroAddress, type Abi } from "viem";
import { sDiemAbi, sDiemV2Abi } from "@/config/abis";
import { useContracts } from "./useContracts";

// Wagmi's strict tuple inference on useReadContracts can't handle ABI
// unions, so we cast each call's `abi` to the generic Abi and each contract
// entry to `never` to bypass the arg-typing narrowing. Result decoding is
// handled manually via the `get<T>` helper, so we don't rely on wagmi's
// inferred return types.
type AnyCall = never;
const c = (x: unknown) => x as AnyCall;

export function useSDiem() {
  const { address } = useAccount();
  const { sdiem, isV2 } = useContracts();
  const user = address ?? zeroAddress;

  const abi: Abi = isV2 ? (sDiemV2Abi as unknown as Abi) : (sDiemAbi as unknown as Abi);

  const { data, isLoading, refetch } = useReadContracts({
    contracts: [
      c({ address: sdiem, abi, functionName: "totalStaked" }),
      c({ address: sdiem, abi, functionName: "rewardRate" }),
      c({ address: sdiem, abi, functionName: "periodFinish" }),
      c({ address: sdiem, abi, functionName: "paused" }),
      c({ address: sdiem, abi, functionName: "balanceOf", args: [user] }),
      c({ address: sdiem, abi, functionName: "earned", args: [user] }),
      c({ address: sdiem, abi, functionName: "withdrawalRequests", args: [user] }),
      c({ address: sdiem, abi, functionName: "canCompleteWithdraw", args: [user] }),
      c({ address: sdiem, abi, functionName: "WITHDRAWAL_DELAY" }),
      c({ address: sdiem, abi, functionName: "MIN_WITHDRAW" }),
    ],
    query: { refetchInterval: 15_000 },
  });

  const get = <T,>(index: number): T | undefined =>
    data?.[index]?.status === "success"
      ? (data[index].result as T)
      : undefined;

  const withdrawalData = get<readonly [bigint, bigint]>(6);

  return {
    totalStaked: get<bigint>(0) ?? 0n,
    rewardRate: get<bigint>(1) ?? 0n,
    periodFinish: get<bigint>(2) ?? 0n,
    paused: get<boolean>(3) ?? false,
    userStaked: address ? (get<bigint>(4) ?? 0n) : 0n,
    earned: address ? (get<bigint>(5) ?? 0n) : 0n,
    pendingWithdrawAmount: address ? (withdrawalData?.[0] ?? 0n) : 0n,
    pendingWithdrawRequestedAt: address ? (withdrawalData?.[1] ?? 0n) : 0n,
    canComplete: address ? (get<boolean>(7) ?? false) : false,
    withdrawalDelay: get<bigint>(8) ?? 86400n,
    minWithdraw: get<bigint>(9) ?? 0n,
    isLoading,
    refetch,
  };
}
