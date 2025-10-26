import { NextResponse } from "next/server";
import { clearSessionCookie } from "@/lib/auth";
export async function POST(){
  const headers = new Headers();
  clearSessionCookie(headers);
  return new NextResponse(JSON.stringify({ ok: true }), { headers });
}
