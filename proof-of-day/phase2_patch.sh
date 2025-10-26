#!/usr/bin/env bash
# Phase 2 patch: LLM Q&A judging + notes (EAS still stubbed)
# Usage: save as phase2_patch.sh in your Next.js project root, then run: bash phase2_patch.sh

set -euo pipefail

printf "\n▶ Installing OpenAI SDK...\n"
npm i openai >/dev/null

printf "\n▶ Ensuring folders exist...\n"
mkdir -p src/lib \
         src/app/api/goal/questions \
         src/app/api/goal/grade

printf "\n▶ Updating env example...\n"
if [ ! -f .env.local ]; then
  cat > .env.local << 'ENVEOF'
NEXT_PUBLIC_USE_MOCKS=true
OPENAI_API_KEY=
RPC_URL_BASE_SEPOLIA=
PLATFORM_PRIVATE_KEY=
EAS_SCHEMA_UID=
ENVEOF
fi

printf "\n▶ Writing src/lib/judge.ts (two-call LLM workflow)\n"
cat > src/lib/judge.ts << 'EOF'
import OpenAI from "openai";

const USE_MOCKS = (process.env.NEXT_PUBLIC_USE_MOCKS ?? 'true') !== 'false';
const MODEL = "gpt-4o-mini"; // tweak later if you want

export async function generateQuestionsLLM(title: string, scope?: string): Promise<{ questions: string[]; transcript: string }>{
  if (USE_MOCKS || !process.env.OPENAI_API_KEY) {
    const q1 = `Explain two key definitions you learned for: ${title}.`;
    const q2 = `Give one concrete example (or mini proof outline) related to: ${scope ?? title}.`;
    return { questions: [q1, q2], transcript: `MOCK_QUESTIONS\nQ1: ${q1}\nQ2: ${q2}` };
  }
  const client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
  const system = `You write exactly TWO short verification questions for a goal. Be specific to the goal/scope. Return ONLY JSON: {"questions":["q1","q2"]}.`;
  const user = `GOAL_TITLE: ${title}\nGOAL_SCOPE: ${scope ?? '(none)'}\nWrite two questions.`;

  const resp = await client.chat.completions.create({
    model: MODEL,
    response_format: { type: "json_object" },
    messages: [
      { role: 'system', content: system },
      { role: 'user', content: user }
    ]
  });
  const content = resp.choices[0]?.message?.content || '{}';
  let parsed: any = {};
  try { parsed = JSON.parse(content); } catch {}
  const qs: string[] = Array.isArray(parsed.questions) ? parsed.questions.slice(0,2).map(String) : [];
  const questions = qs.length === 2 ? qs : [
    `State a core concept related to: ${title}.`,
    `Provide a worked example from: ${scope ?? title}.`
  ];
  const transcript = [
    'LLM GEN QUESTIONS',
    '--- system ---', system,
    '--- user ---', user,
    '--- model ---', content
  ].join('\n');
  return { questions, transcript };
}

export async function gradeAnswersLLM(
  title: string,
  scope: string | undefined,
  questions: string[],
  answers: string[]
): Promise<{ pass: boolean; transcript: string }>{
  if (USE_MOCKS || !process.env.OPENAI_API_KEY) {
    return { pass: true, transcript: `MOCK_GRADE\nQ1: ${questions[0]}\nA1: ${answers[0]}\nQ2: ${questions[1]}\nA2: ${answers[1]}` };
  }
  const client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
  const system = `You decide PASS/FAIL from two Q&A pairs. Default to PASS unless answers are empty, off-topic, or nonsense. Return ONLY JSON: {"pass": true|false}.`;
  const user = JSON.stringify({ title, scope, qa: [ { q: questions[0], a: answers[0] }, { q: questions[1], a: answers[1] } ] }, null, 2);
  const resp = await client.chat.completions.create({
    model: MODEL,
    response_format: { type: 'json_object' },
    messages: [
      { role: 'system', content: system },
      { role: 'user', content: user }
    ]
  });
  const content = resp.choices[0]?.message?.content || '{}';
  let parsed: any = {};
  try { parsed = JSON.parse(content); } catch {}
  const pass = !!parsed.pass;
  const transcript = [
    'LLM GRADE',
    '--- system ---', system,
    '--- input ---', user,
    '--- model ---', content
  ].join('\n');
  return { pass, transcript };
}
EOF

printf "\n▶ Patching src/lib/db.ts (store questions/answers)\n"
cat > src/lib/db.ts << 'EOF'
import { v4 as uuid } from 'uuid'

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
  questions?: string[]
  answers?: string[]
  createdAt: number
}

export interface DBShape { goals: Goal[] }
const g = globalThis as unknown as { __POD_DB?: DBShape }
if (!g.__POD_DB) g.__POD_DB = { goals: [] }
export const DB = g.__POD_DB

export function createGoal(data: Pick<Goal, 'user'|'title'|'scope'|'deadlineISO'>) {
  const goal: Goal = {
    id: uuid(),
    user: data.user,
    title: data.title,
    scope: data.scope,
    deadlineISO: data.deadlineISO,
    status: 'PENDING',
    createdAt: Date.now()
  }
  DB.goals.unshift(goal)
  return goal
}

export function getUserGoals(user: string) { return DB.goals.filter(g => g.user === user) }
export function getGoal(id: string) { return DB.goals.find(g => g.id === id) }
export function updateGoal(id: string, patch: Partial<Goal>) {
  const goal = getGoal(id)
  if (!goal) return null
  Object.assign(goal, patch)
  return goal
}
EOF

printf "\n▶ Adding API: /api/goal/questions (generate two questions)\n"
cat > src/app/api/goal/questions/route.ts << 'EOF'
import { NextRequest, NextResponse } from 'next/server'
import { getGoal, updateGoal } from '@/lib/db'
import { generateQuestionsLLM } from '@/lib/judge'

export async function POST(req: NextRequest){
  const { goalId } = await req.json()
  const goal = getGoal(goalId)
  if(!goal) return NextResponse.json({ error: 'not found' }, { status: 404 })
  const { questions, transcript } = await generateQuestionsLLM(goal.title, goal.scope)
  updateGoal(goalId, { questions })
  return NextResponse.json({ questions, transcript })
}
EOF

printf "\n▶ Adding API: /api/goal/grade (evaluate answers)\n"
cat > src/app/api/goal/grade/route.ts << 'EOF'
import { NextRequest, NextResponse } from 'next/server'
import { getGoal, updateGoal } from '@/lib/db'
import { gradeAnswersLLM } from '@/lib/judge'

export async function POST(req: NextRequest){
  const { goalId, answers } = await req.json()
  const goal = getGoal(goalId)
  if(!goal) return NextResponse.json({ error: 'not found' }, { status: 404 })
  if(!Array.isArray(answers) || answers.length !== 2){
    return NextResponse.json({ error: 'need two answers' }, { status: 400 })
  }
  const qs = goal.questions || ["Q1 missing","Q2 missing"]
  const { pass, transcript } = await gradeAnswersLLM(goal.title, goal.scope, qs, answers)

  const qaNotes = [
    `Q1: ${qs[0]}`,
    `A1: ${answers[0]}`,
    '',
    `Q2: ${qs[1]}`,
    `A2: ${answers[1]}`,
  ].join('\n')

  const appended = [goal.notes ?? '', '', '==== PROOF-OF-DAY Q&A ====', qaNotes, '', '==== LLM TRANSCRIPT ====', transcript].join('\n')

  updateGoal(goalId, { status: pass ? 'PASSED' : 'FAILED', notes: appended, answers })
  return NextResponse.json({ pass })
}
EOF

printf "\n▶ Updating profile UI to run two-step flow (generate → answer → grade)\n"
cat > src/app/profile/page.tsx << 'EOF'
'use client'
import { useEffect, useState } from 'react'
import Link from 'next/link'

type Status = 'PENDING'|'PASSED'|'FAILED'
interface Goal { id:string; user:string; title:string; scope?:string; deadlineISO?:string; status:Status; score?:number; rationale?:string; easUID?:string; evidenceURI?:string; createdAt:number; questions?:string[] }

export default function ProfilePage(){
  const [user,setUser]=useState(''); const [goals,setGoals]=useState<Goal[]>([])
  const [title,setTitle]=useState('Read Diestel §2.1–2.3'); const [scope,setScope]=useState('Summarize key defs; solve 3 exercises'); const [deadlineISO,setDeadlineISO]=useState('')

  // answer modal state
  const [activeId,setActiveId]=useState<string|null>(null)
  const [q1,setQ1]=useState(''); const [q2,setQ2]=useState('')
  const [a1,setA1]=useState(''); const [a2,setA2]=useState('')
  const [loading,setLoading]=useState(false)

  useEffect(()=>{ const u=localStorage.getItem('pod_user'); if(!u) return; setUser(u); refresh(u) },[])
  const refresh = async(u=user)=>{ if(!u) return; const r=await fetch(`/api/goals?user=${encodeURIComponent(u)}`); const d=await r.json(); setGoals(d.goals) }

  const createGoal = async()=>{ if(!user) return; await fetch('/api/goals',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({user,title,scope,deadlineISO})}); refresh() }

  const startComplete = async(id:string)=>{
    setLoading(true)
    const r = await fetch('/api/goal/questions', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ goalId:id }) })
    const d = await r.json(); setLoading(false)
    if(d.questions && d.questions.length===2){ setQ1(d.questions[0]); setQ2(d.questions[1]); setA1(''); setA2(''); setActiveId(id) }
  }

  const submitAnswers = async()=>{
    if(!activeId) return
    setLoading(true)
    const r = await fetch('/api/goal/grade', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ goalId: activeId, answers: [a1,a2] }) })
    const d = await r.json(); setLoading(false)
    setActiveId(null)
    // If pass, optionally ask chain to attest (still stubbed)
    if(d.pass){ await fetch('/api/attest', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ goalId: activeId }) }) }
    await refresh()
  }

  if(!user) return <main className="card">Please <Link href="/" className="underline">login</Link>.</main>

  return (
    <main className="gridish">
      <div className="card gridish">
        <h2 className="text-xl font-semibold">Hello, {user}</h2>
        <div className="grid" style={{gap: '1rem'}}>
          <div>
            <label className="label">Goal title</label>
            <input className="input" value={title} onChange={e=>setTitle(e.target.value)} />
          </div>
          <div>
            <label className="label">Scope / notes</label>
            <input className="input" value={scope} onChange={e=>setScope(e.target.value)} />
          </div>
          <div>
            <label className="label">Deadline (ISO, optional)</label>
            <input className="input" placeholder="2025-10-26T23:00:00+05:30" value={deadlineISO} onChange={e=>setDeadlineISO(e.target.value)} />
          </div>
          <button className="btn" onClick={createGoal}>Create goal</button>
        </div>
      </div>

      {/* Answer panel */}
      {activeId && (
        <div className="card" style={{position:'sticky', top: 8}}>
          <div className="text-sm text-neutral-400 mb-2">Answer these two quick questions (then we grade). Be concise.</div>
          <div className="gridish">
            <div>
              <div className="font-medium mb-1">Q1</div>
              <div className="mb-2 text-neutral-300">{q1}</div>
              <textarea className="input" style={{height: '120px'}} value={a1} onChange={e=>setA1(e.target.value)} />
            </div>
            <div>
              <div className="font-medium mb-1">Q2</div>
              <div className="mb-2 text-neutral-300">{q2}</div>
              <textarea className="input" style={{height: '120px'}} value={a2} onChange={e=>setA2(e.target.value)} />
            </div>
            <div className="flex gap-2">
              <button className="btn" onClick={submitAnswers} disabled={loading || !a1 || !a2}>{loading? 'Scoring…' : 'Submit answers'}</button>
              <button className="btn" onClick={()=>setActiveId(null)}>Cancel</button>
            </div>
          </div>
        </div>
      )}

      <section className="gridish">
        <h3 className="text-lg font-semibold">Your goals</h3>
        <div className="grid gap-3">
          {goals.map(g=> (
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
EOF

printf "\n✅ Phase 2 patch applied.\n- Start dev: npm run dev\n- Flow: Create goal → Complete (generates Qs) → answer 2 Qs → judge → profile updates.\n- Notes page will now contain the Q&A + LLM transcripts.\n\nWhen ready, we’ll wire /api/attest to real EAS on Base Sepolia.\n"
