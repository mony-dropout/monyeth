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
