import { NextResponse } from "next/server";
import OpenAI from "openai";

export async function GET() {
  const hasKey = !!process.env.OPENAI_API_KEY;
  const usingMocks = (process.env.NEXT_PUBLIC_USE_MOCKS ?? "true") !== "false";
  if (!hasKey) {
    return NextResponse.json({
      ok: false,
      usingMocks,
      hasKey,
      hint: "Set OPENAI_API_KEY in .env.local and restart dev server."
    }, { status: 200 });
  }

  try {
    const client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY! });
    // Minimal, cheap ping: ask the model to return a tiny JSON
    const r = await client.chat.completions.create({
      model: "gpt-4o-mini",
      response_format: { type: "json_object" },
      messages: [
        { role: "system", content: "Return ONLY this JSON: {\"pong\":true}" },
        { role: "user", content: "ping" }
      ]
    });
    const raw = r.choices?.[0]?.message?.content ?? "";
    return NextResponse.json({
      ok: true,
      usingMocks,
      hasKey,
      model: "gpt-4o-mini",
      sampleResponse: raw
    });
  } catch (err: any) {
    return NextResponse.json({
      ok: false,
      usingMocks,
      hasKey,
      errorName: err?.name,
      errorMessage: err?.message,
      errorType: err?.type,
      errorStatus: err?.status,
      hint: "429 usually means billing/quota or wrong project. See checklist."
    }, { status: 200 });
  }
}
