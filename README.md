man i really pivoted at last day, and its 20 mins left, so this readme is ai, pls look at demo video, for actual understanding
# Proof-of-Day 😤⏳→ ✅

**A tiny social app for doing what you said you’d do — and proving it.**
Make a goal, answer two softball questions, get a **PASS/FAIL** verdict from an LLM, and instantly publish a **verifiable attestation** on-chain. Profiles, discovery, notes — all baked in. It’s half productivity, half spectacle, 100% hackathon-friendly.

---

## Why this exists (the vibe)

People tweet “reading 3 ML papers today” and then… disappear. Proof-of-Day flips that:

* **Say it → Do it → Show it.**
* **Light verification** (two quick Qs) so you don’t spend a day writing proof.
* **Social proof** that compounds — your public profile becomes a trail of work: what you learned, built, shipped.
* **On-chain attestations** make the receipts portable and tamper-evident.

This is *not* a judge of mastery. It’s a gentle nudge + paper trail + “oh wow, this person actually ships”.

---

## What it does (fast tour)

* **Create a goal** (title + optional scope).
* **Complete** → the app generates **two tiny questions** tailored to your goal.
* **Answer** → an LLM grades **leniently** (defaults to PASS unless clearly bogus).
* **Auto-publish** → we immediately write a **PASS/FAIL attestation** to EAS (Base Sepolia for the demo).
* **Notes** → your Q/A transcript (and result) are saved and viewable inline.
* **Public profiles** → `/<u>/<username>` shows your full history.
* **Discovery** → see recent attestations and search users.

No wallets required for users in the demo — the platform account posts attestations.

---

## Why web3 here (and not just web2)?

* **Verifiable receipts**: a 3rd party (EAS attestation) says “@app saw @you finish X on Y”.
* **Composability**: your “proof of work” can be used by other apps/communities/guilds.
* **Portability**: your record isn’t trapped in our DB. It’s an open credential you can reference anywhere.

---

## Architecture (one glance)

* **UI**: Next.js App Router + Tailwind-ish utility classes (no heavy CSS).
* **Judge**: OpenAI chat API (two calls: make questions; grade answers).
* **Data**: Upstash/Redis (via REST) — goals, notes, feed, users.
* **Attestations**: **EAS** (Ethereum Attestation Service) on **Base Sepolia**.
* **Auth**: ultra-simple demo users (`DEMO_USERS_CSV`), JWT cookie.

```
Client ──> /api/goal/questions ─┐
                                ├─> OpenAI (Q gen)
Client ──> /api/goal/grade ─────┘
        │           │
        │           └─> store transcript + PASS/FAIL in Redis
        │
        └─> /api/attest (auto) ──> EAS attestation (PASS or FAIL)
```

---

## Screens (what you can expect)

* **/login** – Sign in with a demo username/password.
* **/profile** – Create goals, complete, dispute (optional), see notes & proof.
* **/social** – Latest attestations, with inline notes.
* **/discover** – User list + search.
* **/u/<username>** – Public profile (history only).

---

## Local dev: 1-minute quickstart

> You can deploy later — this runs fine locally once you set envs.

### 0) Install & run

```bash
npm install
npm run dev
# open http://localhost:3000/login
```

### 1) Environment variables

Create `.env.local` with these (choose **either** Upstash **or** KV names):

```ini
# Base URL for server-rendered fetches
NEXT_PUBLIC_SITE_URL=http://localhost:3000

# Redis (either pair works)
UPSTASH_REDIS_REST_URL=...
UPSTASH_REDIS_REST_TOKEN=...
# OR
KV_REST_API_URL=...
KV_REST_API_TOKEN=...

# Demo auth
AUTH_SECRET=some-long-random-string
DEMO_USERS_CSV=test1:password1,test2:password2,mony10:graphg0d

# OpenAI
OPENAI_API_KEY=sk-...
NEXT_PUBLIC_USE_MOCKS=false      # set true if you want to bypass the API

# EAS on Base Sepolia (demo network)
RPC_URL_BASE_SEPOLIA=https://sepolia.base.org   # or your node provider URL
PLATFORM_PRIVATE_KEY=0x<your-test-private-key>  # funds for attest txs (testnet!)
EAS_CONTRACT_ADDRESS=0x4200000000000000000000000000000000000021
SCHEMA_REGISTRY_ADDRESS=0x4200000000000000000000000000000000000020
EAS_SCHEMA_UID=0x<schema-uid-you-registered>
```

> Upstash: create a free Redis database and copy **REST URL/TOKEN**.
> EAS: use Base Sepolia. Fund your test key with faucet ETH. Register a schema once, then paste its UID.

---

## Deploying to Vercel

1. Push the repo to GitHub.
2. **Import Project** in Vercel (Next.js auto-detected).
3. Add **Environment Variables** (same as `.env.local`, but with `NEXT_PUBLIC_SITE_URL=https://<your>.vercel.app`).
4. Add **Upstash Redis** via Vercel Marketplace or use your own Upstash creds.
5. Deploy.

---

## Feature details

* **Two-call judge**

  * `/api/goal/questions`: sends `{goal, scope}` → returns 2 questions.
  * `/api/goal/grade`: sends `{goal, scope, questions, answers}` → returns **PASS/FAIL** and **saves full transcript** to Redis.

* **Automatic attestation**

  * On PASS, we immediately publish **PASS** to EAS.
  * On FAIL, you get a dispute prompt:

    * **No dispute** → publish **FAIL**.
    * **Dispute** → optional tweet flow; if you proceed, we publish **PASS (disputed)**.

* **Notes**

  * Inline everywhere (Profile, Social, Public).
  * Shows Q1/A1, Q2/A2, and the result.
  * (Easy to extend with custom user notes.)

* **Public profiles & discovery**

  * `GET /api/user/:username/goals` powers `/u/:username`.
  * `GET /api/users` powers `/discover`.

---

## Tech stack

* **Next.js (App Router)** + TypeScript
* **OpenAI API** (chat completions)
* **Upstash Redis** (or KV REST vars)
* **EAS SDK** (Ethereum Attestation Service)
* **Base Sepolia** testnet

---

## Env var cheat sheet

| Key                                                   | What                                                |
| ----------------------------------------------------- | --------------------------------------------------- |
| `OPENAI_API_KEY`                                      | LLM for questions & grading                         |
| `NEXT_PUBLIC_USE_MOCKS`                               | `true` to bypass live LLM (local demo)              |
| `UPSTASH_REDIS_REST_URL` / `UPSTASH_REDIS_REST_TOKEN` | Redis via REST                                      |
| `KV_REST_API_URL` / `KV_REST_API_TOKEN`               | Alternative var names (also supported)              |
| `RPC_URL_BASE_SEPOLIA`                                | RPC for Base Sepolia                                |
| `PLATFORM_PRIVATE_KEY`                                | Platform signer (test key)                          |
| `EAS_CONTRACT_ADDRESS`                                | EAS on Base Sepolia                                 |
| `SCHEMA_REGISTRY_ADDRESS`                             | EAS SchemaRegistry on Base Sepolia                  |
| `EAS_SCHEMA_UID`                                      | Your registered schema UID                          |
| `AUTH_SECRET`                                         | JWT signing secret                                  |
| `DEMO_USERS_CSV`                                      | `user:pass` pairs for demo login                    |
| `NEXT_PUBLIC_SITE_URL`                                | `http://localhost:3000` locally, Vercel URL in prod |

---

## Caveats (it’s a hackathon!)

* **Lenient grading by design** — we optimize for momentum, not gatekeeping.
* **Not Sybil-resistant** — demo users are just CSV logins.
* **Privacy** — transcripts are public; don’t paste secrets.
* **Gas** — testnet only here; a real product would need bundling/paymasters, quotas, etc.

---

## Roadmap (obvious next steps)

* OAuth logins (X/GitHub) and verified handles in attestations
* Optional **account abstraction** for user-pays gas / sponsor flows
* Richer notes (screenshots, small artifacts, links)
* Team pages + weekly streak badges
* Better dispute flows (UMA / community votes) if we want real stakes

---

## Thanks / credits

* **EAS** for the simple attestation rails
* **Base Sepolia** for painless testnet UX
* **Upstash** for dead-simple serverless Redis
* **OpenAI** for the judge who passes you unless you’re wildly off 😉

---

## License

MIT. Ship cool stuff. Tag us if you build on it 👀

---

**tl;dr**: Proof-of-Day is a tiny, fun way to build a visible habit of finishing things — with receipts you can take anywhere.
