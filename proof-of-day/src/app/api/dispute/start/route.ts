import { NextRequest, NextResponse } from "next/server";
import { getGoal, updateGoal } from "@/lib/db";

function baseUrl(req: NextRequest) {
  const env = process.env.NEXT_PUBLIC_SITE_URL;
  if (env) return env.replace(/\/+$/, "");
  const host = req.headers.get("x-forwarded-host") || req.headers.get("host") || "localhost:3000";
  const proto = req.headers.get("x-forwarded-proto") || "http";
  return `${proto}://${host}`;
}

export async function POST(req: NextRequest) {
  const { goalId } = await req.json();
  const goal = getGoal(goalId);
  if (!goal) return NextResponse.json({ error: "not found" }, { status: 404 });

  // mark disputed (no token anymore)
  updateGoal(goalId, { disputed: true });

  const profileUrl = `${baseUrl(req)}/u/${encodeURIComponent(goal.user)}`;
  const text = encodeURIComponent(
    `Dispute: I completed "${goal.title}". View my Proof-of-Day profile: ${profileUrl}`
  );
  const intentUrl = `https://twitter.com/intent/tweet?text=${text}`;

  return NextResponse.json({ intentUrl, profileUrl });
}
