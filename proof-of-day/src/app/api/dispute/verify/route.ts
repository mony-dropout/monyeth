import { NextRequest, NextResponse } from "next/server"
import { getGoal, updateGoal } from "@/lib/db"
import { attestResult } from "@/lib/eas"

// Extract numeric id from twitter/x url
function parseTweetId(urlStr: string){
  try {
    const u = new URL(urlStr)
    const path = u.pathname
    const m = path.match(/\/status\/(\d+)/)
    return m?.[1] || null
  } catch { return null }
}

export async function POST(req: NextRequest){
  const { goalId, tweetUrl } = await req.json()
  const goal = getGoal(goalId)
  if (!goal) return NextResponse.json({ error: 'not found' }, { status: 404 })
  if (!goal.disputeToken) return NextResponse.json({ error: 'no-dispute' }, { status: 400 })

  const id = parseTweetId(String(tweetUrl||''))
  if (!id) return NextResponse.json({ error: 'bad-tweet-url' }, { status: 400 })

  // Use Twitter public syndication JSON (no auth). May occasionally rate-limit.
  const syndUrl = `https://cdn.syndication.twimg.com/widgets/tweet.json?id=${id}`
  let ok = false
  try {
    const r = await fetch(syndUrl, { cache: 'no-store' })
    if (r.ok) {
      const data = await r.json()
      const text = (data?.text || data?.full_text || '').toString()
      const hasToken = text.includes(goal.disputeToken)
      // profile URL we advertised in /start
      const host = process.env.NEXT_PUBLIC_SITE_URL?.replace(/\/+$/,'') || ''
      const profileLink1 = `${host}/u/${goal.user}`
      const profileLink2 = `/u/${goal.user}`
      const hasProfile = text.includes(profileLink1) || text.includes(profileLink2)
      ok = hasToken && hasProfile
    }
  } catch (e) {
    // network blocked → remain false (we'll tell client)
  }

  if (!ok) {
    return NextResponse.json({ verified: false, error: 'token-or-link-missing' }, { status: 200 })
  }

  // Verified: publish PASS attestation (disputed = true)
  const res = await attestResult({
    username: goal.user,
    goalTitle: goal.title,
    result: "PASS",
    disputed: true,
    ref: goal.id
  })
  updateGoal(goalId, { status: 'PASSED', easUID: res.uid, disputed: true })
  return NextResponse.json({ verified: true, uid: res.uid, txHash: res.txHash, mocked: res.mocked })
}
