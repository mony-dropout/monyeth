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
  if (!goal.disputed) return NextResponse.json({ error: "not-in-dispute" }, { status: 400 });

  const id = parseTweetId(String(tweetUrl || ""));
  if (!id) return NextResponse.json({ error: "bad-tweet-url" }, { status: 400 });

  // Simple rule: PASS if tweet contains /u/<username> (ideal) or any fallback keywords.
  const target = `/u/${goal.user}`.toLowerCase();
  const fallbackKeywords = ["goal", "proof-of-day", "proof of day"];

  let verified = false;
  let lastErr: any = null;

  // Retry a few times because syndication can lag seconds for fresh tweets
  for (let i = 0; i < 3 && !verified; i++) {
    try {
      const data: any = await fetchTweetSyndication(id);
      const text = String(data?.text || data?.full_text || "").toLowerCase();
      const haystacks = [text];

      const urls = (data?.entities?.urls as any[]) || [];
      const inUrls = urls.some((u: any) => {
        const s = String(u?.expanded_url || u?.unwound_url || u?.url || "").toLowerCase();
        haystacks.push(s);
        return s.includes(target);
      });

      const keywordHit = haystacks.some((h) => fallbackKeywords.some((kw) => kw && h.includes(kw)));

      verified = text.includes(target) || inUrls || keywordHit;
      if (!verified && i < 2) await new Promise((r) => setTimeout(r, 1000));
    } catch (e: any) {
      lastErr = e;
      if (i < 2) await new Promise((r) => setTimeout(r, 1000));
    }
  }

  const pass = verified;
  const res = await attestResult({
    username: goal.user,
    goalTitle: goal.title,
    result: pass ? "PASS" : "FAIL",
    disputed: true,
    ref: goal.id,
  });

  updateGoal(goalId, { status: pass ? "PASSED" : "FAILED", easUID: res.uid, disputed: true });

  return NextResponse.json({
    verified,
    result: pass ? "PASS" : "FAIL",
    uid: res.uid,
    txHash: res.txHash,
    mocked: res.mocked,
    note: verified
      ? "Verified via tweet contents."
      : `No verification keywords found${lastErr ? ": " + String(lastErr) : ""}`,
  });
}
