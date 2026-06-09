"use client";

import { ConnectButton } from "@rainbow-me/rainbowkit";

export function Header() {
  return (
    <header className="mx-auto flex max-w-7xl items-center justify-between gap-4 px-4 py-4 sm:px-6 lg:px-8">
      <a href="#" className="flex items-center gap-3">
        <span className="grid h-9 w-9 place-items-center rounded-lg border border-gold/35 bg-gold/10 font-black text-gold">
          D
        </span>
        <span>
          <span className="block text-lg font-black leading-none text-white">DIEM Relay</span>
          <span className="text-xs font-bold uppercase tracking-[0.12em] text-ink-faint">Staking + AI credits</span>
        </span>
      </a>
      <ConnectButton
        showBalance={false}
        chainStatus="icon"
        accountStatus="address"
      />
    </header>
  );
}
