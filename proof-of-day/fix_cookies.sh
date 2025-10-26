#!/usr/bin/env bash
set -euo pipefail

mkdir -p src/lib src/app/api/auth/me src/app/login

# --- src/lib/auth.ts (robust cookie reading) ---
cat > src/lib/auth.ts <<'TS'
import jwt from "jsonwebtoken";
import type { NextRequest } from "next/server";
import { cookies as nextCookies, headers as nextHeaders } from "next/headers";

const COOKIE_NAME = "pod_session";
const AUTH_SECRET = process.env.AUTH_SECRET || "dev-secret-change-me";

/** DEMO_USERS_CSV format: "user1:pass1,user2:pass2" */
function parseDemoUsers(): Record<string,string> {
  const raw = process.env.DEMO_USERS_CSV || "";
  const out: Record<string,string> = {};
  raw.split(",").map(s=>s.trim()).filter(Boolean).forEach(pair=>{
    const [u,p] = pair.split(":");
    if (u && p) out[u.trim()] = p.trim();
  });
  return out;
}

export function validateDemoCredential(username: string, password: string): boolean {
  const users = parseDemoUsers();
  return !!(users[username] && users[username] === password);
}

export function signToken(username: string){
  return jwt.sign({ u: username }, AUTH_SECRET, { expiresIn: "7d" });
}

export function verifyToken(token: string): string | null {
  try {
    const dec = jwt.verify(token, AUTH_SECRET) as any;
    return dec?.u || null;
  } catch { return null; }
}

/** Safe cookie read in any server context (RSC / route handler). */
function readCookieValueSafely(): string | null {
  // Try next/headers cookies()
  try {
    const store: any = (nextCookies as any)();
    const c = typeof store?.get === "function" ? store.get(COOKIE_NAME) : null;
    if (c && typeof c.value === "string") return c.value;
  } catch {}
  // Fallback: read raw Cookie header and parse
  try {
    const h = nextHeaders();
    const raw = h.get("cookie") || "";
    const found = raw.split(";").map(s=>s.trim()).find(s=>s.startsWith(COOKIE_NAME+"="));
    if (found) return decodeURIComponent(found.split("=").slice(1).join("="));
  } catch {}
  return null;
}

/** Use when you don't have access to NextRequest (e.g., RSC, generic server util). */
export function getSessionUsernameFromCookies(): string | null {
  const token = readCookieValueSafely();
  if (!token) return null;
  return verifyToken(token);
}

/** Use inside route handlers where you have the NextRequest. */
export function getSessionUsernameFromRequest(req: NextRequest): string | null {
  try {
    // Next 16: req.cookies.get(name)?.value
    const v = (req as any)?.cookies?.get?.(COOKIE_NAME)?.value;
    if (typeof v === "string") return verifyToken(v);
  } catch {}
  // Fallback to generic reader
  return getSessionUsernameFromCookies();
}

/** Append a Set-Cookie header to the provided Headers */
export function issueSessionCookie(resHeaders: Headers, username: string){
  const token = signToken(username);
  resHeaders.append(
    "Set-Cookie",
    `${COOKIE_NAME}=${token}; Path=/; HttpOnly; SameSite=Lax; Max-Age=604800`
  );
}

export function clearSessionCookie(resHeaders: Headers){
  resHeaders.append(
    "Set-Cookie",
    `${COOKIE_NAME}=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0`
  );
}
TS

# --- src/app/api/goals/route.ts (use req cookies) ---
cat > src/app/api/goals/route.ts <<'TS'
import { NextRequest, NextResponse } from "next/server";
import { getSessionUsernameFromRequest } from "@/lib/auth";
import { createGoalKV, getUserGoalsKV } from "@/lib/store";

export async function GET(req: NextRequest){
  const uParam = req.nextUrl.searchParams.get('user');
  const sessionUser = getSessionUsernameFromRequest(req);
  const username = uParam || sessionUser;
  if(!username) return NextResponse.json({ goals: [] });
  const goals = await getUserGoalsKV(username);
  return NextResponse.json({ goals });
}

export async function POST(req: NextRequest){
  const sessionUser = getSessionUsernameFromRequest(req);
  const body = await req.json();
  const username = sessionUser || body.user; // fallback for demo
  if(!username) return NextResponse.json({ error: 'unauthorized' }, { status: 401 });

  const { title, scope, deadlineISO } = body;
  if(!title) return NextResponse.json({ error: 'missing title' }, { status: 400 });

  const goal = await createGoalKV({ user: username, title, scope, deadlineISO });
  return NextResponse.json({ goal });
}
TS

# --- src/app/api/auth/me/route.ts (robust reader) ---
cat > src/app/api/auth/me/route.ts <<'TS'
import { NextRequest, NextResponse } from "next/server";
import { getSessionUsernameFromRequest, getSessionUsernameFromCookies } from "@/lib/auth";
export async function GET(req: NextRequest){
  const u = getSessionUsernameFromRequest(req) || getSessionUsernameFromCookies();
  return NextResponse.json({ username: u });
}
TS

# --- minimal /login page (to avoid 404) ---
cat > src/app/login/page.tsx <<'TSX'
'use client'
import { useState } from "react"
import { useRouter } from "next/navigation"

export default function LoginPage(){
  const r = useRouter()
  const [username,setUsername] = useState('')
  const [password,setPassword] = useState('')
  const [err,setErr] = useState<string|null>(null)

  const submit = async ()=>{
    setErr(null)
    try {
      const res = await fetch('/api/auth/login', {
        method: 'POST', headers:{'Content-Type':'application/json'},
        body: JSON.stringify({ username, password })
      })
      const d = await res.json()
      if(!res.ok) { setErr(d?.error || 'Login failed'); return }
      localStorage.setItem('pod_user', username)
      r.push('/profile')
    } catch(e:any){ setErr(e?.message || 'Network error') }
  }

  return (
    <main className="gridish">
      <div className="card" style={{maxWidth:520}}>
        <h1 className="text-2xl font-semibold mb-2">Login</h1>
        <div className="text-sm text-neutral-400 mb-4">Use one of the demo accounts you set in DEMO_USERS_CSV.</div>
        <div className="grid" style={{gap:'0.75rem'}}>
          <div><label className="label">Username</label><input className="input" value={username} onChange={e=>setUsername(e.target.value)} /></div>
          <div><label className="label">Password</label><input className="input" type="password" value={password} onChange={e=>setPassword(e.target.value)} /></div>
          {err && <div className="text-sm text-red-400">{err}</div>}
          <button className="btn" onClick={submit}>Sign in</button>
        </div>
      </div>
    </main>
  )
}
TSX

echo "✅ Cookies fixed + /login restored."
