export type JobLike = { label?: string } | string | undefined

export interface Character {
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

export type CharactersMap = Record<number, Character>

export function fetchNui<T = unknown>(eventName: string, data: unknown = {}): Promise<T | void> {
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

export const formatDKK = (n: number | undefined) =>
  (n ?? 0).toLocaleString('da-DK') + ' kr.'

export const sexText = (sex: Character['sex']) =>
  (sex === 'f' || sex === 'female' || sex === 1) ? 'Kvinde' : 'Mand'

export function getCharDisplay(ch?: Character) {
  if (!ch) return { title: 'Tom plads', job: '', dob: '', cash: 0, bank: 0, sex: '' }

  const title =
    ch.name ||
    [ch.firstname, ch.lastname].filter(Boolean).join(' ') ||
    ch.identifier ||
    'Ukendt'

  let jobStr = ''
  if (typeof ch.job === 'string') jobStr = ch.job
  else if (ch.job && (ch.job as any).label) jobStr = (ch.job as any).label

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
}

export function normalizeCharacters(raw: unknown): CharactersMap {
  const normalized: CharactersMap = {}

  if (Array.isArray(raw)) {
    raw.forEach((item: any, i: number) => {
      const slot = Number(item?.slot ?? i + 1)
      if (!Number.isNaN(slot)) normalized[slot] = item
    })
  } else if (raw && typeof raw === 'object') {
    Object.keys(raw as Record<string, Character>).forEach((k) => {
      const n = Number(k)
      if (!Number.isNaN(n)) normalized[n] = (raw as any)[k]
    })
  }

  return normalized
}

export function slotsArray(maxSlot: number): number[] {
  return Array.from({ length: Math.max(maxSlot, 0) }, (_, i) => i + 1)
}

export function expectedCharacterName(ch?: Character): string {
  if (!ch) return ''
  return (
    ch.name ||
    [ch.firstname, ch.lastname].filter(Boolean).join(' ') ||
    ch.identifier ||
    ''
  )
}

export function computeSlotBounds(chars: CharactersMap, providedAllowed?: number, providedMax?: number) {
  const keys = Object.keys(chars).map(Number).sort((a, b) => a - b)
  const maxCharSlot = keys.length ? keys[keys.length - 1] : 0
  const allowed = Math.max(Number(providedAllowed ?? 1), maxCharSlot)
  const maxSlot = Math.max(Number(providedMax ?? allowed), allowed)
  const first = typeof keys[0] === 'number' ? keys[0] : 1
  return { keys, maxCharSlot, allowed, maxSlot, first }
}

export const isLocked = (idx: number, allowedSlot: number) => idx > allowedSlot

export const hasParentResource = () =>
  typeof (window as any).GetParentResourceName === 'function'

export function devPostMockToggle() {
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
  window.postMessage(mock, '*')
}