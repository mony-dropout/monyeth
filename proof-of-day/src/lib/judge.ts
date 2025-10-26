import OpenAI from "openai";

const USE_MOCKS = (process.env.NEXT_PUBLIC_USE_MOCKS ?? 'true') !== 'false';
const MODEL = "gpt-4o-mini"; // tweak later if you want

export async function generateQuestionsLLM(title: string, scope?: string): Promise<{ questions: string[]; transcript: string }>{
  if (USE_MOCKS || !process.env.OPENAI_API_KEY) {
    const q1 = `Explain two key definitions you learned for: ${title}.`;
    const q2 = `Give one concrete example (or mini proof outline) related to: ${scope ?? title}.`;
    return { questions: [q1, q2], transcript: `MOCK_QUESTIONS\nQ1: ${q1}\nQ2: ${q2}` };
  }
  const client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
  const system = `You write exactly TWO short verification questions for a goal. Be specific to the goal/scope. Return ONLY JSON: {"questions":["q1","q2"]}.`;
  const user = `GOAL_TITLE: ${title}\nGOAL_SCOPE: ${scope ?? '(none)'}\nWrite two questions.`;

  const resp = await client.chat.completions.create({
    model: MODEL,
    response_format: { type: "json_object" },
    messages: [
      { role: 'system', content: system },
      { role: 'user', content: user }
    ]
  });
  const content = resp.choices[0]?.message?.content || '{}';
  let parsed: any = {};
  try { parsed = JSON.parse(content); } catch {}
  const qs: string[] = Array.isArray(parsed.questions) ? parsed.questions.slice(0,2).map(String) : [];
  const questions = qs.length === 2 ? qs : [
    `State a core concept related to: ${title}.`,
    `Provide a worked example from: ${scope ?? title}.`
  ];
  const transcript = [
    'LLM GEN QUESTIONS',
    '--- system ---', system,
    '--- user ---', user,
    '--- model ---', content
  ].join('\n');
  return { questions, transcript };
}

export async function gradeAnswersLLM(
  title: string,
  scope: string | undefined,
  questions: string[],
  answers: string[]
): Promise<{ pass: boolean; transcript: string }>{
  if (USE_MOCKS || !process.env.OPENAI_API_KEY) {
    return { pass: true, transcript: `MOCK_GRADE\nQ1: ${questions[0]}\nA1: ${answers[0]}\nQ2: ${questions[1]}\nA2: ${answers[1]}` };
  }
  const client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
  const system = `You decide PASS/FAIL from two Q&A pairs. Default to PASS unless answers are empty, off-topic, or nonsense. Return ONLY JSON: {"pass": true|false}.`;
  const user = JSON.stringify({ title, scope, qa: [ { q: questions[0], a: answers[0] }, { q: questions[1], a: answers[1] } ] }, null, 2);
  const resp = await client.chat.completions.create({
    model: MODEL,
    response_format: { type: 'json_object' },
    messages: [
      { role: 'system', content: system },
      { role: 'user', content: user }
    ]
  });
  const content = resp.choices[0]?.message?.content || '{}';
  let parsed: any = {};
  try { parsed = JSON.parse(content); } catch {}
  const pass = !!parsed.pass;
  const transcript = [
    'LLM GRADE',
    '--- system ---', system,
    '--- input ---', user,
    '--- model ---', content
  ].join('\n');
  return { pass, transcript };
}
