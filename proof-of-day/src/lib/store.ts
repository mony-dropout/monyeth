import { Redis } from "@upstash/redis"

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

/** Accept either Upstash or KV env var names */
const url =
  process.env.UPSTASH_REDIS_REST_URL || process.env.KV_REST_API_URL
const token =
  process.env.UPSTASH_REDIS_REST_TOKEN || process.env.KV_REST_API_TOKEN
if (!url || !token) throw new Error("Missing Redis REST credentials")

const redis = new Redis({ url, token })

/** Helpers */
const normalize = (u: string) => (u || "").trim()

const kGoal = (id:string)=> `goal:${id}`
const kUserGoals = (u:string)=> `user_goals:${u}`
const kFeed = `feed`
const kUsers = `users:set`

/** Safer id gen (works in Node/Edge) */
function newId(){
  const c:any = globalThis.crypto as any
  if (c && typeof c.randomUUID === 'function') return c.randomUUID()
  // fallback
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`
}

/** Users */
export async function addKnownUser(u: string){ if(u) await redis.sadd(kUsers, u) }
export async function listKnownUsers(): Promise<string[]> { return (await redis.smembers<string>(kUsers)) ?? [] }

/** Goals */
export async function createGoalKV(data: Pick<Goal,'user'|'title'|'scope'|'deadlineISO'>){
  const userRaw = normalize(data.user)
  const g: Goal = {
    id: newId(),
    user: userRaw,
    title: data.title,
    scope: data.scope,
    deadlineISO: data.deadlineISO,
    status: 'PENDING',
    createdAt: Date.now(),
  }
  await redis.set(kGoal(g.id), g)
  await redis.lpush(kUserGoals(userRaw), g.id)
  await addKnownUser(userRaw)
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
  const norm = normalize(username)
  // try normalized first
  let ids = await redis.lrange<string>(kUserGoals(norm), 0, -1)
  // fallback to raw key if different and empty
  if ((!ids || ids.length===0) && norm !== username) {
    const raw = normalize(username) // already trimmed
    ids = await redis.lrange<string>(kUserGoals(raw), 0, -1)
  }
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
