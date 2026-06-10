"use client";

import { Header } from "@/components/Header";
import { PortfolioSummary } from "@/components/PortfolioSummary";
import { SDiemCard } from "@/components/SDiemCard";
import { useSDiem } from "@/hooks/useSDiem";
import { calcSDiemApr } from "@/lib/apr";
import { formatDiem, formatUsdc } from "@/lib/format";

export const dynamic = "force-dynamic";

const relayStats = [
  { label: "Network", value: "Base" },
  { label: "Withdrawal path", value: "24h async" },
  { label: "Reward asset", value: "USDC" },
  { label: "Credit market", value: "Venice AI" },
];

const operatorFlow = [
  {
    title: "Stake DIEM",
    body: "Deposited DIEM is forward-staked into Venice compute capacity.",
  },
  {
    title: "Sell compute",
    body: "Relay inventory is sold as discounted API credits through the DIEM Relay/CheapTokens loop.",
  },
  {
    title: "Stream revenue",
    body: "USDC revenue is notified to sDIEM and streams to stakers over the reward period.",
  },
];

const relayEndpoints = [
  { label: "Pricing", value: "GET /v1/pricing" },
  { label: "Auth", value: "POST /auth/login" },
  { label: "Chat", value: "POST /v1/chat/completions" },
];

const poweredBy = [
  {
    name: "CheapTokens.ai",
    description: "discounted inference credits",
    href: "https://cheaptokens.ai",
  },
  {
    name: "Venice.ai",
    description: "private AI infrastructure",
    href: "https://venice.ai",
  },
  {
    name: "DIEMpool.com",
    description: "staking interface lineage",
    href: "https://diempool.com",
  },
];

export default function Home() {
  const sdiem = useSDiem();
  const apr = calcSDiemApr(sdiem.rewardRate, sdiem.totalStaked);
  const rewardPerDay = sdiem.rewardRate * 86_400n;

  return (
    <div className="diem-relay-page min-h-screen overflow-x-hidden bg-surface text-ink">
      <Header />

      <main className="mx-auto max-w-7xl px-4 pb-16 sm:px-6 lg:px-8">
        <section className="grid gap-8 py-10 lg:grid-cols-[minmax(0,1.05fr)_minmax(380px,0.74fr)] lg:items-center lg:py-14">
          <div className="max-w-3xl">
            <p className="mb-4 inline-flex rounded-full border border-gold/35 bg-gold/10 px-3 py-1 text-xs font-bold uppercase tracking-[0.12em] text-gold">
              DIEM Relay on Base
            </p>
            <h1 className="diem-relay-title max-w-full text-4xl font-black leading-[0.98] tracking-normal text-white sm:text-6xl lg:text-7xl">
              Stake DIEM. Fund discounted AI inference.
            </h1>
            <p className="mt-5 max-w-2xl text-lg leading-8 text-ink-muted">
              DIEM Relay connects Venice compute supply to users who need AI credits. Stakers supply DIEM,
              the relay sells compute access, and USDC revenue streams back through sDIEM.
            </p>
            <div className="mt-7 flex flex-col gap-3 sm:flex-row">
              <a
                href="#stake"
                className="inline-flex h-12 items-center justify-center rounded-lg bg-gold px-5 text-sm font-extrabold text-black transition hover:bg-gold-hover"
              >
                Stake DIEM
              </a>
              <a
                href="#relay-api"
                className="inline-flex h-12 items-center justify-center rounded-lg border border-border bg-panel px-5 text-sm font-bold text-white transition hover:border-gold/50"
              >
                View relay API
              </a>
            </div>
          </div>

          <div className="rounded-lg border border-border bg-panel p-4 shadow-2xl shadow-black/30">
            <div className="rounded-md border border-border bg-panel-inner p-4">
              <div className="mb-5 flex items-center justify-between gap-3">
                <div>
                  <p className="text-xs font-bold uppercase tracking-[0.12em] text-ink-faint">Live staking market</p>
                  <h2 className="mt-1 text-2xl font-black text-white">sDIEM</h2>
                </div>
                <span className="rounded-md border border-success/35 bg-success/10 px-3 py-1 text-xs font-bold text-success">
                  {sdiem.paused ? "Paused" : "Active"}
                </span>
              </div>
              <div className="grid gap-3 min-[500px]:grid-cols-2">
                <Metric label="Total staked" value={`${formatDiem(sdiem.totalStaked)} DIEM`} />
                <Metric label="Current APR" value={apr !== null ? `${apr}%` : "Pending"} />
                <Metric label="USDC/day" value={formatUsdc(rewardPerDay)} />
                <Metric label="Reward period" value={sdiem.periodFinish > 0n ? "Streaming" : "Idle"} />
              </div>
            </div>
          </div>
        </section>

        <PortfolioSummary />

        <section className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          {relayStats.map((stat) => (
            <div key={stat.label} className="rounded-lg border border-border bg-panel p-4">
              <p className="text-xs font-bold uppercase tracking-[0.1em] text-ink-faint">{stat.label}</p>
              <p className="mt-2 text-xl font-black text-white">{stat.value}</p>
            </div>
          ))}
        </section>

        <section className="py-8">
          <p className="text-center text-xs font-bold uppercase tracking-[0.16em] text-gold">Powered by</p>
          <div className="mt-4 grid gap-3 sm:grid-cols-3">
            {poweredBy.map((partner) => (
              <a
                key={partner.name}
                href={partner.href}
                target="_blank"
                rel="noreferrer"
                className="rounded-lg border border-border bg-panel p-5 text-center transition hover:border-gold/50 hover:bg-panel-inner"
              >
                <h2 className="text-lg font-black text-white">{partner.name}</h2>
                <p className="mt-1 text-sm leading-6 text-ink-muted">{partner.description}</p>
              </a>
            ))}
          </div>
        </section>

        <section id="stake" className="grid gap-6 py-8 lg:grid-cols-[minmax(0,0.92fr)_minmax(360px,0.58fr)] lg:items-start">
          <div className="rounded-lg border border-border bg-panel p-2 shadow-2xl shadow-gold/10">
            <SDiemCard />
          </div>

          <div className="space-y-4">
            <Panel title="What this contract does">
              <p>
                sDIEM stakes DIEM into Venice, tracks your staked balance, and pays USDC rewards when relay revenue is
                distributed. Withdrawals use the Venice cooldown path, so exiting is asynchronous.
              </p>
            </Panel>
            <Panel title="Risk notes">
              <ul className="space-y-2">
                <li>DIEM Relay is experimental crypto infrastructure.</li>
                <li>Rewards depend on actual compute-credit demand and operator distributions.</li>
                <li>Withdrawals can take roughly 24-48 hours depending on Venice cooldown batching.</li>
              </ul>
            </Panel>
          </div>
        </section>

        <section className="grid gap-6 py-4 lg:grid-cols-[minmax(0,0.7fr)_minmax(0,1fr)]">
          <div className="rounded-lg border border-border bg-panel p-6">
            <p className="text-xs font-bold uppercase tracking-[0.12em] text-gold">Revenue loop</p>
            <h2 className="mt-3 text-3xl font-black text-white">A compute-credit relay, not a mystery farm.</h2>
            <p className="mt-4 text-ink-muted">
              The economic claim is simple: idle DIEM creates Venice compute capacity, buyers pay for that capacity,
              and stakers receive the revenue stream when demand exists.
            </p>
          </div>
          <div className="grid gap-3 sm:grid-cols-3">
            {operatorFlow.map((step, index) => (
              <div key={step.title} className="rounded-lg border border-border bg-panel p-5">
                <span className="font-mono text-sm font-bold text-gold">0{index + 1}</span>
                <h3 className="mt-4 text-lg font-black text-white">{step.title}</h3>
                <p className="mt-2 text-sm leading-6 text-ink-muted">{step.body}</p>
              </div>
            ))}
          </div>
        </section>

        <section id="relay-api" className="grid gap-6 py-8 lg:grid-cols-[minmax(0,1fr)_minmax(340px,0.58fr)]">
          <div className="rounded-lg border border-border bg-panel p-6">
            <p className="text-xs font-bold uppercase tracking-[0.12em] text-gold">For builders</p>
            <h2 className="mt-3 text-3xl font-black text-white">Use discounted Venice credits through the relay.</h2>
            <p className="mt-4 max-w-3xl text-ink-muted">
              Borrowers buy same-day or advance credits, authenticate with a wallet signature, and call an OpenAI-style
              chat endpoint. Usage is metered against the purchased relay balance.
            </p>
            <div className="mt-5 grid gap-3 sm:grid-cols-3">
              {relayEndpoints.map((endpoint) => (
                <div key={endpoint.label} className="rounded-lg border border-border bg-panel-inner p-4">
                  <p className="text-xs font-bold uppercase tracking-[0.1em] text-ink-faint">{endpoint.label}</p>
                  <code className="mt-2 block break-words text-sm font-bold text-white">{endpoint.value}</code>
                </div>
              ))}
            </div>
          </div>
          <div className="rounded-lg border border-border bg-panel-inner p-6">
            <p className="text-xs font-bold uppercase tracking-[0.12em] text-ink-faint">Credit types</p>
            <div className="mt-5 space-y-4">
              <CreditType title="Same-day credits" body="Dynamic discount for compute that expires at midnight UTC." />
              <CreditType title="Advance credits" body="Next-day relay balance bought at a fixed discount rate." />
            </div>
          </div>
        </section>
      </main>
    </div>
  );
}

function Metric({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-lg border border-border bg-surface p-4">
      <p className="text-xs font-bold uppercase tracking-[0.1em] text-ink-faint">{label}</p>
      <p className="mt-2 break-words font-mono text-lg font-black text-white">{value}</p>
    </div>
  );
}

function Panel({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="rounded-lg border border-border bg-panel p-5 text-sm leading-6 text-ink-muted">
      <h3 className="mb-3 text-lg font-black text-white">{title}</h3>
      {children}
    </div>
  );
}

function CreditType({ title, body }: { title: string; body: string }) {
  return (
    <div className="border-l-2 border-gold pl-4">
      <h3 className="font-black text-white">{title}</h3>
      <p className="mt-1 text-sm leading-6 text-ink-muted">{body}</p>
    </div>
  );
}
