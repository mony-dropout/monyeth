'use client'
import { useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
type Status = 'PENDING'|'PASSED'|'FAILED'
type Goal = { id:string; user:string; title:string; scope?:string; deadlineISO?:string; status:Status; score?:number; rationale?:string; easUID?:string; evidenceURI?:string; createdAt:number }
export default function ProfilePage(){
  const [user,setUser]=useState(''); const [goals,setGoals]=useState<Goal[]>([])
  const [title,setTitle]=useState('Read Diestel §2.1–2.3'); const [scope,setScope]=useState('Summarize defs; solve 3 exercises'); const [deadlineISO,setDeadlineISO]=useState('')
  useEffect(()=>{ const u=localStorage.getItem('pod_user'); if(!u) return; setUser(u); refresh(u) },[])
  const refresh=async(u=user)=>{ if(!u) return; const r=await fetch(`/api/goals?user=${encodeURIComponent(u)}`); const d=await r.json(); setGoals(d.goals) }
  const createGoal=async()=>{ if(!user) return; await fetch('/api/goals',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({user,title,scope,deadlineISO})}); refresh() }
  const complete=async(id:string)=>{ const r=await fetch('/api/goal/complete',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({goalId:id,user})}); const d=await r.json(); if(d.pass){ await fetch('/api/attest',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({goalId:id})}) } refresh() }
  const isMock = (process.env.NEXT_PUBLIC_USE_MOCKS ?? 'true') !== 'false'
  if(!user) return <main className="card">Please <Link href="/" className="underline">login</Link>.</main>
  return (
    <main className="gridish">
      <div className="card gridish">
        <h2 className="text-xl font-semibold">Hello, {user}</h2>
        <div className="grid md:grid-cols-2 gap-4">
          <div className="gridish">
            <label className="label">Goal title</label>
            <input className="input" value={title} onChange={e=>setTitle(e.target.value)} />
            <label className="label">Scope / notes</label>
            <input className="input" value={scope} onChange={e=>setScope(e.target.value)} />
            <label className="label">Deadline (ISO, optional)</label>
            <input className="input" placeholder="2025-10-26T23:00:00+05:30" value={deadlineISO} onChange={e=>setDeadlineISO(e.target.value)} />
            <button className="btn" onClick={createGoal}>Create goal</button>
          </div>
          <div className="text-sm text-neutral-400">
            <p>Demo is running with <b>{isMock ? 'MOCKED' : 'LIVE'}</b> judge & attest.</p>
            <p>Click <i>Complete (mock)</i> to simulate quiz → PASS → onchain attestation.</p>
          </div>
        </div>
      </div>
      <section className="gridish">
        <h3 className="text-lg font-semibold">Your goals</h3>
        <div className="grid gap-3">
          {goals.map(g=>(
            <div key={g.id} className="card grid md:grid-cols-4 gap-3 items-center">
              <div className="md:col-span-2">
                <div className="font-medium">{g.title}</div>
                <div className="text-sm text-neutral-400">{g.scope}</div>
              </div>
              <div className="text-sm">
                <span className={`px-2 py-1 rounded-lg ${g.status==='PASSED'?'bg-emerald-500/20 text-emerald-300': g.status==='FAILED'?'bg-rose-500/20 text-rose-300':'bg-neutral-800 text-neutral-300'}`}>{g.status}</span>
              </div>
              <div className="flex gap-2 justify-end">
                {g.status==='PENDING' && (<button className="btn" onClick={()=>complete(g.id)}>Complete (mock)</button>)}
                <Link className="btn" href={`/notes/${g.id}`}>See notes</Link>
                {g.easUID ? (
                  <a className="btn" target="_blank" href={`https://base-sepolia.easscan.org/attestation/view/${g.easUID}`}>Blockchain proof</a>
                ) : (
                  <button className="btn opacity-50 cursor-not-allowed" title="No attestation yet">Blockchain proof</button>
                )}
              </div>
            </div>
          ))}
        </div>
      </section>
    </main>
  )
}
