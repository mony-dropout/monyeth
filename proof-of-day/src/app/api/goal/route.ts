import { NextRequest, NextResponse } from 'next/server'
import { getGoal, updateGoal } from '@/lib/db'
export async function GET(req: NextRequest){
  const id = req.nextUrl.searchParams.get('id')
  if(!id) return NextResponse.json({ error: 'missing id' }, { status: 400 })
  return NextResponse.json({ goal: getGoal(id) })
}
export async function PATCH(req: NextRequest){
  const { id, notes } = await req.json()
  if(!id) return NextResponse.json({ error: 'missing id' }, { status: 400 })
  return NextResponse.json({ goal: updateGoal(id, { notes }) })
}
