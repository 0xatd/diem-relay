"use client";

import { ConnectButton } from "@rainbow-me/rainbowkit";

export function Header() {
  return (
    <header className="site-header">
      <div className="site-header-left">
        <a className="site-logo" href="/">
          <span className="site-logo-icon">◇</span>
          <span className="site-logo-text">DIEMpool</span>
        </a>
        <nav className="site-nav">
          <a className="site-nav-link site-nav-link-active" href="/">
            Supply DIEM
          </a>
          <a
            className="site-nav-link"
            href="https://cheaptokens.ai/buy"
            rel="noopener noreferrer"
          >
            Buy Inference
          </a>
        </nav>
      </div>
      <div className="site-header-right">
        <ConnectButton />
      </div>
    </header>
  );
}
