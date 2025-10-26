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
