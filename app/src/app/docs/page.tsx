import { Header } from "@/components/Header";

export default function DocsPage() {
  return (
    <>
      <Header />
      <main className="pool-page">
        <article className="content-page">
          <h1>Diem Relay Docs</h1>

          <h2>Overview</h2>

          <p>
            Diem Relay is a marketplace that lets DIEM holders earn USDC on their credits.
            DIEM is a $1 inference credit; when it&apos;s sold as compute, the USDC paid is
            distributed to suppliers, minus a platform fee. This page covers how the
            marketplace works, the sDIEM and csDIEM receipts, fees, and withdrawals.
          </p>

          <h2>How it works</h2>

          <ol>
            <li>Supply DIEM to the pool and receive sDIEM or csDIEM.</li>
            <li>The pooled DIEM backs AI inference that&apos;s sold to compute buyers.</li>
            <li>
              USDC from each sale is distributed to suppliers, with a 10% platform fee
              retained by Diem Relay.
            </li>
          </ol>

          <h2>DIEM — the base asset</h2>

          <p>
            DIEM is a perpetual $1 inference credit on Venice, held on Base, and the asset you
            supply to the relay. Diem Relay does not issue DIEM — it runs the marketplace that
            sells the inference your DIEM backs, and issues receipt tokens (sDIEM / csDIEM)
            representing your position.
          </p>

          <h2>Fees</h2>

          <p>
            Diem Relay keeps a 10% platform fee on inference revenue. The remaining 90% is
            distributed to suppliers in USDC, pro-rata to their share of the pool. There is no
            fee to supply or withdraw beyond network gas.
          </p>

          <h2>sDIEM — liquid staking</h2>

          <p>
            Supply DIEM and you receive sDIEM, a liquid receipt for your position. sDIEM
            accrues claimable USDC rewards you collect manually, and stays transferable so you
            keep flexibility — hold it, move it, or wrap it into the compounding vault.
          </p>

          <h2>csDIEM — compounding vault</h2>

          <p>
            csDIEM is an ERC-4626 vault receipt. Instead of claiming by hand, rewards accrue
            through the csDIEM exchange rate, so each csDIEM is worth progressively more of the
            underlying over time. Enter by wrapping existing sDIEM, or by supplying DIEM
            directly into the vault.
          </p>

          <h2>Withdrawals</h2>

          <p>
            Withdrawals run through sDIEM. sDIEM withdraws back to DIEM after a 24-hour
            cooldown. csDIEM unwraps to sDIEM first, then follows the same 24-hour path to DIEM.
          </p>

          <h2>Contracts</h2>

          <p>Deployed on Base:</p>

          <ul>
            <li>DIEMVault — deposit and supply</li>
            <li>sDIEM — liquid staking receipt</li>
            <li>csDIEM — ERC-4626 compounding vault</li>
            <li>RevenueSplitter — USDC reward distribution</li>
          </ul>

          <p>
            {/* TODO: add each deployed Base address, linked to BaseScan */}
            [TODO: add each deployed Base address, linked to BaseScan]
          </p>

          <p>
            {/* TODO: Diem Relay GitHub URL */}
            Source code: [TODO: Diem Relay GitHub URL]
          </p>

          <h2>Risks</h2>

          <p>Interacting with the relay involves smart contract risk.</p>

          <p>
            {/* TODO: add audit status and link, plus any other disclosures you want surfaced */}
            [TODO: add audit status and link, plus any other disclosures you want surfaced]
          </p>
        </article>
      </main>
    </>
  );
}
