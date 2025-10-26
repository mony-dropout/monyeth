#!/usr/bin/env bash
set -euo pipefail

echo "▶ Creating folders…"
mkdir -p src/lib \
         src/app/profile \
         src/app/notes/[id] \
         src/app/discover \
         src/app/api/goals \
         src/app/api/goal \
         src/app/api/goal/complete \
         src/app/api/attest \
         src/app/api/all

echo "▶ Installing deps…"
npm i zod uuid >/dev/null

cat > .env.local.example << 'EOF'
NEXT_PUBLIC_USE_MOCKS=true
OPENAI_API_KEY=
RPC_URL_BASE_SEPOLIA=
PLATFORM_PRIVATE_KEY=
EAS_SCHEMA_UID=
EOF

# --- db singleton ---
cat > src/lib/db.ts << 'EOF'
import { v4 as uuid } from 'uuid'
export type GoalStatus = 'PENDING' | 'PASSED' | 'FAILED'
export interface Goal {
  id: string; user: string; title: string; scope?: string; deadlineISO?: string;
  status: GoalStatus; notes?: string; evidenceURI?: string; easUID?: string;
  score?: number; rationale?: string; createdAt: number
}
export interface DBShape { goals: Goal[] }
const g = globalThis as unknown as { __POD_DB?: DBShape }
if (!g.__POD_DB) g.__POD_DB = { goals: [] }
export const DB = g.__POD_DB
export function createGoal(d: Pick<Goal,'user'|'title'|'scope'|'deadlineISO'>){
  const goal: Goal = { id: uuid(), user: d.user, title: d.title, scope: d.scope, deadlineISO: d.deadlineISO, status: 'PENDING', createdAt: Date.now() }
  DB.goals.unshift(goal); return goal
}
export const getUserGoals = (u:string)=> DB.goals.filter(g=>g.user===u)
export const getGoal = (id:string)=> DB.goals.find(g=>g.id===id)
export function updateGoal(id:string, patch: Partial<Goal>){ const goal=getGoal(id); if(!goal) return null; Object.assign(goal, patch); return goal }
EOF

# --- layout tweaks (keep your existing if you already edited) ---
cat > src/app/globals.css << 'EOF'
@tailwind base;
@tailwind components;
@tailwind utilities;
:root { color-scheme: dark; }
body { @apply bg-neutral-950 text-neutral-100; }
.btn { @apply inline-flex items-center justify-center rounded-xl px-4 py-2 font-medium bg-neutral-800 hover:bg-neutral-700 transition; }
.card { @apply rounded-2xl border border-neutral-800 bg-neutral-900/60 p-4 shadow; }
.input { @apply w-full rounded-xl bg-neutral-950 border border-neutral-800 px-3 py-2 outline-none focus:border-neutral-600; }
.label { @apply text-sm text-neutral-400; }
.gridish { @apply grid gap-4; }
EOF

cat > src/app/layout.tsx << 'EOF'
import type { Metadata } from 'next'
import './globals.css'
import Link from 'next/link'
export const metadata: Metadata = { title: 'ProofOfDay', description: 'On-chain(ish) productivity receipts — demo' }
export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en"><body>
      <div className="max-w-4xl mx-auto px-4 py-6 gridish">
        <header className="flex items-center justify-between">
          <Link href="/" className="text-xl font-semibold">ProofOfDay</Link>
          <nav className="flex gap-3 text-sm text-neutral-400">
            <Link href="/discover" className="hover:text-neutral-200">Discover</Link>
            <Link href="/profile" className="hover:text-neutral-200">Profile</Link>
          </nav>
        </header>
        {children}
      </div>
    </body></html>
  )
}
EOF

# --- simple login page ---
cat > src/app/page.tsx << 'EOF'
'use client'
import { useRouter } from 'next/navigation'
import { useEffect, useState } from 'react'
export default function Page() {
  const [name, setName] = useState(''); const router = useRouter()
  useEffect(()=>{ const u = localStorage.getItem('pod_user'); if(u) router.replace('/profile') },[router])
  return (
    <main className="gridish">
      <div className="card gridish">
        <h1 className="text-2xl font-semibold">Welcome</h1>
        <p className="text-neutral-400">Demo login — just pick a username.</p>
        <label className="label">Username</label>
        <input className="input" value={name} onChange={e=>setName(e.target.value)} placeholder="mony" />
        <button className="btn" onClick={()=>{ if(!name) return; localStorage.setItem('pod_user', name); router.push('/profile')}}>Continue</button>
      </div>
      <div className="text-sm text-neutral-500">No wallets needed. Onchain proofs are mocked until you flip LIVE.</div>
    </main>
  )
}
EOF

# --- profile page ---
cat > src/app/profile/page.tsx << 'EOF'
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
EOF

# --- notes page ---
cat > src/app/notes/[id]/page.tsx << 'EOF'
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
EOF

# --- discover page ---
cat > src/app/discover/page.tsx << 'EOF'
async function getAll(){ const res = await fetch(`${process.env.NEXT_PUBLIC_BASE_URL ?? ''}/api/all`, { cache: 'no-store' }); return res.json() }
export default async function Discover(){
  const data = await getAll()
  return (
    <main className="gridish">
      <h2 className="text-xl font-semibold">Recent passes</h2>
      <div className="grid gap-3">
        {data.goals.filter((g:any)=>g.status==='PASSED').map((g:any)=>(
          <div key={g.id} className="card">
            <div className="font-medium">{g.title}</div>
            <div className="text-sm text-neutral-400">by {g.user}</div>
          </div>
        ))}
      </div>
    </main>
  )
}
EOF

# --- APIs ---
cat > src/app/api/goals/route.ts << 'EOF'
import { NextRequest, NextResponse } from 'next/server'
import { createGoal, getUserGoals } from '@/lib/db'
export async function GET(req: NextRequest){
  const user = req.nextUrl.searchParams.get('user')
  if(!user) return NextResponse.json({ error: 'missing user' }, { status: 400 })
  return NextResponse.json({ goals: getUserGoals(user) })
}
export async function POST(req: NextRequest){
  const { user, title, scope, deadlineISO } = await req.json()
  if(!user || !title) return NextResponse.json({ error: 'missing fields' }, { status: 400 })
  const goal = createGoal({ user, title, scope, deadlineISO })
  return NextResponse.json({ goal })
}
EOF

cat > src/app/api/goal/route.ts << 'EOF'
import { NextRequest, NextResponse } from 'next/server'
import { getGoal, updateGoal } from '@/lib/db'
export async function GET(req: NextRequest){
  const id = req.nextUrl.searchParams.get('id')
  if(!id) return NextResponse.json({ error: 'missing id' }, { status: 400 })
  return NextResponse.json({ goal: getGoal(id) })
}
export async function PATCH(req: NextRequest){
  const { id, notes } = await req.json()
  if(!id) return NextResponse.json({ error: 'missing id' }, { status: 400 })
  return NextResponse.json({ goal: updateGoal(id, { notes }) })
}
EOF

cat > src/app/api/goal/complete/route.ts << 'EOF'
import { NextRequest, NextResponse } from 'next/server'
import { getGoal, updateGoal } from '@/lib/db'
const USE_MOCKS = process.env.NEXT_PUBLIC_USE_MOCKS !== 'false'
export async function POST(req: NextRequest){
  const { goalId } = await req.json()
  const goal = getGoal(goalId)
  if(!goal) return NextResponse.json({ error: 'not found' }, { status: 404 })
  if (USE_MOCKS) {
    updateGoal(goalId, { status: 'PASSED', score: 95, rationale: 'Mock PASS' })
    return NextResponse.json({ pass: true, score: 95 })
  }
  return NextResponse.json({ pass: true, score: 99 })
}
EOF

cat > src/app/api/attest/route.ts << 'EOF'
import { NextRequest, NextResponse } from 'next/server'
import { getGoal, updateGoal } from '@/lib/db'
const USE_MOCKS = process.env.NEXT_PUBLIC_USE_MOCKS !== 'false'
export async function POST(req: NextRequest){
  const { goalId } = await req.json()
  const goal = getGoal(goalId)
  if(!goal) return NextResponse.json({ error: 'not found' }, { status: 404 })
  if (USE_MOCKS) {
    const uid = `MOCK-${goal.id}`
    updateGoal(goalId, { easUID: uid })
    return NextResponse.json({ uid, txHash: '0xMOCK' })
  }
  return NextResponse.json({ uid: 'TODO', txHash: '0xTODO' })
}
EOF

cat > src/app/api/all/route.ts << 'EOF'
import { NextResponse } from 'next/server'
import { DB } from '@/lib/db'
export async function GET(){ return NextResponse.json({ goals: DB.goals }) }
EOF

echo "▶ Done. Now: cp .env.local.example .env.local && npm run dev"
