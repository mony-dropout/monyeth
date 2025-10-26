'use client'
import { useEffect, useState } from 'react'
import { useParams } from 'next/navigation'
export default function NotesPage(){
  const { id } = useParams<{id:string}>()
  const [notes,setNotes]=useState(''); const [goal,setGoal]=useState<any>(null)
  useEffect(()=>{ fetch(`/api/goal?id=${id}`).then(r=>r.json()).then(setGoal) },[id])
  useEffect(()=>{ if(goal?.goal?.notes) setNotes(goal.goal.notes) },[goal])
  const save = async()=>{ await fetch('/api/goal',{method:'PATCH',headers:{'Content-Type':'application/json'},body:JSON.stringify({id,notes})}); alert('Saved') }
  if(!goal) return <main className="card">Loading...</main>
  return (
    <main className="gridish">
      <div className="card gridish">
        <h2 className="text-xl font-semibold">Notes</h2>
        <textarea className="input h-64" value={notes} onChange={e=>setNotes(e.target.value)} placeholder="Paste quiz/chat transcript or write a mini blog here" />
        <button className="btn" onClick={save}>Save</button>
      </div>
    </main>
  )
}
