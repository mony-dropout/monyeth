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
