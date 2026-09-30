// S19: หลายเครื่องสั่ง "ส่งแจ้งเตือน" เคสเดียวกันพร้อมกัน — แต่ละเรื่องต้องถึงถูกคน และครั้งเดียว
// ใช้ handleIncidentWith ตัวจริงของ Worker กับ Firestore/FCM จำลอง (PATCH มีเงื่อนไข updateTime เหมือน REST จริง)
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { handleIncidentWith, encodeValue, planNotifications } from '../src/index.js';

const jitter = () => new Promise((r) => setTimeout(r, Math.random() * 4));

function fakeGoogle(users) {
  const doc = { fields: {}, version: 1, createTime: new Date().toISOString() };
  const sent = [];
  return {
    doc,
    sent,
    setIncident(obj) {
      const pushLog = doc.fields.pushLog;
      doc.fields = Object.fromEntries(Object.entries(obj).map(([k, v]) => [k, encodeValue(v)]));
      if (pushLog) doc.fields.pushLog = pushLog;
      doc.version++;
    },
    async firestore(method, url, body, { allowFail = false } = {}) {
      await jitter();
      if (method === 'GET') return { fields: structuredClone(doc.fields), updateTime: String(doc.version), createTime: doc.createTime };
      const want = decodeURIComponent(/currentDocument\.updateTime=([^&]+)/.exec(url)?.[1] ?? '');
      if (want && want !== String(doc.version)) {
        if (allowFail) return null;
        throw new Error('precondition');
      }
      Object.assign(doc.fields, body.fields);
      doc.version++;
      return {};
    },
    async firestoreByName() { return {}; },
    async usersWhere(field, value) {
      await jitter();
      return users.filter((u) => u.data[field] === value);
    },
    async userByEmail(email) {
      return users.filter((u) => u.name === `users/${String(email).trim().toLowerCase()}`);
    },
    async sendPush(message) {
      sent.push({ token: message.token, kind: message.data.kind, title: message.data.title });
      return 'ok';
    },
  };
}

const user = (email, data) => ({ name: `users/${email}`, data: { email, fcmToken: `tok-${email}`, ...data } });
const USERS = [
  user('h1a@x', { role: 'agency', hospitalId: 'H1' }),
  user('h1b@x', { role: 'agency', hospitalId: 'H1' }),
  user('h2@x', { role: 'agency', hospitalId: 'H2' }),
  user('legacy@x', { role: 'agency' }),
  user('amb1@x', { role: 'ambulance', ambulanceUnitId: 'AMB-1' }),
  user('amb2@x', { role: 'ambulance', ambulanceUnitId: 'AMB-2' }),
  user('amb3@x', { role: 'ambulance', ambulanceUnitId: 'AMB-3' }),
  user('driver@x', { role: 'driver' }),
];

async function burst(g, n = 8) {
  const results = await Promise.all(Array.from({ length: n }, () => handleIncidentWith(g, 'Case #AVCB1', Date.now())));
  const out = g.sent.splice(0);
  return { out, results };
}
const by = (out, kind) => out.filter((m) => m.kind === kind).map((m) => m.token).sort();
// ผลที่วัดได้จริง 1 แถว (results_doc.mjs ดึงไปทำตารางผลการทดลอง)
const result = (condition, expected, out) => {
  const who = {};
  for (const m of out) (who[m.kind] ??= []).push(m.token.replace(/^tok-|@x$/g, ''));
  const actual = out.length
    ? `ส่ง ${out.length} ครั้ง: ${Object.entries(who).map(([k, v]) => `${k} → ${v.join(', ')}`).join(' · ')}`
    : 'ไม่ส่งเลย';
  console.log(`@@RESULT ${JSON.stringify({ sid: 'S19', condition, expected, actual })}`);
};

test('[S19] 8 เครื่องสั่งแจ้งเตือนพร้อมกันทุกขั้นของเคส: ส่งครั้งเดียวต่อคน ถึงถูกคน', async () => {
  const g = fakeGoogle(USERS);
  const base = {
    id: 'Case #AVCB1', type: 'รถชน', severity: 'วิกฤต', address: 'ถ.ห้วยแก้ว', reporterEmail: 'Driver@X',
    targetHospitalId: 'H1', createdAt: new Date().toISOString(), hospitalName: 'รพ.ทดสอบ',
  };
  g.setIncident({ ...base, status: 'pending' });

  // 1. เคสใหม่ → agency ของ H1 (+ บัญชีเก่าไม่ผูก รพ.) และรถทุกคัน ไม่ถึง H2
  let { out } = await burst(g);
  assert.deepEqual(by(out, 'new_incident'), ['tok-amb1@x', 'tok-amb2@x', 'tok-amb3@x', 'tok-h1a@x', 'tok-h1b@x', 'tok-legacy@x']);
  assert.equal(out.length, 6);
  result('เคสใหม่ของ H1 · 8 เครื่องเรียกตัวส่งพร้อมกัน', 'agency H1 (2) + บัญชีเก่า (1) + รถทุกคัน (3) คนละครั้ง ไม่ถึง H2', out);

  // 2. รพ. สั่ง AMB-1 → AMB-1 ได้มอบหมาย, รถอื่นลบแจ้งเตือนเคสใหม่, ผู้แจ้งได้ "รถกำลังไป"
  const u1 = { unitId: 'AMB-1', plate: 'กข 1', vehicleKey: 'plate_กข1', callSign: 'กู้ชีพ 1', assignedBy: 'hospital' };
  g.setIncident({ ...base, status: 'assigned', assignedAmbulanceId: 'AMB-1', assignedBy: 'hospital', assignedAmbulanceCallSign: 'กู้ชีพ 1', assignedUnits: [u1] });
  ({ out } = await burst(g));
  assert.deepEqual(by(out, 'assigned_to_you'), ['tok-amb1@x']);
  assert.deepEqual(by(out, 'case_taken'), ['tok-amb2@x', 'tok-amb3@x']);
  assert.deepEqual(by(out, 'ambulance_on_the_way'), ['tok-driver@x']);
  assert.equal(out.length, 4);
  result('รพ. สั่ง AMB-1 · 8 คำขอพร้อมกัน', 'AMB-1 ได้มอบหมาย, รถอื่นลบแจ้งเตือน, ผู้แจ้งได้ “รถกำลังไป” คนละครั้ง', out);

  // 3. รพ. ส่งรถเพิ่ม AMB-2 → AMB-2 ได้มอบหมาย, ผู้แจ้งได้ "มีรถพยาบาลมาเพิ่ม" ครั้งเดียว
  const u2 = { unitId: 'AMB-2', plate: 'ขค 2', vehicleKey: 'plate_ขค2', callSign: 'กู้ชีพ 2', assignedBy: 'hospital' };
  g.setIncident({ ...base, status: 'assigned', assignedAmbulanceId: 'AMB-1', assignedBy: 'hospital', assignedUnits: [u1, u2] });
  ({ out } = await burst(g));
  assert.deepEqual(by(out, 'assigned_to_you'), ['tok-amb2@x']);
  assert.deepEqual(out.filter((m) => m.title === '🚑 มีรถพยาบาลมาเพิ่ม').map((m) => m.token), ['tok-driver@x']);
  assert.equal(out.length, 2);
  result('รพ. ส่งรถเพิ่ม AMB-2 · 8 คำขอพร้อมกัน', 'AMB-2 ได้มอบหมาย, ผู้แจ้งได้ “มีรถมาเพิ่ม” คนละครั้ง', out);

  // 4. ใกล้ถึง → ผู้แจ้งครั้งเดียว
  const near = new Date().toISOString();
  g.setIncident({ ...base, status: 'assigned', assignedAmbulanceId: 'AMB-1', assignedUnits: [u1, u2], ambulanceNearSceneAt: near });
  ({ out } = await burst(g));
  assert.deepEqual(by(out, 'ambulance_near'), ['tok-driver@x']);
  assert.equal(out.length, 1);
  result('รถเข้าใกล้ < 500 ม. · 8 คำขอพร้อมกัน', 'ผู้แจ้งได้ “รถใกล้ถึง” 1 ครั้ง', out);

  // 5. จบ → ผู้แจ้งครั้งเดียว
  g.setIncident({ ...base, status: 'resolved', statusStep: 5, assignedAmbulanceId: 'AMB-1', assignedUnits: [u1, u2], ambulanceNearSceneAt: near });
  ({ out } = await burst(g));
  assert.deepEqual(by(out, 'resolved'), ['tok-driver@x']);
  assert.equal(out.length, 1);
  result('เคสจบ · 8 คำขอพร้อมกัน', 'ผู้แจ้งได้ “เคสเสร็จสิ้น” 1 ครั้ง', out);

  // 6. เรียกซ้ำอีก = ไม่มีอะไรส่ง
  ({ out } = await burst(g));
  assert.equal(out.length, 0);
  result('เรียกซ้ำหลังทุกอย่างส่งแล้ว · 8 คำขอ', 'ไม่ส่งซ้ำ', out);
});

test('[S19] เคสเก่าที่มีอยู่ก่อนเปิดระบบแจ้งเตือน ถูกแก้ครั้งแรก: จดสถานะเงียบๆ ไม่ส่งย้อนหลัง', () => {
  const old = { status: 'assigned', assignedAmbulanceId: 'AMB-1', createdAt: '2026-01-01T00:00:00Z' };
  const plan = planNotifications(old, {}, Date.parse('2026-09-30T00:00:00Z'), Date.parse('2026-01-01T00:00:00Z'));
  assert.equal(plan.events.length, 0);
  assert.equal(plan.changed, true);
});
