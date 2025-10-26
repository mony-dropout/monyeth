import Link from "next/link"

async function fetchFeed(){
  const r = await fetch(`${process.env.NEXT_PUBLIC_SITE_URL ?? ''}/api/feed`, { cache: 'no-store' }).catch(()=>null)
  if (!r || !r.ok) return { items: [] as any[] }
  return r.json()
}

export default async function SocialPage(){
  const { items } = await fetchFeed()

  return (
    <main className="gridish">
      <div className="card">
        <h1 className="text-2xl font-semibold">Social</h1>
        <div className="text-sm text-neutral-400">Newest on-chain proofs</div>
      </div>

      <section className="grid gap-3">
        {items.length ? items.map((it:any)=>(
          <div key={it.id} className="card" style={{display:'grid', gridTemplateColumns:'1fr auto', gap:'0.75rem', alignItems:'center'}}>
            <div>
              <div className="font-medium"><Link className="underline" href={`/u/${it.username}`}>@{it.username}</Link> — {it.title}</div>
              <div className="text-sm text-neutral-400">{new Date(it.createdAt).toLocaleString()}</div>
            </div>
            <div className="flex items-center gap-2">
              <span className="text-sm" style={{padding:'4px 8px', borderRadius:8, background:it.status==='PASSED'?'#064e3b': it.status==='FAILED'?'#7f1d1d':'#27272a', color:it.status==='PENDING'?'#e5e7eb':'#d1fae5'}}>{it.status}{it.disputed?'·disputed':''}</span>
              <a className="btn" target="_blank" href={`https://base-sepolia.easscan.org/attestation/view/${it.easUID}`}>Proof</a>
            </div>
          </div>
        )) : <div className="text-neutral-400">No attestations yet.</div>}
      </section>

      <div className="text-sm text-neutral-500">
        <Link className="underline" href="/">Back to app</Link>
      </div>
    </main>
  )
}
