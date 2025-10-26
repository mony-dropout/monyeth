#!/usr/bin/env bash
set -euo pipefail

echo "▶ Updating /api/attest to set status + disputed…"
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

    updateGoal(goalId, {
      status: pass ? 'PASSED' : 'FAILED',
      disputed: !!disputed,
      easUID: res.uid
    });

    return NextResponse.json({ uid: res.uid, txHash: res.txHash, mocked: res.mocked });
  } catch (e: any) {
    console.error("attest route error:", e);
    return NextResponse.json({ error: "attestation failed", details: e?.message ?? String(e) }, { status: 500 });
  }
}
TS

echo "▶ Replacing Profile dispute UI with self-verify buttons…"
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

  // dispute (self-verify)
  const [pendingFailId, setPendingFailId] = useState<string|null>(null)
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
        // auto-publish PASS (not disputed)
        await fetch('/api/attest', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ goalId: activeId, pass: true, disputed: false }) })
        await refresh()
      } else {
        // start dispute → just open prefilled tweet, then user self-verifies
        setPendingFailId(activeId)
        const s = await fetch('/api/dispute/start', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ goalId: activeId }) }).then(r=>r.json())
        setTweetIntent(s.intentUrl || '#')
      }
    } catch(e:any){
      alert(e?.message || "Network error")
    } finally { setLoading(false) }
  }

  const publishFail = async() => {
    if (!pendingFailId) return
    setLoading(true)
    try {
      await fetch('/api/attest', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ goalId: pendingFailId, pass: false, disputed: true }) })
      await refresh()
    } finally {
      setPendingFailId(null)
      setLoading(false)
    }
  }

  const markPassAfterTweet = async () => {
    if (!pendingFailId) return
    setLoading(true)
    try {
      await fetch('/api/attest', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ goalId: pendingFailId, pass: true, disputed: true }) })
      await refresh()
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

      {/* Dispute (self-verify) */}
      {pendingFailId && (
        <div className="card">
          <div className="font-medium mb-2">You FAILED this check. Dispute via tweet?</div>
          <div className="flex gap-2 mb-3">
            <a className="btn" href={tweetIntent || '#'} target="_blank" rel="noreferrer">Open tweet (prefilled)</a>
          </div>
          <div className="flex flex-wrap gap-2">
            <button className="btn" onClick={markPassAfterTweet} disabled={loading}>{loading?'Working…':'I posted the tweet — PASS me'}</button>
            <button className="btn" onClick={publishFail} disabled={loading}>{loading?'Working…':'I didn’t tweet — publish FAIL'}</button>
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

echo "✅ Self-verify dispute flow installed."
