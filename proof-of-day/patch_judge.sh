#!/usr/bin/env bash
set -euo pipefail
mkdir -p src/lib

cat > src/lib/judge.ts <<'TS'
/**
 * LLM judge helpers (server only).
 * Exports:
 *  - generateQuestions({ goal, scope }) -> { questions: [string, string] }
 *  - gradeAnswers({ goal, scope, question, answer }) -> 'PASS' | 'FAIL'
 *
 * Uses OpenAI if OPENAI_API_KEY is set; otherwise returns safe fallbacks.
 * If the API errors, we still return a sensible result (no hard crash).
 */

const OPENAI_API_KEY = process.env.OPENAI_API_KEY || "";
const USE_MOCKS = String(process.env.NEXT_PUBLIC_USE_MOCKS || "").toLowerCase() === "true";
const MODEL = process.env.OPENAI_MODEL || "gpt-4o-mini";

/** Low-level chat call via fetch (no SDK dependency) */
async function chat(system: string, user: string): Promise<string> {
  if (!OPENAI_API_KEY) {
    throw new Error("NO_OPENAI_KEY");
  }
  const r = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${OPENAI_API_KEY}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model: MODEL,
      messages: [
        { role: "system", content: system },
        { role: "user", content: user }
      ],
      temperature: 0.2
    })
  });
  if (!r.ok) {
    const txt = await r.text().catch(()=> "");
    throw new Error(`OPENAI_${r.status}:${txt}`);
  }
  const j = await r.json();
  const content = j?.choices?.[0]?.message?.content;
  if (typeof content !== "string") throw new Error("OPENAI_NO_CONTENT");
  return content.trim();
}

/** ---------- Question generation ---------- */

const GEN_SYSTEM = `
You write exactly TWO short verification questions for a goal. Be specific to the goal/scope.
Return ONLY JSON: {"questions":["q1","q2"]}.
- Q1: core definition/basic concept (or short implementation summary if it's a build task)
- Q2: small apply/explain or tiny code snippet request (~5–15 lines for build tasks)
- Respect the scope (include/skip). No trick questions. Keep answerable in ~1–3 minutes.
`;

export async function generateQuestions(input: { goal: string; scope?: string }) {
  const goal = (input?.goal ?? "").trim();
  const scope = (input?.scope ?? "").trim();

  if (USE_MOCKS || !OPENAI_API_KEY) {
    // Fallback that is deterministic and safe
    return {
      questions: [
        `Name one definition central to: "${goal}". (consider scope: ${scope || "none"})`,
        `Give a short explanation/example related to "${goal}".`
      ]
    };
  }

  try {
    const user = JSON.stringify({ goal, scope });
    const raw = await chat(GEN_SYSTEM, user);

    // Try to parse either ["q1","q2"] or {questions:[...]} or typed objects
    let q1 = "", q2 = "";
    try {
      const parsed = JSON.parse(raw);
      let arr: any[] = Array.isArray(parsed) ? parsed : parsed?.questions;
      if (!Array.isArray(arr)) throw new Error("no questions array");
      const first = arr[0];
      const second = arr[1];
      q1 = typeof first === "string" ? first : (first?.text ?? "");
      q2 = typeof second === "string" ? second : (second?.text ?? "");
    } catch {
      // If the model didn't follow JSON perfectly, do a loose extraction
      const m = raw.match(/"questions"\s*:\s*\[(.*?)\]/s);
      if (m) {
        const inner = m[1];
        const parts = inner.split(/,(?=(?:[^"]*"[^"]*")*[^"]*$)/).map(s=>s.replace(/^(\s*)?{?"?text"?\s*:\s*"?|"?}?\s*$/g,"").replace(/^"|"$|\\n/g,"").trim()).filter(Boolean);
        q1 = parts[0] || "";
        q2 = parts[1] || "";
      }
    }

    if (!q1 || !q2) {
      // final safety
      return {
        questions: [
          `Name one definition central to: "${goal}".`,
          `Give a short explanation/example related to "${goal}".`
        ]
      };
    }

    return { questions: [q1, q2] };
  } catch (e) {
    // ultimate fallback
    return {
      questions: [
        `Name one definition central to: "${goal}".`,
        `Give a short explanation/example related to "${goal}".`
      ]
    };
  }
}

/** ---------- Answer grading ---------- */

const GRADE_SYSTEM = `
You are "Proof-of-Day Adjudicator". Given a goal, scope, a single question, and the user's answer, decide if the answer plausibly indicates the user completed the goal. Be LENIENT and default-to-PASS.
Return ONLY one token: PASS or FAIL (uppercase; no punctuation, no extra text).
PASS unless the answer is clearly nonsense, entirely irrelevant, or demonstrates a fundamental misunderstanding of the core concept.
`;

export async function gradeAnswers(input: { goal: string; scope?: string; question: string; answer: string }): Promise<'PASS'|'FAIL'> {
  const goal = (input?.goal ?? "").trim();
  const scope = (input?.scope ?? "").trim();
  const question = (input?.question ?? "").toString();
  const answer = (input?.answer ?? "").toString();

  if (USE_MOCKS || !OPENAI_API_KEY) {
    // Super-lenient local fallback
    const ok = answer && answer.trim().length > 3;
    return ok ? "PASS" : "FAIL";
  }

  try {
    const user = JSON.stringify({ goal, scope, question, answer });
    const raw = await chat(GRADE_SYSTEM, user);
    const token = raw.trim().toUpperCase();
    if (token === "PASS" || token === "FAIL") return token as 'PASS'|'FAIL';
    // If model returns something unexpected, default to PASS (lenient)
    return "PASS";
  } catch {
    // On any LLM error, be lenient
    return "PASS";
  }
}
TS

echo "✅ judge.ts replaced with generateQuestions + gradeAnswers (with safe fallbacks)."
