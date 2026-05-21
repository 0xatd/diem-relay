"use client";

import { useEffect } from "react";
import {
  useWriteContract,
  useWaitForTransactionReceipt,
  useAccount,
} from "wagmi";
import { useQueryClient } from "@tanstack/react-query";
import { type Abi } from "viem";
import { csDiemAbi, csDiemV2Abi } from "@/config/abis";
import { useContracts } from "./useContracts";

// Deposits raw DIEM into csDIEM.
//   - v1: `deposit(diem, receiver)` — the v1 vault's asset() is DIEM.
//   - v2: `depositDIEM(diem, receiver)` zap — the v2 vault's asset() is sDIEM v2,
//         so raw-DIEM users go through the zap which stakes internally.
// Approval target is the csDIEM contract in both cases.
export function useDepositCSDiem() {
  const { address } = useAccount();
  const { csdiem, isV2 } = useContracts();
  const abi: Abi = isV2
    ? (csDiemV2Abi as unknown as Abi)
    : (csDiemAbi as unknown as Abi);

  const queryClient = useQueryClient();
  const { writeContract, data: hash, isPending, error, reset } =
    useWriteContract();

  const { isLoading: isConfirming, isSuccess } =
    useWaitForTransactionReceipt({ hash });

  useEffect(() => {
    if (isSuccess) queryClient.invalidateQueries();
  }, [isSuccess, queryClient]);

  const deposit = (diemAmount: bigint) => {
    if (!address) return;
    writeContract({
      address: csdiem,
      abi,
      functionName: isV2 ? "depositDIEM" : "deposit",
      args: [diemAmount, address],
    });
  };

  return { deposit, isPending, isConfirming, isSuccess, error, hash, reset };
}
