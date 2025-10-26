import { NextResponse } from "next/server";
import { listKnownUsers } from "@/lib/store";

export async function GET(){
  const users = await listKnownUsers();
  // newest-ish first by alpha invert just to vary a bit; for real we’d track createdAt
  const sorted = [...users].sort((a,b)=> a.localeCompare(b));
  return NextResponse.json({ users: sorted });
}
