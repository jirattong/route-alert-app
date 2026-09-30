// ตัวส่ง push แบบ Cloud Functions (ต้องเปิด Blaze plan) — ทางเลือกแทน push-worker/
// ต้องคงตรรกะ/ข้อความ/รูปแบบข้อความให้ตรงกับ push-worker/src/index.js เสมอ และ
// เปิดใช้ได้ทีละอย่าง (เปิดทั้งคู่จะได้แจ้งเตือนซ้ำ)

const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const { setGlobalOptions } = require('firebase-functions/v2');
const logger = require('firebase-functions/logger');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');

initializeApp();

// Firestore ของโปรเจกต์อยู่ที่ asia-southeast3 (กรุงเทพฯ) — ตัว trigger จะผูกกับ
// region ของฐานข้อมูลเอง ส่วนตัวฟังก์ชันรันที่สิงคโปร์ซึ่งใกล้ที่สุดและรองรับแน่นอน
setGlobalOptions({ region: 'asia-southeast1', maxInstances: 5 });

const db = getFirestore();
const NEW_INCIDENT_WINDOW_MS = 15 * 60 * 1000;
const DEAD_TOKEN_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
]);

function toIso(value) {
  if (!value) return '';
  if (typeof value === 'string') return value;
  return value.toDate ? value.toDate().toISOString() : '';
}

// [createdMs] = เวลาที่ Firestore สร้างเอกสารจริง (createdAt จากแอปเป็นเวลาไทยไม่มี timezone)
function planNotifications(incident, log, nowMs, createdMs = Date.parse(toIso(incident.createdAt))) {
  const next = { ...log };
  const events = [];
  const age = Number.isFinite(createdMs) ? nowMs - createdMs : Infinity;
  const fresh = age >= -60_000 && age <= NEW_INCIDENT_WINDOW_MS;
  const silent = incident.archived || (!log.created && !fresh);
  const closed = incident.status === 'resolved' || incident.status === 'cancelled';

  if (!log.created) {
    next.created = true;
    if (!silent && incident.status === 'pending') events.push({ kind: 'new_incident' });
  }

  // เคสเดียวรับได้หลายคัน (ตรงกับ push-worker/src/index.js)
  const units = unitsOf(incident);
  const notified = new Set([...(log.assignedTo ? [log.assignedTo] : []), ...(log.assignedUnits || [])]);
  const newUnits = units.filter((u) => !notified.has(u.unitId));
  if (newUnits.length) {
    const first = notified.size === 0;
    const prevVehicles = log.vehicleCount ?? (first ? 0 : 1);
    const count = vehicleCountOf(incident);
    next.assignedTo = log.assignedTo || units[0].unitId;
    next.assignedUnits = [...notified, ...newUnits.map((u) => u.unitId)];
    next.vehicleCount = count;
    if (!silent && !closed) {
      const byHospital = newUnits.filter((u) => u.assignedBy !== 'ambulance').map((u) => u.unitId);
      for (const id of byHospital) events.push({ kind: 'assigned_to_you', ambulanceId: id });
      if (first) {
        events.push({ kind: 'case_taken', exceptAmbulanceIds: byHospital });
        events.push({ kind: 'ambulance_on_the_way' });
      } else if (count > prevVehicles) {
        events.push({ kind: 'more_vehicles', count });
      }
    }
  }

  if (incident.ambulanceNearSceneAt && !log.nearScene) {
    next.nearScene = true;
    if (!silent && !closed) events.push({ kind: 'ambulance_near' });
  }

  if (incident.status === 'resolved' && !log.resolved) {
    next.resolved = true;
    if (!silent) events.push({ kind: 'resolved' });
  }

  const changed = ['created', 'assignedTo', 'nearScene', 'resolved', 'vehicleCount'].some((k) => next[k] !== log[k]) ||
    JSON.stringify(next.assignedUnits ?? null) !== JSON.stringify(log.assignedUnits ?? null);
  return { events, next, changed };
}

const placeOf = (i) => i.address || i.province || 'ไม่ระบุตำแหน่ง';
const unitOf = (i) => i.assignedAmbulanceCallSign || i.assignedAmbulancePlate || 'หน่วยกู้ชีพ';

function unitsOf(incident) {
  const list = Array.isArray(incident.assignedUnits)
    ? incident.assignedUnits.filter((u) => u && u.unitId)
    : [];
  if (list.length) return list;
  if (!incident.assignedAmbulanceId) return [];
  return [{ unitId: incident.assignedAmbulanceId, assignedBy: incident.assignedBy || 'hospital' }];
}

const vehicleCountOf = (i) => new Set(unitsOf(i).map((u) => u.vehicleKey || u.unitId)).size;

function vehiclesLabelOf(incident) {
  const seen = new Set();
  const labels = [];
  for (const u of unitsOf(incident)) {
    const key = u.vehicleKey || u.unitId;
    if (seen.has(key)) continue;
    seen.add(key);
    labels.push(u.plate && u.plate !== 'ยังไม่ระบุทะเบียน' ? u.plate : u.callSign || u.unitId);
  }
  return labels.join(', ');
}

const lookup = {
  async usersWhere(field, value) {
    const snap = await db.collection('users').where(field, '==', value).get();
    return snap.docs.map((d) => ({ ref: d.ref, data: d.data() }));
  },
  async userByEmail(email) {
    const clean = (email || '').trim().toLowerCase();
    if (!clean) return [];
    const d = await db.collection('users').doc(clean).get();
    return d.exists ? [{ ref: d.ref, data: d.data() }] : [];
  },
};

async function buildMessages(event, incident, incidentId) {
  const type = incident.type || 'เหตุฉุกเฉิน';
  const msg = (users, audience, title, body) => ({
    users, incidentId, kind: event.kind, audience, title, body,
  });

  switch (event.kind) {
    case 'new_incident': {
      const target = incident.targetHospitalId || null;
      const agencies = (await lookup.usersWhere('role', 'agency')).filter(
        (u) => !target || !u.data.hospitalId || u.data.hospitalId === target,
      );
      const ambulances = await lookup.usersWhere('role', 'ambulance');
      const severity = incident.severity ? `${incident.severity} · ` : '';
      return [
        msg(agencies, 'agency', `🚨 เคสใหม่: ${type}`, `${severity}${placeOf(incident)}`),
        msg(ambulances, 'ambulance', '🚑 มีเคสใหม่รอรับ', `${type} · ${placeOf(incident)}`),
      ];
    }
    case 'assigned_to_you':
      return [msg(
        await lookup.usersWhere('ambulanceUnitId', event.ambulanceId),
        'ambulance', '🚑 ได้รับมอบหมายเคสใหม่', `${type} · ${placeOf(incident)}`,
      )];
    case 'case_taken': {
      const except = new Set(event.exceptAmbulanceIds || []);
      const others = (await lookup.usersWhere('role', 'ambulance')).filter(
        (u) => !except.has(u.data.ambulanceUnitId),
      );
      return [msg(others, 'ambulance', '', '')];
    }
    case 'ambulance_on_the_way':
      return [msg(
        await lookup.userByEmail(incident.reporterEmail),
        'reporter', '🚑 รถพยาบาลกำลังเดินทางไปหาคุณ', `${unitOf(incident)} รับเคสของคุณแล้ว`,
      )];
    case 'more_vehicles':
      return [{
        ...msg(
          await lookup.userByEmail(incident.reporterEmail),
          'reporter', '🚑 มีรถพยาบาลมาเพิ่ม',
          `ตอนนี้มี ${event.count} คันกำลังไปหาคุณ (${vehiclesLabelOf(incident)})`,
        ),
        kind: 'ambulance_on_the_way',
      }];
    case 'ambulance_near': {
      const eta = incident.ambulanceNearEtaMinutes;
      const etaText = eta ? ` (อีกราว ${eta} นาที)` : '';
      return [msg(
        await lookup.userByEmail(incident.reporterEmail),
        'reporter', '📍 รถพยาบาลใกล้ถึงแล้ว',
        `${incident.ambulanceNearCallSign || unitOf(incident)} อยู่ห่างไม่ถึง 500 ม.${etaText} เตรียมตัวรอที่จุดเกิดเหตุ`,
      )];
    }
    case 'resolved':
      return [msg(
        await lookup.userByEmail(incident.reporterEmail),
        'reporter', '✅ เคสของคุณเสร็จสิ้นแล้ว',
        incident.hospitalName
          ? `ผู้ป่วยถึง ${incident.hospitalName} เรียบร้อยแล้ว`
          : 'ทีมกู้ชีพดำเนินการเสร็จสิ้นแล้ว ขอบคุณที่แจ้งเหตุ',
      )];
    default:
      return [];
  }
}

function buildFcmMessage(token, m, nowSec) {
  const silent = m.kind === 'case_taken';
  const ttl = m.kind === 'new_incident' || silent ? 900 : 3600;
  const expiration = String(nowSec + ttl);
  return {
    token,
    data: { incidentId: m.incidentId, kind: m.kind, audience: m.audience, title: m.title, body: m.body },
    android: { priority: silent ? 'normal' : 'high', ttl: ttl * 1000 },
    apns: silent
      ? {
          headers: { 'apns-push-type': 'background', 'apns-priority': '5', 'apns-expiration': expiration },
          payload: { aps: { contentAvailable: true } },
        }
      : {
          headers: {
            'apns-push-type': 'alert',
            'apns-priority': '10',
            'apns-expiration': expiration,
            'apns-collapse-id': truncateUtf8(m.incidentId, 64),
          },
          payload: { aps: { alert: { title: m.title, body: m.body }, sound: 'default', threadId: m.incidentId } },
        },
  };
}

function truncateUtf8(text, maxBytes) {
  let out = '';
  let bytes = 0;
  for (const ch of text) {
    const size = Buffer.byteLength(ch);
    if (bytes + size > maxBytes) break;
    out += ch;
    bytes += size;
  }
  return out;
}

async function sendAll(messages, nowSec) {
  const jobs = [];
  for (const m of messages) {
    const byToken = new Map();
    for (const u of m.users) {
      if (u.data.fcmToken && !byToken.has(u.data.fcmToken)) byToken.set(u.data.fcmToken, u);
    }
    for (const [token, user] of byToken) jobs.push({ token, user, m });
  }
  if (jobs.length === 0) return 0;

  const res = await getMessaging().sendEach(jobs.map((j) => buildFcmMessage(j.token, j.m, nowSec)));
  const cleanups = [];
  res.responses.forEach((r, i) => {
    if (!r.success && DEAD_TOKEN_CODES.has(r.error?.code)) {
      cleanups.push(jobs[i].user.ref.update({ fcmToken: FieldValue.delete() }));
    }
  });
  await Promise.all(cleanups);
  logger.info(`ส่งสำเร็จ ${res.successCount}/${jobs.length} เครื่อง`);
  return res.successCount;
}

// ทุกครั้งที่เคสถูกเขียน — การเขียน pushLog เองจะ trigger ซ้ำแต่แผนจะไม่เปลี่ยน จึงจบทันที
exports.notifyIncident = onDocumentWritten('incident_reports/{incidentId}', async (event) => {
  const after = event.data?.after;
  if (!after?.exists) return;

  const nowMs = Date.now();
  const claimed = await db.runTransaction(async (tx) => {
    const snap = await tx.get(after.ref);
    if (!snap.exists) return null;
    const incident = snap.data();
    const plan = planNotifications(incident, incident.pushLog || {}, nowMs, snap.createTime?.toMillis());
    if (!plan.changed) return null;
    tx.update(after.ref, { pushLog: plan.next });
    return { plan, incident };
  });
  if (!claimed) return;

  const messages = [];
  for (const e of claimed.plan.events) {
    messages.push(...(await buildMessages(e, claimed.incident, event.params.incidentId)));
  }
  await sendAll(messages, Math.floor(nowMs / 1000));
});
