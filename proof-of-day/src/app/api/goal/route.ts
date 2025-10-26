import { NextRequest, NextResponse } from 'next/server'
import { getGoalKV, updateGoalKV } from '@/lib/store'
import { getGoal as getGoalLegacy, updateGoal as updateGoalLegacy } from '@/lib/db'

export async function GET(req: NextRequest){
  const id = req.nextUrl.searchParams.get('id')
  if(!id) return NextResponse.json({ error: 'missing id' }, { status: 400 })

  const goal = await getGoalKV(id).catch(()=>null)
  if (goal) return NextResponse.json({ goal })

  const legacy = getGoalLegacy(id)
  if (legacy) return NextResponse.json({ goal: legacy })

  return NextResponse.json({ error: 'not found' }, { status: 404 })
}

export async function PATCH(req: NextRequest){
  const { id, notes } = await req.json()
  if(!id) return NextResponse.json({ error: 'missing id' }, { status: 400 })

  const updated = await updateGoalKV(id, { notes }).catch(()=>null)
  if (updated) return NextResponse.json({ goal: updated })

  const legacy = updateGoalLegacy(id, { notes })
  if (legacy) return NextResponse.json({ goal: legacy })

  return NextResponse.json({ error: 'not found' }, { status: 404 })
}
