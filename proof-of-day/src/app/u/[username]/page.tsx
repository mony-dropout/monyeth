import Link from "next/link"

async function fetchGoals(username: string){
  const r = await fetch(`${process.env.NEXT_PUBLIC_SITE_URL ?? ''}/api/user/${username}/goals`, { cache: 'no-store' })
    .catch(()=> null)
  if (!r || !r.ok) return { username, goals: [] as any[] }
  return r.json()
}

export default async function PublicProfile({ params }: { params: { username: string } }){
  const { username } = params
  const data = await fetchGoals(username)

  return (
    <main className="gridish">
      <div className="card">
        <h1 className="text-2xl font-semibold">@{username}</h1>
        <div className="text-sm text-neutral-400">Public proof-of-day profile</div>
      </div>

      <section className="gridish">
        <h3 className="text-lg font-semibold">History</h3>
        <div className="grid gap-3">
          {data.goals?.length ? data.goals.map((g:any)=>(
            <div key={g.id} className="card" style={{display:'grid', gridTemplateColumns:'1fr auto', gap:'0.75rem', alignItems:'center'}}>
              <div>
                <div className="font-medium">{g.title}</div>
                <div className="text-sm text-neutral-400">{g.scope}</div>
              </div>
              <div className="flex items-center gap-2">
                <span className="text-sm" style={{padding:'4px 8px', borderRadius:8, background:g.status==='PASSED'?'#064e3b': g.status==='FAILED'?'#7f1d1d':'#27272a', color:g.status==='PENDING'?'#e5e7eb':'#d1fae5'}}>{g.status}{g.disputed?'·disputed':''}</span>
                {g.easUID ? (
                  <a className="btn" target="_blank" href={`https://base-sepolia.easscan.org/attestation/view/${g.easUID}`}>Proof</a>
                ) : (
                  <button className="btn" disabled>Proof</button>
                )}
              </div>
            </div>
          )) : (
            <div className="text-neutral-400">No entries yet.</div>
          )}
        </div>
      </section>

      <div className="text-sm text-neutral-500">
        <Link className="underline" href="/">Back to app</Link>
      </div>
    </main>
  )
}
