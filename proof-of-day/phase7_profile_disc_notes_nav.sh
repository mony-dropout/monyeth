#!/usr/bin/env bash
set -euo pipefail

mkdir -p src/app/notes/[id] src/app/u/[username] src/app/discover src/app/api/users src/components

echo "▶ Add Notes page (/notes/[id])…"
cat > src/app/notes/[id]/page.tsx <<'TSX'
import { notFound } from "next/navigation"
import { getGoalKV } from "@/lib/store"

export const dynamic = 'force-dynamic'

export default async function NotesPage({ params }: { params: { id: string } }){
  const g = await getGoalKV(params.id)
  if(!g) notFound()

  return (
    <main className="gridish">
      <div className="card">
        <h1 className="text-2xl font-semibold mb-1">Notes</h1>
        <div className="text-sm text-neutral-400">Goal transcript & details</div>
      </div>

      <div className="card">
        <div className="mb-2">
          <div className="text-sm text-neutral-400">User</div>
          <div className="font-medium">@{g.user}</div>
        </div>
        <div className="mb-2">
          <div className="text-sm text-neutral-400">Title</div>
          <div className="font-medium">{g.title}</div>
        </div>
        {g.scope ? (
          <div className="mb-2">
            <div className="text-sm text-neutral-400">Scope</div>
            <div>{g.scope}</div>
          </div>
        ) : null}
        <div className="mb-2">
          <div className="text-sm text-neutral-400">Status</div>
          <div className="font-medium">{g.status}{g.disputed ? ' · disputed' : ''}</div>
        </div>
        {g.easUID ? (
          <div className="mb-4">
            <a className="btn" target="_blank" href={`https://base-sepolia.easscan.org/attestation/view/${g.easUID}`}>Blockchain proof</a>
          </div>
        ) : null}

        <div className="mb-1 text-sm text-neutral-400">Transcript</div>
        <pre className="whitespace-pre-wrap text-neutral-200 bg-neutral-900 p-3 rounded-xl border border-neutral-800">
{g.notes || 'No notes yet.'}
        </pre>
      </div>
    </main>
  )
}
TSX

echo "▶ Public profile page (/u/[username])…"
cat > src/app/u/[username]/page.tsx <<'TSX'
import Link from "next/link"
import { getUserGoalsKV } from "@/lib/store"

export const dynamic = 'force-dynamic'

export default async function PublicProfile({ params }: { params: { username: string } }){
  const username = params.username
  const goals = await getUserGoalsKV(username)

  return (
    <main className="gridish">
      <div className="card">
        <h1 className="text-2xl font-semibold">@{username}</h1>
        <div className="text-sm text-neutral-400">Public history</div>
      </div>

      <section className="grid gap-3">
        {goals.length ? goals.map(g=>(
          <div key={g.id} className="card" style={{display:'grid', gridTemplateColumns:'1fr auto', gap:'0.75rem', alignItems:'center'}}>
            <div>
              <div className="font-medium">{g.title}</div>
              {g.scope ? <div className="text-sm text-neutral-400">{g.scope}</div> : null}
              <div className="text-xs text-neutral-500 mt-1">{new Date(g.createdAt).toLocaleString()}</div>
            </div>
            <div className="flex items-center gap-2">
              <span className="text-sm" style={{padding:'4px 8px', borderRadius:8, background:g.status==='PASSED'?'#064e3b': g.status==='FAILED'?'#7f1d1d':'#27272a', color:g.status==='PENDING'?'#e5e7eb':'#d1fae5'}}>{g.status}{g.disputed?'·disputed':''}</span>
              <Link className="btn" href={`/notes/${g.id}`}>Notes</Link>
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

echo "▶ Discovery API (/api/users) & page (/discover)…"
cat > src/app/api/users/route.ts <<'TS'
import { NextResponse } from "next/server";
import { listKnownUsers } from "@/lib/store";

export async function GET(){
  const users = await listKnownUsers();
  // newest-ish first by alpha invert just to vary a bit; for real we’d track createdAt
  const sorted = [...users].sort((a,b)=> a.localeCompare(b));
  return NextResponse.json({ users: sorted });
}
TS

cat > src/app/discover/page.tsx <<'TSX'
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
TSX

echo "▶ Shared Nav with Sign in / Sign out across pages…"
cat > src/components/Nav.tsx <<'TSX'
'use client'
import Link from "next/link"
import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"

export default function Nav(){
  const r = useRouter()
  const [me,setMe] = useState<string|null>(null)

  const refreshMe = async ()=>{
    try {
      const d = await fetch('/api/auth/me', { cache:'no-store' }).then(r=>r.json())
      setMe(d?.username || null)
    } catch { setMe(null) }
  }

  useEffect(()=>{ refreshMe() },[])

  const signOut = async ()=>{
    await fetch('/api/auth/logout', { method:'POST' })
    localStorage.removeItem('pod_user')
    setMe(null)
    r.push('/login')
  }

  return (
    <header className="w-full border-b border-neutral-800 bg-neutral-950/60 sticky top-0 z-40">
      <div className="mx-auto max-w-4xl px-4 py-2 flex items-center gap-3">
        <Link href="/" className="font-semibold">Proof-of-Day</Link>
        <nav className="flex items-center gap-3 text-sm">
          <Link className="underline" href="/social">Social</Link>
          <Link className="underline" href="/discover">Discover</Link>
          {me ? (
            <>
              <Link className="underline" href="/profile">Profile</Link>
              <Link className="underline" href={`/u/${me}`}>Public</Link>
              <button className="btn" onClick={signOut}>Sign out</button>
            </>
          ) : (
            <Link className="btn" href="/login">Sign in</Link>
          )}
        </nav>
      </div>
    </header>
  )
}
TSX

echo "▶ Wrap layout with Nav…"
cat > src/app/layout.tsx <<'TSX'
import type { Metadata } from "next"
import "./globals.css"
import Nav from "@/components/Nav"

export const metadata: Metadata = {
  title: "Proof-of-Day",
  description: "Quick-check productivity with on-chain attestations",
}

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <Nav />
        <div className="mx-auto max-w-4xl px-4 py-6">{children}</div>
      </body>
    </html>
  )
}
TSX

echo "✅ Notes, public profiles, discovery, and nav (sign in/out) installed."
