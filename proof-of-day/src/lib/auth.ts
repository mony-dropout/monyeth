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
