#!/usr/bin/env bash
set -euo pipefail

echo "▶ Installing deps (@eas-sdk + ethers)…"
npm i @ethereum-attestation-service/eas-sdk ethers >/dev/null

echo "▶ Adding lib/eas.ts (Base Sepolia attestation helper)…"
mkdir -p src/lib
cat > src/lib/eas.ts <<'TS'
import { EAS, SchemaEncoder } from "@ethereum-attestation-service/eas-sdk";
import { ethers } from "ethers";

const ZERO_UID = "0x0000000000000000000000000000000000000000000000000000000000000000";
const DEFAULT_EAS = "0x4200000000000000000000000000000000000021"; // Base Sepolia EAS
// Schema for this demo:
//   string app,string username,string goal,string result,bool disputed,string ref
// You'll register it and paste UID into EAS_SCHEMA_UID.
const SCHEMA = "string app,string username,string goal,string result,bool disputed,string ref";

type AttestInput = {
  username: string;
  goalTitle: string;
  result: "PASS" | "FAIL";
  disputed: boolean;
  ref: string; // goal id
};

export async function attestResult(input: AttestInput): Promise<{ uid: string; txHash: string; mocked: boolean }> {
  const RPC = process.env.RPC_URL_BASE_SEPOLIA;
  const PK  = process.env.PLATFORM_PRIVATE_KEY;
  const SCHEMA_UID = process.env.EAS_SCHEMA_UID;
  const EAS_ADDR = process.env.EAS_CONTRACT_ADDRESS ?? DEFAULT_EAS;

  // Mock if envs are missing
  if (!RPC || !PK || !SCHEMA_UID) {
    const uid = `MOCK-${input.result}-${input.ref}`;
    return { uid, txHash: "0xMOCK", mocked: true };
  }

  const provider = new ethers.JsonRpcProvider(RPC);
  const wallet = new ethers.Wallet(PK, provider);

  const eas = new EAS(EAS_ADDR);
  eas.connect(wallet);

  const encoder = new SchemaEncoder(SCHEMA);
  const data = encoder.encodeData([
    { name: "app",      type: "string", value: "ProofOfDay" },
    { name: "username", type: "string", value: input.username },
    { name: "goal",     type: "string", value: input.goalTitle },
    { name: "result",   type: "string", value: input.result },
    { name: "disputed", type: "bool",   value: input.disputed },
    { name: "ref",      type: "string", value: input.ref },
  ]);

  const tx = await eas.attest({
    schema: SCHEMA_UID,
    data: {
      recipient: wallet.address,     // platform as recipient for demo
      expirationTime: 0,             // no expiry
      revocable: true,
      refUID: ZERO_UID,
      data,
      value: 0,
    },
  });

  const uid = await tx.wait();
  return { uid, txHash: tx.hash, mocked: false };
}

export const EAS_SCHEMA_STRING = SCHEMA;
TS

echo "▶ Wiring /api/attest to call EAS…"
mkdir -p src/app/api/attest
cat > src/app/api/attest/route.ts <<'TS'
import { NextRequest, NextResponse } from "next/server";
import { getGoal, updateGoal } from "@/lib/db";
import { attestResult } from "@/lib/eas";

export async function POST(req: NextRequest){
  try {
    const { goalId, pass, disputed } = await req.json(); // pass:boolean, disputed:boolean
    const goal = getGoal(goalId);
    if (!goal) return NextResponse.json({ error: "not found" }, { status: 404 });

    const res = await attestResult({
      username: goal.user,
      goalTitle: goal.title,
      result: pass ? "PASS" : "FAIL",
      disputed: !!disputed,
      ref: goal.id,
    });

    updateGoal(goalId, { easUID: res.uid });

    return NextResponse.json({ uid: res.uid, txHash: res.txHash, mocked: res.mocked });
  } catch (e: any) {
    console.error("attest route error:", e);
    return NextResponse.json({ error: "attestation failed", details: e?.message ?? String(e) }, { status: 500 });
  }
}
TS

echo "▶ Updating DB: add 'disputed' flag (non-breaking)…"
cat > src/lib/db.ts <<'TS'
import { v4 as uuid } from 'uuid'

export type GoalStatus = 'PENDING' | 'PASSED' | 'FAILED'
export interface Goal {
  id: string
  user: string
  title: string
  scope?: string
  deadlineISO?: string
  status: GoalStatus
  notes?: string
  evidenceURI?: string
  easUID?: string
  score?: number
  rationale?: string
  questions?: any[]
  answers?: string[]
  disputed?: boolean
  createdAt: number
}

export interface DBShape { goals: Goal[] }
const g = globalThis as unknown as { __POD_DB?: DBShape }
if (!g.__POD_DB) g.__POD_DB = { goals: [] }
export const DB = g.__POD_DB

export function createGoal(data: Pick<Goal, 'user'|'title'|'scope'|'deadlineISO'>) {
  const goal: Goal = {
    id: uuid(),
    user: data.user,
    title: data.title,
    scope: data.scope,
    deadlineISO: data.deadlineISO,
    status: 'PENDING',
    disputed: false,
    createdAt: Date.now()
  }
  DB.goals.unshift(goal)
  return goal
}

export const getUserGoals = (u:string)=> DB.goals.filter(g=>g.user===u)
export const getGoal = (id:string)=> DB.goals.find(g=>g.id===id)
export function updateGoal(id:string, patch: Partial<Goal>){ const goal=getGoal(id); if(!goal) return null; Object.assign(goal, patch); return goal }
TS

echo "▶ Updating Profile UI for dispute flow…"
cat > src/app/profile/page.tsx <<'TSX'
'use client'
import { useEffect, useState } from 'react'
import Link from 'next/link'

type Status = 'PENDING'|'PASSED'|'FAILED'
interface Goal { id:string; user:string; title:string; scope?:string; deadlineISO?:string; status:Status; easUID?:string; createdAt:number; disputed?:boolean }

export default function ProfilePage(){
  const [user,setUser]=useState(''); const [goals,setGoals]=useState<Goal[]>([])
  const [title,setTitle]=useState('Read Diestel §2.1–2.3'); const [scope,setScope]=useState('Summarize key defs; solve 3 exercises'); const [deadlineISO,setDeadlineISO]=useState('')

  const [activeId,setActiveId]=useState<string|null>(null)
  const [q1,setQ1]=useState(''); const [q2,setQ2]=useState('')
  const [a1,setA1]=useState(''); const [a2,setA2]=useState('')
  const [loading,setLoading]=useState(false)

  // dispute panel state
  const [pendingFailId, setPendingFailId] = useState<string|null>(null)
  const [showTweetPanel, setShowTweetPanel] = useState(false)

  useEffect(()=>{ const u=localStorage.getItem('pod_user'); if(!u) return; setUser(u); refresh(u) },[])
  const refresh = async(u=user)=>{ if(!u) return; const r=await fetch(`/api/goals?user=${encodeURIComponent(u)}`); const d=await r.json(); setGoals(d.goals) }

  const createGoal = async()=>{ if(!user) return; await fetch('/api/goals',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({user,title,scope,deadlineISO})}); refresh() }

  const startComplete = async (id: string) => {
    setLoading(true);
    try {
      const r = await fetch("/api/goal/questions", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ goalId: id }) });
      let d: any; let raw = "";
      try { d = await r.json(); } catch { raw = await r.text(); }
      if (!r.ok) return alert(d?.error ?? raw ?? "Error generating questions");
      if (d?.questions?.length === 2) {
        const q1t = typeof d.questions[0] === "string" ? d.questions[0] : d.questions[0]?.text;
        const q2t = typeof d.questions[1] === "string" ? d.questions[1] : d.questions[1]?.text;
        setQ1(q1t || "Q1"); setQ2(q2t || "Q2"); setA1(''); setA2(''); setActiveId(id);
      } else { alert("Unexpected question format."); }
    } finally { setLoading(false); }
  };

  const submitAnswers = async()=> {
    if(!activeId) return
    setLoading(true)
    try {
      const r = await fetch('/api/goal/grade', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ goalId: activeId, answers: [a1,a2] }) })
      const d = await r.json()
      setActiveId(null)
      if (d?.pass) {
        // auto-publish PASS
        await fetch('/api/attest', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ goalId: activeId, pass: true, disputed: false }) })
        await refresh()
      } else {
        // ask for dispute
        setPendingFailId(activeId)
      }
    } catch(e:any){
      alert(e?.message || "Network error")
    } finally { setLoading(false) }
  }

  const publishFail = async() => {
    if (!pendingFailId) return
    setLoading(true)
    try {
      await fetch('/api/attest', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ goalId: pendingFailId, pass: false, disputed: false }) })
      await refresh()
    } finally {
      setPendingFailId(null)
      setShowTweetPanel(false)
      setLoading(false)
    }
  }

  const disputeYes = () => {
    setShowTweetPanel(true)
  }

  const disputeTweetConfirmed = async() => {
    if (!pendingFailId) return
    setLoading(true)
    try {
      await fetch('/api/attest', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ goalId: pendingFailId, pass: true, disputed: true }) })
      await refresh()
    } finally {
      setPendingFailId(null)
      setShowTweetPanel(false)
      setLoading(false)
    }
  }

  if(!user) return <main className="card">Please <Link href="/" className="underline">login</Link>.</main>

  return (
    <main className="gridish">
      <div className="card gridish">
        <h2 className="text-xl font-semibold">Hello, {user}</h2>
        <div className="grid" style={{gap:'1rem'}}>
          <div><label className="label">Goal title</label><input className="input" value={title} onChange={e=>setTitle(e.target.value)} /></div>
          <div><label className="label">Scope / notes</label><input className="input" value={scope} onChange={e=>setScope(e.target.value)} /></div>
          <div><label className="label">Deadline (ISO, optional)</label><input className="input" placeholder="2025-10-26T23:00:00+05:30" value={deadlineISO} onChange={e=>setDeadlineISO(e.target.value)} /></div>
          <button className="btn" onClick={createGoal}>Create goal</button>
        </div>
      </div>

      {/* Answer panel */}
      {activeId && (
        <div className="card" style={{position:'sticky', top: 8}}>
          <div className="text-sm text-neutral-400 mb-2">Answer these two quick questions, then we grade.</div>
          <div className="gridish">
            <div><div className="font-medium mb-1">Q1</div><div className="mb-2 text-neutral-300">{q1}</div><textarea className="input" style={{height:'120px'}} value={a1} onChange={e=>setA1(e.target.value)} /></div>
            <div><div className="font-medium mb-1">Q2</div><div className="mb-2 text-neutral-300">{q2}</div><textarea className="input" style={{height:'120px'}} value={a2} onChange={e=>setA2(e.target.value)} /></div>
            <div className="flex gap-2">
              <button className="btn" onClick={submitAnswers} disabled={loading || !a1 || !a2}>{loading ? 'Scoring…' : 'Submit answers'}</button>
              <button className="btn" onClick={()=>setActiveId(null)}>Cancel</button>
            </div>
          </div>
        </div>
      )}

      {/* Dispute dialog */}
      {pendingFailId && !showTweetPanel && (
        <div className="card">
          <div className="font-medium mb-2">You FAILED this check. Raise a dispute?</div>
          <div className="flex gap-2">
            <button className="btn" onClick={disputeYes}>Yes, dispute (tweet)</button>
            <button className="btn" onClick={publishFail}>No, publish FAIL</button>
          </div>
        </div>
      )}
      {pendingFailId && showTweetPanel && (
        <div className="card">
          <div className="text-sm text-neutral-300 mb-2">Post a tweet linking your goal page (dummy for now), then click below.</div>
          <div className="flex gap-2">
            <button className="btn" onClick={()=>alert('Pretend we opened Twitter with prefilled text…')}>Open Twitter (dummy)</button>
            <button className="btn" onClick={disputeTweetConfirmed}>I tweeted — publish PASS</button>
          </div>
        </div>
      )}

      <section className="gridish">
        <h3 className="text-lg font-semibold">Your goals</h3>
        <div className="grid gap-3">
          {goals.map(g=>(
            <div key={g.id} className="card" style={{display:'grid', gridTemplateColumns:'1fr auto', gap:'0.75rem', alignItems:'center'}}>
              <div>
                <div className="font-medium">{g.title}</div>
                <div className="text-sm text-neutral-400">{g.scope}</div>
              </div>
              <div className="flex items-center gap-2">
                <span className="text-sm" style={{padding:'4px 8px', borderRadius:8, background:g.status==='PASSED'?'#064e3b': g.status==='FAILED'?'#7f1d1d':'#27272a', color:g.status==='PENDING'?'#e5e7eb':'#d1fae5'}}>{g.status}</span>
                <Link className="btn" href={`/notes/${g.id}`}>See notes</Link>
                {g.easUID ? (
                  <a className="btn" target="_blank" href={`https://base-sepolia.easscan.org/attestation/view/${g.easUID}`}>Blockchain proof</a>
                ) : (
                  <button className="btn" title="Will appear after publish" disabled>Blockchain proof</button>
                )}
              </div>
            </div>
          ))}
        </div>
      </section>
    </main>
  )
}
TSX

echo "▶ Adding schema registration script (one-off)…"
mkdir -p scripts
cat > scripts/register-eas-schema.mjs <<'MJS'
import { SchemaRegistry } from "@ethereum-attestation-service/eas-sdk";
import { ethers } from "ethers";

const RPC = process.env.RPC_URL_BASE_SEPOLIA;
const PK  = process.env.PLATFORM_PRIVATE_KEY;
const REG = process.env.SCHEMA_REGISTRY_ADDRESS ?? "0x4200000000000000000000000000000000000020"; // Base Sepolia

const SCHEMA = "string app,string username,string goal,string result,bool disputed,string ref";

if (!RPC || !PK) {
  console.error("Missing RPC_URL_BASE_SEPOLIA or PLATFORM_PRIVATE_KEY");
  process.exit(1);
}

const provider = new ethers.JsonRpcProvider(RPC);
const wallet = new ethers.Wallet(PK, provider);

const registry = new SchemaRegistry(REG);
registry.connect(wallet);

console.log("Registering schema on Base Sepolia…");
const tx = await registry.register({
  schema: SCHEMA,
  resolverAddress: "0x0000000000000000000000000000000000000000",
  revocable: true
});
const uid = await tx.wait();
console.log("Schema UID:", uid);
console.log("Paste this into .env.local as EAS_SCHEMA_UID");
MJS

echo "▶ Updating .env.local.example and ensuring keys…"
if [ ! -f .env.local.example ]; then
  cat > .env.local.example <<'ENV'
OPENAI_API_KEY=
NEXT_PUBLIC_USE_MOCKS=false

# EAS / Base Sepolia
RPC_URL_BASE_SEPOLIA=
PLATFORM_PRIVATE_KEY=
EAS_CONTRACT_ADDRESS=0x4200000000000000000000000000000000000021
EAS_SCHEMA_UID=
SCHEMA_REGISTRY_ADDRESS=0x4200000000000000000000000000000000000020
ENV
fi

echo "▶ Done.

Next:
1) Fill .env.local with:
   OPENAI_API_KEY=sk-...
   NEXT_PUBLIC_USE_MOCKS=false
   RPC_URL_BASE_SEPOLIA= (e.g. https://base-sepolia.example-rpc)
   PLATFORM_PRIVATE_KEY= (your test wallet key with a bit of Base Sepolia ETH)
   EAS_SCHEMA_UID= (run: node scripts/register-eas-schema.mjs)

2) Restart: npm run dev

3) Flow: Complete → if PASS auto-publishes PASS → if FAIL shows dispute → choose No (publishes FAIL) or Yes+Tweet (publishes PASS).

Explorer link appears on each goal once published (Base Sepolia EAS Scan).
"
