import { useEffect, useMemo, useState, useCallback, useMemo as useMemo2 } from 'react'
import icon from './assets/icon.png'

type JobLike = { label?: string } | string | undefined

interface Character {
  name?: string
  firstname?: string
  lastname?: string
  identifier?: string
  jobLabel?: string
  job?: JobLike
  employed?: boolean
  skin?: any
  model?: any
  sex?: string | number
  bank?: number
  money?: number
  dateofbirth?: string
}

type CharactersMap = Record<number, Character>

function fetchNui<T = unknown>(eventName: string, data: unknown = {}): Promise<T | void> {
  const anyWin = window as any
  const hasPRN = typeof anyWin.GetParentResourceName === 'function'
  const resourceName = hasPRN ? anyWin.GetParentResourceName() : 'dev-resource'

  if (!hasPRN) {
    return Promise.resolve()
  }

  return fetch(`https://${resourceName}/${eventName}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data),
  })
    .then(async (r) => {
      try { return (await r.json()) as T } catch { return }
    })
    .catch((err) => console.debug('[NUI ERROR]', eventName, err?.message))
}

const formatDKK = (n: number | undefined) =>
  (n ?? 0).toLocaleString('da-DK') + ' kr.'

const sexText = (sex: Character['sex']) =>
  (sex === 'f' || sex === 'female' || sex === 1) ? 'Kvinde' : 'Mand'

function App() {
  const [show, setShow] = useState(false)
  const [characters, setCharacters] = useState<CharactersMap>({})
  const [allowedSlot, setAllowedSlot] = useState(1)
  const [maxSlot, setMaxSlot] = useState(1)
  const [canDelete, setCanDelete] = useState(false)
  const [selected, setSelected] = useState<number | null>(null)
  const [identityOpen, setIdentityOpen] = useState(false)

  const [confirmOpen, setConfirmOpen] = useState(false)
  const [confirmInput, setConfirmInput] = useState('')

  const [L, setL] = useState({
    locked_slot: 'Låst plads',
    empty_slot: 'Tom plads',
    create_char: 'Opret karakter',
    play_char: 'Påbegynd RP',
    delete_char: 'Slet karakter',
    job: 'Arbejde',
    cash: 'Kontanter',
    bank: 'Bank',
    dob: 'Fødselsdato',
    sex: 'Køn',

    confirm_title: 'Er du helt sikker?',
    confirm_warning: 'Sletter du din karakter mister du alt indhold på karakteren. (Penge, biler, lejligheder etc.)',
    confirm_label: 'Skriv karakterens fulde navn for at bekræfte:',
    confirm_placeholder: 'Skriv navnet her...',
    cancel: 'Annuller',
    confirm_delete: 'Slet permanent',
  })

  useEffect(() => {
    fetchNui('nuiReady', {})
    fetchNui('ready', {}).catch(() => {}) 
  }, [])

  useEffect(() => {
    const onMsg = (e: MessageEvent) => {
      const m = e?.data as any
      if (m?.type === 'enableui') setIdentityOpen(!!m.enable)
    }
    window.addEventListener('message', onMsg as EventListener)
    return () => window.removeEventListener('message', onMsg as EventListener)
  }, [])

  useEffect(() => {
    const anyWin = window as any
    if (typeof anyWin.GetParentResourceName === 'function') return
    const mock = {
      action: 'ToggleMulticharacter',
      data: {
        show: true,
        CanDelete: true,
        AllowedSlot: 2,
        MaxSlot: 4,
        Characters: {
          1: {
            name: 'Video Video',
            jobLabel: 'Arbejdsløs - Kontanthjælp',
            money: 0,
            bank: 491_014,
            dateofbirth: '10/01/1950',
            sex: 'm',
          },
        },
      },
    }
    const t = setTimeout(() => window.postMessage(mock, '*'), 120)
    return () => clearTimeout(t)
  }, [])

  useEffect(() => {
    const handler = (e: MessageEvent) => {
      const { action, data } = (e?.data ?? {}) as any
      if (!action) return

      if (action === 'Locales' && data) {
        setL((prev) => ({ ...prev, ...data }))
        return
      }

      if (action !== 'ToggleMulticharacter' || !data) return

      const raw = data.Characters ?? {}
      const normalized: Record<number, Character> = {}
      if (Array.isArray(raw)) {
        raw.forEach((item, i) => normalized[Number(item?.slot ?? i + 1)] = item)
      } else if (typeof raw === 'object') {
        Object.keys(raw).forEach(k => {
          const n = Number(k); if (!Number.isNaN(n)) normalized[n] = raw[k]
        })
      }

      const keys = Object.keys(normalized).map(Number).sort((a,b)=>a-b)
      const maxCharSlot = keys.length ? keys[keys.length - 1] : 0
      const providedAllowed = Number(data.AllowedSlot ?? 1)
      const providedMax = Number(data.MaxSlot ?? providedAllowed)
      const effectiveAllowed = Math.max(providedAllowed, maxCharSlot)

      setShow(!!data.show)
      setCharacters(normalized)
      setCanDelete(!!data.CanDelete)
      setAllowedSlot(effectiveAllowed)
      setMaxSlot(Math.max(providedMax, effectiveAllowed))

      const first = keys[0]
      setSelected(typeof first === 'number' ? first : 1)
    }

    window.addEventListener('message', handler as EventListener)
    return () => window.removeEventListener('message', handler as EventListener)
  }, [])

  const slots = useMemo(() => Array.from({ length: Math.max(maxSlot, 0) }, (_, i) => i + 1), [maxSlot])

  const getCharDisplay = useCallback((ch?: Character) => {
    if (!ch) return { title: 'Tom plads', job: '', dob: '', cash: 0, bank: 0, sex: '' }
    const title = ch.name || [ch.firstname, ch.lastname].filter(Boolean).join(' ') || ch.identifier || 'Ukendt'
    
    let jobStr = ''
    if (typeof ch.job === 'string') {
      jobStr = ch.job
    } else if (ch.job && (ch.job as any).label) {
      jobStr = (ch.job as any).label
    }

    const jobLabel = ch.jobLabel || (ch.employed === false ? 'Arbejdsløs' : '')
    const combinedJob = [jobStr, jobLabel].filter(Boolean).join(' - ')

    return {
      title,
      job: combinedJob || '',
      dob: ch.dateofbirth || '',
      cash: ch.money ?? 0,
      bank: ch.bank ?? 0,
      sex: sexText(ch.sex),
    }
  }, [])

  const handleSelect = useCallback((idx: number) => {
    setSelected(idx)
    if (characters[idx]) fetchNui('SelectCharacter', { id: idx })
  }, [characters])

  const handleCreate = useCallback(() => {
    fetchNui('CreateCharacter', {})
  }, [])

  const handlePlay   = useCallback(() => { if (show) fetchNui('PlayCharacter', {}) }, [show])

  const requestDelete = useCallback(() => {
    if (!show || !canDelete) return
    if (selected == null || !characters[selected]) return
    setConfirmInput('')
    setConfirmOpen(true)
  }, [show, canDelete, characters, selected])

  const performDelete = useCallback(() => {
    fetchNui('DeleteCharacter', {})
    setConfirmOpen(false)
    setConfirmInput('')
  }, [])

  const expectedName = useMemo2(() => {
    if (selected == null) return ''
    const ch = characters[selected]
    if (!ch) return ''
    return ch.name || [ch.firstname, ch.lastname].filter(Boolean).join(' ') || ch.identifier || ''
  }, [selected, characters])

  const confirmEnabled = expectedName.trim().length > 0
    && confirmInput.trim() === expectedName.trim()

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (!show) return
      const k = (e as any).key
      if (confirmOpen) {
        if (k === 'Enter' && confirmEnabled) {
          e.preventDefault()
          performDelete()
        } else if (k === 'Escape') {
          e.preventDefault()
          setConfirmOpen(false)
        }
        return
      }
      if (k === 'Enter') { e.preventDefault(); handlePlay() }
      else if (k === 'Delete' || k === 'Backspace') { e.preventDefault(); requestDelete() }
    }
    window.addEventListener('keydown', onKey as EventListener)
    return () => window.removeEventListener('keydown', onKey as EventListener)
  }, [show, confirmOpen, confirmEnabled, performDelete, handlePlay, requestDelete])

  if (!show && !identityOpen) return null

  return (
    <div className="screen">
      <div className="screen-blur" />
      <header className="top-header">
        <img src={icon} alt="Logo" />
      </header>

      <main className="cards-row" role="list">
        {slots.map((idx) => {
          const ch = characters[idx]
          const info = getCharDisplay(ch)
          const isSelected = selected === idx
          const isLocked = idx > allowedSlot

          return (
            <div
              key={idx}
              className={'card' + (isSelected ? ' selected' : '') + (isLocked ? ' locked' : '')}
              role="listitem"
              tabIndex={isLocked ? -1 : 0}
              aria-disabled={isLocked || undefined}
              onClick={() => { if (!isLocked) { setSelected(idx); if (ch) handleSelect(idx) } }}
              onKeyDown={(e) => {
                if (isLocked) return
                if (e.key === 'Enter') { setSelected(idx); if (ch) handleSelect(idx) }
              }}
            >
              {isLocked ? (
                <div className="locked-content">
                  <h3 className="locked-text">{L.locked_slot}</h3>
                </div>
              ) : (
                <>
                  <div className="card-header">
                    <h3 className="card-title">{info.title}</h3>
                  </div>
                  <div className="card-body">
                    <div className="row"><span className="label">{L.job}:</span><span className="value">{info.job || '—'}</span></div>
                    <div className="row"><span className="label">{L.cash}:</span><span className="value">{formatDKK(info.cash)}</span></div>
                    <div className="row"><span className="label">{L.bank}:</span><span className="value">{formatDKK(info.bank)}</span></div>
                    <div className="row"><span className="label">{L.dob}:</span><span className="value">{info.dob || '—'}</span></div>
                    <div className="row"><span className="label">{L.sex}:</span><span className="value">{info.sex || '—'}</span></div>
                    <div className="row"></div>
                  </div>
                  <div className={'slot-badge' + (isSelected ? ' red' : '')}><p>{idx}</p></div>
                </>
              )}
            </div>
          )
        })}
      </main>

      <div className="actions">
        {selected == null ? null
          : (selected > allowedSlot) ? null
          : !characters[selected] ? (
            <button className="btn primary" onClick={handleCreate}>Opret karakter</button>
          ) : (
            <>
              <button className="btn primary" onClick={handlePlay}>
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="lucide lucide-circle-play">
                  <path d="M9 9.003a1 1 0 0 1 1.517-.859l4.997 2.997a1 1 0 0 1 0 1.718l-4.997 2.997A1 1 0 0 1 9 14.996z"/>
                  <circle cx="12" cy="12" r="10"/>
                </svg>
                {L.play_char}
              </button>

              <button className="btn danger" onClick={requestDelete}>
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="lucide lucide-trash-2">
                  <path d="M10 11v6"/><path d="M14 11v6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6"/><path d="M3 6h18"/><path d="M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/>
                </svg>
                {L.delete_char}
              </button>
            </>
          )
        }
      </div>

      {confirmOpen && (
        <>
          <div className="modal-backdrop" />
          <div className="modal" role="dialog" aria-modal="true" aria-labelledby="del-title">
            <div className="modal-icon">
              <svg xmlns="http://www.w3.org/2000/svg" width="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="lucide lucide-triangle-alert">
                <path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3"/>
                <path d="M12 9v4"/><path d="M12 17h.01"/>
              </svg>
            </div>
            <div className='header'>
              <h3 id="del-title" className="modal-title">{L.confirm_title}</h3>
              <p className="modal-sub">{L.confirm_warning}</p>
            </div>

            <div className='fillout'>
              <label className="modal-label">{L.confirm_label}</label>
              <div className="name-pill">{expectedName || '—'}</div>

              <input
                className="modal-input"
                placeholder={L.confirm_placeholder}
                value={confirmInput}
                onChange={(e) => setConfirmInput(e.target.value)}
                autoFocus
              />
            </div>

            <div className='divider'></div>

            <div className="modal-actions">
              <button className="modalbtn outline" onClick={() => setConfirmOpen(false)}>{L.cancel}</button>
              <button className="modalbtn danger solid" disabled={!confirmEnabled} onClick={performDelete}>
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="lucide lucide-trash-2">
                  <path d="M10 11v6"/><path d="M14 11v6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6"/><path d="M3 6h18"/><path d="M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/>
                </svg>
                {L.confirm_delete}
              </button>
            </div>
          </div>
        </>
      )}
    </div>
  )
}

export default App