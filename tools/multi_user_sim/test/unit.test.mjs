// ตรวจว่าการคำนวณของตัวจำลองตรงกับแอป Dart (ค่าจริงจาก latlong2 ใน fixtures)
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { appHospitalDistanceKm, vincentyMeters, findNearestHospital, hospitalsSortedByDistance } from '../src/geo.mjs';
import { bangkokIso, parseDartIso, isLocalNoOffset, isUtcZ } from '../src/timefmt.mjs';
import { validateIncidentDoc, buildSosIncidentMap, firestoreMapFor } from '../src/model.mjs';
import { estimateCost, buildConfig } from '../src/cli.mjs';
import { assertSimId, SafetyError } from '../src/firebase.mjs';

const golden = JSON.parse(readFileSync(new URL('./fixtures/latlong2_golden.json', import.meta.url)));

test('ระยะทาง รพ. ตรงกับ latlong2 ของแอป (Vincenty ปัดเป็น กม. เต็ม)', () => {
  for (const g of golden) {
    const p = { latitude: g.a[0], longitude: g.a[1] };
    const h = { latitude: g.b[0], longitude: g.b[1] };
    assert.ok(Math.abs(vincentyMeters(g.a[0], g.a[1], g.b[0], g.b[1]) - g.rawM) < 1e-6, JSON.stringify(g));
    assert.equal(appHospitalDistanceKm(p, h), g.km);
    const [row] = hospitalsSortedByDistance([{ ...h, hospitalId: 'X', isErAvailable: true }], p);
    assert.equal(row.etaMinutes, g.eta);
  }
});

test('ระยะเท่ากันเลือกตามลำดับ doc id และ ER ว่างมาก่อน', () => {
  const p = { latitude: 18.8, longitude: 98.97 };
  const a = { hospitalId: 'A', latitude: 18.8, longitude: 98.971, isErAvailable: true };
  const b = { hospitalId: 'B', latitude: 18.8, longitude: 98.969, isErAvailable: true };
  assert.equal(findNearestHospital([a, b], p).profile.hospitalId, 'A');
  assert.equal(findNearestHospital([{ ...a, isErAvailable: false }, b], p).profile.hospitalId, 'B');
});

test('รูปแบบเวลาเหมือน Dart toIso8601String', () => {
  const d = new Date(Date.UTC(2026, 8, 29, 1, 2, 3, 456));
  assert.equal(bangkokIso(d), '2026-09-29T08:02:03.456');
  assert.ok(isLocalNoOffset(bangkokIso(d)));
  assert.ok(isUtcZ(d.toISOString()));
  assert.equal(parseDartIso('2026-09-29T08:02:03.456'), d.getTime());
  assert.equal(parseDartIso('2026-09-29T01:02:03.456Z'), d.getTime());
});

test('เอกสารเคสจำลองผ่านการตรวจรูปแบบแอป', () => {
  const nearest = { profile: { hospitalId: 'SIM-HOSP-1', hospitalName: 'x', latitude: 18.8, longitude: 98.9 }, distanceKm: 3, etaMinutes: 3 };
  const id = 'SIM-Case #AVCB1';
  const map = buildSosIncidentMap({
    id, type: 'อุบัติเหตุทางรถยนต์', severity: 'วิกฤต (Code Red - หมดสติ / บาดเจ็บสาหัส)', description: '', latitude: 18.8,
    longitude: 98.9, address: 'a', photos: [], reporterName: 'r', reporterEmail: 'r@x', reporterPhone: '1', nearest,
    createdAt: new Date(), extra: { simulation: true },
  });
  assert.deepEqual(validateIncidentDoc(id, map), []);
});

test('Firestore mirror ไม่มี array ซ้อน array และไม่เกิน ~201 จุด', () => {
  const routePoints = Array.from({ length: 1500 }, (_, i) => ({ latitude: 18 + i * 1e-4, longitude: 99 }));
  const m = firestoreMapFor({ id: 'SIM-AMB-1', routePoints, sirenActive: true, timestamp: bangkokIso() });
  assert.ok(m.routePoints.every((p) => !Array.isArray(p)));
  assert.ok(m.routePoints.length <= 201);
});

test('กันเขียนเอกสารที่ไม่ใช่ข้อมูลจำลอง', () => {
  assert.throws(() => assertSimId('incident_reports', 'Case #AVCB123'), SafetyError);
  assert.doesNotThrow(() => assertSimId('incident_reports', 'SIM-Case #AVCB123'));
});

test('ค่าเริ่มต้นปลอดภัย: emulator เป็นค่าเริ่มต้น, prod ต้องยืนยัน, topic จริงต้องยืนยันสองชั้น', () => {
  assert.equal(buildConfig({}).target, 'emulator');
  assert.equal(buildConfig({ target: 'prod' }).prodOptIn, false);
  assert.equal(buildConfig({ target: 'prod', 'real-topic': true }).realTopic, false);
  assert.equal(buildConfig({ target: 'prod', 'with-mqtt': true }).withMqtt, true);
  assert.equal(buildConfig({ target: 'prod' }).withMqtt, false);
  const est = estimateCost(buildConfig({}), 'all');
  assert.ok(est.total.writes > 0 && est.total.reads < 50000);
});
