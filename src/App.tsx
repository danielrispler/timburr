import { useState } from 'react'
import { library } from './library'

const tabs = ['Home', 'History', 'Exercises', 'More'] as const
type Tab = (typeof tabs)[number]

// Stage 1 shell: proves the build, the Capacitor wrap and the bundled library. Screens arrive in stage 2.
export default function App() {
  const [tab, setTab] = useState<Tab>('Home')

  return (
    <div className="app">
      <header className="header">
        <h1>Timburr</h1>
        <span className="sync">not synced</span>
      </header>
      <main className="screen">
        <p className="muted">
          {tab === 'Exercises' ? `${library.length} library exercises bundled.` : `${tab}: coming in stage 2.`}
        </p>
      </main>
      <nav className="tabs">
        {tabs.map((t) => (
          <button key={t} className={t === tab ? 'active' : ''} onClick={() => setTab(t)}>
            {t}
          </button>
        ))}
      </nav>
    </div>
  )
}
