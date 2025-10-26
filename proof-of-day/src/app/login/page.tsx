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
