import { NextRequest, NextResponse } from "next/server";
import { getSessionUsernameFromRequest } from "@/lib/auth";
import { createGoalKV, getUserGoalsKV } from "@/lib/store";

export async function GET(req: NextRequest){
  const uParam = req.nextUrl.searchParams.get('user');
  const sessionUser = getSessionUsernameFromRequest(req);
  const username = uParam || sessionUser;
  if(!username) return NextResponse.json({ goals: [] });
  const goals = await getUserGoalsKV(username);
  return NextResponse.json({ goals });
}

export async function POST(req: NextRequest){
  const sessionUser = getSessionUsernameFromRequest(req);
  const body = await req.json();
  const username = sessionUser || body.user; // fallback for demo
  if(!username) return NextResponse.json({ error: 'unauthorized' }, { status: 401 });

  const { title, scope, deadlineISO } = body;
  if(!title) return NextResponse.json({ error: 'missing title' }, { status: 400 });

  const goal = await createGoalKV({ user: username, title, scope, deadlineISO });
  return NextResponse.json({ goal });
}
