'use client'
import { useEffect, useMemo, useState } from "react"
import Link from "next/link"

export default function DiscoverPage(){
  const [users,setUsers] = useState<string[]>([])
  const [q,setQ] = useState('')

  useEffect(()=>{
    fetch('/api/users').then(r=>r.json()).then(d=> setUsers(d?.users || []))
  },[])

  const filtered = useMemo(()=>{
    const s = q.trim().toLowerCase()
    if(!s) return users
    return users.filter(u=> u.toLowerCase().includes(s))
  },[users,q])

  return (
    <main className="gridish">
      <div className="card">
        <h1 className="text-2xl font-semibold">Discover</h1>
        <div className="text-sm text-neutral-400">Find users and browse their public history</div>
      </div>
      <div className="card">
        <input className="input" placeholder="Search username…" value={q} onChange={e=>setQ(e.target.value)} />
      </div>
      <section className="grid gap-2">
        {filtered.length ? filtered.map(u=>(
          <div key={u} className="card" style={{display:'flex', alignItems:'center', justifyContent:'space-between'}}>
            <div className="font-medium">@{u}</div>
            <Link className="btn" href={`/u/${u}`}>View profile</Link>
          </div>
        )) : <div className="text-neutral-400">No users found.</div>}
      </section>
    </main>
  )
}
