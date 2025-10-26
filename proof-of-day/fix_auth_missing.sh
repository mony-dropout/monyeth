#!/usr/bin/env bash
set -euo pipefail

mkdir -p src/lib src/app/api/auth/login src/app/api/auth/logout src/app/api/auth/me

# --- src/lib/auth.ts ---
cat > src/lib/auth.ts <<'TS'
import jwt from "jsonwebtoken";
import { cookies } from "next/headers";

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

export function getSessionUsernameFromCookies(): string | null {
  const c = cookies().get(COOKIE_NAME);
  if (!c || !c.value) return null;
  return verifyToken(c.value);
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

# --- /api/auth/login ---
cat > src/app/api/auth/login/route.ts <<'TS'
import { NextRequest, NextResponse } from "next/server";
import { issueSessionCookie, validateDemoCredential } from "@/lib/auth";
import { addKnownUser } from "@/lib/store";

export async function POST(req: NextRequest){
  const { username, password } = await req.json();
  if (!username || !password) return NextResponse.json({ error: "missing" }, { status: 400 });
  const ok = validateDemoCredential(username, password);
  if (!ok) return NextResponse.json({ error: "invalid" }, { status: 401 });

  const headers = new Headers();
  issueSessionCookie(headers, username);
  await addKnownUser(username);
  return new NextResponse(JSON.stringify({ ok: true, username }), { headers });
}
TS

# --- /api/auth/logout ---
cat > src/app/api/auth/logout/route.ts <<'TS'
import { NextResponse } from "next/server";
import { clearSessionCookie } from "@/lib/auth";
export async function POST(){
  const headers = new Headers();
  clearSessionCookie(headers);
  return new NextResponse(JSON.stringify({ ok: true }), { headers });
}
TS

# --- /api/auth/me ---
cat > src/app/api/auth/me/route.ts <<'TS'
import { NextResponse } from "next/server";
import { getSessionUsernameFromCookies } from "@/lib/auth";
export async function GET(){
  const u = getSessionUsernameFromCookies();
  return NextResponse.json({ username: u });
}
TS

# Ensure tsconfig has @/* -> src/* mapping (idempotent)
if [ -f tsconfig.json ]; then
  node - <<'NODE'
const fs=require('fs');const p='tsconfig.json';
const j=JSON.parse(fs.readFileSync(p,'utf8'));
j.compilerOptions=j.compilerOptions||{};
j.compilerOptions.baseUrl=j.compilerOptions.baseUrl||'.';
j.compilerOptions.paths=j.compilerOptions.paths||{};
if(!j.compilerOptions.paths['@/*']) j.compilerOptions.paths['@/*']=['src/*'];
fs.writeFileSync(p, JSON.stringify(j,null,2));
console.log('tsconfig updated with @/* alias');
NODE
fi

echo "✅ Auth library and routes added."
