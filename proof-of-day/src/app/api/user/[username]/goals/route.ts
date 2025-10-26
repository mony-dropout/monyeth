import { NextRequest, NextResponse } from 'next/server'
import { getUserGoalsKV, getFeedKV } from '@/lib/store'
import { getUserGoals as getUserGoalsLegacy } from '@/lib/db'

export async function GET(req: NextRequest, { params }: { params: { username: string } }) {
  const username = params.username
  let goals = await getUserGoalsKV(username)
  if (!goals.length) {
    try {
      const feed = await getFeedKV(400)
      goals = feed.filter(g => g.user === username)
    } catch {}
  }
  if (!goals.length) {
    const legacy = getUserGoalsLegacy(username)
    if (legacy?.length) goals = legacy
  }
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
