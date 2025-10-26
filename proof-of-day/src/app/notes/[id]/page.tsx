import { notFound } from "next/navigation"
import { getGoalKV } from "@/lib/store"

export const dynamic = 'force-dynamic'

export default async function NotesPage({ params }: { params: { id: string } }){
  const g = await getGoalKV(params.id)
  if(!g) notFound()

  return (
    <main className="gridish">
      <div className="card">
        <h1 className="text-2xl font-semibold mb-1">Notes</h1>
        <div className="text-sm text-neutral-400">Goal transcript & details</div>
      </div>

      <div className="card">
        <div className="mb-2">
          <div className="text-sm text-neutral-400">User</div>
          <div className="font-medium">@{g.user}</div>
        </div>
        <div className="mb-2">
          <div className="text-sm text-neutral-400">Title</div>
          <div className="font-medium">{g.title}</div>
        </div>
        {g.scope ? (
          <div className="mb-2">
            <div className="text-sm text-neutral-400">Scope</div>
            <div>{g.scope}</div>
          </div>
        ) : null}
        <div className="mb-2">
          <div className="text-sm text-neutral-400">Status</div>
          <div className="font-medium">{g.status}{g.disputed ? ' · disputed' : ''}</div>
        </div>
        {g.easUID ? (
          <div className="mb-4">
            <a className="btn" target="_blank" href={`https://base-sepolia.easscan.org/attestation/view/${g.easUID}`}>Blockchain proof</a>
          </div>
        ) : null}

        <div className="mb-1 text-sm text-neutral-400">Transcript</div>
        <pre className="whitespace-pre-wrap text-neutral-200 bg-neutral-900 p-3 rounded-xl border border-neutral-800">
{g.notes || 'No notes yet.'}
        </pre>
      </div>
    </main>
  )
}
