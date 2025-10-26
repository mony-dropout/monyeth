import { NextRequest, NextResponse } from "next/server";
import { getGoal, updateGoal } from "@/lib/db";
import { attestResult } from "@/lib/eas";

export async function POST(req: NextRequest){
  try {
    const { goalId, pass, disputed } = await req.json(); // pass:boolean, disputed:boolean
    const goal = getGoal(goalId);
    if (!goal) return NextResponse.json({ error: "not found" }, { status: 404 });

    const res = await attestResult({
      username: goal.user,
      goalTitle: goal.title,
      result: pass ? "PASS" : "FAIL",
      disputed: !!disputed,
      ref: goal.id,
    });

    updateGoal(goalId, { easUID: res.uid });

    return NextResponse.json({ uid: res.uid, txHash: res.txHash, mocked: res.mocked });
  } catch (e: any) {
    console.error("attest route error:", e);
    return NextResponse.json({ error: "attestation failed", details: e?.message ?? String(e) }, { status: 500 });
  }
}
