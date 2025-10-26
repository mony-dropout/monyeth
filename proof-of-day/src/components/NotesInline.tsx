'use client'
import { useState } from 'react'

export default function NotesInline({
  goalId,
  initialNotes
}: {
  goalId: string
  initialNotes?: string | null
}) {
  const [open, setOpen] = useState(false)
  const [loading, setLoading] = useState(false)
  const [notes, setNotes] = useState<string | null>(initialNotes ?? null)
  const [err, setErr] = useState<string | null>(null)

  const toggle = async () => {
    const willOpen = !open
    setOpen(willOpen)
    if (willOpen && notes == null) {
      setLoading(true); setErr(null)
      try {
        const r = await fetch(`/api/goal/${goalId}`, { cache: 'no-store' })
        if (!r.ok) throw new Error(`HTTP ${r.status}`)
        const d = await r.json()
        setNotes(d?.goal?.notes || '')
      } catch (e: any) {
        setErr(e?.message || 'Failed to load notes')
      } finally {
        setLoading(false)
      }
    }
  }

  return (
    <div className="flex flex-col gap-2">
      <button className="btn" onClick={toggle}>{open ? 'Hide notes' : 'Notes'}</button>
      {open && (
        <div className="mt-1 w-full">
          {loading ? (
            <div className="text-sm text-neutral-400">Loading notes…</div>
          ) : err ? (
            <div className="text-sm text-red-400">{err}</div>
          ) : (
            <pre className="whitespace-pre-wrap text-neutral-200 bg-neutral-900 p-3 rounded-xl border border-neutral-800">
{(notes ?? 'No notes yet.')}
            </pre>
          )}
        </div>
      )}
    </div>
  )
}
