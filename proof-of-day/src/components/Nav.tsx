'use client'
import Link from "next/link"
import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"

export default function Nav(){
  const r = useRouter()
  const [me,setMe] = useState<string|null>(null)

  const refreshMe = async ()=>{
    try {
      const d = await fetch('/api/auth/me', { cache:'no-store' }).then(r=>r.json())
      setMe(d?.username || null)
    } catch { setMe(null) }
  }

  useEffect(()=>{ refreshMe() },[])

  const signOut = async ()=>{
    await fetch('/api/auth/logout', { method:'POST' })
    localStorage.removeItem('pod_user')
    setMe(null)
    r.push('/login')
  }

  return (
    <header className="w-full border-b border-neutral-800 bg-neutral-950/60 sticky top-0 z-40">
      <div className="mx-auto max-w-4xl px-4 py-2 flex items-center gap-3">
        <Link href="/" className="font-semibold">Proof-of-Day</Link>
        <nav className="flex items-center gap-3 text-sm">
          <Link className="underline" href="/social">Social</Link>
          <Link className="underline" href="/discover">Discover</Link>
          {me ? (
            <>
              <Link className="underline" href="/profile">Profile</Link>
              <Link className="underline" href={`/u/${me}`}>Public</Link>
              <button className="btn" onClick={signOut}>Sign out</button>
            </>
          ) : (
            <Link className="btn" href="/login">Sign in</Link>
          )}
        </nav>
      </div>
    </header>
  )
}
