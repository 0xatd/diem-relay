import { Header } from "@/components/Header";
import {
  AUDIT_BRIEF_URL,
  CHEAPTOKENS_BUY_URL,
  CONTRACTS_SECTION_URL,
  GITHUB_URL,
  KNOWN_ISSUES_URL,
} from "@/config/protocol-links";

export default function AboutPage() {
  return (
    <>
      <Header />
      <main className="pool-page">
        <article className="content-page">
          <h1>About Diem Relay</h1>

          <p>
            Diem Relay is a marketplace for DIEM-backed inference. DIEM is a perpetual $1
            inference credit on Venice. Holders supply their DIEM to the pool, that credit is
            forward-staked for AI compute, and the USDC from every sale is paid back to
            suppliers.
          </p>

          <p>
            Think of it like Airbnb: you own the asset, we run the marketplace. Suppliers
            bring the DIEM, Diem Relay handles selling the inference and distributing the
            revenue, and keeps a 20% platform fee. The other 80% goes to suppliers in USDC,
            in proportion to what they&apos;ve supplied. The inference itself is bought at{" "}
            <a href={CHEAPTOKENS_BUY_URL} rel="noreferrer" target="_blank">
              CheapTokens
            </a>
            .
          </p>

          <h2>Two ways to supply</h2>

          <ul>
            <li>
              sDIEM v2 — a transferable ERC-20 staking receipt with EIP-2612 permit. Keep a
              liquid token and claim your streamed USDC rewards manually.
            </li>
            <li>
              csDIEM v2 — a canonical ERC-4626 vault over sDIEM v2. Rewards accrue into the
              csDIEM exchange rate so your position grows on its own.
            </li>
          </ul>

          <p>
            You can convert between them without leaving the system, and enter csDIEM either
            by wrapping sDIEM or supplying DIEM directly.
          </p>

          <h2>What happens under the hood</h2>

          <p>
            Supplied DIEM is forward-staked on Venice. Customer USDC payments land on
            RevenueSplitter, where anyone can call <code>distribute()</code> once the balance
            and cooldown requirements are met. RevenueSplitter sends 20% to the 2-of-2 Safe and
            notifies sDIEM with the remaining 80%, which streams to suppliers over 24 hours.
          </p>

          <p>
            Withdrawals follow Venice&apos;s cooldown. A normal sDIEM exit is a request, wait,
            then complete flow; batched withdrawals can make the practical wait closer to 48
            hours in some cases. csDIEM exits by redeeming back to sDIEM first.
          </p>

          <h2>Open and on-chain</h2>

          <p>
            The v2 staking contracts were deployed on Base on May 21, 2026. The contracts are
            open source, admined by the same 2-of-2 Safe, and documented in the upstream GitHub
            repository.
          </p>

          <p>
            <a href={GITHUB_URL} rel="noreferrer" target="_blank">View on GitHub</a> ·{" "}
            <a href={CONTRACTS_SECTION_URL}>View contracts on BaseScan</a>
          </p>

          <h2>Security status</h2>

          <p>
            Bretzel and Pashov AI reviewed the original sDIEM and DIEMVault contracts in March
            2026. RevenueSplitter, csDIEM, sDIEM v2, and csDIEM v2 have in-house adversarial
            review coverage and are pending external review before meaningful TVL. See the{" "}
            <a href={AUDIT_BRIEF_URL} rel="noreferrer" target="_blank">audit briefing</a>{" "}
            and{" "}
            <a href={KNOWN_ISSUES_URL} rel="noreferrer" target="_blank">known issues</a>.
          </p>
        </article>
      </main>
    </>
  );
}
