import type { Metadata } from 'next'
import './globals.css'
import Link from 'next/link'
export const metadata: Metadata = { title: 'ProofOfDay', description: 'On-chain(ish) productivity receipts — demo' }
export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en"><body>
      <div className="max-w-4xl mx-auto px-4 py-6 gridish">
        <header className="flex items-center justify-between">
          <Link href="/" className="text-xl font-semibold">ProofOfDay</Link>
          <nav className="flex gap-3 text-sm text-neutral-400">
            <Link href="/discover" className="hover:text-neutral-200">Discover</Link>
            <Link href="/profile" className="hover:text-neutral-200">Profile</Link>
          </nav>
        </header>
        {children}
      </div>
    </body></html>
  )
}
