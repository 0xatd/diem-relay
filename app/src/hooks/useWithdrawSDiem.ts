"use client";

import { useEffect } from "react";
import { useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { useQueryClient } from "@tanstack/react-query";
import { type Abi } from "viem";
import { sDiemAbi, sDiemV2Abi } from "@/config/abis";
import { useContracts } from "./useContracts";

function pickAbi(isV2: boolean): Abi {
  return isV2 ? (sDiemV2Abi as unknown as Abi) : (sDiemAbi as unknown as Abi);
}

function useTx() {
  const queryClient = useQueryClient();
  const { writeContract, data: hash, isPending, error, reset } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } =
    useWaitForTransactionReceipt({ hash });
  useEffect(() => {
    if (isSuccess) queryClient.invalidateQueries();
  }, [isSuccess, queryClient]);
  return { writeContract, hash, isPending, isConfirming, isSuccess, error, reset };
}

export function useRequestWithdraw() {
  const { sdiem, isV2 } = useContracts();
  const abi = pickAbi(isV2);
  const tx = useTx();
  const requestWithdraw = (amount: bigint) => {
    tx.writeContract({
      address: sdiem,
      abi,
      functionName: "requestWithdraw",
      args: [amount],
    });
  };
  return { requestWithdraw, ...tx };
}

export function useCompleteWithdraw() {
  const { sdiem, isV2 } = useContracts();
  const abi = pickAbi(isV2);
  const tx = useTx();
  const completeWithdraw = () => {
    tx.writeContract({
      address: sdiem,
      abi,
      functionName: "completeWithdraw",
    });
  };
  return { completeWithdraw, ...tx };
}

export function useCancelWithdraw() {
  const { sdiem, isV2 } = useContracts();
  const abi = pickAbi(isV2);
  const tx = useTx();
  const cancelWithdraw = () => {
    tx.writeContract({
      address: sdiem,
      abi,
      functionName: "cancelWithdraw",
    });
  };
  return { cancelWithdraw, ...tx };
}
