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
