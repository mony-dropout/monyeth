'use client'
import { useState } from 'react'

export default function NotesEditor({
  goalId,
  initialNotes
}: {
  goalId: string
  initialNotes?: string | null
}) {
  const [text, setText] = useState(initialNotes ?? '')
  const [lastSaved, setLastSaved] = useState(initialNotes ?? '')
  const [saving, setSaving] = useState(false)
  const [status, setStatus] = useState<{ kind: 'success' | 'error'; message: string } | null>(null)

  const updateStatus = (kind: 'success' | 'error', message: string) => {
    setStatus({ kind, message })
    setTimeout(() => setStatus(null), 2500)
  }

  const save = async () => {
    setSaving(true)
    setStatus(null)
    try {
      const r = await fetch('/api/goal', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ id: goalId, notes: text })
      })
      if (!r.ok) throw new Error(`HTTP ${r.status}`)
      const d = await r.json().catch(() => ({}))
      const notes = d?.goal?.notes ?? text
      setText(notes)
      setLastSaved(notes)
      updateStatus('success', 'Saved')
    } catch (e: any) {
      updateStatus('error', e?.message || 'Failed to save')
    } finally {
      setSaving(false)
    }
  }

  const reset = () => {
    setText(lastSaved)
    setStatus(null)
  }

  return (
    <div className="grid gap-3">
      <div>
        <label className="label mb-1 block text-sm text-neutral-400">Notes (edit or add more)</label>
        <textarea
          className="input"
          style={{ minHeight: '220px' }}
          value={text}
          onChange={(e) => setText(e.target.value)}
          placeholder="Add context, sources, or anything else you want to remember."
        />
      </div>
      <div className="flex items-center gap-3">
        <button className="btn" onClick={save} disabled={saving}>
          {saving ? 'Saving…' : 'Save notes'}
        </button>
        <button className="btn" onClick={reset} disabled={saving || text === lastSaved}>
          Reset changes
        </button>
        {status ? (
          <span className={status.kind === 'success' ? 'text-emerald-300 text-sm' : 'text-red-400 text-sm'}>
            {status.message}
          </span>
        ) : null}
      </div>
    </div>
  )
}
