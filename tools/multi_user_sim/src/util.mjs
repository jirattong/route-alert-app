// เครื่องมือทั่วไป: เวลา, สุ่มแบบกำหนด seed, สถิติ latency

/** เวลา wall-clock ความละเอียดสูง (ms) — ทุก "อุปกรณ์" อยู่ใน process เดียวกัน
 * จึงใช้นาฬิกาเดียวกันวัด latency ข้ามเครื่องได้ตรงๆ ไม่มีปัญหานาฬิกาเหลื่อม */
export const nowMs = () => performance.timeOrigin + performance.now();

export const sleep = (ms) => new Promise((r) => setTimeout(r, Math.max(0, ms)));

/** รอจนถึงเวลา wall-clock t (ใช้ยิงหลายอุปกรณ์ "พร้อมกัน") */
export const atTime = (t) => sleep(t - nowMs());

export async function withTimeout(promise, ms, label = 'operation') {
  let timer;
  const timeout = new Promise((_, rej) => {
    timer = setTimeout(() => rej(new Error(`${label} timed out after ${ms} ms`)), ms);
  });
  try {
    return await Promise.race([promise, timeout]);
  } finally {
    clearTimeout(timer);
  }
}

/** poll จน predicate เป็นจริง คืน true/false (ไม่ throw) */
export async function waitFor(predicate, { timeoutMs = 20000, intervalMs = 50 } = {}) {
  const end = nowMs() + timeoutMs;
  while (nowMs() < end) {
    try {
      if (await predicate()) return true;
    } catch {
      // ยังไม่พร้อม ลองใหม่
    }
    await sleep(intervalMs);
  }
  try {
    return Boolean(await predicate());
  } catch {
    return false;
  }
}

/** mulberry32 — สุ่มซ้ำได้ด้วย seed เดิม เพื่อให้รันซ้ำได้ตำแหน่งเดิม */
export function makeRng(seed) {
  let a = seed >>> 0;
  const next = () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  return {
    next,
    range: (lo, hi) => lo + (hi - lo) * next(),
    int: (lo, hi) => lo + Math.floor(next() * (hi - lo + 1)),
    pick: (arr) => arr[Math.floor(next() * arr.length)],
  };
}

/** สถิติแบบ nearest-rank (p50/p95) — ค่าเป็น ms */
export function stats(values) {
  const v = values.filter((x) => Number.isFinite(x)).sort((a, b) => a - b);
  if (v.length === 0) return { n: 0, min: null, p50: null, p95: null, max: null, mean: null };
  const rank = (p) => v[Math.min(v.length - 1, Math.max(0, Math.ceil((p / 100) * v.length) - 1))];
  const mean = v.reduce((s, x) => s + x, 0) / v.length;
  return { n: v.length, min: v[0], p50: rank(50), p95: rank(95), max: v[v.length - 1], mean };
}

export const round1 = (x) => (x == null ? null : Math.round(x * 10) / 10);

export function deepEqual(a, b) {
  return JSON.stringify(sortKeys(a)) === JSON.stringify(sortKeys(b));
}

function sortKeys(v) {
  if (Array.isArray(v)) return v.map(sortKeys);
  if (v && typeof v === 'object') {
    return Object.fromEntries(Object.keys(v).sort().map((k) => [k, sortKeys(v[k])]));
  }
  return v;
}

export function pad(n, width = 2) {
  return String(n).padStart(width, '0');
}
