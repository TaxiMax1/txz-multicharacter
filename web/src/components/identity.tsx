import { useCallback, useEffect, useMemo, useState } from 'react'

type Sex = 'm' | 'f'
type FormState = {
  firstname: string
  lastname: string
  dateofbirth: string
  sex: Sex
  height: string
}

type Props = {
  open?: boolean
  onClose?: () => void
}

function fetchNui<T = unknown>(eventName: string, data: unknown = {}): Promise<T | void> {
  const anyWin = window as any
  const hasPRN = typeof anyWin.GetParentResourceName === 'function'
  const resourceName = hasPRN ? anyWin.GetParentResourceName() : 'dev-resource'

  if (!hasPRN) return Promise.resolve()

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

const LABELS = {
  title: 'Opret identitet',
  subtitle: 'Udfyld oplysningerne herunder for at fortsætte.',
  first: 'Fornavn',
  last: 'Efternavn',
  dob: 'Fødselsdato (DD/MM/ÅÅÅÅ)',
  sex: 'Køn',
  male: 'Mand',
  female: 'Kvinde',
  height: 'Højde (cm)',
  register: 'Registrer',
  invalid_first: 'Ugyldigt fornavn',
  invalid_last: 'Ugyldigt efternavn',
  invalid_dob: 'Ugyldig dato (DD/MM/ÅÅÅÅ) og min. 18 år',
  invalid_sex: 'Vælg køn',
  invalid_height: 'Højde skal være mellem 120 og 220 cm',
}

function isLettersAndBasic(name: string) {
  return /^[A-Za-zÀ-ÿ' -]+$/.test(name.trim())
}

function clamp(n: number, min: number, max: number) {
  return Math.max(min, Math.min(max, n))
}

function normalizeDOB(input: string) {
  let v = input.replace(/[^\d/]/g, '')
  if (v.length === 2 && !v.includes('/')) v = v + '/'
  if (v.length === 5 && v.split('/').length - 1 === 1) v = v + '/'
  return v.slice(0, 10)
}

function validDOB(dob: string) {
  const m = dob.match(/^(\d{2})\/(\d{2})\/(\d{4})$/)
  if (!m) return false
  const d = parseInt(m[1], 10)
  const mo = parseInt(m[2], 10)
  const y = parseInt(m[3], 10)
  if (mo < 1 || mo > 12) return false

  const isLeap = (y % 4 === 0 && y % 100 !== 0) || (y % 400 === 0)
  const dim = [31, isLeap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
  if (d < 1 || d > dim[mo - 1]) return false

  const today = new Date()
  const minYear = today.getFullYear() - 120
  const maxYear = today.getFullYear() - 18
  if (y < minYear || y > maxYear) return false

  const eighteenth = new Date(y + 18, mo - 1, d)
  if (eighteenth > today) return false

  return true
}

function validHeight(h: string) {
  const n = Number(h)
  if (!Number.isFinite(n)) return false
  return n >= 120 && n <= 220
}

export default function Identity({ open: controlledOpen, onClose }: Props) {
  const [openInternal, setOpenInternal] = useState(false)
  const open = typeof controlledOpen === 'boolean' ? controlledOpen : openInternal

  const [submitting, setSubmitting] = useState(false)
  const [errors, setErrors] = useState<string[]>([])
  const [form, setForm] = useState<FormState>({
    firstname: '',
    lastname: '',
    dateofbirth: '',
    sex: 'm',
    height: '',
  })

  useEffect(() => {
    const onMsg = (e: MessageEvent) => {
      const m = e?.data as any
      if (m?.type === 'enableui') setOpenInternal(!!m.enable)
    }
    window.addEventListener('message', onMsg as EventListener)
    return () => window.removeEventListener('message', onMsg as EventListener)
  }, [])

  useEffect(() => {
    fetchNui('ready', {}).catch(() => {})
  }, [])

  const canSubmit = useMemo(() => {
    return (
      isLettersAndBasic(form.firstname) &&
      isLettersAndBasic(form.lastname) &&
      validDOB(form.dateofbirth) &&
      (form.sex === 'm' || form.sex === 'f') &&
      validHeight(form.height) &&
      !submitting
    )
  }, [form, submitting])

  const onChange = useCallback(
    (key: keyof FormState, value: string) => {
      setForm((f) => ({
        ...f,
        [key]:
          key === 'dateofbirth'
            ? normalizeDOB(value)
            : key === 'height'
            ? value.replace(/[^\d]/g, '').slice(0, 3)
            : value,
      }))
    },
    []
  )

  const validateAndCollectErrors = useCallback(() => {
    const es: string[] = []
    if (!isLettersAndBasic(form.firstname)) es.push(LABELS.invalid_first)
    if (!isLettersAndBasic(form.lastname)) es.push(LABELS.invalid_last)
    if (!validDOB(form.dateofbirth)) es.push(LABELS.invalid_dob)
    if (!(form.sex === 'm' || form.sex === 'f')) es.push(LABELS.invalid_sex)
    if (!validHeight(form.height)) es.push(LABELS.invalid_height)
    setErrors(es)
    return es.length === 0
  }, [form])

  const handleSubmit = useCallback(async () => {
    if (!validateAndCollectErrors()) return
    setSubmitting(true)
    try {
      const first = form.firstname.trim()
      const last = form.lastname.trim()
      const prettyFirst = first.charAt(0).toUpperCase() + first.slice(1).toLowerCase()
      const prettyLast = last.charAt(0).toUpperCase() + last.slice(1).toLowerCase()
      const heightNum = clamp(Number(form.height), 120, 220)

      await fetchNui('register', {
        firstname: prettyFirst,
        lastname: prettyLast,
        dateofbirth: form.dateofbirth,
        sex: form.sex,
        height: heightNum,
      })

      onClose?.()
      setOpenInternal(false)
    } finally {
      setSubmitting(false)
    }
  }, [form, onClose, validateAndCollectErrors])

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (!open) return
      if (e.key === 'Enter' && canSubmit) {
        e.preventDefault()
        handleSubmit()
      }
    }
    window.addEventListener('keydown', onKey as EventListener)
    return () => window.removeEventListener('keydown', onKey as EventListener)
  }, [open, canSubmit, handleSubmit])

  if (!open) return null

  return (
    <>
      <div className="identity-backdrop" />
      <div className="modal identity-modal" role="dialog" aria-modal="true" aria-labelledby="id-title">
        <div className="modal-icon">
            <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <path d="M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/>
            </svg>
        </div>

        <div className="header">
          <h3 id="id-title" className="modal-title">{LABELS.title}</h3>
          <p className="modal-sub">{LABELS.subtitle}</p>
        </div>

        <div className="fillout">
          <label className="modal-label" htmlFor="first">{LABELS.first}</label>
          <input
            id="first"
            className="modal-input"
            placeholder="Fx. TXZ"
            value={form.firstname}
            onChange={(e) => onChange('firstname', e.target.value)}
            autoFocus
          />

          <label className="modal-label" htmlFor="last">{LABELS.last}</label>
          <input
            id="last"
            className="modal-input"
            placeholder="Fx. Scripts"
            value={form.lastname}
            onChange={(e) => onChange('lastname', e.target.value)}
          />

          <label className="modal-label" htmlFor="dob">{LABELS.dob}</label>
          <input
            id="dob"
            className="modal-input"
            placeholder="DD/MM/ÅÅÅÅ"
            inputMode="numeric"
            value={form.dateofbirth}
            onChange={(e) => onChange('dateofbirth', e.target.value)}
          />

          <label className="modal-label" htmlFor="sex">{LABELS.sex}</label>
          <select
            id="sex"
            className="modal-input"
            value={form.sex}
            onChange={(e) => onChange('sex', (e.target.value === 'f' ? 'f' : 'm'))}
          >
            <option value="m">{LABELS.male}</option>
            <option value="f">{LABELS.female}</option>
          </select>

          <label className="modal-label" htmlFor="height">{LABELS.height}</label>
          <input
            id="height"
            className="modal-input"
            placeholder="Fx. 180"
            inputMode="numeric"
            value={form.height}
            onChange={(e) => onChange('height', e.target.value)}
          />
        </div>

        {errors.length > 0 && (
          <div style={{ marginTop: 10, fontSize: 12, color: '#ffb3b3' }}>
            {errors.map((e, i) => <div key={i}>• {e}</div>)}
          </div>
        )}

        <div className="divider" />

        <div className="modal-actions">
          <button
            className="modalbtn danger solid"
            onClick={handleSubmit}
            disabled={!canSubmit}
          >
            {submitting ? 'Gemmer…' : LABELS.register}
          </button>
        </div>
      </div>
    </>
  )
}