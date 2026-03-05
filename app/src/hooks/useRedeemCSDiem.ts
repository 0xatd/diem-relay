"use client";

import { useEffect } from "react";
import {
  useWriteContract,
  useWaitForTransactionReceipt,
  useAccount,
} from "wagmi";
import { useQueryClient } from "@tanstack/react-query";
import { csDiemAbi } from "@/config/abis";
import { CSDIEM_ADDRESS } from "@/config/contracts";

export function useRedeemCSDiem() {
  const { address } = useAccount();
  const queryClient = useQueryClient();
  const { writeContract, data: hash, isPending, error, reset } = useWriteContract();

  const { isLoading: isConfirming, isSuccess } =
    useWaitForTransactionReceipt({ hash });

  useEffect(() => {
    if (isSuccess) queryClient.invalidateQueries();
  }, [isSuccess, queryClient]);

  const redeem = (shares: bigint) => {
    if (!address) return;
    writeContract({
      address: CSDIEM_ADDRESS,
      abi: csDiemAbi,
      functionName: "redeem",
      args: [shares, address, address],
    });
  };

  return { redeem, isPending, isConfirming, isSuccess, error, hash, reset };
}
