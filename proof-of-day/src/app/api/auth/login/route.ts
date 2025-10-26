import { NextRequest, NextResponse } from "next/server";
import { issueSessionCookie, validateDemoCredential } from "@/lib/auth";
import { addKnownUser } from "@/lib/store";

export async function POST(req: NextRequest){
  const { username, password } = await req.json();
  if (!username || !password) return NextResponse.json({ error: "missing" }, { status: 400 });
  const ok = validateDemoCredential(username, password);
  if (!ok) return NextResponse.json({ error: "invalid" }, { status: 401 });

  const headers = new Headers();
  issueSessionCookie(headers, username);
  await addKnownUser(username);
  return new NextResponse(JSON.stringify({ ok: true, username }), { headers });
}
