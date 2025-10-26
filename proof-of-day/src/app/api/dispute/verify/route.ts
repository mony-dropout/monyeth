import { NextRequest, NextResponse } from "next/server";
import { getGoal, updateGoal } from "@/lib/db";
import { attestResult } from "@/lib/eas";

// Accept twitter.com/x.com/mobile URLs
function parseTweetId(urlStr: string) {
  try {
    const u = new URL(urlStr);
    const m = u.pathname.match(/\/status\/(\d+)/);
    return m?.[1] || null;
  } catch {
    return null;
  }
}

function includesCI(hay: string, needle: string) {
  return hay.toLowerCase().includes(needle.toLowerCase());
}

// True if any expanded/unwound/url contains /u/<username>
function urlsContainProfile(urls: any[] | undefined | null, username: string) {
  if (!Array.isArray(urls)) return false;
  const target = `/u/${username}`.toLowerCase();
  for (const u of urls) {
    const cand = String(u?.expanded_url || u?.unwound_url || u?.url || "").toLowerCase();
    if (cand.includes(target)) return true;
  }
  return false;
}

async function fetchTweetSyndication(id: string) {
  const url = `https://cdn.syndication.twimg.com/widgets/tweet.json?id=${id}`;
  const r = await fetch(url, { cache: "no-store", headers: { "User-Agent": "Mozilla/5.0" } });
  if (!r.ok) throw new Error(`tweet json ${r.status}`);
  return r.json();
}

export async function POST(req: NextRequest) {
  const { goalId, tweetUrl } = await req.json();
  const goal = getGoal(goalId);
  if (!goal) return NextResponse.json({ error: "not found" }, { status: 404 });
  if (!goal.disputeToken) return NextResponse.json({ error: "no-dispute" }, { status: 400 });

  const id = parseTweetId(String(tweetUrl || ""));
  if (!id) return NextResponse.json({ error: "bad-tweet-url" }, { status: 400 });

  // Retry a few times because syndication can lag seconds for fresh tweets
  let data: any = null,
    ok = false,
    lastErr: any = null;
  for (let i = 0; i < 3 && !ok; i++) {
    try {
      data = await fetchTweetSyndication(id);
      const text = String(data?.text || data?.full_text || "");
      const tokenOK = includesCI(text, goal.disputeToken || "");
      const profileOK =
        includesCI(text, `/u/${goal.user}`) ||
        urlsContainProfile(data?.entities?.urls, goal.user);

      ok = tokenOK && profileOK;
      if (!ok && i < 2) await new Promise((r) => setTimeout(r, 1000));
    } catch (e: any) {
      lastErr = e;
      if (i < 2) await new Promise((r) => setTimeout(r, 1000));
    }
  }

  // Decide + publish on-chain (always)
  const result = ok ? "PASS" : "FAIL";
  const res = await attestResult({
    username: goal.user,
    goalTitle: goal.title,
    result: result as "PASS" | "FAIL",
    disputed: true,
    ref: goal.id,
  });
  updateGoal(goalId, { status: ok ? "PASSED" : "FAILED", easUID: res.uid, disputed: true });

  return NextResponse.json({
    verified: ok,
    result,
    uid: res.uid,
    txHash: res.txHash,
    mocked: res.mocked,
    note: ok ? "Verified via tweet" : `Could not verify (published FAIL${lastErr ? ": " + String(lastErr) : ""})`,
  });
}
