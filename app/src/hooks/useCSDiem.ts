"use client";

import { useReadContracts, useAccount } from "wagmi";
import { parseUnits, zeroAddress } from "viem";
import { csDiemAbi } from "@/config/abis";
import { CSDIEM_ADDRESS } from "@/config/contracts";

const ONE_SHARE = parseUnits("1", 18);

export function useCSDiem() {
  const { address } = useAccount();
  const user = address ?? zeroAddress;

  const { data, isLoading, refetch } = useReadContracts({
    contracts: [
      { address: CSDIEM_ADDRESS, abi: csDiemAbi, functionName: "totalAssets" },
      { address: CSDIEM_ADDRESS, abi: csDiemAbi, functionName: "totalSupply" },
      { address: CSDIEM_ADDRESS, abi: csDiemAbi, functionName: "convertToAssets", args: [ONE_SHARE] },
      { address: CSDIEM_ADDRESS, abi: csDiemAbi, functionName: "paused" },
      { address: CSDIEM_ADDRESS, abi: csDiemAbi, functionName: "balanceOf", args: [user] },
    ],
    query: { refetchInterval: 15_000 },
  });

  const get = <T,>(index: number): T | undefined =>
    data?.[index]?.status === "success"
      ? (data[index].result as T)
      : undefined;

  const userShares = address ? (get<bigint>(4) ?? 0n) : 0n;
  const sharePrice = get<bigint>(2) ?? parseUnits("1", 18);

  const userAssetsValue =
    userShares > 0n ? (userShares * sharePrice) / ONE_SHARE : 0n;

  return {
    totalAssets: get<bigint>(0) ?? 0n,
    totalSupply: get<bigint>(1) ?? 0n,
    sharePrice,
    paused: get<boolean>(3) ?? false,
    userShares,
    userAssetsValue,
    isLoading,
    refetch,
  };
}
