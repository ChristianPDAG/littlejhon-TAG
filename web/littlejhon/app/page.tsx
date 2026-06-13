import Link from "next/link";

const REPO_URL = "https://github.com/ChristianPDAG/littlejhon-TAG";

const NAV_LINKS = [
  { href: "#protocol", label: "protocol" },
  { href: "#compliance", label: "compliance" },
  { href: "#developers", label: "developers" },
  { href: "#docs", label: "docs" },
];

const PROTOCOL_STEPS = [
  {
    n: "01",
    title: "intent",
    body: "broker submits a transfer intent — chain, asset, amount, recipient — to the risk-check endpoint before any on-chain call.",
  },
  {
    n: "02",
    title: "evaluate",
    body: "the policy engine runs twelve deterministic checks: kyc, sanctions, reserve ratio, transfer caps, recipient eligibility, circuit breaker, asset whitelist.",
  },
  {
    n: "03",
    title: "attest",
    body: "if it passes, a trusted signer issues an eip-712 attestation binding the operation hash, risk score, and deadline.",
  },
  {
    n: "04",
    title: "settle",
    body: "shieldrwaguard verifies the signature on-chain and lets the settlement through — or reverts. nothing in-between.",
  },
];

const COMPLIANCE_CHECKS = [
  { k: "kyc / aml", v: "sender and recipient verified against trusted issuer registries." },
  { k: "sanctions", v: "screening against ofac and sanction lists at request time." },
  { k: "reserve backing", v: "asset must be ≥ 1:1 reserve-backed at the moment of transfer." },
  { k: "transfer caps", v: "per-asset, per-wallet, per-jurisdiction limits enforced on-chain." },
  { k: "circuit breaker", v: "transfers halt automatically if any verifier flags anomalous flow." },
  { k: "asset whitelist", v: "only tokens registered in the official asset registry can move." },
  { k: "recipient eligibility", v: "destination wallet must pass jurisdictional eligibility for the asset class." },
  { k: "safety vault", v: "high-risk routes are routed through the vault with cap and emergency drain." },
];

const CODE_SNIPPET = `POST /api/risk-check
content-type: application/json

{
  "chainId": 421614,
  "from":   "0x…broker",
  "to":     "0x…recipient",
  "asset":  "RWA-USD",
  "token":  "0x…token",
  "amount": "1000000000",
  "context": { "action": "TRANSFER" }
}

→ 200 OK
{
  "decision":       "ALLOW",
  "riskScore":      4,
  "policyId":       "transfer.default",
  "operationHash":  "0x…",
  "humanSummary":   "transfer cleared — 12 checks passed",
  "attestation":    { "signer": "0x…", "signature": "0x…" }
}`;

export default function Home() {
  return (
    <main className="bg-black text-white">
      <nav className="fixed top-0 left-0 right-0 z-50 px-6 md:px-10 pt-6 flex items-center justify-between gap-4">
        <Link
          href="#top"
          className="flex items-center gap-2 bg-neutral-900/90 backdrop-blur rounded-full pl-4 pr-6 py-3"
        >
          <svg
            viewBox="0 0 256 256"
            className="h-5 w-5"
            xmlns="http://www.w3.org/2000/svg"
            aria-hidden="true"
          >
            <path
              d="M 128 192 L 128 256 L 64.5 256 L 32 223 L 0 192 L 0 128 L 64 128 Z M 256 192 L 256 256 L 192.5 256 L 160 223 L 128 192 L 128 128 L 192 128 Z M 128 64 L 128 128 L 64.5 128 L 32 95 L 0 64 L 0 0 L 64 0 Z M 256 64 L 256 128 L 192.5 128 L 160 95 L 128 64 L 128 0 L 192 0 Z"
              fill="#ffffff"
            />
          </svg>
          <span className="text-white text-sm font-normal tracking-tight">
            littlejohn
          </span>
        </Link>

        <div className="hidden md:flex items-center gap-1 bg-neutral-900/90 backdrop-blur rounded-full px-3 py-2">
          {NAV_LINKS.map((l) => (
            <a
              key={l.href}
              href={l.href}
              className="text-neutral-300 hover:text-white transition-colors text-sm px-5 py-2 rounded-full"
            >
              {l.label}
            </a>
          ))}
        </div>

        <Link
          href="/demo"
          className="bg-white text-black text-sm font-normal rounded-full px-6 py-3 hover:bg-neutral-200 transition-colors"
        >
          request access
        </Link>
      </nav>

      <section
        id="top"
        className="relative h-screen w-full overflow-hidden bg-black"
      >
        <video
          className="absolute inset-0 w-full h-full object-cover"
          autoPlay
          loop
          muted
          playsInline
          src="https://d8j0ntlcm91z4.cloudfront.net/user_38xzZboKViGWJOttwIXH07lWA1P/hf_20260418_063509_7d167302-4fd4-480b-8260-18ab572333d4.mp4"
        />

        <div className="relative h-full w-full">
          <div className="absolute right-6 md:right-24 top-[14%]">
            <div className="flex items-center gap-3 justify-end">
              <span className="hidden md:block h-px w-24 bg-white/40 rotate-[20deg]" />
              <span className="text-4xl md:text-5xl font-medium tracking-tight text-white">
                12
              </span>
            </div>
            <p className="text-xs md:text-sm text-white/70 mt-1 text-right">
              safety checks per transfer
            </p>
          </div>

          <h1 className="hero-title absolute text-white font-medium text-[14vw] md:text-[13vw] left-4 md:left-10 top-[18%]">
            guard
          </h1>
          <h1 className="hero-title absolute text-white font-medium text-[14vw] md:text-[13vw] right-4 md:right-10 top-[38%]">
            every
          </h1>

          <p className="absolute left-6 md:left-10 top-[46%] max-w-[260px] text-[15px] leading-snug text-white/90">
            we screen every tokenized-asset transfer before it settles — compliant,
            reserve-backed, and verified on-chain
          </p>

          <h1 className="hero-title absolute text-white font-medium text-[14vw] md:text-[13vw] left-[18%] md:left-[28%] top-[58%]">
            asset
          </h1>

          <div className="absolute left-6 md:left-20 bottom-20 md:bottom-24">
            <div className="flex items-center gap-3">
              <span className="text-4xl md:text-5xl font-medium tracking-tight text-white">
                113
              </span>
              <span className="hidden md:block h-px w-24 bg-white/40 rotate-[-20deg]" />
            </div>
            <p className="text-xs md:text-sm text-white/70 mt-1">tests passing</p>
          </div>

          <div className="absolute right-6 md:right-20 bottom-16 md:bottom-20">
            <div className="flex items-center gap-3 justify-end">
              <span className="hidden md:block h-px w-24 bg-white/40 rotate-[-20deg]" />
              <span className="text-4xl md:text-5xl font-medium tracking-tight text-white">
                0
              </span>
            </div>
            <p className="text-xs md:text-sm text-white/70 mt-1 text-right">
              non-compliant settlements
            </p>
          </div>
        </div>

        <div className="pointer-events-none absolute bottom-0 left-0 right-0 h-48 bg-gradient-to-b from-transparent to-black" />
      </section>

      <section id="protocol" className="bg-black border-t border-white/10 py-28 md:py-40">
        <div className="max-w-6xl mx-auto px-6 md:px-10">
          <p className="text-white/40 text-sm mb-6">/ protocol</p>
          <h2 className="hero-title font-medium text-[12vw] md:text-[7vw] mb-12 md:mb-20">
            screen first.<br />settle second.
          </h2>
          <p className="max-w-2xl text-white/70 text-base md:text-lg leading-relaxed mb-16 md:mb-24">
            tokenized assets settle in seconds. compliance and reserve checks
            should not run after the fact. littlejohn sits between your broker
            and the chain, evaluates every transfer intent, and only attests
            transfers that pass twelve deterministic safety policies.
          </p>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            {PROTOCOL_STEPS.map((step) => (
              <div
                key={step.n}
                className="border border-white/10 rounded-2xl p-6 md:p-8 bg-neutral-950"
              >
                <div className="flex items-baseline gap-4 mb-4">
                  <span className="text-white/40 text-sm font-mono">{step.n}</span>
                  <span className="text-white text-lg md:text-xl">{step.title}</span>
                </div>
                <p className="text-white/70 text-sm md:text-base leading-relaxed">
                  {step.body}
                </p>
              </div>
            ))}
          </div>
        </div>
      </section>

      <section id="compliance" className="bg-black border-t border-white/10 py-28 md:py-40">
        <div className="max-w-6xl mx-auto px-6 md:px-10">
          <p className="text-white/40 text-sm mb-6">/ compliance</p>
          <h2 className="hero-title font-medium text-[12vw] md:text-[7vw] mb-12 md:mb-20">
            every check.<br />every transfer.
          </h2>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-x-12 gap-y-10">
            {COMPLIANCE_CHECKS.map((c) => (
              <div key={c.k} className="border-t border-white/10 pt-6">
                <p className="text-white text-base md:text-lg mb-2">{c.k}</p>
                <p className="text-white/60 text-sm md:text-base leading-relaxed">
                  {c.v}
                </p>
              </div>
            ))}
          </div>

          <div className="mt-20 md:mt-28 flex flex-col md:flex-row md:items-end gap-10 md:gap-20">
            <div>
              <p className="text-5xl md:text-6xl font-medium tracking-tight">12</p>
              <p className="text-white/60 text-sm mt-2 max-w-[200px]">
                checks evaluated before any attestation is signed
              </p>
            </div>
            <div>
              <p className="text-5xl md:text-6xl font-medium tracking-tight">1:1</p>
              <p className="text-white/60 text-sm mt-2 max-w-[200px]">
                reserve ratio required for every tokenized asset in motion
              </p>
            </div>
            <div>
              <p className="text-5xl md:text-6xl font-medium tracking-tight">0</p>
              <p className="text-white/60 text-sm mt-2 max-w-[200px]">
                non-compliant settlements across the test corpus
              </p>
            </div>
          </div>
        </div>
      </section>

      <section id="developers" className="bg-black border-t border-white/10 py-28 md:py-40">
        <div className="max-w-6xl mx-auto px-6 md:px-10">
          <p className="text-white/40 text-sm mb-6">/ developers</p>
          <h2 className="hero-title font-medium text-[12vw] md:text-[7vw] mb-12 md:mb-20">
            one call.<br />no rewrites.
          </h2>

          <div className="grid grid-cols-1 lg:grid-cols-5 gap-10 lg:gap-16 items-start">
            <div className="lg:col-span-2 space-y-8">
              <p className="text-white/70 text-base md:text-lg leading-relaxed">
                point your broker stack at a single risk-check endpoint. get
                back a decision, a risk score, and — when allowed — a signed
                eip-712 attestation your contract verifies on-chain.
              </p>

              <div className="grid grid-cols-2 gap-6">
                <div className="border-t border-white/10 pt-4">
                  <p className="text-white text-2xl md:text-3xl font-medium">5</p>
                  <p className="text-white/60 text-xs md:text-sm mt-1">rest endpoints</p>
                </div>
                <div className="border-t border-white/10 pt-4">
                  <p className="text-white text-2xl md:text-3xl font-medium">6</p>
                  <p className="text-white/60 text-xs md:text-sm mt-1">verified contracts</p>
                </div>
                <div className="border-t border-white/10 pt-4">
                  <p className="text-white text-2xl md:text-3xl font-medium">arb</p>
                  <p className="text-white/60 text-xs md:text-sm mt-1">arbitrum + robinhood testnet</p>
                </div>
                <div className="border-t border-white/10 pt-4">
                  <p className="text-white text-2xl md:text-3xl font-medium">eip-712</p>
                  <p className="text-white/60 text-xs md:text-sm mt-1">typed attestations</p>
                </div>
              </div>

              <div className="flex flex-col sm:flex-row gap-3">
                <Link
                  href="/demo"
                  className="inline-flex items-center justify-center bg-white text-black text-sm rounded-full px-6 py-3 hover:bg-neutral-200 transition-colors"
                >
                  try the demo →
                </Link>
                <a
                  href={REPO_URL}
                  target="_blank"
                  rel="noreferrer"
                  className="inline-flex items-center justify-center border border-white/20 text-white text-sm rounded-full px-6 py-3 hover:bg-white/5 transition-colors"
                >
                  read the source ↗
                </a>
              </div>
            </div>

            <div className="lg:col-span-3 rounded-2xl border border-white/10 bg-neutral-950 overflow-hidden">
              <div className="flex items-center gap-2 border-b border-white/10 px-5 py-3">
                <span className="h-2.5 w-2.5 rounded-full bg-white/20" />
                <span className="h-2.5 w-2.5 rounded-full bg-white/20" />
                <span className="h-2.5 w-2.5 rounded-full bg-white/20" />
                <span className="ml-3 text-white/40 text-xs font-mono">
                  risk-check.http
                </span>
              </div>
              <pre className="text-[12px] md:text-[13px] leading-relaxed text-white/80 font-mono p-5 md:p-6 overflow-x-auto">
                <code>{CODE_SNIPPET}</code>
              </pre>
            </div>
          </div>
        </div>
      </section>

      <section id="docs" className="bg-black border-t border-white/10 py-28 md:py-40">
        <div className="max-w-6xl mx-auto px-6 md:px-10">
          <p className="text-white/40 text-sm mb-6">/ docs</p>
          <h2 className="hero-title font-medium text-[12vw] md:text-[7vw] mb-12 md:mb-20">
            open source.<br />ship today.
          </h2>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <a
              href={REPO_URL}
              target="_blank"
              rel="noreferrer"
              className="group border border-white/10 rounded-2xl p-8 md:p-10 hover:bg-white/5 transition-colors block"
            >
              <p className="text-white/40 text-xs mb-4">github</p>
              <p className="text-2xl md:text-3xl font-medium mb-3 group-hover:text-white text-white">
                ChristianPDAG / littlejhon-TAG ↗
              </p>
              <p className="text-white/60 text-sm md:text-base leading-relaxed">
                contracts, policy engine, broker api, and the demo console — all
                in one repo. mit-licensed, hackathon-ready.
              </p>
            </a>

            <Link
              href="/demo"
              className="group border border-white/10 rounded-2xl p-8 md:p-10 hover:bg-white/5 transition-colors block"
            >
              <p className="text-white/40 text-xs mb-4">live demo</p>
              <p className="text-2xl md:text-3xl font-medium mb-3 text-white">
                run a transfer through the guard →
              </p>
              <p className="text-white/60 text-sm md:text-base leading-relaxed">
                exercise the risk-check, attestation, and on-chain enforcement
                flow against the robinhood testnet from your browser.
              </p>
            </Link>
          </div>

          <div className="mt-20 md:mt-28 pt-10 border-t border-white/10 flex flex-col md:flex-row md:items-center justify-between gap-6">
            <div className="flex items-center gap-2">
              <svg viewBox="0 0 256 256" className="h-4 w-4" aria-hidden="true">
                <path
                  d="M 128 192 L 128 256 L 64.5 256 L 32 223 L 0 192 L 0 128 L 64 128 Z M 256 192 L 256 256 L 192.5 256 L 160 223 L 128 192 L 128 128 L 192 128 Z M 128 64 L 128 128 L 64.5 128 L 32 95 L 0 64 L 0 0 L 64 0 Z M 256 64 L 256 128 L 192.5 128 L 160 95 L 128 64 L 128 0 L 192 0 Z"
                  fill="#ffffff"
                />
              </svg>
              <span className="text-white/60 text-sm">
                littlejohn — tokenized asset guard
              </span>
            </div>
            <div className="flex items-center gap-6 text-sm text-white/40">
              <a href={REPO_URL} target="_blank" rel="noreferrer" className="hover:text-white transition-colors">
                github
              </a>
              <Link href="/demo" className="hover:text-white transition-colors">
                demo
              </Link>
              <a href="#top" className="hover:text-white transition-colors">
                back to top
              </a>
            </div>
          </div>
        </div>
      </section>
    </main>
  );
}
