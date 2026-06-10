"use client";

import { ConnectButton } from "@rainbow-me/rainbowkit";
import { ThemeToggle } from "@/components/ThemeToggle";

export function Header() {
  return (
    <header className="site-header">
      <div className="site-header-left">
        <a className="site-logo" href="/">
          <span className="site-logo-icon">◆</span>
          <span className="site-logo-text">Diem Relay</span>
        </a>
        <nav className="site-nav">
          <a className="site-nav-link site-nav-link-active" href="/">
            Stake
          </a>
          <a className="site-nav-link" href="#earnings">
            Earnings
          </a>
          <a className="site-nav-link" href="#csdiem">
            csDIEM
          </a>
          <a className="site-nav-link" href="#activity">
            Activity
          </a>
          <a
            className="site-nav-link"
            href="https://cheaptokens.ai/buy"
            rel="noopener noreferrer"
          >
            Buy inference
          </a>
        </nav>
      </div>
      <div className="site-header-right">
        <ThemeToggle />
        <ConnectButton />
      </div>
    </header>
  );
}
