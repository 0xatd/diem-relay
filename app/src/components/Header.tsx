"use client";

import { ConnectButton } from "@rainbow-me/rainbowkit";
import { useVersion, type Version } from "@/hooks/useVersion";

function VersionToggle() {
  const { version, setVersion } = useVersion();

  const opt = (v: Version) => {
    const active = version === v;
    return (
      <button
        key={v}
        type="button"
        onClick={() => setVersion(v)}
        aria-pressed={active}
        className={`rounded-full px-2.5 py-0.5 font-mono text-[10px] font-semibold uppercase transition ${
          active
            ? "bg-accent text-black"
            : "text-gray-400 hover:text-gray-200"
        }`}
      >
        {v}
      </button>
    );
  };

  return (
    <div
      role="group"
      aria-label="Contract version"
      className="flex items-center gap-0.5 rounded-full border border-border bg-card p-0.5"
    >
      {opt("v1")}
      {opt("v2")}
    </div>
  );
}

export function Header() {
  return (
    <header className="flex items-center justify-between px-6 py-4">
      <div className="flex items-center gap-1.5">
        <span className="font-mono text-sm font-bold text-accent">diem-relay</span>
        <span className="font-mono text-sm font-bold text-[#555]">.com</span>
        <span className="ml-2 rounded-full bg-[#e8a435] px-2 py-0.5 text-[10px] font-bold uppercase text-black">
          beta
        </span>
      </div>
      <div className="flex items-center gap-3">
        <VersionToggle />
        <ConnectButton
          showBalance={false}
          chainStatus="icon"
          accountStatus="address"
        />
      </div>
    </header>
  );
}
