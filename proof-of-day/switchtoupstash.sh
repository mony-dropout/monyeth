# save as switch_to_upstash.sh, then: bash switch_to_upstash.sh && npm run dev
set -euo pipefail

echo "▶ Uninstalling @vercel/kv (if present) and installing @upstash/redis…"
npm uninstall @vercel/kv >/dev/null 2>&1 || true
npm i @upstash/redis jsonwebtoken >/dev/null

mkdir -p src/lib

echo "▶ Creating src/lib/store.ts (Upstash Redis wrapper)…"
cat > src/lib/store.ts <<'TS'
import { Redis } from "@upstash/redis"
import { randomUUID } from "crypto"

export type GoalStatus = 'PENDING' | 'PASSED' | 'FAILED'
export interface Goal {
  id: string
  user: string
  title: string
  scope?: string
  deadlineISO?: string
  status: GoalStatus
  notes?: string
  evidenceURI?: string
  easUID?: string
  score?: number
  rationale?: string
  questions?: any[]
  answers?: string[]
  disputed?: boolean
  createdAt: number
}

const redis = new Redis({
  url: process.env.UPSTASH_REDIS_REST_URL!,
  token: process.env.UPSTASH_REDIS_REST_TOKEN!,
})

/** Keys */
const kGoal = (id:string)=> `goal:${id}`
const kUserGoals = (u:string)=> `user_goals:${u}`
const kFeed = `feed`
const kUsers = `users:set`

/** Users */
export async function addKnownUser(u: string){ await redis.sadd(kUsers, u) }
export async function listKnownUsers(): Promise<string[]> { return (await redis.smembers<string>(kUsers)) ?? [] }

/** Goals */
export async function createGoalKV(data: Pick<Goal,'user'|'title'|'scope'|'deadlineISO'>){
  const g: Goal = {
    id: randomUUID(),
    user: data.user,
    title: data.title,
    scope: data.scope,
    deadlineISO: data.deadlineISO,
    status: 'PENDING',
    createdAt: Date.now(),
  }
  await redis.set(kGoal(g.id), g)
  await redis.lpush(kUserGoals(g.user), g.id)
  await addKnownUser(g.user)
  return g
}

export async function getGoalKV(id:string): Promise<Goal|null>{
  const g = await redis.get<Goal>(kGoal(id))
  return g ?? null
}

export async function updateGoalKV(id:string, patch: Partial<Goal>): Promise<Goal|null>{
  const cur = await getGoalKV(id)
  if(!cur) return null
  const upd = { ...cur, ...patch }
  await redis.set(kGoal(id), upd)
  return upd
}

export async function getUserGoalsKV(username: string): Promise<Goal[]>{
  const ids = await redis.lrange<string>(kUserGoals(username), 0, -1)
  if (!ids?.length) return []
  const pipeline = redis.pipeline()
  ids.forEach(id => pipeline.get<Goal>(kGoal(id)))
  const res = await pipeline.exec<Goal[]>()
  const goals = (res ?? []).filter(Boolean) as Goal[]
  return goals.sort((a,b)=> b.createdAt - a.createdAt)
}

/** Feed of attested goals */
export async function pushFeedKV(goalId: string){
  await redis.lpush(kFeed, goalId)
  await redis.ltrim(kFeed, 0, 499)
}
export async function getFeedKV(limit=200): Promise<Goal[]>{
  const ids = await redis.lrange<string>(kFeed, 0, Math.max(0, limit-1))
  if (!ids?.length) return []
  const pipeline = redis.pipeline()
  ids.forEach(id => pipeline.get<Goal>(kGoal(id)))
  const res = await pipeline.exec<Goal[]>()
  const goals = (res ?? []).filter(Boolean) as Goal[]
  return goals.sort((a,b)=> b.createdAt - a.createdAt)
}
TS

echo "▶ Rewiring API routes to use '@/lib/store'…"

# goals
mkdir -p src/app/api/goals
cat > src/app/api/goals/route.ts <<'TS'
import { NextRequest, NextResponse } from "next/server";
import { getSessionUsernameFromCookies } from "@/lib/auth";
import { createGoalKV, getUserGoalsKV } from "@/lib/store";

export async function GET(req: NextRequest){
  const uParam = req.nextUrl.searchParams.get('user');
  const username = uParam || getSessionUsernameFromCookies();
  if(!username) return NextResponse.json({ goals: [] });
  const goals = await getUserGoalsKV(username);
  return NextResponse.json({ goals });
}

export async function POST(req: NextRequest){
  const sessionUser = getSessionUsernameFromCookies();
  const body = await req.json();
  const username = sessionUser || body.user;
  if(!username) return NextResponse.json({ error: 'unauthorized' }, { status: 401 });
  const { title, scope, deadlineISO } = body;
  if(!title) return NextResponse.json({ error: 'missing title' }, { status: 400 });
  const goal = await createGoalKV({ user: username, title, scope, deadlineISO });
  return NextResponse.json({ goal });
}
TS

# goal/questions
mkdir -p src/app/api/goal/questions
cat > src/app/api/goal/questions/route.ts <<'TS'
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
TS

# goal/grade
mkdir -p src/app/api/goal/grade
cat > src/app/api/goal/grade/route.ts <<'TS'
import { NextRequest, NextResponse } from "next/server";
import { getGoalKV, updateGoalKV } from "@/lib/store";
import { gradeAnswers } from "@/lib/judge";

export async function POST(req: NextRequest){
  try {
    const { goalId, answers } = await req.json();
    const goal = await getGoalKV(goalId);
    if(!goal) return NextResponse.json({ error: 'not found' }, { status: 404 });

    const q = goal.questions || [];
    const a = Array.isArray(answers) ? answers : [];
    const g1 = await gradeAnswers({ goal: goal.title, scope: goal.scope || "", question: q[0], answer: a[0] || "" });
    const g2 = await gradeAnswers({ goal: goal.title, scope: goal.scope || "", question: q[1], answer: a[1] || "" });
    const pass = (g1 === 'PASS') && (g2 === 'PASS');

    const transcript = [
      "==== LLM TRANSCRIPT ====",
      `Q1: ${q[0] ?? ''}`,
      `A1: ${a[0] ?? ''}`,
      `Q2: ${q[1] ?? ''}`,
      `A2: ${a[1] ?? ''}`,
      `RESULT: ${pass ? 'PASS' : 'FAIL'}`
    ].join('\n');

    await updateGoalKV(goalId, { status: pass ? 'PASSED' : 'FAILED', answers: a, notes: transcript });
    return NextResponse.json({ pass });
  } catch(e:any){
    return NextResponse.json({ error: e?.message || 'error' }, { status: 500 })
  }
}
TS

# attest
mkdir -p src/app/api/attest
cat > src/app/api/attest/route.ts <<'TS'
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
TS

# public profile API
mkdir -p src/app/api/user/[username]/goals
cat > src/app/api/user/[username]/goals/route.ts <<'TS'
import { NextRequest, NextResponse } from 'next/server'
import { getUserGoalsKV } from '@/lib/store'

export async function GET(req: NextRequest, { params }: { params: { username: string } }) {
  const username = params.username
  const goals = await getUserGoalsKV(username)
  const pub = goals.map(g => ({
    id: g.id,
    title: g.title,
    scope: g.scope,
    status: g.status,
    easUID: g.easUID,
    disputed: g.disputed,
    createdAt: g.createdAt
  }))
  return NextResponse.json({ username, goals: pub })
}
TS

# social feed API
mkdir -p src/app/api/feed
cat > src/app/api/feed/route.ts <<'TS'
import { NextResponse } from 'next/server'
import { getFeedKV } from '@/lib/store'

export async function GET() {
  const items = await getFeedKV(200);
  const out = items.map(g => ({
    id: g.id,
    username: g.user,
    title: g.title,
    scope: g.scope,
    status: g.status,
    disputed: g.disputed,
    easUID: g.easUID,
    createdAt: g.createdAt
  }));
  return NextResponse.json({ items: out })
}
TS

# dispute/start (mark disputed, build tweet intent)
mkdir -p src/app/api/dispute/start
cat > src/app/api/dispute/start/route.ts <<'TS'
import { NextRequest, NextResponse } from "next/server"
import { getGoalKV, updateGoalKV } from "@/lib/store"

function baseUrl(req: NextRequest){
  const env = process.env.NEXT_PUBLIC_SITE_URL
  if (env) return env.replace(/\/+$/,'')
  const host = req.headers.get('x-forwarded-host') || req.headers.get('host') || 'localhost:3000'
  const proto = (req.headers.get('x-forwarded-proto') || 'http')
  return `${proto}://${host}`
}

export async function POST(req: NextRequest){
  const { goalId } = await req.json()
  const goal = await getGoalKV(goalId)
  if (!goal) return NextResponse.json({ error: 'not found' }, { status: 404 })
  await updateGoalKV(goalId, { disputed: true })

  const profileUrl = `${baseUrl(req)}/u/${encodeURIComponent(goal.user)}`
  const text = encodeURIComponent(`Dispute: I completed "${goal.title}". View my Proof-of-Day profile: ${profileUrl}`)
  const intentUrl = `https://twitter.com/intent/tweet?text=${text}`

  return NextResponse.json({ intentUrl, profileUrl })
}
TS

echo "✅ Switched to Upstash Redis."
