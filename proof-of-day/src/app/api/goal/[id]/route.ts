import { NextRequest, NextResponse } from "next/server";
import { getGoalKV } from "@/lib/store";
import { getFeedKV } from "@/lib/store";

export async function GET(req: NextRequest, { params }: { params: { id: string } }){
  const direct = await getGoalKV(params.id)
  if (direct) return NextResponse.json({ goal: direct })

  // Fallback: try to find it in the recent feed (helps if key was saved but list is authoritative)
  try {
    const feed = await getFeedKV(400)
    const hit = feed.find(g => g.id === params.id)
    if (hit) return NextResponse.json({ goal: hit })
  } catch {}

  return NextResponse.json({ error: 'not found' }, { status: 404 })
}
