import NotesInline from "@/components/NotesInline"

async function fetchUserGoals(username: string){
  const r = await fetch(`${process.env.NEXT_PUBLIC_SITE_URL ?? ''}/api/user/${username}/goals`, { cache:'no-store' }).catch(()=>null)
  if(!r || !r.ok) return { goals: [] as any[] }
  return r.json()
}

export default async function PublicProfile({ params }: { params: { username: string } }){
  const username = params.username
  const { goals } = await fetchUserGoals(username)

  return (
    <main className="gridish">
      <div className="card">
        <h1 className="text-2xl font-semibold">@{username}</h1>
        <div className="text-sm text-neutral-400">Public history</div>
      </div>

      <section className="grid gap-3">
        {goals.length ? goals.map((g:any)=>(
          <div key={g.id} className="card" style={{display:'grid', gridTemplateColumns:'1fr auto', gap:'0.75rem', alignItems:'flex-start'}}>
            <div>
              <div className="font-medium">{g.title}</div>
              {g.scope ? <div className="text-sm text-neutral-400">{g.scope}</div> : null}
              <div className="text-xs text-neutral-500 mt-1">{new Date(g.createdAt).toLocaleString()}</div>
            </div>
            <div className="flex items-start gap-2">
              <span className="text-sm" style={{padding:'4px 8px', borderRadius:8, background:g.status==='PASSED'?'#064e3b': g.status==='FAILED'?'#7f1d1d':'#27272a', color:g.status==='PENDING'?'#e5e7eb':'#d1fae5'}}>{g.status}{g.disputed?'·disputed':''}</span>
              <NotesInline goalId={g.id} initialNotes={g.notes} />
              {g.easUID ? (
                <a className="btn" target="_blank" href={`https://base-sepolia.easscan.org/attestation/view/${g.easUID}`}>Proof</a>
              ) : (
                <button className="btn" disabled title="No attestation yet">Proof</button>
              )}
            </div>
          </div>
        )) : (
          <div className="text-neutral-400">No entries yet.</div>
        )}
      </section>
    </main>
  )
}
