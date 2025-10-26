import type { Metadata } from "next"
import "./globals.css"
import Nav from "@/components/Nav"

export const metadata: Metadata = {
  title: "Proof-of-Day",
  description: "Quick-check productivity with on-chain attestations",
}

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <Nav />
        <div className="mx-auto max-w-4xl px-4 py-6">{children}</div>
      </body>
    </html>
  )
}
