#!/usr/bin/env bash
set -euo pipefail

echo "▶ Make store username lookups robust + fix ID generation…"
cat > src/lib/store.ts <<'TS'
import { Redis } from "@upstash/redis"

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

/** Accept either Upstash or KV env var names */
const url =
  process.env.UPSTASH_REDIS_REST_URL || process.env.KV_REST_API_URL
const token =
  process.env.UPSTASH_REDIS_REST_TOKEN || process.env.KV_REST_API_TOKEN
if (!url || !token) throw new Error("Missing Redis REST credentials")

const redis = new Redis({ url, token })

/** Helpers */
const normalize = (u: string) => (u || "").trim()

const kGoal = (id:string)=> `goal:${id}`
const kUserGoals = (u:string)=> `user_goals:${u}`
const kFeed = `feed`
const kUsers = `users:set`

/** Safer id gen (works in Node/Edge) */
function newId(){
  const c:any = globalThis.crypto as any
  if (c && typeof c.randomUUID === 'function') return c.randomUUID()
  // fallback
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`
}

/** Users */
export async function addKnownUser(u: string){ if(u) await redis.sadd(kUsers, u) }
export async function listKnownUsers(): Promise<string[]> { return (await redis.smembers<string>(kUsers)) ?? [] }

/** Goals */
export async function createGoalKV(data: Pick<Goal,'user'|'title'|'scope'|'deadlineISO'>){
  const userRaw = normalize(data.user)
  const g: Goal = {
    id: newId(),
    user: userRaw,
    title: data.title,
    scope: data.scope,
    deadlineISO: data.deadlineISO,
    status: 'PENDING',
    createdAt: Date.now(),
  }
  await redis.set(kGoal(g.id), g)
  await redis.lpush(kUserGoals(userRaw), g.id)
  await addKnownUser(userRaw)
  return g
}

export async function getGoalKV(id:string): Promise<Goal|null>{
  const g = await redis.get<Goal>(kGoal(id))
  return g ?? null
}

export async function updateGoalKV(id:string, patch: Partial<Goal>): Promise<Goal|null>{
  const cur = await getGoalKV(id)
  if(!cur) return null
  const upd = { ...cur, ...patch }
  await redis.set(kGoal(id), upd)
  return upd
}

export async function getUserGoalsKV(username: string): Promise<Goal[]>{
  const norm = normalize(username)
  // try normalized first
  let ids = await redis.lrange<string>(kUserGoals(norm), 0, -1)
  // fallback to raw key if different and empty
  if ((!ids || ids.length===0) && norm !== username) {
    const raw = normalize(username) // already trimmed
    ids = await redis.lrange<string>(kUserGoals(raw), 0, -1)
  }
  if (!ids?.length) return []
  const pipeline = redis.pipeline()
  ids.forEach(id => pipeline.get<Goal>(kGoal(id)))
  const res = await pipeline.exec<Goal[]>()
  const goals = (res ?? []).filter(Boolean) as Goal[]
  return goals.sort((a,b)=> b.createdAt - a.createdAt)
}

/** Feed of attested goals */
export async function pushFeedKV(goalId: string){
  await redis.lpush(kFeed, goalId)
  await redis.ltrim(kFeed, 0, 499)
}
export async function getFeedKV(limit=200): Promise<Goal[]>{
  const ids = await redis.lrange<string>(kFeed, 0, Math.max(0, limit-1))
  if (!ids?.length) return []
  const pipeline = redis.pipeline()
  ids.forEach(id => pipeline.get<Goal>(kGoal(id)))
  const res = await pipeline.exec<Goal[]>()
  const goals = (res ?? []).filter(Boolean) as Goal[]
  return goals.sort((a,b)=> b.createdAt - a.createdAt)
}
TS

echo "▶ API for fetching a single goal (with notes)…"
mkdir -p src/app/api/goal/[id]
cat > src/app/api/goal/[id]/route.ts <<'TS'
import { NextRequest, NextResponse } from "next/server";
import { getGoalKV } from "@/lib/store";

export async function GET(req: NextRequest, { params }: { params: { id: string } }){
  const g = await getGoalKV(params.id)
  if(!g) return NextResponse.json({ error: 'not found' }, { status: 404 })
  return NextResponse.json({ goal: g })
}
TS

echo "▶ Notes page now fetches via API (avoids env/runtime mismatches)…"
cat > src/app/notes/[id]/page.tsx <<'TSX'
import { notFound } from "next/navigation"

async function fetchGoal(id: string){
  const r = await fetch(`${process.env.NEXT_PUBLIC_SITE_URL ?? ''}/api/goal/${id}`, { cache: 'no-store' }).catch(()=>null)
  if(!r || !r.ok) return null
  const d = await r.json()
  return d.goal as any
}

export default async function NotesPage({ params }: { params: { id: string } }){
  const g = await fetchGoal(params.id)
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

echo "▶ Public profile page now fetches via API (uses same data path as /social)…"
cat > src/app/u/[username]/page.tsx <<'TSX'
import Link from "next/link"

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

echo "✅ Patched: Notes now via API, public profile via API, store lookups robust."

