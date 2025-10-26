import { NextRequest, NextResponse } from 'next/server'
import { getUserGoals } from '@/lib/db'

export async function GET(req: NextRequest, { params }: { params: { username: string } }) {
  const username = params.username
  const goals = getUserGoals(username)
  // Public: show all, but only include fields relevant for public view
  const pub = goals.map(g => ({
    id: g.id,
    title: g.title,
    scope: g.scope,
    status: g.status,
    easUID: g.easUID,
    disputed: g.disputed,
    createdAt: g.createdAt
  }))
  return NextResponse.json({ username, goals: pub })
}
