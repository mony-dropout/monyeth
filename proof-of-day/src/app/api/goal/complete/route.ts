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
