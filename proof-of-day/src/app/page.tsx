'use client'
import { useRouter } from 'next/navigation'
import { useEffect, useState } from 'react'

export default function Page() {
  const [name, setName] = useState('')
  const router = useRouter()
  useEffect(() => {
    const u = localStorage.getItem('pod_user')
    if (u) router.replace('/profile')
  }, [router])

  return (
    <main className="gridish">
      <div className="card gridish">
        <h1 className="text-2xl font-semibold">Welcome</h1>
        <p className="text-neutral-400">Demo login — just pick a username.</p>
        <div className="gridish">
          <label className="label">Username</label>
          <input className="input" value={name} onChange={e=>setName(e.target.value)} placeholder="mony" />
          <button className="btn" onClick={()=>{ if(!name) return; localStorage.setItem('pod_user', name); router.push('/profile')}}>Continue</button>
        </div>
      </div>
      <div className="text-sm text-neutral-500">No wallets needed. Onchain proofs are mocked until you turn them on.</div>
    </main>
  )
}
