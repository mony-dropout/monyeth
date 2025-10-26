import { NextRequest, NextResponse } from 'next/server'
import { getUserGoalsKV } from '@/lib/store'

export async function GET(req: NextRequest, { params }: { params: { username: string } }) {
  const username = params.username
  const goals = await getUserGoalsKV(username)
  const pub = goals.map(g => ({
    id: g.id,
    title: g.title,
    scope: g.scope,
    status: g.status,
    easUID: g.easUID,
    disputed: g.disputed,
    createdAt: g.createdAt,
    notes: g.notes ?? null,
  }))
  return NextResponse.json({ username, goals: pub })
}
