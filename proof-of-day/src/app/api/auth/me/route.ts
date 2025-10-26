import { NextRequest, NextResponse } from "next/server";
import { getSessionUsernameFromRequest, getSessionUsernameFromCookies } from "@/lib/auth";
export async function GET(req: NextRequest){
  const u = getSessionUsernameFromRequest(req) || getSessionUsernameFromCookies();
  return NextResponse.json({ username: u });
}
