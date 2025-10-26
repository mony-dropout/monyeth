'use client'
import { useEffect, useState } from 'react'
import Link from 'next/link'

type Status = 'PENDING'|'PASSED'|'FAILED'
interface Goal { id:string; user:string; title:string; scope?:string; deadlineISO?:string; status:Status; score?:number; rationale?:string; easUID?:string; evidenceURI?:string; createdAt:number; questions?:any[] }

export default function ProfilePage(){
  const [user,setUser]=useState(''); const [goals,setGoals]=useState<Goal[]>([])
  const [title,setTitle]=useState('Read Diestel §2.1–2.3'); const [scope,setScope]=useState('Summarize key defs; solve 3 exercises'); const [deadlineISO,setDeadlineISO]=useState('')

  const [activeId,setActiveId]=useState<string|null>(null)
  const [q1,setQ1]=useState(''); const [q2,setQ2]=useState('')
  const [a1,setA1]=useState(''); const [a2,setA2]=useState('')
  const [loading,setLoading]=useState(false)

  useEffect(()=>{ const u=localStorage.getItem('pod_user'); if(!u) return; setUser(u); refresh(u) },[])
  const refresh = async(u=user)=>{ if(!u) return; const r=await fetch(`/api/goals?user=${encodeURIComponent(u)}`); const d=await r.json(); setGoals(d.goals) }

  const createGoal = async()=>{ if(!user) return; await fetch('/api/goals',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({user,title,scope,deadlineISO})}); refresh() }

  const startComplete = async (id: string) => {
    setLoading(true);
    try {
      const r = await fetch("/api/goal/questions", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ goalId: id }),
      });

      let d: any; let raw = "";
      try { d = await r.json(); } catch { raw = await r.text(); }
      if (!r.ok) return alert(d?.error ?? raw ?? "Error generating questions");

      if (d?.questions && d.questions.length === 2) {
        const q1Text = typeof d.questions[0] === "string" ? d.questions[0] : d.questions[0]?.text;
        const q2Text = typeof d.questions[1] === "string" ? d.questions[1] : d.questions[1]?.text;
        setQ1(q1Text || "Q1"); setQ2(q2Text || "Q2"); setA1(''); setA2(''); setActiveId(id);
      } else {
        alert("API returned unexpected question format.");
      }
    } catch (e:any) {
      alert(e?.message || "Network error");
    } finally {
      setLoading(false);
    }
  };

  const submitAnswers = async()=> {
    if(!activeId) return
    setLoading(true)
    try {
      const r = await fetch('/api/goal/grade', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ goalId: activeId, answers: [a1,a2] }) })
      let d: any; let raw = "";
      try { d = await r.json(); } catch { raw = await r.text(); }
      if (!r.ok) return alert(d?.error ?? raw ?? "Grader error");
      setActiveId(null)
      // If pass, still hit stubbed attest (mock)
      if(d?.pass){ await fetch('/api/attest', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ goalId: activeId }) }) }
      await refresh()
    } catch(e:any){
      alert(e?.message || "Network error")
    } finally {
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

      {activeId && (
        <div className="card" style={{position:'sticky', top: 8}}>
          <div className="text-sm text-neutral-400 mb-2">Answer these two quick questions, then we grade. Be concise.</div>
          <div className="gridish">
            <div>
              <div className="font-medium mb-1">Q1</div>
              <div className="mb-2 text-neutral-300">{q1}</div>
              <textarea className="input" style={{height:'120px'}} value={a1} onChange={e=>setA1(e.target.value)} />
            </div>
            <div>
              <div className="font-medium mb-1">Q2</div>
              <div className="mb-2 text-neutral-300">{q2}</div>
              <textarea className="input" style={{height:'120px'}} value={a2} onChange={e=>setA2(e.target.value)} />
            </div>
            <div className="flex gap-2">
              <button className="btn" onClick={submitAnswers} disabled={loading || !a1 || !a2}>{loading ? 'Scoring…' : 'Submit answers'}</button>
              <button className="btn" onClick={()=>setActiveId(null)}>Cancel</button>
            </div>
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
                {g.status==='PENDING' && (<button className="btn" onClick={()=>startComplete(g.id)} disabled={!!activeId}>Complete</button>)}
                <Link className="btn" href={`/notes/${g.id}`}>See notes</Link>
                {g.easUID ? (
                  <a className="btn" target="_blank" href={`https://base-sepolia.easscan.org/attestation/view/${g.easUID}`}>Blockchain proof</a>
                ) : (
                  <button className="btn" title="No attestation yet" disabled>Blockchain proof</button>
                )}
              </div>
            </div>
          ))}
        </div>
      </section>
    </main>
  )
}
