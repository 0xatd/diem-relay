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

// v1 csDIEM uses async exits:
//   requestRedeem(shares) → 24h delay → completeRedeem() | cancelRedeem()
//
// v2 csDIEM is a canonical ERC-4626 with synchronous redeem. Calling
// `redeem(shares, receiver, owner)` burns shares immediately and returns
// sDIEM v2 to the receiver. Users who want raw DIEM then exit sDIEM v2
// via the standard 24h flow.

function pickAbi(isV2: boolean): Abi {
  return isV2 ? (csDiemV2Abi as unknown as Abi) : (csDiemAbi as unknown as Abi);
}

function useTxAction() {
  const queryClient = useQueryClient();
  const { writeContract, data: hash, isPending, error, reset } =
    useWriteContract();

  const { isLoading: isConfirming, isSuccess } =
    useWaitForTransactionReceipt({ hash });

  useEffect(() => {
    if (isSuccess) queryClient.invalidateQueries();
  }, [isSuccess, queryClient]);

  return { writeContract, hash, isPending, isConfirming, isSuccess, error, reset };
}

// ── v1 async flow ──────────────────────────────────────────────────────

export function useRequestRedeemCSDiem() {
  const { csdiem, isV2 } = useContracts();
  const abi = pickAbi(isV2);
  const tx = useTxAction();
  const requestRedeem = (shares: bigint) => {
    tx.writeContract({
      address: csdiem,
      abi,
      functionName: "requestRedeem",
      args: [shares],
    });
  };
  return { requestRedeem, ...tx };
}

export function useCompleteRedeemCSDiem() {
  const { csdiem, isV2 } = useContracts();
  const abi = pickAbi(isV2);
  const tx = useTxAction();
  const completeRedeem = () => {
    tx.writeContract({
      address: csdiem,
      abi,
      functionName: "completeRedeem",
    });
  };
  return { completeRedeem, ...tx };
}

export function useCancelRedeemCSDiem() {
  const { csdiem, isV2 } = useContracts();
  const abi = pickAbi(isV2);
  const tx = useTxAction();
  const cancelRedeem = () => {
    tx.writeContract({
      address: csdiem,
      abi,
      functionName: "cancelRedeem",
    });
  };
  return { cancelRedeem, ...tx };
}

// ── v2 sync flow ───────────────────────────────────────────────────────

export function useRedeemCSDiemV2() {
  const { csdiem, isV2 } = useContracts();
  const abi = pickAbi(isV2);
  const { address } = useAccount();
  const tx = useTxAction();
  const redeem = (shares: bigint) => {
    if (!address) return;
    tx.writeContract({
      address: csdiem,
      abi,
      functionName: "redeem",
      args: [shares, address, address],
    });
  };
  return { redeem, ...tx };
}
