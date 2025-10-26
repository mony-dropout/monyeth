import { NextRequest, NextResponse } from "next/server";
import { getGoalKV } from "@/lib/store";

export async function GET(req: NextRequest, { params }: { params: { id: string } }){
  const g = await getGoalKV(params.id)
  if(!g) return NextResponse.json({ error: 'not found' }, { status: 404 })
  return NextResponse.json({ goal: g })
}
