import dayjs from 'dayjs'
import utc from 'dayjs/plugin/utc'
import timezone from 'dayjs/plugin/timezone'
import relativeTime from 'dayjs/plugin/relativeTime'

dayjs.extend(utc)
dayjs.extend(timezone)
dayjs.extend(relativeTime)

/** Every Station is in Cambodia; report days are Phnom Penh days (ADR-0005). */
export const PP_TZ = 'Asia/Phnom_Penh'

export { dayjs }

/** A timestamp as staff read it: Phnom Penh wall-clock time. */
export const when = (iso?: string | null) => (iso ? dayjs(iso).tz(PP_TZ).format('D MMM YYYY, HH:mm') : '—')
export const ago = (iso?: string | null) => (iso ? dayjs(iso).fromNow() : '—')

/** `YYYY-MM-DD` of the current Phnom Penh day, shifted by `days`. */
export const ppDay = (days = 0) => dayjs().tz(PP_TZ).add(days, 'day').format('YYYY-MM-DD')

/** Start of a Phnom Penh day as a UTC instant, for report ranges. */
export const dayStartUtc = (day: string) => dayjs.tz(day, PP_TZ).startOf('day').toISOString()

export const fmtDay = (day: string, f = 'D MMM YYYY') => dayjs(day).format(f)
