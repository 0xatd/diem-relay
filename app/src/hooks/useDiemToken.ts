"use client";

import { useReadContracts, useAccount } from "wagmi";
import { type Address } from "viem";
import { erc20Abi } from "@/config/abis";
import { DIEM_TOKEN } from "@/config/contracts";

// Read an ERC-20 token's balance and (optionally) the user's allowance for a
// given spender. Defaults to DIEM for callers that predate the v2 sDIEM-as-
// ERC-20 work; pass `token` to read sDIEM v2 or any other ERC-20 balance.
export function useDiemToken(spender?: Address, token: Address = DIEM_TOKEN) {
  const { address } = useAccount();
  const contract = { address: token, abi: erc20Abi } as const;

  const { data, isLoading, refetch } = useReadContracts({
    contracts: [
      ...(address
        ? [
            { ...contract, functionName: "balanceOf" as const, args: [address] as const },
            ...(spender
              ? [
                  {
                    ...contract,
                    functionName: "allowance" as const,
                    args: [address, spender] as const,
                  },
                ]
              : []),
          ]
        : []),
    ],
    query: {
      enabled: !!address,
      refetchInterval: 15_000,
    },
  });

  const get = <T,>(index: number): T | undefined =>
    data?.[index]?.status === "success"
      ? (data[index].result as T)
      : undefined;

  return {
    balance: get<bigint>(0) ?? 0n,
    allowance: spender ? (get<bigint>(1) ?? 0n) : 0n,
    isLoading,
    refetch,
  };
}
