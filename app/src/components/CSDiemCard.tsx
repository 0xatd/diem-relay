"use client";

import { useState } from "react";
import { parseUnits, formatUnits } from "viem";
import { useAccount, useReadContract } from "wagmi";

import { VaultCard } from "./VaultCard";
import { StatRow } from "./StatRow";
import { PausedBanner } from "./PausedBanner";
import { DepositWithdrawTabs } from "./DepositWithdrawTabs";
import { AmountInput } from "./AmountInput";
import { ActionButton } from "./ActionButton";
import { TxStatus } from "./TxStatus";

import { useCSDiem } from "@/hooks/useCSDiem";
import { useDiemToken } from "@/hooks/useDiemToken";
import { useApproval } from "@/hooks/useApproval";
import { useDepositCSDiem } from "@/hooks/useDepositCSDiem";
import { useRedeemCSDiem } from "@/hooks/useRedeemCSDiem";
import { DIEM_TOKEN, CSDIEM_ADDRESS, DIEM_DECIMALS } from "@/config/contracts";
import { csDiemAbi } from "@/config/abis";
import { formatDiem, formatSharePrice } from "@/lib/format";

export function CSDiemCard() {
  const { isConnected } = useAccount();
  const csdiem = useCSDiem();
  const diem = useDiemToken(CSDIEM_ADDRESS);
  const approval = useApproval(DIEM_TOKEN, CSDIEM_ADDRESS);
  const depositAction = useDepositCSDiem();
  const redeemAction = useRedeemCSDiem();

  const [depositAmt, setDepositAmt] = useState("");
  const [redeemAmt, setRedeemAmt] = useState("");

  // Preview: how many shares for deposit amount
  const depositParsed = depositAmt
    ? parseUnits(depositAmt, DIEM_DECIMALS)
    : 0n;
  const { data: previewShares } = useReadContract({
    address: CSDIEM_ADDRESS,
    abi: csDiemAbi,
    functionName: "previewDeposit",
    args: [depositParsed],
    query: { enabled: depositParsed > 0n },
  });

  // Preview: how many assets for redeem amount
  const redeemParsed = redeemAmt
    ? parseUnits(redeemAmt, DIEM_DECIMALS)
    : 0n;
  const { data: previewAssets } = useReadContract({
    address: CSDIEM_ADDRESS,
    abi: csDiemAbi,
    functionName: "previewRedeem",
    args: [redeemParsed],
    query: { enabled: redeemParsed > 0n },
  });

  const needsApproval =
    depositAmt !== "" && diem.allowance < depositParsed;

  const handleDeposit = () => {
    if (!depositAmt) return;
    depositAction.deposit(depositParsed);
  };

  const handleRedeem = () => {
    if (!redeemAmt) return;
    redeemAction.redeem(redeemParsed);
  };

  const depositing =
    approval.isPending || approval.isConfirming ||
    depositAction.isPending || depositAction.isConfirming;
  const redeeming =
    redeemAction.isPending || redeemAction.isConfirming;

  return (
    <VaultCard title="csDIEM" subtitle="Deposit DIEM, earn compounding DIEM">
      {csdiem.paused && <PausedBanner />}

      <StatRow
        label="Share Price"
        value={`${formatSharePrice(csdiem.sharePrice)} DIEM`}
      />
      <StatRow
        label="Total Deposits"
        value={`${formatDiem(csdiem.totalAssets)} DIEM`}
      />
      <StatRow
        label="Your Shares"
        value={`${formatDiem(csdiem.userShares)} csDIEM`}
      />
      <StatRow
        label="Your Value"
        value={`${formatDiem(csdiem.userAssetsValue)} DIEM`}
      />

      {isConnected && (
        <DepositWithdrawTabs
          tabs={[
            {
              label: "Deposit",
              content: (
                <div className="space-y-3">
                  <AmountInput
                    value={depositAmt}
                    onChange={setDepositAmt}
                    max={diem.balance}
                    disabled={csdiem.paused}
                  />
                  {previewShares !== undefined && depositParsed > 0n && (
                    <p className="text-xs text-gray-500">
                      You will receive ~
                      {Number(formatUnits(previewShares, DIEM_DECIMALS)).toLocaleString(
                        undefined,
                        { maximumFractionDigits: 4 },
                      )}{" "}
                      csDIEM
                    </p>
                  )}
                  <ActionButton
                    needsApproval={needsApproval}
                    onApprove={() => approval.approve()}
                    onAction={handleDeposit}
                    actionLabel="Deposit DIEM"
                    disabled={
                      !depositAmt || depositAmt === "0" || csdiem.paused
                    }
                    loading={depositing}
                  />
                  <TxStatus
                    isPending={depositAction.isPending || approval.isPending}
                    isConfirming={
                      depositAction.isConfirming || approval.isConfirming
                    }
                    isSuccess={depositAction.isSuccess}
                    error={depositAction.error ?? approval.error}
                    hash={depositAction.hash ?? approval.hash}
                    onReset={() => {
                      depositAction.reset();
                      approval.reset();
                    }}
                  />
                </div>
              ),
            },
            {
              label: "Withdraw",
              content: (
                <div className="space-y-3">
                  <AmountInput
                    value={redeemAmt}
                    onChange={setRedeemAmt}
                    max={csdiem.userShares}
                    symbol="csDIEM"
                    disabled={csdiem.paused}
                  />
                  {previewAssets !== undefined && redeemParsed > 0n && (
                    <p className="text-xs text-gray-500">
                      You will receive ~
                      {Number(formatUnits(previewAssets, DIEM_DECIMALS)).toLocaleString(
                        undefined,
                        { maximumFractionDigits: 4 },
                      )}{" "}
                      DIEM
                    </p>
                  )}
                  <ActionButton
                    needsApproval={false}
                    onApprove={() => {}}
                    onAction={handleRedeem}
                    actionLabel="Withdraw DIEM"
                    disabled={
                      !redeemAmt || redeemAmt === "0" || csdiem.paused
                    }
                    loading={redeeming}
                  />
                  <TxStatus
                    isPending={redeemAction.isPending}
                    isConfirming={redeemAction.isConfirming}
                    isSuccess={redeemAction.isSuccess}
                    error={redeemAction.error}
                    hash={redeemAction.hash}
                    onReset={redeemAction.reset}
                  />
                </div>
              ),
            },
          ]}
        />
      )}
    </VaultCard>
  );
}
