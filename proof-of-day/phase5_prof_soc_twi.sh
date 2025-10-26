#!/usr/bin/env bash
set -euo pipefail

echo "▶ Updating DB with disputeToken…"
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
  disputeToken?: string
  createdAt: number
}

export interface DBShape { goals: Goal[] }
const g = (globalThis as any)
if (!g.__POD_DB) g.__POD_DB = { goals: [] as Goal[] }
export const DB: DBShape = g.__POD_DB

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

echo "▶ Public profile API: /api/user/[username]/goals…"
mkdir -p src/app/api/user/[username]/goals
cat > src/app/api/user/[username]/goals/route.ts <<'TS'
import { NextRequest, NextResponse } from 'next/server'
import { getUserGoals } from '@/lib/db'

export async function GET(req: NextRequest, { params }: { params: { username: string } }) {
  const username = params.username
  const goals = getUserGoals(username)
  // Public: show all, but only include fields relevant for public view
  const pub = goals.map(g => ({
    id: g.id,
    title: g.title,
    scope: g.scope,
    status: g.status,
    easUID: g.easUID,
    disputed: g.disputed,
    createdAt: g.createdAt
  }))
  return NextResponse.json({ username, goals: pub })
}
TS

echo "▶ Social feed API: /api/feed…"
mkdir -p src/app/api/feed
cat > src/app/api/feed/route.ts <<'TS'
import { NextResponse } from 'next/server'
import { DB } from '@/lib/db'

export async function GET() {
  // Latest published (has easUID), newest first
  const items = DB.goals
    .filter(g => !!g.easUID)
    .sort((a,b)=> b.createdAt - a.createdAt)
    .slice(0,200)
    .map(g => ({
      id: g.id,
      username: g.user,
      title: g.title,
      status: g.status,
      disputed: g.disputed,
      easUID: g.easUID,
      createdAt: g.createdAt
    }))
  return NextResponse.json({ items })
}
TS

echo "▶ Public profile page: /u/[username]…"
mkdir -p src/app/u/[username]
cat > src/app/u/[username]/page.tsx <<'TSX'
import Link from "next/link"

async function fetchGoals(username: string){
  const r = await fetch(`${process.env.NEXT_PUBLIC_SITE_URL ?? ''}/api/user/${username}/goals`, { cache: 'no-store' })
    .catch(()=> null)
  if (!r || !r.ok) return { username, goals: [] as any[] }
  return r.json()
}

export default async function PublicProfile({ params }: { params: { username: string } }){
  const { username } = params
  const data = await fetchGoals(username)

  return (
    <main className="gridish">
      <div className="card">
        <h1 className="text-2xl font-semibold">@{username}</h1>
        <div className="text-sm text-neutral-400">Public proof-of-day profile</div>
      </div>

      <section className="gridish">
        <h3 className="text-lg font-semibold">History</h3>
        <div className="grid gap-3">
          {data.goals?.length ? data.goals.map((g:any)=>(
            <div key={g.id} className="card" style={{display:'grid', gridTemplateColumns:'1fr auto', gap:'0.75rem', alignItems:'center'}}>
              <div>
                <div className="font-medium">{g.title}</div>
                <div className="text-sm text-neutral-400">{g.scope}</div>
              </div>
              <div className="flex items-center gap-2">
                <span className="text-sm" style={{padding:'4px 8px', borderRadius:8, background:g.status==='PASSED'?'#064e3b': g.status==='FAILED'?'#7f1d1d':'#27272a', color:g.status==='PENDING'?'#e5e7eb':'#d1fae5'}}>{g.status}{g.disputed?'·disputed':''}</span>
                {g.easUID ? (
                  <a className="btn" target="_blank" href={`https://base-sepolia.easscan.org/attestation/view/${g.easUID}`}>Proof</a>
                ) : (
                  <button className="btn" disabled>Proof</button>
                )}
              </div>
            </div>
          )) : (
            <div className="text-neutral-400">No entries yet.</div>
          )}
        </div>
      </section>

      <div className="text-sm text-neutral-500">
        <Link className="underline" href="/">Back to app</Link>
      </div>
    </main>
  )
}
TSX

echo "▶ Social page: /social…"
mkdir -p src/app/social
cat > src/app/social/page.tsx <<'TSX'
import Link from "next/link"

async function fetchFeed(){
  const r = await fetch(`${process.env.NEXT_PUBLIC_SITE_URL ?? ''}/api/feed`, { cache: 'no-store' }).catch(()=>null)
  if (!r || !r.ok) return { items: [] as any[] }
  return r.json()
}

export default async function SocialPage(){
  const { items } = await fetchFeed()

  return (
    <main className="gridish">
      <div className="card">
        <h1 className="text-2xl font-semibold">Social</h1>
        <div className="text-sm text-neutral-400">Newest on-chain proofs</div>
      </div>

      <section className="grid gap-3">
        {items.length ? items.map((it:any)=>(
          <div key={it.id} className="card" style={{display:'grid', gridTemplateColumns:'1fr auto', gap:'0.75rem', alignItems:'center'}}>
            <div>
              <div className="font-medium"><Link className="underline" href={`/u/${it.username}`}>@{it.username}</Link> — {it.title}</div>
              <div className="text-sm text-neutral-400">{new Date(it.createdAt).toLocaleString()}</div>
            </div>
            <div className="flex items-center gap-2">
              <span className="text-sm" style={{padding:'4px 8px', borderRadius:8, background:it.status==='PASSED'?'#064e3b': it.status==='FAILED'?'#7f1d1d':'#27272a', color:it.status==='PENDING'?'#e5e7eb':'#d1fae5'}}>{it.status}{it.disputed?'·disputed':''}</span>
              <a className="btn" target="_blank" href={`https://base-sepolia.easscan.org/attestation/view/${it.easUID}`}>Proof</a>
            </div>
          </div>
        )) : <div className="text-neutral-400">No attestations yet.</div>}
      </section>

      <div className="text-sm text-neutral-500">
        <Link className="underline" href="/">Back to app</Link>
      </div>
    </main>
  )
}
TSX

echo "▶ Dispute START API: issues token + tweet intent URL…"
mkdir -p src/app/api/dispute/start
cat > src/app/api/dispute/start/route.ts <<'TS'
import { NextRequest, NextResponse } from "next/server"
import { getGoal, updateGoal } from "@/lib/db"
import { randomBytes } from "crypto"

function baseUrl(req: NextRequest){
  const env = process.env.NEXT_PUBLIC_SITE_URL
  if (env) return env.replace(/\/+$/,'')
  const host = req.headers.get('x-forwarded-host') || req.headers.get('host') || 'localhost:3000'
  const proto = (req.headers.get('x-forwarded-proto') || 'http')
  return `${proto}://${host}`
}

export async function POST(req: NextRequest){
  const { goalId } = await req.json()
  const goal = getGoal(goalId)
  if (!goal) return NextResponse.json({ error: 'not found' }, { status: 404 })
  const token = 'POD-' + randomBytes(6).toString('hex').toUpperCase()
  updateGoal(goalId, { disputeToken: token, disputed: true })

  const profileUrl = `${baseUrl(req)}/u/${encodeURIComponent(goal.user)}`
  const text = encodeURIComponent(`Dispute: I completed "${goal.title}". Proof-of-Day token ${token} ${profileUrl}`)
  const intent = `https://twitter.com/intent/tweet?text=${text}`
  return NextResponse.json({ token, intentUrl: intent, profileUrl })
}
TS

echo "▶ Dispute VERIFY API: checks tweet text for token + profile link…"
mkdir -p src/app/api/dispute/verify
cat > src/app/api/dispute/verify/route.ts <<'TS'
import { NextRequest, NextResponse } from "next/server"
import { getGoal, updateGoal } from "@/lib/db"
import { attestResult } from "@/lib/eas"

// Extract numeric id from twitter/x url
function parseTweetId(urlStr: string){
  try {
    const u = new URL(urlStr)
    const path = u.pathname
    const m = path.match(/\/status\/(\d+)/)
    return m?.[1] || null
  } catch { return null }
}

export async function POST(req: NextRequest){
  const { goalId, tweetUrl } = await req.json()
  const goal = getGoal(goalId)
  if (!goal) return NextResponse.json({ error: 'not found' }, { status: 404 })
  if (!goal.disputeToken) return NextResponse.json({ error: 'no-dispute' }, { status: 400 })

  const id = parseTweetId(String(tweetUrl||''))
  if (!id) return NextResponse.json({ error: 'bad-tweet-url' }, { status: 400 })

  // Use Twitter public syndication JSON (no auth). May occasionally rate-limit.
  const syndUrl = `https://cdn.syndication.twimg.com/widgets/tweet.json?id=${id}`
  let ok = false
  try {
    const r = await fetch(syndUrl, { cache: 'no-store' })
    if (r.ok) {
      const data = await r.json()
      const text = (data?.text || data?.full_text || '').toString()
      const hasToken = text.includes(goal.disputeToken)
      // profile URL we advertised in /start
      const host = process.env.NEXT_PUBLIC_SITE_URL?.replace(/\/+$/,'') || ''
      const profileLink1 = `${host}/u/${goal.user}`
      const profileLink2 = `/u/${goal.user}`
      const hasProfile = text.includes(profileLink1) || text.includes(profileLink2)
      ok = hasToken && hasProfile
    }
  } catch (e) {
    // network blocked → remain false (we'll tell client)
  }

  if (!ok) {
    return NextResponse.json({ verified: false, error: 'token-or-link-missing' }, { status: 200 })
  }

  // Verified: publish PASS attestation (disputed = true)
  const res = await attestResult({
    username: goal.user,
    goalTitle: goal.title,
    result: "PASS",
    disputed: true,
    ref: goal.id
  })
  updateGoal(goalId, { status: 'PASSED', easUID: res.uid, disputed: true })
  return NextResponse.json({ verified: true, uid: res.uid, txHash: res.txHash, mocked: res.mocked })
}
TS

echo "▶ Wiring dispute UI on profile page…"
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

  // dispute state
  const [pendingFailId, setPendingFailId] = useState<string|null>(null)
  const [tweetIntent, setTweetIntent] = useState<string>('')
  const [tweetUrl, setTweetUrl] = useState<string>('')

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
        // start dispute
        setPendingFailId(activeId)
        const s = await fetch('/api/dispute/start', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ goalId: activeId }) }).then(r=>r.json())
        setTweetIntent(s.intentUrl); setTweetUrl('')
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
      setLoading(false)
    }
  }

  const verifyTweet = async () => {
    if (!pendingFailId) return
    if (!tweetUrl) { alert('Paste your tweet URL first'); return }
    setLoading(true)
    try {
      const r = await fetch('/api/dispute/verify', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ goalId: pendingFailId, tweetUrl }) })
      const d = await r.json()
      if (d.verified) {
        alert('Verified! Publishing PASS.')
        await refresh()
      } else {
        alert('Could not verify token/link in tweet. You can publish FAIL instead, or try another tweet.')
      }
    } finally {
      setPendingFailId(null)
      setLoading(false)
    }
  }

  if(!user) return <main className="card">Please <Link href="/" className="underline">login</Link>.</main>

  return (
    <main className="gridish">
      <div className="card gridish">
        <h2 className="text-xl font-semibold">Hello, {user}</h2>
        <div className="flex gap-3 text-sm text-neutral-400">
          <Link className="underline" href={`/u/${user}`}>Your public profile</Link>
          <Link className="underline" href={`/social`}>Social</Link>
        </div>
        <div className="grid" style={{gap:'1rem'}}>
          <div><label className="label">Goal title</label><input className="input" value={title} onChange={e=>setTitle(e.target.value)} /></div>
          <div><label className="label">Scope / notes</label><input className="input" value={scope} onChange={e=>setScope(e.target.value)} /></div>
          <div><label className="label">Deadline (ISO, optional)</label><input className="input" placeholder="2025-10-26T23:00:00+05:30" value={deadlineISO} onChange={e=>setDeadlineISO(e.target.value)} /></div>
          <button className="btn" onClick={createGoal}>Create goal</button>
        </div>
      </div>

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

      {/* Dispute flow */}
      {pendingFailId && (
        <div className="card">
          <div className="font-medium mb-2">You FAILED this check. Raise a dispute via tweet?</div>
          <div className="flex gap-2 mb-3">
            <a className="btn" href={tweetIntent || '#'} target="_blank">Open tweet (prefilled)</a>
            <button className="btn" onClick={publishFail}>No, publish FAIL</button>
          </div>
          <div className="text-sm text-neutral-300 mb-1">Paste your tweet URL:</div>
          <input className="input" placeholder="https://x.com/you/status/123..." value={tweetUrl} onChange={e=>setTweetUrl(e.target.value)} />
          <div className="flex gap-2 mt-3">
            <button className="btn" onClick={verifyTweet} disabled={loading || !tweetUrl}>{loading?'Verifying…':'I tweeted — verify & publish PASS'}</button>
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
                <span className="text-sm" style={{padding:'4px 8px', borderRadius:8, background:g.status==='PASSED'?'#064e3b': g.status==='FAILED'?'#7f1d1d':'#27272a', color:g.status==='PENDING'?'#e5e7eb':'#d1fae5'}}>{g.status}{g.disputed?'·disputed':''}</span>
                {(g.status !== "PASSED") && !activeId && !pendingFailId && (
                  <button className="btn" onClick={()=>startComplete(g.id)}>Complete</button>
                )}
                <Link className="btn" href={`/notes/${g.id}`}>See notes</Link>
                {g.easUID ? (
                  <a className="btn" target="_blank" href={`https://base-sepolia.easscan.org/attestation/view/${g.easUID}`}>Blockchain proof</a>
                ) : (
                  <button className="btn" title="Publishes automatically after grading" disabled>Blockchain proof</button>
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

echo "▶ Reminder: set NEXT_PUBLIC_SITE_URL in .env.local for correct links"
echo "Done. Restart your dev server."
