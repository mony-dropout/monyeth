import { NextResponse } from 'next/server'
import { DB } from '@/lib/db'

export async function GET() {
  // Latest published (has easUID), newest first
  const items = DB.goals
    .filter(g => !!g.easUID)
    .sort((a,b)=> b.createdAt - a.createdAt)
    .slice(0,200)
    .map(g => ({
      id: g.id,
      username: g.user,
      title: g.title,
      status: g.status,
      disputed: g.disputed,
      easUID: g.easUID,
      createdAt: g.createdAt
    }))
  return NextResponse.json({ items })
}
