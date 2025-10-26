import { v4 as uuid } from 'uuid'

export type GoalStatus = 'PENDING' | 'PASSED' | 'FAILED'
export interface Goal {
  id: string
  user: string // username (demo)
  title: string
  scope?: string
  deadlineISO?: string
  status: GoalStatus
  notes?: string
  evidenceURI?: string
  easUID?: string
  score?: number
  rationale?: string
  createdAt: number
}

export interface DBShape {
  goals: Goal[]
}

const g = globalThis as unknown as { __POD_DB?: DBShape }
if (!g.__POD_DB) g.__POD_DB = { goals: [] }
export const DB = g.__POD_DB

export function createGoal(data: Pick<Goal, 'user'|'title'|'scope'|'deadlineISO'>) {
  const goal: Goal = {
    id: uuid(),
    user: data.user,
    title: data.title,
    scope: data.scope,
    deadlineISO: data.deadlineISO,
    status: 'PENDING',
    createdAt: Date.now()
  }
  DB.goals.unshift(goal)
  return goal
}

export function getUserGoals(user: string) {
  return DB.goals.filter(g => g.user === user)
}

export function getGoal(id: string) {
  return DB.goals.find(g => g.id === id)
}

export function updateGoal(id: string, patch: Partial<Goal>) {
  const goal = getGoal(id)
  if (!goal) return null
  Object.assign(goal, patch)
  return goal
}
