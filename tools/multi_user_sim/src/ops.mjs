// การกระทำของแต่ละบทบาท แปลงจาก IncidentService ของแอป (lib/core/services/incident_service.dart)
// ทีละขั้น — เงื่อนไข transaction, ฟิลด์ที่เขียน และรูปแบบเวลาต้องตรงกับแอปทุกอย่าง
import {
  COLL, buildSosIncidentMap, parseIncident, isClosed, unitsOf, unitFields, vehicleKeyFor, isJoinable, STATUS_RANK,
} from './model.mjs';
import { findNearestHospital } from './geo.mjs';
import { bangkokIso, utcIso } from './timefmt.mjs';
import { nowMs, withTimeout } from './util.mjs';

class CaseTakenError extends Error {}

/** id แบบหน้า SOS ('Case #AVCB' + ms + สุ่ม 1000-9999) นำหน้าด้วย SIM- */
export function sosIncidentId(rng) {
  return `SIM-Case #AVCB${Date.now()}${1000 + Math.floor(rng.next() * 9000)}`;
}

/** หน้า SOS → IncidentService.createIncident: เลือก รพ. ใกล้สุดจากรายการเดียวกับแอป แล้ว set() */
export async function createIncident(device, { rng, point, hospitals, reporter, runId, extra = {} }) {
  const id = sosIncidentId(rng);
  const nearest = findNearestHospital(hospitals, point);
  const map = buildSosIncidentMap({
    id,
    type: rng.pick(['อุบัติเหตุทางรถยนต์', 'ผู้ป่วยหมดสติ / หัวใจหยุดเต้น', 'ไฟไหม้ / สารเคมีรั่วไหล', 'เหตุฉุกเฉินอื่นๆ']),
    severity: 'วิกฤต (Code Red - หมดสติ / บาดเจ็บสาหัส)',
    description: 'เคสจำลองสำหรับทดสอบหลายผู้ใช้',
    latitude: point.latitude,
    longitude: point.longitude,
    address: `บริเวณพิกัด ${point.latitude.toFixed(4)}, ${point.longitude.toFixed(4)} (เชียงใหม่)`,
    photos: [],
    reporterName: reporter.name,
    reporterEmail: reporter.email,
    reporterPhone: '081-234-5678',
    nearest,
    createdAt: new Date(),
    extra: { simulation: true, simRun: runId, ...extra },
  });
  const t0 = nowMs();
  await device.set(COLL.incidents, id, map);
  return { id, map, nearest, writeStartMs: t0, writeEndMs: nowMs() };
}

/** ตรรกะแอปที่ใช้: 'fixed' (ปัจจุบัน) หรือ 'legacy' (ก่อนแก้ — ใช้แสดงผลก่อน/หลังแก้) */
const logicOf = (device) => device.backend.cfg.appLogic ?? 'fixed';

/** id เอกสารล็อกรถในตัวจำลอง — แอปใช้ ambulance_locks/{vehicleKey} ตรงๆ แต่ตัวจำลองเขียนได้เฉพาะ SIM- */
export const simLockId = (vehicleKey) => `SIM-LOCK-${vehicleKey}`;

/**
 * IncidentService.assignAmbulance (รพ. สั่งจ่าย / รถกดรับเอง / ร่วมรับเคส) — ทุกเงื่อนไขตรงกับแอป
 * fixed: เคสเดียวหลายคัน + ล็อกรถ (อ่านล็อก → ถ้าชี้เคสอื่นที่ยังเปิดและมีรถคันนี้ = ไม่ว่าง)
 * legacy: ผู้ชนะคนเดียว ล็อกแค่เอกสารเคส (ก่อนแก้)
 * ล้มแล้วอ่านจากเซิร์ฟเวอร์ ถ้ามีรถคันนี้ในเคส = สำเร็จ (commit ไปแล้วแต่ฝั่งแอป timeout)
 */
export async function dispatchIncident(device, id, {
  ambulanceId, ambulancePlate, ambulanceCallSign, selfAccepted = false, onlyIfUnassigned = false,
}) {
  const legacy = logicOf(device) === 'legacy';
  const by = selfAccepted ? 'ambulance' : 'hospital';
  const callSign = ambulanceCallSign ?? `กู้ชีพ ${ambulancePlate}`;
  const unit = {
    unitId: ambulanceId,
    plate: ambulancePlate,
    callSign,
    vehicleKey: vehicleKeyFor(ambulancePlate, ambulanceId),
    assignedBy: by,
    joinedAt: bangkokIso(new Date()),
  };
  let attempts = 0;
  let outcome = 'failed';
  let txMs = null;
  let error = null;
  let txPromise = null;
  const t0 = nowMs();
  try {
    txPromise = device.transactionMulti(async (tx) => {
        attempts++;
        const current = (await tx.get(COLL.incidents, id)).data();
        if (!current) return 'not-found';
        if (legacy) {
          const taken = String(current.assignedAmbulanceId ?? '');
          if (taken === ambulanceId) return 'noop';
          if (current.status !== 'pending' || taken.length > 0) throw new CaseTakenError('case already taken');
          tx.update(COLL.incidents, id, {
            status: 'assigned', statusStep: 1, assignedAmbulanceId: ambulanceId,
            assignedAmbulancePlate: ambulancePlate, assignedAmbulanceCallSign: callSign, assignedBy: by,
          });
          return 'written';
        }
        const units = unitsOf(current);
        if (units.some((u) => u.unitId === ambulanceId)) return 'noop';
        if (isClosed(current) || current.archived === true) return 'closed';
        if (onlyIfUnassigned && units.length) return 'has-vehicles';
        if (!isJoinable(current)) return 'not-joinable';
        const lockId = simLockId(unit.vehicleKey);
        const lock = (await tx.get(COLL.locks, lockId)).data();
        const otherId = String(lock?.openCaseId ?? '');
        if (otherId && otherId !== id) {
          const other = (await tx.get(COLL.incidents, otherId)).data();
          if (other && !isClosed(other) && other.archived !== true &&
              unitsOf(other).some((u) => u.vehicleKey === unit.vehicleKey)) {
            return 'busy';
          }
        }
        const first = units.length === 0;
        tx.update(COLL.incidents, id, {
          ...unitFields([...units, unit]),
          ...(first ? {
            assignedAmbulanceId: ambulanceId, assignedAmbulancePlate: ambulancePlate,
            assignedAmbulanceCallSign: callSign, assignedBy: by,
          } : {}),
          ...(current.status === 'pending' ? { status: 'assigned', statusStep: 1 } : {}),
        });
        tx.set(COLL.locks, lockId, {
          vehicleKey: lockId, plate: ambulancePlate, unitId: ambulanceId, openCaseId: id,
          updatedAt: bangkokIso(new Date()), simulation: true, simRun: device.backend.runId ?? null,
        });
        return first ? 'assigned' : 'joined';
      });
    outcome = await withTimeout(txPromise, 15000, 'dispatch transaction');
    txMs = nowMs() - t0;
  } catch (e) {
    txMs = nowMs() - t0; // เวลาจนกว่า transaction จบ (ไม่รวมการอ่านซ้ำตอนล้ม)
    error = String(e?.code ?? e?.message ?? e).slice(0, 80);
    try {
      const snap = await device.get(COLL.incidents, id, { server: true });
      if (unitsOf(snap.data()).some((u) => u.unitId === ambulanceId)) outcome = 'committed-after-error';
    } catch {
      // อ่านไม่ได้ = ถือว่าไม่สำเร็จ เหมือนแอป
    }
  }
  const ok = ['written', 'noop', 'assigned', 'joined', 'committed-after-error'].includes(outcome);
  // แอปรอ transaction ไม่เกิน 15 วิ แต่ SDK ยังทำต่อเบื้องหลังได้ — settled บอกว่าสุดท้าย commit ไหม
  const settled = txPromise
    ? txPromise.then((r) => ['assigned', 'joined', 'written'].includes(r), () => false)
    : Promise.resolve(false);
  return { ok, outcome, attempts, ms: nowMs() - t0, txMs, error, settled };
}

/** AmbulanceCaseActions.acceptCase: อ่านสถานะจริงล่าสุด → เช็คว่างไหม → transaction แบบรับเอง */
export async function selfAccept(device, id, unit, busyIds) {
  const legacy = logicOf(device) === 'legacy';
  const snap = await device.get(COLL.incidents, id, { server: true });
  const fresh = snap.data();
  if (!fresh) return { ok: false, outcome: 'missing', attempts: 0, ms: 0 };
  const units = unitsOf(fresh);
  if (units.some((u) => u.unitId === unit.id)) return { ok: true, outcome: 'already-mine', attempts: 0, ms: 0 };
  if (legacy ? (units.length || fresh.status !== 'pending') : (isClosed(fresh) || !isJoinable(fresh))) {
    return { ok: false, outcome: 'taken-before-tx', attempts: 0, ms: 0 };
  }
  if (busyIds.has(unit.id)) return { ok: false, outcome: 'busy', attempts: 0, ms: 0 };
  // acceptIncidentByAmbulance ไม่ส่ง callSign → แอปเก็บ 'กู้ชีพ <ทะเบียน>'
  return dispatchIncident(device, id, { ambulanceId: unit.id, ambulancePlate: unit.plateNumber, selfAccepted: true });
}

/**
 * updateIncidentProgressStep / advanceIncidentStatus
 * fixed: transaction เดินหน้าอย่างเดียว ไม่แตะเคสที่ปิดแล้ว, ขั้นคำนวณจากสถานะ
 * legacy: update ตรงๆ ไม่มีเงื่อนไข (ก่อนแก้)
 */
export async function updateStep(device, id, status, statusStep = STATUS_RANK[status]) {
  if (logicOf(device) === 'legacy') {
    await device.update(COLL.incidents, id, { status, statusStep });
    return 'updated';
  }
  const rank = STATUS_RANK[status];
  const t0 = nowMs();
  const p = device.transactionMulti(async (tx) => {
    const current = (await tx.get(COLL.incidents, id)).data();
    if (!current) return 'not-found';
    if (isClosed(current)) return 'closed';
    const currentRank = STATUS_RANK[current.status] ?? current.statusStep;
    if (rank <= currentRank) return 'already-past';
    tx.update(COLL.incidents, id, { status, statusStep: rank });
    return 'updated';
  });
  // แอปรอไม่เกิน 15 วิ (runTransaction timeout) แล้วแจ้งว่าไม่สำเร็จ
  try {
    return await withTimeout(p, 15000, 'progress transaction');
  } catch (e) {
    if (process.env.SIM_DEBUG) console.error(`[updateStep ${status}] ${nowMs() - t0}ms ${e?.code ?? e?.message}`);
    return 'failed';
  }
}

/** updateAmbulanceEta — เวลา UTC ลงท้าย Z */
export function updateEta(device, id, { etaMinutes, distanceMeters, target }) {
  return device.update(COLL.incidents, id, {
    ambulanceEtaMinutes: etaMinutes,
    ambulanceDistanceMeters: distanceMeters,
    ambulanceEtaTarget: target,
    ambulanceEtaUpdatedAt: utcIso(new Date()),
  });
}

/** markAmbulanceNearScene — เวลาท้องถิ่นไม่มี Z, eta ต่ำสุด 1 */
export function markNearScene(device, id, etaMinutes) {
  const eta = etaMinutes == null ? null : Math.max(1, etaMinutes);
  return device.update(COLL.incidents, id, {
    ambulanceNearSceneAt: bangkokIso(new Date()),
    ambulanceNearEtaMinutes: eta,
  });
}

/** closeIncidentByHospital */
export function closeByHospital(device, id) {
  return device.update(COLL.incidents, id, {
    status: 'cancelled',
    cancelledBy: 'hospital',
    cancelReason: 'โรงพยาบาลปิดเคส',
    cancelledAt: bangkokIso(new Date()),
  });
}

/** getBusyAmbulanceIds: ทุกหน่วยในเคสที่ยังไม่ปิด ใน cache ของเครื่องนั้น (archived ก็นับ) */
export function busyIdsFrom(incidentsById) {
  const busy = new Set();
  for (const i of incidentsById.values()) {
    if (isClosed(i)) continue;
    for (const u of i.units ?? []) busy.add(u.unitId);
  }
  return busy;
}

/** cache ในเครื่อง = snapshot ล่าสุดจาก listener (แปลงแบบ IncidentReport.fromMap ข้ามเอกสารที่พัง) */
export function attachIncidentCache(device, { onChange, runId, scenario } = {}) {
  const cache = new Map();
  const firstSeen = new Map();
  device.listen(device.incidentsQuery(), (snap) => {
    const t = nowMs();
    for (const ch of snap.docChanges()) {
      const raw = ch.doc.data();
      if (runId && raw.simRun !== runId) continue;
      // รันหลายสถานการณ์ในรอบเดียว — แต่ละสถานการณ์เห็นเฉพาะเคสของตัวเอง
      if (scenario && raw.simScenario !== scenario) continue;
      if (ch.type === 'removed') {
        cache.delete(ch.doc.id);
        continue;
      }
      try {
        const parsed = parseIncident(raw);
        cache.set(ch.doc.id, parsed);
        if (!firstSeen.has(ch.doc.id)) firstSeen.set(ch.doc.id, t);
        onChange?.(ch.doc.id, parsed, raw, t);
      } catch {
        // แอปข้ามเอกสารที่ fromMap ไม่ได้ (try/catch ต่อเอกสาร)
      }
    }
  });
  return { cache, firstSeen };
}

/**
 * IncidentService.cancelIncident (ผู้แจ้งยกเลิก)
 * fixed: transaction — ยกเลิกได้เฉพาะเมื่อเซิร์ฟเวอร์ยังเป็น pending/0 และยังไม่มีรถ
 * legacy: เช็คจาก cache ในเครื่อง แล้วเขียนทับตรงๆ (ก่อนแก้)
 */
export async function cancelByReporter(device, id, cachedView, reason = 'แจ้งผิด') {
  if (logicOf(device) === 'legacy') {
    if (!cachedView || cachedView.status !== 'pending' || cachedView.statusStep !== 0) return 'rejected';
    await device.update(COLL.incidents, id, { status: 'cancelled', cancelReason: reason, cancelledAt: bangkokIso(new Date()) });
    return 'cancelled';
  }
  const p = device.transactionMulti(async (tx) => {
    const current = (await tx.get(COLL.incidents, id)).data();
    if (!current) return 'not-found';
    if (current.status !== 'pending' || (current.statusStep ?? 0) !== 0 || unitsOf(current).length) return 'rejected';
    tx.update(COLL.incidents, id, {
      status: 'cancelled', cancelledBy: 'reporter', cancelReason: reason, cancelledAt: bangkokIso(new Date()),
    });
    return 'cancelled';
  });
  try {
    return await withTimeout(p, 15000, 'cancel transaction');
  } catch {
    return 'failed';
  }
}
