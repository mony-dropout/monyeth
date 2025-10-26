#!/usr/bin/env bash
set -euo pipefail

echo "▶ Ensuring deps…"
npm i openai >/dev/null

echo "▶ Writing src/lib/judge.ts …"
mkdir -p src/lib
cat > src/lib/judge.ts <<'TS'
import OpenAI from "openai";

// Toggle mocks via NEXT_PUBLIC_USE_MOCKS
const USE_MOCKS = (process.env.NEXT_PUBLIC_USE_MOCKS ?? "true") !== "false";
const MODEL_Q = "gpt-4o-mini";
const MODEL_G = "gpt-4o-mini";

/** ===================== Prompts (from your files) ===================== **
 * Question generator prompt (expects objects: {type,text}) — we will map to strings for the UI.
 * Source: SYSTEM_PROMPT (user file)
 */
const SYSTEM_PROMPT_Q = `
You are "Proof-of-Day Quick-Check", a generator of two simple questions to verify whether someone likely completed a stated study/build goal.

You will receive one JSON input from the user:
{
  "goal": "<what they planned to do>",
  "scope": "<what to include/skip; constraints or exclusions>"
}

Your job:
- Produce EXACTLY TWO questions.
- Purpose: quickly check they actually covered/built the material—not to test mastery.
- Difficulty: easy/basic; each should be answerable in ~1–3 minutes.
- Style: concrete, unambiguous, self-contained. No page numbers, no “see Exercise 1.3”.
- Respect the \`scope\`: do NOT ask about excluded sections/features.
- Avoid esoterica, trick questions, long proofs, heavy notation, or lengthy code. Prefer plain ASCII; minimal math only if essential.
- If the goal/scope is vague, infer the central basics from the most standard interpretation and still produce two reasonable questions.

General format and coverage:
- Q1 = a core definition / key term / fundamental concept OR (for builds) a brief implementation-summary question.
- Q2 = a light "show/explain/apply" check OR (for builds) a tiny snippet/artefact request.
- Keep each question concise; the respondent should not need extra materials beyond what's in the goal.

Specialization for PROGRAMMING / BUILD tasks (e.g., “build an online chess app”):
- Q1 (implementation summary): Ask for a short description of stack and one core architectural choice tied to the scope (e.g., how state sync or persistence is handled). Keep it open enough that any reasonable implementation qualifies; do not force specific tech unless mentioned in goal/scope.
- Q2 (tiny artefact): Ask them to paste a small code/config snippet (≈5–15 lines) from *any* relevant part they built that matches the scope. Accept UI code, handler/endpoint, schema/migration, simple state update, or minimal test. Never require secrets, API keys, or full files. Never ask for excluded features.
- Examples of acceptable architectural hooks to ask about: how clients communicate (WebSocket, polling, HTTP), where game state lives (in-memory, DB), basic schema shape, or a minimal reducer/handler.

Output format: return ONLY this JSON (no preface, no extra keys, no commentary):
{
  "questions": [
    { "type": "recall", "text": "<question 1>" },
    { "type": "check",  "text": "<question 2>" }
  ]
}
`.trim();

/** Adjudicator prompt (single Q/A → returns PASS or FAIL token). 
 * We will call it twice (once per Q/A) and combine: PASS unless BOTH fail.
 * Source: EVAL_SYSTEM_PROMPT (user file)
 */
const EVAL_SYSTEM_PROMPT = `
You are "Proof-of-Day Adjudicator". Given a goal, scope, a single question, and the user's answer, decide if the answer plausibly indicates the user completed the goal. You must be LENIENT and default-to-PASS. Only FAIL if the answer is clearly bogus or fundamentally wrong.

You will receive JSON like:
{
  "goal": "<what they planned to do>",
  "scope": "<what to include/skip; constraints or exclusions>",
  "question": "<the quick-check question>",
  "answer": "<the user's reply>"
}

Your task:
- Return ONLY one token: PASS or FAIL (uppercase; no punctuation, no extra text).
- Assume good faith. If the answer makes basic sense relative to the question and the goal/scope, PASS.
- Borderline or partially-correct answers -> PASS.
- FAIL only for clear nonsense, fundamental errors on the core concept, obvious irrelevance, or non-answers.

Evaluation checklist (be quick, forgiving):
1) Relevance: Is the answer on-topic for the question and roughly aligned with the goal/scope?
2) Minimal correctness: Does it capture the basic idea/definition/mechanism, even informally?
3) Consistency with scope: If the question touches an excluded topic and the user reasonably acknowledges or redirects (e.g., “scope excludes minors”), PASS.
4) Brevity is fine: Short sketches or examples are acceptable.

Special handling — PROGRAMMING/BUILD answers:
- PASS if the answer provides a plausible brief stack/architecture summary (e.g., “Next.js + WebSocket; server keeps game state in-memory”) OR includes a small, relevant snippet (≈5–15 lines) tied to the scope. It does NOT need to compile or be perfect.
- Accept any reasonable stack; do not require specific technologies unless stated in goal/scope.
- Do NOT demand secrets, full files, or excluded features.
- FAIL only if the answer is obviously unrelated (e.g., a generic "hello world" when asked about move handling), pure buzzwords with no substance, or contradicts the scope in a way that shows non-completion.

Strong FAIL triggers (any one is enough):
- Empty, “idk”, or purely evasive response.
- Word salad/buzzword dump with no real content.
- Core concept plainly wrong (e.g., defining girth as “number of vertices”).
- Claims that contradict the scope in a way that reveals non-completion (e.g., bragging about implementing a chess engine when scope forbids it AND giving nothing relevant to the allowed parts).
- Code that is obviously unrelated to the asked area and no other supporting explanation.

Output requirement:
Return exactly one of: PASS or FAIL.
`.trim();

/** ===================== Helpers ===================== */
function safeTwo<T>(arr: any[], fallback: T[]): T[] {
  if (!Array.isArray(arr)) return fallback;
  return [arr[0], arr[1]].map((v, i) => (v === undefined ? fallback[i] : v)) as T[];
}

function toPlainQuestions(qs: any[]): string[] {
  // Accept either strings OR {type,text}; return a [q1,q2] string array.
  const [q1, q2] = safeTwo(qs, ["State one basic concept you learned.", "Give one tiny example related to your goal."]);
  const pickText = (q: any, i: number) =>
    typeof q === "string" ? q : (typeof q?.text === "string" && q.text.trim()) || (i === 0 ? "Q1" : "Q2");
  return [pickText(q1, 0), pickText(q2, 1)];
}

/** ===================== Public API ===================== */
export async function generateQuestionsLLM(
  title: string,
  scope?: string
): Promise<{ questions: string[]; transcript: string }> {
  if (USE_MOCKS || !process.env.OPENAI_API_KEY) {
    const questions = [
      `Name one core definition you covered for: ${title}.`,
      `Give a tiny example or outline related to: ${scope ?? title}.`,
    ];
    return { questions, transcript: "MOCK_QUESTIONS" };
  }

  const client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

  const userPayload = { goal: title, scope: scope ?? "(none)" };

  try {
    const resp = await client.chat.completions.create({
      model: MODEL_Q,
      response_format: { type: "json_object" },
      messages: [
        { role: "system", content: SYSTEM_PROMPT_Q },
        { role: "user", content: JSON.stringify(userPayload) },
      ],
    });

    const content = resp.choices[0]?.message?.content || "{}";
    let parsed: any = {};
    try { parsed = JSON.parse(content); } catch {}

    const questions = toPlainQuestions(parsed?.questions ?? []);
    const transcript = [
      "LLM GEN QUESTIONS",
      "--- system ---", SYSTEM_PROMPT_Q,
      "--- user ---", JSON.stringify(userPayload, null, 2),
      "--- model ---", content,
    ].join("\n");

    return { questions, transcript };
  } catch (err: any) {
    console.error("OpenAI error (questions):", err);
    // graceful fallback so the app never breaks
    return {
      questions: [
        `Name one core definition you covered for: ${title}.`,
        `Give a tiny example or outline related to: ${scope ?? title}.`,
      ],
      transcript: `FALLBACK_AFTER_ERROR: ${err?.message ?? String(err)}`,
    };
  }
}

async function gradeOneLLM(
  title: string,
  scope: string | undefined,
  question: string,
  answer: string
): Promise<{ pass: boolean; raw: string }> {
  if (USE_MOCKS || !process.env.OPENAI_API_KEY) {
    // Default-pass mock unless empty nonsense
    const pass = !!(answer && answer.trim().length > 2);
    return { pass, raw: pass ? "PASS" : "FAIL" };
  }

  const client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

  const payload = {
    goal: title,
    scope: scope ?? "(none)",
    question,
    answer,
  };

  const resp = await client.chat.completions.create({
    model: MODEL_G,
    // No response_format here because your prompt returns a bare token.
    messages: [
      { role: "system", content: EVAL_SYSTEM_PROMPT },
      { role: "user", content: JSON.stringify(payload, null, 2) },
    ],
  });

  const raw = (resp.choices[0]?.message?.content ?? "").trim();
  const token = raw.replace(/["\s]/g, "").toUpperCase();
  const pass = token === "PASS" ? true : token === "FAIL" ? false : true; // default lenient
  return { pass, raw };
}

/** Grade two answers (lenient): PASS unless BOTH fail */
export async function gradeAnswersLLM(
  title: string,
  scope: string | undefined,
  questions: Array<string>,
  answers: string[]
): Promise<{ pass: boolean; transcript: string }> {
  // Guard
  const [q1, q2] = safeTwo(questions, ["Q1", "Q2"]);
  const [a1, a2] = safeTwo(answers, ["", ""]);

  try {
    const r1 = await gradeOneLLM(title, scope, q1, a1);
    const r2 = await gradeOneLLM(title, scope, q2, a2);

    // Lenient aggregation: pass if at least one passes
    const overall = (r1.pass || r2.pass);

    const transcript = [
      "LLM GRADE",
      "--- Q1 ---",
      `Q: ${q1}`,
      `A: ${a1}`,
      `Result: ${r1.raw}`,
      "",
      "--- Q2 ---",
      `Q: ${q2}`,
      `A: ${a2}`,
      `Result: ${r2.raw}`,
      "",
      `OVERALL: ${overall ? "PASS" : "FAIL"} (lenient: pass if any answer passes)`,
    ].join("\n");

    return { pass: overall, transcript };
  } catch (err: any) {
    console.error("OpenAI error (grade):", err);
    // Default to PASS on error to keep demo flowing
    return { pass: true, transcript: `FALLBACK_PASS_AFTER_ERROR: ${err?.message ?? String(err)}` };
  }
}
TS

echo "▶ Hardening /api/goal/questions route…"
cat > src/app/api/goal/questions/route.ts <<'TS'
import { NextRequest, NextResponse } from 'next/server'
import { getGoal, updateGoal } from '@/lib/db'
import { generateQuestionsLLM } from '@/lib/judge'

export async function POST(req: NextRequest){
  try {
    const { goalId } = await req.json()
    const goal = getGoal(goalId)
    if(!goal) return NextResponse.json({ error: 'not found' }, { status: 404 })

    const { questions, transcript } = await generateQuestionsLLM(goal.title, goal.scope)
    updateGoal(goalId, { questions })
    return NextResponse.json({ questions, transcript })
  } catch (err: any) {
    console.error("questions route error:", err)
    return NextResponse.json({ error: "LLM question generation failed", details: err?.message ?? String(err) }, { status: 500 })
  }
}
TS

echo "▶ Hardening /api/goal/grade route…"
cat > src/app/api/goal/grade/route.ts <<'TS'
import { NextRequest, NextResponse } from 'next/server'
import { getGoal, updateGoal } from '@/lib/db'
import { gradeAnswersLLM } from '@/lib/judge'

export async function POST(req: NextRequest){
  try {
    const { goalId, answers } = await req.json()
    const goal = getGoal(goalId)
    if(!goal) return NextResponse.json({ error: 'not found' }, { status: 404 })
    if(!Array.isArray(answers) || answers.length !== 2){
      return NextResponse.json({ error: 'need two answers' }, { status: 400 })
    }

    const qs = (goal.questions ?? ["Q1","Q2"]).map((q:any,i:number)=> typeof q === 'string' ? q : (q?.text ?? (i===0?'Q1':'Q2')))
    const { pass, transcript } = await gradeAnswersLLM(goal.title, goal.scope, qs, answers)

    const qaNotes = [
      `Q1: ${qs[0]}`,
      `A1: ${answers[0]}`,
      '',
      `Q2: ${qs[1]}`,
      `A2: ${answers[1]}`
    ].join('\n')

    const appended = [goal.notes ?? '', '', '==== PROOF-OF-DAY Q&A ====', qaNotes, '', '==== LLM TRANSCRIPT ====', transcript].join('\n')

    updateGoal(goalId, { status: pass ? 'PASSED' : 'FAILED', notes: appended, answers })
    return NextResponse.json({ pass })
  } catch (err:any) {
    console.error("grade route error:", err)
    // extremely lenient fallback
    return NextResponse.json({ pass: true, error: 'grader failed; default pass' }, { status: 200 })
  }
}
TS

echo "▶ Making Profile fetch resilient…"
cat > src/app/profile/page.tsx <<'TSX'
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
TSX

echo "▶ Done."
echo "Now restart: npm run dev"
