"use client";

import { useEffect } from "react";
import { useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { useQueryClient } from "@tanstack/react-query";
import { type Abi } from "viem";
import { sDiemAbi, sDiemV2Abi } from "@/config/abis";
import { useContracts } from "./useContracts";

export function useExit() {
  const { sdiem, isV2 } = useContracts();
  const abi: Abi = isV2 ? (sDiemV2Abi as unknown as Abi) : (sDiemAbi as unknown as Abi);

  const queryClient = useQueryClient();
  const { writeContract, data: hash, isPending, error, reset } = useWriteContract();

  const { isLoading: isConfirming, isSuccess } =
    useWaitForTransactionReceipt({ hash });

  useEffect(() => {
    if (isSuccess) queryClient.invalidateQueries();
  }, [isSuccess, queryClient]);

  const exit = () => {
    writeContract({
      address: sdiem,
      abi,
      functionName: "exit",
    });
  };

  return { exit, isPending, isConfirming, isSuccess, error, hash, reset };
}
