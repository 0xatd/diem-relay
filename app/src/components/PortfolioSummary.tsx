"use client";

import { useAccount } from "wagmi";
import { useSDiem } from "@/hooks/useSDiem";
import { useDiemToken } from "@/hooks/useDiemToken";
import { useCSDiem, isCSDiemDeployed } from "@/hooks/useCSDiem";
import { useContracts } from "@/hooks/useContracts";
import { formatDiem, formatUsdc } from "@/lib/format";

export function PortfolioSummary() {
  const { isConnected } = useAccount();
  const { isV2 } = useContracts();
  const { userStaked, earned } = useSDiem();
  const { balance } = useDiemToken();
  const { userShares, userAssetsValue } = useCSDiem();

  if (!isConnected) return null;

  const sLabel = "Staked (sDIEM)";
  const csLabel = "Wrapped (csDIEM)";
  const csAvailable = isV2 || isCSDiemDeployed;

  const stats = [
    { label: "Wallet", value: `${formatDiem(balance)} DIEM` },
    { label: sLabel, value: `${formatDiem(userStaked)} DIEM` },
    ...(csAvailable
      ? [
          {
            label: csLabel,
            value: `${formatDiem(userShares)} csDIEM`,
            sub: `${formatDiem(userAssetsValue)} DIEM`,
          },
        ]
      : []),
    { label: "USDC Earned", value: `${formatUsdc(earned)} USDC` },
  ];

  const cols = stats.length === 4 ? "sm:grid-cols-4" : "sm:grid-cols-3";

  return (
    <div className={`mx-6 mb-6 grid grid-cols-2 gap-3 rounded-xl border border-border bg-card p-4 ${cols}`}>
      {stats.map((s) => (
        <div key={s.label}>
          <p className="text-[10px] font-semibold uppercase tracking-widest text-[#555]">{s.label}</p>
          <p className="font-mono text-sm font-medium text-gray-100">{s.value}</p>
          {"sub" in s && s.sub && (
            <p className="font-mono text-[10px] text-[#666]">≈ {s.sub}</p>
          )}
        </div>
      ))}
    </div>
  );
}
