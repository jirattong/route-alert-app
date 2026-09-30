// รูปแบบเวลาให้ตรงกับ Dart DateTime.toIso8601String() บนมือถือที่ตั้งเขตเวลา
// Asia/Bangkok (UTC+7 ไม่มี DST) — จัดรูปแบบเองชัดๆ ไม่พึ่ง TZ ของเครื่อง Mac

const BANGKOK_OFFSET_MS = 7 * 3600 * 1000;

/** เวลาท้องถิ่นกรุงเทพแบบไม่มี offset เช่น 2026-09-29T14:03:12.345 (เหมือน DateTime.now().toIso8601String()) */
export function bangkokIso(date = new Date()) {
  return new Date(date.getTime() + BANGKOK_OFFSET_MS).toISOString().replace('Z', '');
}

/** UTC ลงท้าย Z (เหมือน DateTime.now().toUtc().toIso8601String()) */
export function utcIso(date = new Date()) {
  return date.toISOString();
}

const ISO_RE =
  /^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2})(?:[.,](\d{1,6}))?)?)?(Z|[+-]\d{2}:?\d{2})?$/;

/** จำลอง DateTime.tryParse: ไม่มี offset = เวลาท้องถิ่นของมือถือ (กรุงเทพ) คืน epoch ms หรือ null */
export function parseDartIso(value) {
  if (typeof value !== 'string') return null;
  const m = ISO_RE.exec(value.trim());
  if (!m) return null;
  const [, y, mo, d, h = '00', mi = '00', s = '00', frac = '', tz] = m;
  const ms = Number((frac + '000').slice(0, 3));
  const base = Date.UTC(Number(y), Number(mo) - 1, Number(d), Number(h), Number(mi), Number(s), ms);
  if (Number.isNaN(base)) return null;
  if (!tz) return base - BANGKOK_OFFSET_MS;
  if (tz === 'Z') return base;
  const sign = tz[0] === '-' ? -1 : 1;
  const digits = tz.slice(1).replace(':', '');
  const off = (Number(digits.slice(0, 2)) * 60 + Number(digits.slice(2, 4))) * 60000;
  return base - sign * off;
}

export const isLocalNoOffset = (s) => typeof s === 'string' && ISO_RE.test(s) && !/(Z|[+-]\d{2}:?\d{2})$/.test(s);
export const isUtcZ = (s) => typeof s === 'string' && ISO_RE.test(s) && s.endsWith('Z');
