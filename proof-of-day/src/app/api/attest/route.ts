import { NextRequest, NextResponse } from "next/server";
import { getGoalKV, updateGoalKV, pushFeedKV } from "@/lib/store";
import { attestResult } from "@/lib/eas";

export async function POST(req: NextRequest){
  try {
    const { goalId, pass, disputed } = await req.json();
    const goal = await getGoalKV(goalId);
    if (!goal) return NextResponse.json({ error: "not found" }, { status: 404 });

    const res = await attestResult({
      username: goal.user,
      goalTitle: goal.title,
      result: pass ? "PASS" : "FAIL",
      disputed: !!disputed,
      ref: goal.id,
    });

    const updated = await updateGoalKV(goalId, {
      status: pass ? 'PASSED' : 'FAILED',
      disputed: !!disputed,
      easUID: res.uid
    });

    if (updated?.easUID) {
      await pushFeedKV(goalId);
    }

    return NextResponse.json({ uid: res.uid, txHash: res.txHash, mocked: res.mocked });
  } catch (e: any) {
    console.error("attest route error:", e);
    return NextResponse.json({ error: "attestation failed", details: e?.message ?? String(e) }, { status: 500 });
  }
}
