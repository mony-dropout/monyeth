import { NextRequest, NextResponse } from "next/server";
import { getGoalKV, updateGoalKV } from "@/lib/store";
import { generateQuestions } from "@/lib/judge";

export async function POST(req: NextRequest){
  try{
    const { goalId } = await req.json();
    const goal = await getGoalKV(goalId);
    if(!goal) return NextResponse.json({ error: 'not found' }, { status: 404 });
    const { questions } = await generateQuestions({ goal: goal.title, scope: goal.scope || "" });
    await updateGoalKV(goalId, { questions });
    return NextResponse.json({ questions });
  }catch(e:any){
    return NextResponse.json({ error: e?.message || 'error' }, { status: 500 })
  }
}
