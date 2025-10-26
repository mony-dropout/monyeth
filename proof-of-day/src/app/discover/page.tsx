async function getAll(){ const res = await fetch(`${process.env.NEXT_PUBLIC_BASE_URL ?? ''}/api/all`, { cache: 'no-store' }); return res.json() }
export default async function Discover(){
  const data = await getAll()
  return (
    <main className="gridish">
      <h2 className="text-xl font-semibold">Recent passes</h2>
      <div className="grid gap-3">
        {data.goals.filter((g:any)=>g.status==='PASSED').map((g:any)=>(
          <div key={g.id} className="card">
            <div className="font-medium">{g.title}</div>
            <div className="text-sm text-neutral-400">by {g.user}</div>
          </div>
        ))}
      </div>
    </main>
  )
}
