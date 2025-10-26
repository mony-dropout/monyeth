#!/usr/bin/env bash
set -euo pipefail

echo "▶ Ensure grading writes a full transcript into goal.notes and return it…"
cat > src/app/api/goal/grade/route.ts <<'TS'
import { NextRequest, NextResponse } from "next/server";
import { getGoalKV, updateGoalKV } from "@/lib/store";
import { gradeAnswers } from "@/lib/judge";

export async function POST(req: NextRequest){
  try {
    const { goalId, answers } = await req.json();
    const goal = await getGoalKV(goalId);
    if(!goal) return NextResponse.json({ error: 'not found' }, { status: 404 });

    const q = goal.questions || [];
    const a = Array.isArray(answers) ? answers : [];

    const g1 = await gradeAnswers({ goal: goal.title, scope: goal.scope || "", question: q[0] ?? "", answer: a[0] ?? "" });
    const g2 = await gradeAnswers({ goal: goal.title, scope: goal.scope || "", question: q[1] ?? "", answer: a[1] ?? "" });
    const pass = (g1 === 'PASS') && (g2 === 'PASS');

    // Build a clear transcript we can show inline
    const transcript = [
      "==== LLM TRANSCRIPT ====",
      `Goal: ${goal.title}`,
      goal.scope ? `Scope: ${goal.scope}` : null,
      "",
      `Q1: ${q[0] ?? ''}`,
      `A1: ${a[0] ?? ''}`,
      `Judge1: ${g1}`,
      "",
      `Q2: ${q[1] ?? ''}`,
      `A2: ${a[1] ?? ''}`,
      `Judge2: ${g2}`,
      "",
      `RESULT: ${pass ? 'PASS' : 'FAIL'}`
    ].filter(Boolean).join('\n');

    const updated = await updateGoalKV(goalId, {
      status: pass ? 'PASSED' : 'FAILED',
      answers: a,
      notes: transcript
    });

    return NextResponse.json({ pass, transcript: updated?.notes ?? transcript });
  } catch(e:any){
    return NextResponse.json({ error: e?.message || 'error' }, { status: 500 })
  }
}
TS

echo "▶ API: include notes in public profile payload…"
cat > src/app/api/user/[username]/goals/route.ts <<'TS'
import { NextRequest, NextResponse } from 'next/server'
import { getUserGoalsKV } from '@/lib/store'

export async function GET(req: NextRequest, { params }: { params: { username: string } }) {
  const username = params.username
  const goals = await getUserGoalsKV(username)
  const pub = goals.map(g => ({
    id: g.id,
    title: g.title,
    scope: g.scope,
    status: g.status,
    easUID: g.easUID,
    disputed: g.disputed,
    createdAt: g.createdAt,
    notes: g.notes ?? null,
  }))
  return NextResponse.json({ username, goals: pub })
}
TS

echo "▶ API: include notes in social feed items so Notes can render instantly…"
cat > src/app/api/feed/route.ts <<'TS'
import { NextResponse } from 'next/server'
import { getFeedKV } from '@/lib/store'

export async function GET() {
  const items = await getFeedKV(200);
  const out = items.map(g => ({
    id: g.id,
    username: g.user,
    title: g.title,
    scope: g.scope,
    status: g.status,
    disputed: g.disputed,
    easUID: g.easUID,
    createdAt: g.createdAt,
    notes: g.notes ?? null,
  }));
  return NextResponse.json({ items: out })
}
TS

echo "▶ NotesInline: if initialNotes is provided, show immediately (no fetch); otherwise fetch once…"
cat > src/components/NotesInline.tsx <<'TSX'
'use client'
import { useState } from 'react'

export default function NotesInline({
  goalId,
  initialNotes
}: {
  goalId: string
  initialNotes?: string | null
}) {
  const [open, setOpen] = useState(false)
  const [loading, setLoading] = useState(false)
  const [notes, setNotes] = useState<string | null>(initialNotes ?? null)
  const [err, setErr] = useState<string | null>(null)

  const toggle = async () => {
    const willOpen = !open
    setOpen(willOpen)
    if (willOpen && notes == null) {
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

echo "▶ Use initialNotes everywhere so Notes opens with data immediately…"
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

              <NotesInline goalId={it.id} initialNotes={it.notes} />

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

cat > src/app/u/[username]/page.tsx <<'TSX'
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
              <NotesInline goalId={g.id} initialNotes={g.notes} />
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

echo "▶ Harden /api/goal/[id] to try feed as a fallback if direct key missing…"
mkdir -p src/app/api/goal/[id]
cat > src/app/api/goal/[id]/route.ts <<'TS'
import { NextRequest, NextResponse } from "next/server";
import { getGoalKV } from "@/lib/store";
import { getFeedKV } from "@/lib/store";

export async function GET(req: NextRequest, { params }: { params: { id: string } }){
  const direct = await getGoalKV(params.id)
  if (direct) return NextResponse.json({ goal: direct })

  // Fallback: try to find it in the recent feed (helps if key was saved but list is authoritative)
  try {
    const feed = await getFeedKV(400)
    const hit = feed.find(g => g.id === params.id)
    if (hit) return NextResponse.json({ goal: hit })
  } catch {}

  return NextResponse.json({ error: 'not found' }, { status: 404 })
}
TS

echo "✅ Notes now saved on grade, returned from APIs, shown inline instantly, with a fallback fetch."
