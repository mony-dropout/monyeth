#!/usr/bin/env bash
set -euo pipefail

mkdir -p src/components

echo "▶ Add a reusable inline notes expander (client)…"
cat > src/components/NotesInline.tsx <<'TSX'
'use client'
import { useState } from 'react'

export default function NotesInline({
  goalId,
  initialNotes
}: {
  goalId: string
  initialNotes?: string
}) {
  const [open, setOpen] = useState(false)
  const [loading, setLoading] = useState(false)
  const [notes, setNotes] = useState<string | null>(initialNotes ?? null)
  const [err, setErr] = useState<string | null>(null)

  const toggle = async () => {
    setOpen(o => !o)
    if (!open && notes == null) {
      setLoading(true); setErr(null)
      try {
        const r = await fetch(`/api/goal/${goalId}`, { cache: 'no-store' })
        if (!r.ok) throw new Error(`HTTP ${r.status}`)
        const d = await r.json()
        setNotes(d?.goal?.notes || '')
      } catch (e: any) {
        setErr(e?.message || 'Failed to load notes')
      } finally {
        setLoading(false)
      }
    }
  }

  return (
    <div className="flex flex-col gap-2">
      <button className="btn" onClick={toggle}>{open ? 'Hide notes' : 'Notes'}</button>
      {open && (
        <div className="mt-1 w-full">
          {loading ? (
            <div className="text-sm text-neutral-400">Loading notes…</div>
          ) : err ? (
            <div className="text-sm text-red-400">{err}</div>
          ) : (
            <pre className="whitespace-pre-wrap text-neutral-200 bg-neutral-900 p-3 rounded-xl border border-neutral-800">
{(notes ?? 'No notes yet.')}
            </pre>
          )}
        </div>
      )}
    </div>
  )
}
TSX

echo "▶ Update /profile to show inline notes (remove link)…"
cat > src/app/profile/page.tsx <<'TSX'
'use client'
import { useEffect, useState } from 'react'
import Link from 'next/link'
import NotesInline from '@/components/NotesInline'

type Status = 'PENDING'|'PASSED'|'FAILED'
interface Goal { id:string; user:string; title:string; scope?:string; deadlineISO?:string; status:Status; easUID?:string; createdAt:number; disputed?:boolean; notes?:string }

type DisputePhase = 'ask' | 'tweet' | null

export default function ProfilePage(){
  const [user,setUser]=useState(''); const [goals,setGoals]=useState<Goal[]>([])
  const [title,setTitle]=useState('Read Diestel §2.1–2.3'); const [scope,setScope]=useState('Summarize key defs; solve 3 exercises'); const [deadlineISO,setDeadlineISO]=useState('')

  const [activeId,setActiveId]=useState<string|null>(null)
  const [q1,setQ1]=useState(''); const [q2,setQ2]=useState('')
  const [a1,setA1]=useState(''); const [a2,setA2]=useState('')
  const [loading,setLoading]=useState(false)

  // dispute state
  const [pendingFailId, setPendingFailId] = useState<string|null>(null)
  const [disputePhase, setDisputePhase] = useState<DisputePhase>(null)
  const [tweetIntent, setTweetIntent] = useState<string>('')

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
        await fetch('/api/attest', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ goalId: activeId, pass: true, disputed: false }) })
        await refresh()
      } else {
        setPendingFailId(activeId)
        setDisputePhase('ask')
      }
    } catch(e:any){
      alert(e?.message || "Network error")
    } finally { setLoading(false) }
  }

  const noDisputePublishFail = async () => {
    if (!pendingFailId) return
    setLoading(true)
    try {
      await fetch('/api/attest', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ goalId: pendingFailId, pass: false, disputed: false }) })
      await refresh()
    } finally {
      setPendingFailId(null)
      setDisputePhase(null)
      setLoading(false)
    }
  }
  const goToDisputePanel = async () => {
    if (!pendingFailId) return
    setLoading(true)
    try {
      const s = await fetch('/api/dispute/start', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ goalId: pendingFailId }) }).then(r=>r.json())
      setTweetIntent(s.intentUrl || '#')
      setDisputePhase('tweet')
    } finally { setLoading(false) }
  }
  const markPassAfterTweet = async () => {
    if (!pendingFailId) return
    setLoading(true)
    try {
      await fetch('/api/attest', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ goalId: pendingFailId, pass: true, disputed: true }) })
      await refresh()
    } finally {
      setPendingFailId(null); setDisputePhase(null); setLoading(false)
    }
  }
  const publishFailFromDispute = async() => {
    if (!pendingFailId) return
    setLoading(true)
    try {
      await fetch('/api/attest', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ goalId: pendingFailId, pass: false, disputed: true }) })
      await refresh()
    } finally {
      setPendingFailId(null); setDisputePhase(null); setLoading(false)
    }
  }

  if(!user) return <main className="card">Please <Link href="/login" className="underline">login</Link>.</main>

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

      {/* Dispute step 1 */}
      {pendingFailId && disputePhase === 'ask' && (
        <div className="card">
          <div className="font-medium mb-2">You FAILED this check.</div>
          <div className="text-sm text-neutral-300 mb-3">Would you like to dispute?</div>
          <div className="flex flex-wrap gap-2">
            <button className="btn" onClick={noDisputePublishFail} disabled={loading}>{loading?'Working…':'No dispute — publish FAIL'}</button>
            <button className="btn" onClick={goToDisputePanel} disabled={loading}>{loading?'Working…':'Dispute this check'}</button>
          </div>
        </div>
      )}

      {/* Dispute step 2 */}
      {pendingFailId && disputePhase === 'tweet' && (
        <div className="card">
          <div className="font-medium mb-2">Dispute via tweet</div>
          <div className="flex gap-2 mb-3">
            <a className="btn" href={tweetIntent || '#'} target="_blank" rel="noreferrer">Open tweet (prefilled)</a>
          </div>
          <div className="flex flex-wrap gap-2">
            <button className="btn" onClick={markPassAfterTweet} disabled={loading}>{loading?'Working…':'I posted the tweet — PASS me'}</button>
            <button className="btn" onClick={publishFailFromDispute} disabled={loading}>{loading?'Working…':'I didn’t tweet — publish FAIL'}</button>
          </div>
        </div>
      )}

      <section className="gridish">
        <h3 className="text-lg font-semibold">Your goals</h3>
        <div className="grid gap-3">
          {goals.map(g=>(
            <div key={g.id} className="card" style={{display:'grid', gridTemplateColumns:'1fr auto', gap:'0.75rem', alignItems:'flex-start'}}>
              <div>
                <div className="font-medium">{g.title}</div>
                <div className="text-sm text-neutral-400">{g.scope}</div>
              </div>
              <div className="flex items-start gap-2">
                <span className="text-sm" style={{padding:'4px 8px', borderRadius:8, background:g.status==='PASSED'?'#064e3b': g.status==='FAILED'?'#7f1d1d':'#27272a', color:g.status==='PENDING'?'#e5e7eb':'#d1fae5'}}>{g.status}{g.disputed?'·disputed':''}</span>
                {g.status === "PENDING" && !activeId && !pendingFailId && (
                  <button className="btn" onClick={()=>startComplete(g.id)}>Complete</button>
                )}
                {/* Inline notes here (no more links) */}
                <NotesInline goalId={g.id} initialNotes={g.notes} />
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

echo "▶ Update /social to use inline notes (fetch per item)…"
cat > src/app/social/page.tsx <<'TSX'
import Link from "next/link"
import NotesInline from "@/components/NotesInline"

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
          <div key={it.id} className="card" style={{display:'grid', gridTemplateColumns:'1fr auto', gap:'0.75rem', alignItems:'flex-start'}}>
            <div>
              <div className="font-medium">
                <Link className="underline" href={`/u/${it.username}`}>@{it.username}</Link> — {it.title}
              </div>
              {it.scope ? <div className="text-sm text-neutral-400">{it.scope}</div> : null}
              <div className="text-xs text-neutral-500 mt-1">{new Date(it.createdAt).toLocaleString()}</div>
            </div>
            <div className="flex items-start gap-2">
              <span
                className="text-sm"
                style={{
                  padding:'4px 8px',
                  borderRadius:8,
                  background:it.status==='PASSED'?'#064e3b': it.status==='FAILED'?'#7f1d1d':'#27272a',
                  color:it.status==='PENDING'?'#e5e7eb':'#d1fae5'
                }}
              >
                {it.status}{it.disputed ? '·disputed' : ''}
              </span>

              {/* Inline notes fetches goal notes by id */}
              <NotesInline goalId={it.id} />

              <a className="btn" target="_blank" href={`https://base-sepolia.easscan.org/attestation/view/${it.easUID}`}>
                Proof
              </a>
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

echo "▶ Update public profile /u/[username] to use inline notes too…"
cat > src/app/u/[username]/page.tsx <<'TSX'
import Link from "next/link"
import NotesInline from "@/components/NotesInline"

async function fetchUserGoals(username: string){
  const r = await fetch(`${process.env.NEXT_PUBLIC_SITE_URL ?? ''}/api/user/${username}/goals`, { cache:'no-store' }).catch(()=>null)
  if(!r || !r.ok) return { goals: [] as any[] }
  return r.json()
}

export default async function PublicProfile({ params }: { params: { username: string } }){
  const username = params.username
  const { goals } = await fetchUserGoals(username)

  return (
    <main className="gridish">
      <div className="card">
        <h1 className="text-2xl font-semibold">@{username}</h1>
        <div className="text-sm text-neutral-400">Public history</div>
      </div>

      <section className="grid gap-3">
        {goals.length ? goals.map((g:any)=>(
          <div key={g.id} className="card" style={{display:'grid', gridTemplateColumns:'1fr auto', gap:'0.75rem', alignItems:'flex-start'}}>
            <div>
              <div className="font-medium">{g.title}</div>
              {g.scope ? <div className="text-sm text-neutral-400">{g.scope}</div> : null}
              <div className="text-xs text-neutral-500 mt-1">{new Date(g.createdAt).toLocaleString()}</div>
            </div>
            <div className="flex items-start gap-2">
              <span className="text-sm" style={{padding:'4px 8px', borderRadius:8, background:g.status==='PASSED'?'#064e3b': g.status==='FAILED'?'#7f1d1d':'#27272a', color:g.status==='PENDING'?'#e5e7eb':'#d1fae5'}}>{g.status}{g.disputed?'·disputed':''}</span>
              <NotesInline goalId={g.id} />
              {g.easUID ? (
                <a className="btn" target="_blank" href={`https://base-sepolia.easscan.org/attestation/view/${g.easUID}`}>Proof</a>
              ) : (
                <button className="btn" disabled title="No attestation yet">Proof</button>
              )}
            </div>
          </div>
        )) : (
          <div className="text-neutral-400">No entries yet.</div>
        )}
      </section>
    </main>
  )
}
TSX

echo "✅ Inline notes now render directly on profile, social, and public profile."
