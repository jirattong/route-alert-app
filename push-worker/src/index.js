// ตัวสั่งส่ง push notification ของ RouteAlert บน Cloudflare Workers (ใช้แทน
// Cloud Functions ได้โดยไม่ต้องเปิด Firebase Blaze plan)
//
// แอป/เว็บ Data ส่งแค่ { incidentId } มาหลังบันทึกเคสลง Firestore เสร็จ — Worker
// อ่านข้อมูลเคสจริงเอง ตัดสินใจเองว่าต้องแจ้งอะไร แล้วจด pushLog ไว้ในเคสกันส่งซ้ำ
// คนนอกที่รู้ URL จึงทำได้แค่ "กระตุ้น" แจ้งเตือนที่ควรเกิดอยู่แล้ว ครั้งเดียวต่อเหตุการณ์

const NEW_INCIDENT_WINDOW_MS = 15 * 60 * 1000;
// แพลนฟรีจำกัด 50 subrequest ต่อครั้ง เผื่อไว้ให้การอ่าน/เขียน Firestore
const MAX_PUSHES_PER_CALL = 40;
const SCOPES = [
  'https://www.googleapis.com/auth/datastore',
  'https://www.googleapis.com/auth/firebase.messaging',
].join(' ');

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...CORS },
  });

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });
    if (request.method !== 'POST') return json({ error: 'POST only' }, 405);

    let body;
    try {
      body = await request.json();
    } catch {
      return json({ error: 'invalid json' }, 400);
    }
    const incidentId = body?.incidentId;
    if (!isValidDocId(incidentId)) return json({ error: 'invalid incidentId' }, 400);

    try {
      return json(await handleIncident(incidentId, env, Date.now()));
    } catch (e) {
      console.error('notify failed', incidentId, e?.stack || e);
      return json({ error: 'internal' }, 500);
    }
  },
};

// ---------- ตัดสินใจว่าต้องแจ้งอะไร (pure function ทดสอบแยกได้) ----------

// รหัสเคสจากแอปเป็นแบบ 'Case #AVCB1234' (มีช่องว่าง/#) — รับได้ทุกอย่างที่เป็น document id
// ของ Firestore ได้ ขอแค่ไม่มี '/' และไม่ใช่ '.' / '..'
export function isValidDocId(id) {
  return typeof id === 'string' && id.length > 0 && id.length <= 500 &&
    !id.includes('/') && id !== '.' && id !== '..' && !/[\u0000-\u001f]/.test(id);
}

// [createdMs] = เวลาที่ Firestore สร้างเอกสารจริง — createdAt ที่แอปเขียนเป็นเวลาไทย
// ไม่มี timezone ติดมา เซิร์ฟเวอร์ (UTC) จะอ่านเพี้ยนไป 7 ชั่วโมง
export function planNotifications(incident, log, nowMs, createdMs = Date.parse(incident.createdAt || '')) {
  const next = { ...log };
  const events = [];
  const age = Number.isFinite(createdMs) ? nowMs - createdMs : Infinity;
  const fresh = age >= -60_000 && age <= NEW_INCIDENT_WINDOW_MS;
  // เคสเก่าที่มีอยู่ก่อนเปิดระบบนี้ ถูกแก้ไขครั้งแรก → จดสถานะไว้เฉยๆ ไม่ส่งย้อนหลัง
  const silent = incident.archived || (!log.created && !fresh);
  const closed = incident.status === 'resolved' || incident.status === 'cancelled';

  if (!log.created) {
    next.created = true;
    if (!silent && incident.status === 'pending') events.push({ kind: 'new_incident' });
  }

  // เคสเดียวรับได้หลายคัน — แจ้งทีละหน่วยที่เพิ่งเข้าเคส (pushLog เดิมมีแค่ assignedTo คันแรก)
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
        // ลบ "มีเคสใหม่รอรับ" ที่ค้างในเครื่องรถคันอื่น (รวมคันที่กดรับเองด้วย)
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

function placeOf(incident) {
  return incident.address || incident.province || 'ไม่ระบุตำแหน่ง';
}

function unitOf(incident) {
  return incident.assignedAmbulanceCallSign || incident.assignedAmbulancePlate || 'หน่วยกู้ชีพ';
}

// ทุกหน่วยที่รับเคส — เคสก่อนรองรับหลายคันมีแค่ assignedAmbulanceId
export function unitsOf(incident) {
  const list = Array.isArray(incident.assignedUnits)
    ? incident.assignedUnits.filter((u) => u && u.unitId)
    : [];
  if (list.length) return list;
  if (!incident.assignedAmbulanceId) return [];
  return [{ unitId: incident.assignedAmbulanceId, assignedBy: incident.assignedBy || 'hospital' }];
}

// นับรถตามทะเบียน (vehicleKey) — หลายบัญชีบนรถคันเดียวกัน = 1 คัน
export function vehicleCountOf(incident) {
  return new Set(unitsOf(incident).map((u) => u.vehicleKey || u.unitId)).size;
}

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

// ---------- ขั้นตอนหลัก ----------

async function handleIncident(incidentId, env, nowMs) {
  return handleIncidentWith(await googleClient(env), incidentId, nowMs);
}

// แยกออกมาให้ทดสอบได้ด้วย google client จำลอง (test/notify.test.mjs)
export async function handleIncidentWith(google, incidentId, nowMs) {
  const path = `incident_reports/${encodeURIComponent(incidentId)}`;

  // จอง pushLog ก่อนส่ง แบบมีเงื่อนไข updateTime — ถ้าเคสถูกแก้ระหว่างอ่านกับเขียน
  // (คำขออื่นจองไปแล้ว หรือมีคนแก้ฟิลด์อื่น) อ่านใหม่แล้ววางแผนใหม่ สูงสุด 3 รอบ
  let incident;
  let plan;
  for (let attempt = 0; ; attempt++) {
    const doc = await google.firestore('GET', path);
    if (!doc) return { skipped: 'not found' };
    incident = decodeFields(doc.fields || {});
    plan = planNotifications(incident, incident.pushLog || {}, nowMs, Date.parse(doc.createTime || ''));
    if (!plan.changed) return { sent: 0, events: [] };
    const claimed = await google.firestore(
      'PATCH',
      `${path}?updateMask.fieldPaths=pushLog&currentDocument.updateTime=${encodeURIComponent(doc.updateTime)}`,
      { fields: { pushLog: encodeValue(plan.next) } },
      { allowFail: true },
    );
    if (claimed) break;
    if (attempt >= 2) return { skipped: 'busy' };
  }

  const messages = [];
  for (const event of plan.events) {
    messages.push(...(await buildMessages(event, incident, incidentId, google)));
  }
  const sent = await sendAll(messages, google, Math.floor(nowMs / 1000));
  return { sent, events: plan.events.map((e) => e.kind) };
}

// lookup ต้องมี usersWhere(field, value) และ userByEmail(email) คืน [{ name, data }]
export async function buildMessages(event, incident, incidentId, lookup) {
  const type = incident.type || 'เหตุฉุกเฉิน';
  const msg = (users, audience, title, body) => ({
    users, incidentId, kind: event.kind, audience, title, body,
  });

  switch (event.kind) {
    case 'new_incident': {
      const target = incident.targetHospitalId || null;
      // agency ที่ยังไม่ผูกโรงพยาบาล (บัญชีเก่า/เดโม) เห็นทุกเคสในแอปอยู่แล้ว จึงแจ้งด้วย
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
      const except = new Set(event.exceptAmbulanceIds || (event.exceptAmbulanceId ? [event.exceptAmbulanceId] : []));
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
      // ส่งเป็นชนิดเดียวกับ "รถกำลังไปหาคุณ" — แอปรุ่นเดิมเปิดหน้าติดตามได้โดยไม่ต้องรู้จักชนิดใหม่
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

// Android ได้แบบ data-only ให้แอปวาดแจ้งเตือนเอง (ใส่ปุ่ม/ทับอันเดิมของเคสเดียวกันได้)
// iOS ต้องมี alert ให้ระบบโชว์เองเพราะแอปที่ถูกปัดทิ้งรับ data-only ไม่ได้
export function buildFcmMessage(token, m, nowSec) {
  const silent = m.kind === 'case_taken';
  const ttl = m.kind === 'new_incident' || silent ? 900 : 3600;
  const expiration = String(nowSec + ttl);
  return {
    token,
    data: { incidentId: m.incidentId, kind: m.kind, audience: m.audience, title: m.title, body: m.body },
    android: { priority: silent ? 'NORMAL' : 'HIGH', ttl: `${ttl}s` },
    apns: silent
      ? {
          headers: { 'apns-push-type': 'background', 'apns-priority': '5', 'apns-expiration': expiration },
          payload: { aps: { 'content-available': 1 } },
        }
      : {
          headers: {
            'apns-push-type': 'alert',
            'apns-priority': '10',
            'apns-expiration': expiration,
            'apns-collapse-id': truncateUtf8(m.incidentId, 64),
          },
          payload: { aps: { alert: { title: m.title, body: m.body }, sound: 'default', 'thread-id': m.incidentId } },
        },
  };
}

// apns-collapse-id จำกัด 64 ไบต์ (ไม่ใช่ 64 ตัวอักษร)
function truncateUtf8(text, maxBytes) {
  let out = '';
  let bytes = 0;
  for (const ch of text) {
    const size = new TextEncoder().encode(ch).length;
    if (bytes + size > maxBytes) break;
    out += ch;
    bytes += size;
  }
  return out;
}

async function sendAll(messages, google, nowSec) {
  const jobs = [];
  for (const m of messages) {
    // เครื่องเดียวอาจเคยล็อกอินหลายบัญชี — ส่งครั้งเดียวต่อ token
    const byToken = new Map();
    for (const u of m.users) {
      if (u.data.fcmToken && !byToken.has(u.data.fcmToken)) byToken.set(u.data.fcmToken, u);
    }
    for (const [token, user] of byToken) jobs.push({ token, user, m });
  }
  if (jobs.length > MAX_PUSHES_PER_CALL) {
    // ถ้าต้องตัด ให้ตัดคำสั่งลบแจ้งเตือน (case_taken) ทิ้งก่อนแจ้งเตือนจริง
    jobs.sort((a, b) => (a.m.kind === 'case_taken') - (b.m.kind === 'case_taken'));
    console.warn(`ตัดเหลือ ${MAX_PUSHES_PER_CALL} จาก ${jobs.length} เครื่อง (ลิมิตแพลนฟรี)`);
    jobs.length = MAX_PUSHES_PER_CALL;
  }

  const results = await Promise.all(
    jobs.map(async ({ token, user, m }) => {
      const status = await google.sendPush(buildFcmMessage(token, m, nowSec));
      // token ใช้ไม่ได้แล้ว (ลบแอป/ล้างข้อมูล) — ลบออกจากบัญชีกันส่งพลาดซ้ำ
      if (status === 'dead') {
        await google.firestoreByName('PATCH', `${user.name}?updateMask.fieldPaths=fcmToken`, { fields: {} });
      }
      return status === 'ok';
    }),
  );
  return results.filter(Boolean).length;
}

// ---------- Google APIs (Firestore REST + FCM HTTP v1) ----------

let cachedToken = null; // { value, exp, email } — ใช้ซ้ำได้ระหว่างคำขอใน isolate เดียวกัน

async function googleClient(env) {
  const sa = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT);
  const project = sa.project_id;
  const docsBase = `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents`;
  const accessToken = await getAccessToken(sa);
  const auth = { Authorization: `Bearer ${accessToken}` };

  async function call(method, url, body, { allowFail = false } = {}) {
    const res = await fetch(url, {
      method,
      headers: { ...auth, 'Content-Type': 'application/json' },
      body: body ? JSON.stringify(body) : undefined,
    });
    if (res.status === 404 && method === 'GET') return null;
    if (!res.ok) {
      const text = await res.text();
      if (allowFail) {
        console.warn(`${method} ${url} -> ${res.status} ${text}`);
        return null;
      }
      throw new Error(`${method} ${url} -> ${res.status} ${text}`);
    }
    return res.json();
  }

  const toUser = (d) => ({ name: d.name, data: decodeFields(d.fields || {}) });

  return {
    firestore: (method, path, body, opts) => call(method, `${docsBase}/${path}`, body, opts),
    firestoreByName: (method, nameAndQuery, body) =>
      call(method, `https://firestore.googleapis.com/v1/${nameAndQuery}`, body, { allowFail: true }),

    async usersWhere(field, value) {
      const rows = await call('POST', `${docsBase}:runQuery`, {
        structuredQuery: {
          from: [{ collectionId: 'users' }],
          where: { fieldFilter: { field: { fieldPath: field }, op: 'EQUAL', value: { stringValue: value } } },
        },
      });
      return rows.filter((r) => r.document).map((r) => toUser(r.document));
    },

    async userByEmail(email) {
      const clean = (email || '').trim().toLowerCase();
      if (!clean) return [];
      const d = await call('GET', `${docsBase}/users/${encodeURIComponent(clean)}`);
      return d ? [toUser(d)] : [];
    },

    async sendPush(message) {
      const res = await fetch(`https://fcm.googleapis.com/v1/projects/${project}/messages:send`, {
        method: 'POST',
        headers: { ...auth, 'Content-Type': 'application/json' },
        body: JSON.stringify({ message }),
      });
      if (res.ok) return 'ok';
      const text = await res.text();
      const unregistered = res.status === 404 || text.includes('UNREGISTERED') ||
        (res.status === 400 && text.includes('registration token'));
      console.warn(`FCM ${res.status}: ${text}`);
      return unregistered ? 'dead' : 'error';
    },
  };
}

async function getAccessToken(sa) {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.email === sa.client_email && cachedToken.exp - 60 > now) {
    return cachedToken.value;
  }
  const b64url = (bytes) =>
    btoa(String.fromCharCode(...new Uint8Array(bytes)))
      .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  const enc = (obj) => b64url(new TextEncoder().encode(JSON.stringify(obj)));

  const unsigned = `${enc({ alg: 'RS256', typ: 'JWT' })}.${enc({
    iss: sa.client_email,
    scope: SCOPES,
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  })}`;

  const pem = sa.private_key.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    'pkcs8', der, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign'],
  );
  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(unsigned));

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: `${unsigned}.${b64url(signature)}`,
    }),
  });
  if (!res.ok) throw new Error(`Google token ${res.status}: ${await res.text()}`);
  const { access_token, expires_in } = await res.json();
  cachedToken = { value: access_token, exp: now + (expires_in || 3600), email: sa.client_email };
  return access_token;
}

// ---------- แปลงค่าจากรูปแบบ Firestore REST ----------

function decodeValue(v) {
  if ('stringValue' in v) return v.stringValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return v.doubleValue;
  if ('booleanValue' in v) return v.booleanValue;
  if ('timestampValue' in v) return v.timestampValue;
  if ('nullValue' in v) return null;
  if ('mapValue' in v) return decodeFields(v.mapValue.fields || {});
  if ('arrayValue' in v) return (v.arrayValue.values || []).map(decodeValue);
  return undefined;
}

export function decodeFields(fields) {
  return Object.fromEntries(Object.entries(fields).map(([k, v]) => [k, decodeValue(v)]));
}

export function encodeValue(value) {
  if (value === null || value === undefined) return { nullValue: null };
  if (typeof value === 'boolean') return { booleanValue: value };
  if (typeof value === 'number') return { doubleValue: value };
  if (typeof value === 'string') return { stringValue: value };
  if (Array.isArray(value)) return { arrayValue: { values: value.map(encodeValue) } };
  return {
    mapValue: {
      fields: Object.fromEntries(Object.entries(value).map(([k, v]) => [k, encodeValue(v)])),
    },
  };
}
