import { Header } from "@/components/Header";

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
            sold as AI compute, and the USDC from every sale is paid back to suppliers.
          </p>

          <p>
            Think of it like Airbnb: you own the asset, we run the marketplace. Suppliers
            bring the DIEM, Diem Relay handles selling the inference and distributing the
            revenue, and keeps a 10% platform fee. The other 90% goes to suppliers in USDC,
            in proportion to what they&apos;ve supplied. The inference itself is bought at{" "}
            <a href="https://cheaptokens.ai/buy" rel="noreferrer" target="_blank">
              CheapTokens
            </a>
            .
          </p>

          <h2>Two ways to supply</h2>

          <ul>
            <li>
              sDIEM — a liquid staking receipt. Keep a transferable token and claim your
              streamed USDC rewards manually. Like stETH, but for DIEM.
            </li>
            <li>
              csDIEM — an ERC-4626 auto-compounding vault. Rewards accrue into the csDIEM
              exchange rate so your position grows on its own. Like wstETH.
            </li>
          </ul>

          <p>
            You can convert between them without leaving the system, and enter csDIEM either
            by wrapping sDIEM or supplying DIEM directly.
          </p>

          <h2>Open and on-chain</h2>

          <p>The contracts are deployed on Base and the code is open source.</p>

          <p>
            {/* TODO: Diem Relay GitHub URL */}
            <a href="#">View on GitHub</a> · {/* TODO: contracts URL */}
            <a href="#">View contracts on BaseScan</a>
          </p>
        </article>
      </main>
    </>
  );
}
