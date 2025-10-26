import { NextResponse } from 'next/server'
import { getFeedKV } from '@/lib/store'

export async function GET() {
  const items = await getFeedKV(200);
  const out = items.map(g => ({
    id: g.id,
    username: g.user,
    title: g.title,
    scope: g.scope,
    status: g.status,
    disputed: g.disputed,
    easUID: g.easUID,
    createdAt: g.createdAt,
    notes: g.notes ?? null,
  }));
  return NextResponse.json({ items: out })
}
