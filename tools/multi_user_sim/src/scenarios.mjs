// สถานการณ์ทดสอบหลายผู้ใช้พร้อมกัน — ทุกผู้ใช้จำลองมี Firebase app แยกกัน (เหมือนมือถือคนละเครื่อง)
// ผลแต่ละข้อ: pass/fail (ต้องเป็นจริงเสมอ) หรือ measure (วัดค่า — แอปไม่ได้บังคับฝั่งเซิร์ฟเวอร์)
import { COLL, parseHospital, validateIncidentDoc, hospitalToMap, isClosed, isValidPair } from './model.mjs';
import { findNearestHospital, haversineMeters, fallbackRoute, moveToward, offsetPoint, bearingDeg } from './geo.mjs';
import {
  createIncident,
  dispatchIncident,
  selfAccept,
  updateStep,
  updateEta,
  markNearScene,
  closeByHospital,
  busyIdsFrom,
  attachIncidentCache,
} from './ops.mjs';
import { FleetPublisher, FleetSubscriber, startLocalBroker, topicFor, APP_BROKER } from './mqtt.mjs';
import { bangkokIso } from './timefmt.mjs';
import { nowMs, sleep, atTime, waitFor, stats, makeRng } from './util.mjs';
import { unitsOf, vehicleCountOf } from './model.mjs';
import { where, query, collection } from 'firebase/firestore';

const SEED_HOSPITALS = [
  { hospitalId: 'SIM-HOSP-1', hospitalName: 'โรงพยาบาลจำลอง 1 (ในเมือง)', latitude: 18.7883, longitude: 98.9853 },
  { hospitalId: 'SIM-HOSP-2', hospitalName: 'โรงพยาบาลจำลอง 2 (แม่ริม)', latitude: 18.9135, longitude: 98.9440 },
  { hospitalId: 'SIM-HOSP-3', hospitalName: 'โรงพยาบาลจำลอง 3 (สันทราย)', latitude: 18.8480, longitude: 99.0680 },
  { hospitalId: 'SIM-HOSP-4', hospitalName: 'โรงพยาบาลจำลอง 4 (หางดง)', latitude: 18.6860, longitude: 98.9190 },
  { hospitalId: 'SIM-HOSP-5', hospitalName: 'โรงพยาบาลจำลอง 5 (สารภี)', latitude: 18.7100, longitude: 99.0350 },
].map((h) => ({ ...h, address: `${h.hospitalName} จ.เชียงใหม่`, erPhone: '053-000000', isErAvailable: true }));

// assert = ทดสอบพฤติกรรมระบบ (นับผ่าน/ไม่ผ่าน) · integrity = ตรวจความถูกต้องของข้อมูลที่ตัวจำลองสร้าง (ไม่นับเป็นผลทดสอบแอป)
// measure = วัดค่า (สิ่งที่แอปไม่ได้บังคับ)
// sid = รหัสสถานการณ์ในรายการ (catalog.mjs) — ไม่ใส่ = ใช้ค่าตั้งต้นของสถานการณ์นั้น (DEFAULT_SID)
const check = (name, ok, detail = '', kind = 'assert', sid = null) => ({ name, kind, ok: kind === 'measure' ? null : Boolean(ok), detail, ...(sid ? { sid } : {}) });
export const DEFAULT_SID = { burst: ['S01'], race: ['S09'], isolation: ['S06'], lifecycle: ['S15'], risks: [] };
// หน้ารายการเคสของโรงพยาบาลซ่อนเคสที่ไกลกว่า alertDistanceKm (ค่าเริ่มต้น 5 กม.)
const AGENCY_LIST_MAX_KM = 5;
const msStats = (arr) => stats(arr);

/** รายชื่อ รพ. ที่แอปใช้ = hospital_profiles ทั้งหมด เรียงตาม doc id (ว่าง = 4 รพ. ตั้งต้นของแอป) */
export async function prepareHospitals(ctx) {
  const setup = ctx.backend.device('setup-hospitals');
  if (ctx.cfg.target === 'emulator' || ctx.cfg.seedHospitals) {
    const n = Math.min(ctx.cfg.hospitals, SEED_HOSPITALS.length);
    for (const h of SEED_HOSPITALS.slice(0, n)) {
      // ระบบจริง: ตั้ง ER ไม่ว่าง ให้เคสจริงของผู้ใช้จริงยังเรียงไปหาโรงพยาบาลจริงก่อน
      const profile = ctx.cfg.target === 'prod' ? { ...h, isErAvailable: false } : h;
      await setup.set(COLL.hospitals, h.hospitalId, hospitalToMap(profile, { simulation: true, simRun: ctx.runId }));
    }
  }
  const snap = await setup.getAll(collection(setup.db, COLL.hospitals));
  const docs = snap.docs.slice().sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
  let hospitals = docs.map((d) => parseHospital(d.data()));
  if (ctx.cfg.target === 'emulator') hospitals = hospitals.filter((h) => h.hospitalId.startsWith('SIM-HOSP-'));
  if (hospitals.length < 2) throw new Error(`ต้องมีโรงพยาบาลอย่างน้อย 2 แห่ง (พบ ${hospitals.length})`);
  ctx.hospitals = hospitals;
  await ctx.backend.closeDevice(setup);
  return hospitals;
}

function randomPointNear(rng, hospital, maxMeters) {
  return offsetPoint(hospital, rng.range(0, 360), rng.range(200, maxMeters));
}

// ---------------------------------------------------------------- 1. burst
export async function burst(ctx) {
  const { backend, cfg, hospitals, runId } = ctx;
  backend.scope = 'burst';
  const rng = makeRng(cfg.seed + 1);
  const N = cfg.reporters;
  const K = Math.min(cfg.observers, hospitals.length);
  const observers = hospitals.slice(0, K).map((h, i) => {
    const d = backend.device(`agency-obs-${i + 1}`, { hospitalId: h.hospitalId });
    return { device: d, hospitalId: h.hospitalId, ...attachIncidentCache(d, { scenario: 'burst', runId }) };
  });
  await sleep(1500); // ให้ listener เชื่อมต่อก่อน (เหมือนแอปเปิดค้างไว้)

  const reporters = Array.from({ length: N }, (_, i) => ({
    device: backend.device(`reporter-${i + 1}`),
    email: `sim-reporter-${i + 1}@routealert.test`,
    name: `ผู้แจ้งจำลอง ${i + 1}`,
    point: randomPointNear(rng, rng.pick(hospitals), 4000),
  }));
  const fireAt = nowMs() + 1500;
  const results = await Promise.all(
    reporters.map(async (r) => {
      await atTime(fireAt);
      try {
        return await createIncident(r.device, { rng, point: r.point, hospitals, reporter: r, runId, extra: { simScenario: 'burst' } });
      } catch (e) {
        return { error: e.message };
      }
    }),
  );
  const created = results.filter((r) => r && r.id);
  const ids = new Set(created.map((r) => r.id));

  // ทุกเครื่องโรงพยาบาลต้องเห็นเคสใหม่ทุกเคส (เหมือนฟังทั้ง collection)
  await waitFor(() => observers.every((o) => [...ids].every((id) => o.firstSeen.has(id))), { timeoutMs: 30000 });

  const verify = backend.device('verifier');
  const snap = await verify.getAll(query(collection(verify.db, COLL.incidents), where('simRun', '==', runId)));
  const docs = snap.docs.filter((d) => ids.has(d.id));
  const docProblems = [];
  const routingProblems = [];
  for (const d of docs) {
    const map = d.data();
    for (const p of validateIncidentDoc(d.id, map)) docProblems.push(`${d.id}: ${p}`);
    const expected = findNearestHospital(hospitals, { latitude: map.latitude, longitude: map.longitude });
    if (map.targetHospitalId !== expected.profile.hospitalId) routingProblems.push(`${d.id}: ได้ ${map.targetHospitalId} ควรเป็น ${expected.profile.hospitalId}`);
    if (map.hospitalDistanceKm !== expected.distanceKm) routingProblems.push(`${d.id}: ระยะ ${map.hospitalDistanceKm} ≠ ${expected.distanceKm}`);
    if (map.eta !== `${expected.etaMinutes} นาที`) routingProblems.push(`${d.id}: eta ${map.eta}`);
  }
  const writeLat = created.map((r) => r.writeEndMs - r.writeStartMs);
  const propagation = [];
  for (const o of observers) for (const r of created) if (o.firstSeen.has(r.id)) propagation.push(o.firstSeen.get(r.id) - r.writeStartMs);
  const perHospital = {};
  for (const d of docs) perHospital[d.data().targetHospitalId] = (perHospital[d.data().targetHospitalId] ?? 0) + 1;

  return {
    name: 'burst',
    title: `แจ้งเหตุพร้อมกัน ${N} คน`,
    params: { reporters: N, observers: K, hospitals: hospitals.length },
    checks: [
      check('ทุกคนส่งสำเร็จ (ไม่มี error)', created.length === N, `${created.length}/${N}`),
      check('ไม่มีเคสหาย (จำนวนเอกสาร = จำนวนที่ส่งสำเร็จ)', docs.length === created.length, `${docs.length}/${created.length}`),
      check('ทุกเครื่องโรงพยาบาลได้รับเคสใหม่ครบทุกเคส (listener แบบเรียลไทม์)', observers.every((o) => [...ids].every((id) => o.firstSeen.has(id))), `${K} เครื่อง × ${created.length} เคส`),
      check('เคสอยู่ในรายการของโรงพยาบาลปลายทาง (ไม่เกินระยะ 5 กม. ที่หน้ารายการกรอง)', docs.every((d) => d.data().hospitalDistanceKm <= AGENCY_LIST_MAX_KM), `ไกลสุด ${Math.max(...docs.map((d) => d.data().hospitalDistanceKm))} กม.`),
      check('เอกสารที่สร้างถูกรูปแบบแอป (fromMap อ่านได้, ครบทุกฟิลด์)', docProblems.length === 0, docProblems.slice(0, 5).join('; '), 'integrity'),
      check('ข้อมูลโรงพยาบาลปลายทางในเอกสารตรงกับการคำนวณซ้ำ', routingProblems.length === 0, routingProblems.slice(0, 5).join('; ') || JSON.stringify(perHospital), 'integrity'),
    ],
    metrics: { writeLatencyMs: msStats(writeLat), propagationMs: msStats(propagation), perHospital },
  };
}

// ---------------------------------------------------------------- 2. race
export async function race(ctx) {
  const { backend, cfg, hospitals, runId } = ctx;
  backend.scope = 'race';
  const rng = makeRng(cfg.seed + 2);
  const M = cfg.ambulances;
  const R = cfg.rounds;
  const reporterDev = backend.device('race-reporter');
  const hospitalDev = backend.device('race-hospital');
  const hospitalCache = attachIncidentCache(hospitalDev, { scenario: 'race', runId });
  const ambulances = Array.from({ length: M }, (_, i) => {
    const d = backend.device(`ambulance-${i + 1}`);
    const unit = { id: `SIM-AMB-R${i + 1}`, plateNumber: `กข ${1000 + i}`, callSign: `กู้ชีพจำลอง R${i + 1}` };
    return { device: d, unit, ...attachIncidentCache(d, { scenario: 'race', runId }) };
  });
  await sleep(1500);

  const legacy = cfg.appLogic === 'legacy';
  let lateCommits = 0;
  const failReasons = {};
  const rounds = [];
  const txMs = [];
  const outcomeCounts = {};
  let contendedRounds = 0;
  for (let r = 0; r < R; r++) {
    const mixed = r % 2 === 1; // รอบคี่: รพ. สั่งจ่ายรถแข่งกับรถกดรับเอง
    const reporter = { email: `sim-reporter-race-${r}@routealert.test`, name: `ผู้แจ้งแข่ง ${r}` };
    // ผู้แจ้งคนละเครื่องทุกรอบ (แอปมี cooldown 2 นาทีต่อเครื่อง)
    const roundReporter = backend.device(`race-reporter-${r}`);
    const c = await createIncident(roundReporter, {
      rng, point: randomPointNear(rng, hospitals[0], 4000), hospitals, reporter, runId, extra: { simScenario: 'race' },
    });
    await backend.closeDevice(roundReporter);
    // รถทุกคันต้อง "เห็น" เคสในรายการก่อนถึงกดรับได้ (เหมือนหน้ารายการเคส)
    await waitFor(() => ambulances.every((a) => a.cache.has(c.id)) && (!mixed || hospitalCache.cache.has(c.id)), { timeoutMs: 20000 });
    const fireAt = nowMs() + 300;
    const contenders = ambulances.map((a) => async () => {
      await atTime(fireAt);
      return { who: a.unit.id, via: 'ambulance', ...(await selfAccept(a.device, c.id, a.unit, busyIdsFrom(a.cache))) };
    });
    if (mixed) {
      const target = ambulances[r % M];
      contenders.push(async () => {
        await atTime(fireAt);
        return {
          who: target.unit.id,
          via: 'hospital',
          // ปุ่ม "ส่งรถพยาบาล" ของ รพ. = คันแรกเท่านั้น
          ...(await dispatchIncident(hospitalDev, c.id, {
            ambulanceId: target.unit.id, ambulancePlate: target.unit.plateNumber, ambulanceCallSign: target.unit.callSign,
            onlyIfUnassigned: true,
          })),
        };
      });
    }
    const outcomes = await Promise.all(contenders.map((f) => f()));
    // รอให้ transaction ที่แอปเลิกรอ (timeout) จบจริงก่อนอ่านผล — ถ้า commit ทีหลัง แอปจะเห็นผ่าน snapshot
    for (const o of outcomes) {
      if (!o.ok && o.settled && (await o.settled)) {
        o.lateCommit = true;
        lateCommits++;
      }
      if (!o.ok && o.error) failReasons[o.error] = (failReasons[o.error] ?? 0) + 1;
    }
    for (const o of outcomes) if (o.attempts > 0 && o.txMs != null) txMs.push(o.txMs);
    for (const o of outcomes) outcomeCounts[o.outcome] = (outcomeCounts[o.outcome] ?? 0) + 1;
    // แย่งกันจริง = มีผู้เข้า transaction มากกว่า 1 ราย (ไม่ใช่แพ้ตั้งแต่อ่านก่อน)
    if (outcomes.filter((o) => o.attempts > 0).length > 1) contendedRounds++;
    const finalMap = (await reporterDev.get(COLL.incidents, c.id, { server: true })).data();
    const docUnits = new Set(unitsOf(finalMap).map((u) => u.unitId));
    // ทุกคันที่แอปบอกว่าสำเร็จต้องอยู่ในเคสจริง และคันที่บอกว่าไม่สำเร็จต้องไม่อยู่ (ไม่มีการเขียนทับ)
    // legacy: ได้คันเดียว / fixed: เคสเดียวรับได้หลายคัน (รพ. ส่งคันแรกเท่านั้น)
    const okUnits = new Set(outcomes.filter((o) => o.ok || o.lateCommit).map((o) => o.who));
    const hospitalOk = outcomes.filter((o) => o.via === 'hospital' && o.ok && o.outcome !== 'noop');
    const sameSet = okUnits.size === docUnits.size && [...okUnits].every((u) => docUnits.has(u));
    const countOk = legacy ? docUnits.size === 1 : finalMap.assignedVehicleCount === vehicleCountOf(finalMap);
    const primary = finalMap.assignedAmbulanceId;
    rounds.push({
      round: r,
      mixed,
      vehicles: docUnits.size,
      finalAssigned: primary,
      assignedBy: finalMap.assignedBy,
      ok:
        sameSet && countOk && docUnits.size >= 1 &&
        finalMap.status === 'assigned' && finalMap.statusStep === 1 &&
        (hospitalOk.length
          ? hospitalOk.length === 1 && primary === hospitalOk[0].who && finalMap.assignedBy === 'hospital'
          : finalMap.assignedBy === 'ambulance'),
      outcomes: outcomes.map((o) => `${o.via}:${o.who}=${o.outcome}${o.lateCommit ? '(commit ทีหลัง)' : ''}${o.error ? `[${o.error}]` : ''}`),
      docUnits: [...docUnits],
    });
    // คันที่อยู่ในเคสกดรับซ้ำ = สำเร็จแต่ไม่เขียน, รพ. สั่งจ่าย "คันแรก" ทับเคสที่มีรถแล้ว = ไม่เขียน
    const inCase = ambulances.find((a) => docUnits.has(a.unit.id));
    const again = await dispatchIncident(inCase.device, c.id, { ambulanceId: inCase.unit.id, ambulancePlate: inCase.unit.plateNumber, selfAccepted: true });
    const other = ambulances.find((a) => !docUnits.has(a.unit.id)) ?? ambulances.find((a) => a.unit.id !== primary);
    const overwrite = await dispatchIncident(hospitalDev, c.id, { ambulanceId: `${other.unit.id}-X`, ambulancePlate: `${other.unit.plateNumber}X`, onlyIfUnassigned: true });
    const after = (await reporterDev.get(COLL.incidents, c.id, { server: true })).data();
    rounds[rounds.length - 1].repeatOk = again.ok && again.outcome === 'noop';
    rounds[rounds.length - 1].noOverwrite = !overwrite.ok && JSON.stringify(unitsOf(after)) === JSON.stringify(unitsOf(finalMap));
    // ปิดรอบ: ส่งผู้ป่วยถึง รพ. เพื่อให้รถทุกคันว่างในรอบถัดไป
    await updateStep(inCase.device, c.id, 'resolved', 5);
    await waitFor(() => ambulances.every((a) => isClosed(a.cache.get(c.id) ?? { status: 'resolved' })), { timeoutMs: 10000 });
  }

  // ปิดเคสแล้วสั่งจ่ายรถไม่ได้อีก
  const closeReporter = backend.device('race-reporter-close');
  const closedCase = await createIncident(closeReporter, {
    rng, point: randomPointNear(rng, hospitals[0], 3000), hospitals, runId,
    reporter: { email: 'sim-reporter-race-close@routealert.test', name: 'ผู้แจ้งปิดเคส' }, extra: { simScenario: 'race' },
  });
  await closeByHospital(hospitalDev, closedCase.id);
  const afterClose = await dispatchIncident(hospitalDev, closedCase.id, {
    ambulanceId: ambulances[0].unit.id, ambulancePlate: ambulances[0].unit.plateNumber,
  });

  return {
    name: 'race',
    title: `รถ ${M} คันกดรับเคสเดียวกันพร้อมกัน (${R} รอบ)`,
    params: { ambulances: M, rounds: R, appLogic: cfg.appLogic },
    checks: [
      check(legacy
        ? 'ทุกรอบมีผู้ชนะคนเดียว และเอกสารตรงกับผู้ชนะ'
        : 'ทุกคันที่สำเร็จอยู่ในเคสจริง นับจำนวนคันถูก และ รพ. ได้คันแรกเฉพาะตอนเคสยังว่าง',
        rounds.every((x) => x.ok),
        rounds.filter((x) => !x.ok).map((x) => `รอบ ${x.round}: ${x.outcomes.join(', ')} → ในเอกสาร ${x.docUnits.join('/')}`).join(' | ') ||
          `จำนวนรถต่อเคส: ${rounds.map((x) => x.vehicles).join('/')}`),
      check('คันที่อยู่ในเคสกดรับซ้ำ = สำเร็จโดยไม่เขียนซ้ำ', rounds.every((x) => x.repeatOk),
        `${rounds.filter((x) => x.repeatOk).length}/${R} รอบ ได้ "อยู่ในเคสแล้ว" และไม่มีการเขียนเพิ่ม`),
      check('โรงพยาบาลสั่งจ่าย "คันแรก" ทับเคสที่มีรถแล้วไม่ได้', rounds.every((x) => x.noOverwrite),
        `${rounds.filter((x) => x.noOverwrite).length}/${R} รอบ ถูกปฏิเสธและรายชื่อรถในเคสไม่เปลี่ยน`),
      check('เคสที่โรงพยาบาลปิดแล้ว สั่งจ่ายรถไม่ได้', !afterClose.ok, `สั่งจ่ายหลังปิดเคสได้ผล: ${afterClose.outcome}`),
      check('มีการแย่งกันจริงใน transaction (ผู้เข้า transaction > 1 รายต่อรอบ)', contendedRounds === R, `${contendedRounds}/${R} รอบ · ${JSON.stringify(outcomeCounts)}`),
      check('transaction ที่แอปรายงานว่าไม่สำเร็จ', null,
        `${Object.values(failReasons).reduce((a, b) => a + b, 0)} ครั้ง ${JSON.stringify(failReasons)} · commit ทีหลังหลังแอปเลิกรอ ${lateCommits} ครั้ง`, 'measure'),
      check('รอบที่ รพ. แข่งกับรถ (assignedBy ตรงกับฝ่ายที่ชนะ)', rounds.filter((x) => x.mixed).every((x) => x.ok), `${rounds.filter((x) => x.mixed).length} รอบ`),
    ],
    metrics: { transactionMs: msStats(txMs), outcomeCounts, contendedRounds, rounds: rounds.map(({ round, mixed, vehicles, finalAssigned, assignedBy }) => ({ round, mixed, vehicles, finalAssigned, assignedBy })) },
  };
}

// ---------------------------------------------------------------- 3. isolation
export async function isolation(ctx) {
  const { backend, cfg, hospitals, runId } = ctx;
  backend.scope = 'isolation';
  const rng = makeRng(cfg.seed + 3);
  const perHospital = cfg.casesPerHospital;
  const agencies = hospitals.map((h, i) => {
    const d = backend.device(`agency-${i + 1}`, { hospitalId: h.hospitalId });
    return { hospitalId: h.hospitalId, device: d, ...attachIncidentCache(d, { scenario: 'isolation', runId }) };
  });
  const legacy = backend.device('agency-legacy'); // บัญชีเก่าไม่มี hospitalId → เห็นทุกเคส
  const legacyCache = attachIncidentCache(legacy, { scenario: 'isolation', runId });
  await sleep(1500);

  const jobs = [];
  for (const h of hospitals) {
    for (let k = 0; k < perHospital; k++) {
      const dev = backend.device(`iso-reporter-${h.hospitalId}-${k}`);
      jobs.push(async () =>
        createIncident(dev, {
          rng, point: randomPointNear(rng, h, 2500), hospitals, runId,
          reporter: { email: `sim-reporter-iso-${h.hospitalId}-${k}@routealert.test`.toLowerCase(), name: `ผู้แจ้ง ${h.hospitalId}-${k}` },
          extra: { simScenario: 'isolation' },
        }),
      );
    }
  }
  const created = await Promise.all(jobs.map((f) => f()));
  const expectedBy = new Map(hospitals.map((h) => [h.hospitalId, new Set()]));
  for (const c of created) expectedBy.get(c.map.targetHospitalId)?.add(c.id);
  const allIds = new Set(created.map((c) => c.id));
  await waitFor(() => [...allIds].every((id) => legacyCache.firstSeen.has(id)) && agencies.every((a) => [...allIds].every((id) => a.firstSeen.has(id))), { timeoutMs: 30000 });

  // ตัวกรองหน้า agency: targetHospitalId == hospitalId ของบัญชี (null = ไม่กรอง)
  const leaks = [];
  const misses = [];
  for (const a of agencies) {
    const visible = new Set([...a.cache.values()].filter((i) => i.targetHospitalId === a.hospitalId).map((i) => i.id));
    for (const id of visible) if (!expectedBy.get(a.hospitalId).has(id)) leaks.push(`${a.hospitalId} เห็น ${id}`);
    for (const id of expectedBy.get(a.hospitalId)) if (!visible.has(id)) misses.push(`${a.hospitalId} ไม่เห็น ${id}`);
  }
  const legacyVisible = [...legacyCache.cache.values()].filter((i) => allIds.has(i.id)).length;
  const distribution = Object.fromEntries([...expectedBy].map(([k, v]) => [k, v.size]));

  return {
    name: 'isolation',
    title: `แยกข้อมูลโรงพยาบาล ${hospitals.length} แห่ง`,
    params: { hospitals: hospitals.length, casesPerHospitalArea: perHospital, total: created.length },
    checks: [
      check('ทุกเครื่องโรงพยาบาลได้รับเคสที่แจ้งพร้อมกันครบ', agencies.every((a) => [...allIds].every((id) => a.firstSeen.has(id))), `${agencies.length} เครื่อง × ${created.length} เคส`),
      check('เคสกระจายไปทุกโรงพยาบาลตามพื้นที่', Object.values(distribution).every((n) => n > 0), JSON.stringify(distribution)),
      check('ตัวกรองโรงพยาบาล: ไม่เห็นเคสของโรงพยาบาลอื่น', leaks.length === 0, leaks.slice(0, 5).join('; '), 'integrity'),
      check('ตัวกรองโรงพยาบาล: เห็นเคสของตัวเองครบ', misses.length === 0, misses.slice(0, 5).join('; '), 'integrity'),
      check('บัญชีเก่าที่ไม่มี hospitalId เห็นทุกเคส', legacyVisible === created.length, `${legacyVisible}/${created.length}`, 'integrity'),
    ],
    metrics: { distribution },
  };
}

// ---------------------------------------------------------------- 4. lifecycle
/** รถพยาบาลจำลอง 1 คัน: ทำตามหน้า ambulance_home_screen (เคสล่าสุดที่เป็นของหน่วยนี้, ETA, ใกล้ถึง, ขั้นสถานะ) */
class AmbulanceAgent {
  constructor(ctx, idx, start, publisher) {
    this.ctx = ctx;
    this.device = ctx.backend.device(`lc-ambulance-${idx}`);
    this.unit = { id: `SIM-AMB-${idx}`, plateNumber: `ฉจ ${2000 + idx}`, callSign: `กู้ชีพจำลอง ${idx}` };
    this.pos = start;
    this.publisher = publisher;
    this.lastEta = null; // { key, at, eta, meters }
    this.nearReported = new Set();
    this.lastApproachAt = 0;
    this.writes = 0;
    this.stepWritten = new Map(); // คนในแอปกดปุ่มครั้งเดียว — กันเขียนซ้ำระหว่างรอ snapshot กลับมา
    const { cache } = attachIncidentCache(this.device, { runId: ctx.runId, scenario: 'lifecycle' });
    this.cache = cache;
  }

  activeCase() {
    let best = null;
    for (const i of this.cache.values()) {
      if (isClosed(i) || !i.units.some((u) => u.unitId === this.unit.id)) continue;
      if (!best || i.createdAt > best.createdAt) best = i;
    }
    return best;
  }

  vehicle(active, route) {
    const step = active?.statusStep ?? 1;
    return {
      id: this.unit.id,
      callSign: this.unit.callSign,
      latitude: this.pos.latitude,
      longitude: this.pos.longitude,
      speed: 60,
      heading: this.heading ?? 0,
      plateNumber: this.unit.plateNumber,
      emergencyType: active?.type ?? 'ผู้ป่วยวิกฤตฉุกเฉิน (Red Code)',
      sirenActive: true,
      timestamp: bangkokIso(new Date()),
      routePoints: active ? route?.points ?? null : null,
      turnIntent: active ? route?.nextTurnInstruction ?? null : null,
      destinationName: active ? (step >= 3 ? 'โรงพยาบาลมหาราชนคร (ER)' : active.address || 'จุดเกิดเหตุ') : 'ลาดตระเวน (ยังไม่มีเคส)',
      simulation: true,
    };
  }

  async tick() {
    const { cfg } = this.ctx;
    const scale = cfg.timeScale;
    const active = this.activeCase();
    let route = null;
    if (active) {
      const step = active.statusStep;
      const dest = step >= 3
        ? { latitude: active.hospitalLatitude ?? this.pos.latitude, longitude: active.hospitalLongitude ?? this.pos.longitude }
        : { latitude: active.latitude, longitude: active.longitude };
      const before = { ...this.pos };
      if (step !== 2) this.pos = moveToward(this.pos, dest, cfg.stepMeters);
      if (haversineMeters(before, this.pos) >= 2) this.heading = bearingDeg(before, this.pos);
      route = fallbackRoute(this.pos, dest);
      const distKm = route.distanceMeters / 1000;
      const eta = Math.ceil(route.durationSeconds / 60);
      this.phase = 'eta';
      await this.maybeSendEta(active, step >= 3 ? 'hospital' : 'scene', eta, route.distanceMeters, scale);
      // ใกล้ถึงจุดเกิดเหตุ < 500 ม. — ครั้งเดียวต่อเคส
      if (active.status === 'assigned' && step <= 1 && active.ambulanceNearSceneAt == null && distKm <= 0.5 && !this.nearReported.has(active.id)) {
        this.nearReported.add(active.id);
        this.phase = 'near';
        await markNearScene(this.device, active.id, eta).then(() => this.writes++).catch(() => this.nearReported.delete(active.id));
      }
      const once = async (status, s) => {
        if ((this.stepWritten.get(active.id) ?? -1) >= s) return;
        this.stepWritten.set(active.id, s);
        this.phase = `step:${status}`;
        const r = await updateStep(this.device, active.id, status, s);
        if (process.env.SIM_DEBUG) console.error(`[${this.unit.id}] ${active.id.slice(-6)} ${status} → ${r}`);
        // ไม่สำเร็จ (เน็ต/timeout) = ปุ่มยังอยู่ เจ้าหน้าที่กดใหม่ได้
        if (r === 'failed') this.stepWritten.delete(active.id);
        this.writes++;
      };
      if (step <= 1 && route.distanceMeters <= 30) {
        await once('at_scene', 2);
      } else if (step === 2) {
        this.phase = 'scene-wait';
        if ((this.stepWritten.get(active.id) ?? -1) < 3) await sleep(cfg.sceneMs / scale);
        await once('transporting', 3);
      } else if (step >= 3 && route.distanceMeters <= 30) {
        await once('resolved', 5);
      } else if (step === 3 && distKm <= 1.5 && nowMs() - this.lastApproachAt >= 4000 / scale) {
        // แอปเขียน approaching_er ซ้ำทุกครั้งที่คำนวณเส้นทางใหม่ (จำกัด 4 วิ)
        this.lastApproachAt = nowMs();
        await updateStep(this.device, active.id, 'approaching_er', 4); this.writes++;
      }
    }
    this.phase = 'publish';
    // แอปส่งตำแหน่งแบบไม่รอ PUBACK (publishMessage ไม่มี await) — ไม่ให้ broker ที่ช้าถ่วงรอบ GPS
    if (this.publisher) this.publisher.publish(this.vehicle(active, route)).catch(() => {});
  }

  async maybeSendEta(active, target, eta, meters, scale) {
    if (active.statusStep === 2) return;
    const key = `${active.id}|${target}`;
    // routeMode=fallback = OSRM ล่ม: แอปถือว่าเป็นค่าประมาณ ส่งครั้งเดียวต่อช่วงแล้วหยุด
    // routeMode=osrm (ค่าเริ่มต้น) = จำลองว่าได้เส้นทางจริง (ระยะใช้เส้นตรงแทน) ส่งตามรอบปกติ
    if (this.ctx.cfg.routeMode === 'fallback' && this.lastEta?.key === key) return;
    const t = nowMs();
    const last = this.lastEta;
    const since = last ? t - last.at : null;
    const changed = !last || eta !== last.eta || Math.abs((last.meters ?? -100000) - meters) >= 150;
    const due = !last || key !== last.key || (changed && since >= 10000 / scale) || since >= 60000 / scale;
    if (!due) return;
    this.lastEta = { key, at: t, eta, meters };
    await updateEta(this.device, active.id, { etaMinutes: eta, distanceMeters: meters, target });
    this.writes++;
  }
}

/** โรงพยาบาลจำลอง: เห็นเฉพาะเคสของตัวเอง สั่งจ่ายรถว่างที่ใกล้ที่สุด (กองรถจาก MQTT หักรถที่ติดเคส) */
class HospitalAgent {
  constructor(ctx, hospital, fleetSource, rng) {
    this.ctx = ctx;
    this.hospital = hospital;
    this.rng = rng;
    this.device = ctx.backend.device(`lc-hospital-${hospital.hospitalId}`);
    this.fleetSource = fleetSource;
    this.handled = new Set(); // เจ้าหน้าที่กดสั่งจ่ายครั้งเดียวต่อเคส
    // แอปอัปเดต cache ในเครื่องก่อน transaction (optimistic) เครื่องเดียวกันจึงนับรถคันนั้น
    // ว่าติดเคสทันที — เก็บไว้จนกว่า snapshot จากเซิร์ฟเวอร์จะตามมา
    this.optimisticBusy = new Map(); // unitId -> incidentId
    this.noticedAt = new Map(); // incidentId -> { at, delay }
    this.dispatches = [];
    const { cache } = attachIncidentCache(this.device, { runId: ctx.runId, scenario: 'lifecycle' });
    this.cache = cache;
  }

  humanDelay() {
    return this.ctx.cfg.dispatchDelayMs * (0.5 + this.rng.next());
  }

  async tick() {
    const busy = busyIdsFrom(this.cache);
    for (const [unit, incId] of this.optimisticBusy) {
      const seen = this.cache.get(incId);
      if (seen && (seen.units.some((u) => u.unitId === unit) || isClosed(seen))) this.optimisticBusy.delete(unit);
      else busy.add(unit);
    }
    const now = nowMs();
    for (const inc of this.cache.values()) {
      if (inc.targetHospitalId !== this.hospital.hospitalId) continue;
      if (inc.status !== 'pending' || inc.units.length || this.handled.has(inc.id)) continue;
      // เจ้าหน้าที่ต้องเห็นเคส เปิดหน้ารายละเอียด แล้วกดปุ่ม — ไม่ได้สั่งทันทีที่ข้อมูลมาถึง
      // ใช้เวลาไม่เท่ากันทุกครั้ง (0.5–1.5 เท่าของ --dispatch-delay-ms, สุ่มแบบกำหนด seed)
      if (!this.noticedAt.has(inc.id)) this.noticedAt.set(inc.id, { at: now, delay: this.humanDelay() });
      const n = this.noticedAt.get(inc.id);
      if (now - n.at < n.delay) continue;
      const fleet = this.fleetSource().filter((v) => this.ctx.cfg.dispatch === 'web' || !busy.has(v.id));
      if (fleet.length === 0) continue;
      let nearest = fleet[0];
      let best = haversineMeters(inc, nearest);
      for (const v of fleet.slice(1)) {
        const d = haversineMeters(inc, v);
        if (d < best) { nearest = v; best = d; }
      }
      this.handled.add(inc.id);
      this.optimisticBusy.set(nearest.id, inc.id);
      const r = await dispatchIncident(this.device, inc.id, {
        ambulanceId: nearest.id,
        ambulancePlate: nearest.plateNumber,
        ambulanceCallSign: nearest.callSign,
        onlyIfUnassigned: true,
      });
      this.dispatches.push({ id: inc.id, unit: nearest.id, ...r });
      if (!r.ok) {
        // แอปแค่ขึ้นข้อความ ไม่ลองใหม่เอง — จำลองว่าเจ้าหน้าที่กดส่งใหม่หลังรอเท่าเดิม
        this.handled.delete(inc.id);
        this.noticedAt.set(inc.id, { at: nowMs(), delay: this.humanDelay() });
        this.optimisticBusy.delete(nearest.id); // แอป revert cache เมื่อ transaction ล้ม
      }
      busy.add(nearest.id);
    }
  }
}

export async function lifecycle(ctx) {
  const { backend, cfg, hospitals, runId } = ctx;
  backend.scope = 'lifecycle';
  const rng = makeRng(cfg.seed + 4);
  const C = cfg.cases;
  const A = cfg.lifecycleAmbulances ?? C;

  // กองรถ: MQTT (มือถือ) หรือ Firestore emergency_fleet (เว็บ) — ในตัวจำลองใช้ MQTT เสมอเมื่อเปิด
  let broker = null;
  let brokerUrl = null;
  if (cfg.withMqtt) {
    if (cfg.target === 'emulator') {
      broker = await startLocalBroker();
      brokerUrl = broker.url;
    } else {
      brokerUrl = cfg.brokerUrl ?? APP_BROKER;
    }
  }
  const topic = topicFor(cfg, runId);
  const subscribers = [];
  const directFleet = new Map();

  const ambulances = [];
  for (let i = 1; i <= A; i++) {
    const start = randomPointNear(rng, rng.pick(hospitals), 5000);
    const pub = brokerUrl ? await FleetPublisher.create(brokerUrl, topic, runId) : null;
    ambulances.push(new AmbulanceAgent(ctx, i, start, pub));
  }
  const agencies = [];
  for (const h of hospitals) {
    let source;
    if (brokerUrl) {
      const sub = await FleetSubscriber.create(brokerUrl, topic, runId);
      subscribers.push(sub);
      source = () => sub.activeFleet().filter((v) => v.id.startsWith('SIM-AMB-'));
    } else {
      source = () => [...directFleet.values()];
    }
    agencies.push(new HospitalAgent(ctx, h, source, makeRng(cfg.seed + 100 + agencies.length)));
  }

  // ผู้เฝ้าดู: ประวัติทุกเคส (ตรวจสถานะถอยหลัง, เปลี่ยนรถ, ออกจากสถานะจบ, รถถือ 2 เคส)
  const monitor = backend.device('lc-monitor');
  const history = new Map();
  let maxOpenPerUnit = 0;
  const doubleAssign = new Set();
  const monitorCache = attachIncidentCache(monitor, {
    runId,
    scenario: 'lifecycle',
    onChange: (id, inc, raw, t) => {
      const h = history.get(id) ?? [];
      h.push({ t, status: inc.status, step: inc.statusStep, unit: inc.assignedAmbulanceId, near: raw.ambulanceNearSceneAt ?? null });
      history.set(id, h);
    },
  });
  const auditOpen = () => {
    const perUnit = new Map();
    for (const i of monitorCache.cache.values()) {
      if (isClosed(i)) continue;
      for (const u of i.units) perUnit.set(u.unitId, (perUnit.get(u.unitId) ?? []).concat(i.id));
    }
    for (const [unit, list] of perUnit) {
      maxOpenPerUnit = Math.max(maxOpenPerUnit, list.length);
      if (list.length > 1) doubleAssign.add(`${unit}: ${list.join(', ')}`);
    }
  };
  await sleep(1500);

  let running = true;
  const loops = [
    ...ambulances.map((a) => (async () => {
      while (running) {
        const t0 = nowMs();
        try { await a.tick(); } catch (e) { ctx.log(`ambulance ${a.unit.id}: ${e.message}`); }
        if (process.env.SIM_DEBUG && nowMs() - t0 > 3000) console.error(`[slow tick ${a.unit.id}] ${Math.round(nowMs() - t0)}ms at ${a.phase}`);
        if (!brokerUrl) directFleet.set(a.unit.id, a.vehicle(a.activeCase(), null));
        await sleep(cfg.tickMs);
      }
    })()),
    ...agencies.map((g) => (async () => {
      while (running) {
        try { await g.tick(); } catch (e) { ctx.log(`hospital ${g.hospital.hospitalId}: ${e.message}`); }
        await sleep(cfg.tickMs);
      }
    })()),
    (async () => { while (running) { auditOpen(); await sleep(100); } })(),
  ];

  // ผู้แจ้งเหตุ C คน แจ้งพร้อมกัน แต่ละคนฟังเคสของตัวเอง (เหมือนหน้าติดตามเคส)
  await sleep(brokerUrl ? 2500 : 500); // ให้รถประกาศตำแหน่งก่อน
  const reporters = Array.from({ length: C }, (_, i) => ({
    device: backend.device(`lc-reporter-${i + 1}`),
    email: `sim-reporter-lc-${i + 1}@routealert.test`,
    name: `ผู้แจ้งครบวงจร ${i + 1}`,
  }));
  // เวลาที่ "เจ้าของเคส" เห็น (แต่ละเครื่องผู้แจ้งเก็บของตัวเอง ไม่ใช่เครื่องที่เร็วที่สุด)
  const seen = new Map(); // id -> { assigned, eta, near, at_scene, transporting, resolved }
  for (const r of reporters) {
    attachIncidentCache(r.device, {
      runId,
      scenario: 'lifecycle',
      onChange: (id, inc, raw, t) => {
        if (inc.reporterEmail.trim().toLowerCase() !== r.email) return;
        const s = seen.get(id) ?? {};
        s.last = `${inc.status}/${inc.statusStep}`;
        s.snaps = (s.snaps ?? 0) + 1;
        if (inc.assignedAmbulanceId && !s.assigned) s.assigned = t;
        if (raw.ambulanceEtaUpdatedAt && !s.eta) s.eta = t;
        if (raw.ambulanceNearSceneAt && !s.near) s.near = t;
        for (const st of ['at_scene', 'transporting', 'resolved']) if (inc.status === st && !s[st]) s[st] = t;
        seen.set(id, s);
      },
    });
  }
  await sleep(1000);
  const fireAt = nowMs() + 500;
  const created = await Promise.all(reporters.map(async (r) => {
    await atTime(fireAt);
    return createIncident(r.device, {
      rng, point: randomPointNear(rng, rng.pick(hospitals), 4000), hospitals, reporter: r, runId, extra: { simScenario: 'lifecycle' },
    });
  }));
  const ids = created.map((c) => c.id);
  const done = await waitFor(
    () => ids.every((id) => isClosed(monitorCache.cache.get(id) ?? { status: 'pending' })),
    { timeoutMs: cfg.lifecycleTimeoutMs, intervalMs: 200 },
  );
  running = false;
  await Promise.all(loops);
  auditOpen();
  if (process.env.SIM_DEBUG) {
    for (const a of ambulances) {
      const act = a.activeCase();
      const mine = [...a.cache.values()].filter((i) => i.units.some((u) => u.unitId === a.unit.id));
      console.error(`[end ${a.unit.id}] active=${act ? `${act.id.slice(-6)} ${act.status}/${act.statusStep}` : 'none'} mine=${mine.map((i) => `${i.id.slice(-6)}:${i.status}`).join(',')} cache=${a.cache.size} stepWritten=${JSON.stringify([...a.stepWritten].map(([k, v]) => [k.slice(-6), v]))}`);
    }
    for (const i of monitorCache.cache.values()) console.error(`[monitor] ${i.id.slice(-6)} ${i.status}/${i.statusStep} units=${i.units.map((u) => u.unitId).join('+')}`);
  }
  // มอนิเตอร์เห็นจบแล้ว ให้เวลาเครื่องผู้แจ้งตามทัน (ผู้ใช้จริงก็เห็นช้ากว่ากันเล็กน้อย)
  const ownerFull = (id) => { const x = seen.get(id); return x?.assigned && x?.eta && x?.near && x?.resolved; };
  const ownersCaughtUp = await waitFor(() => ids.every(ownerFull), { timeoutMs: 10000, intervalMs: 200 });
  const ownerMissing = ids.filter((id) => !ownerFull(id)).map((id) => {
    const x = seen.get(id) ?? {};
    const miss = ['assigned', 'eta', 'near', 'resolved'].filter((k) => !x[k]).join('+');
    return `${id.slice(-6)} ขาด ${miss} (เห็นล่าสุด ${x.last ?? '–'}, ${x.snaps ?? 0} snapshot)`;
  });

  // ประวัติแต่ละเคส
  const regress = [];
  const reassigned = [];
  const leftTerminal = [];
  const nearTwice = [];
  const badPairs = [];
  for (const id of ids) {
    const h = history.get(id) ?? [];
    let maxStep = -1;
    let unit = null;
    let terminal = false;
    let near = null;
    for (const e of h) {
      if (!isValidPair(e.status, e.step)) badPairs.push(`${id}: ${e.status}/${e.step}`);
      if (e.step < maxStep && e.status !== 'cancelled') regress.push(`${id}: ${maxStep}→${e.step}`);
      maxStep = Math.max(maxStep, e.step);
      if (unit && e.unit && e.unit !== unit) reassigned.push(`${id}: ${unit}→${e.unit}`);
      unit = e.unit ?? unit;
      if (terminal && !isClosed(e)) leftTerminal.push(`${id}: → ${e.status}`);
      terminal = terminal || isClosed(e);
      if (near && e.near && e.near !== near) nearTwice.push(id);
      near = e.near ?? near;
    }
  }
  const finalStates = ids.map((id) => monitorCache.cache.get(id)?.status);
  const e2e = created.map((c) => (seen.get(c.id)?.resolved ?? NaN) - c.writeStartMs);
  const toAssigned = created.map((c) => (seen.get(c.id)?.assigned ?? NaN) - c.writeStartMs);
  const nearSeen = created.filter((c) => seen.get(c.id)?.near).length;
  const etaSeen = created.filter((c) => seen.get(c.id)?.eta).length;
  const mqttLatency = subscribers.flatMap((s) => s.latencies);

  for (const a of ambulances) {
    if (a.publisher) {
      await a.publisher.publish({ ...a.vehicle(null, null), sirenActive: false });
      await a.publisher.close();
    }
  }
  for (const s of subscribers) await s.close();
  if (broker) await broker.close();

  return {
    name: 'lifecycle',
    title: `${C} เคสครบวงจรพร้อมกัน (${hospitals.length} รพ., รถ ${A} คัน${brokerUrl ? ', กองรถผ่าน MQTT' : ''})`,
    params: { cases: C, ambulances: A, hospitals: hospitals.length, mqtt: Boolean(brokerUrl), dispatch: cfg.dispatch, timeScale: cfg.timeScale, dispatchDelayMs: cfg.dispatchDelayMs, routeMode: cfg.routeMode, appLogic: cfg.appLogic },
    checks: [
      check('ทุกเคสจบครบวงจร (resolved) ภายในเวลา', done && finalStates.every((s) => s === 'resolved'), `${finalStates.filter((s) => s === 'resolved').length}/${C}`),
      check('เคสไม่ถูกเปลี่ยนรถกลางทาง', reassigned.length === 0, reassigned.slice(0, 5).join('; ') || `เปลี่ยนรถ 0 ครั้งใน ${C} เคส`),
      check('ขั้นสถานะไม่ถอยหลัง และเป็นคู่ที่แอปใช้', regress.length === 0 && badPairs.length === 0,
        [...regress, ...badPairs].slice(0, 5).join('; ') || `ถอยหลัง 0 · คู่สถานะผิด 0 จาก ${ids.reduce((n, id) => n + (history.get(id)?.length ?? 0), 0)} ครั้งที่สถานะเปลี่ยน`),
      check('เคสที่จบแล้วไม่ถูกเปิดกลับ', leftTerminal.length === 0, leftTerminal.slice(0, 5).join('; ') || `ออกจากสถานะจบ 0 ครั้ง (${C} เคส)`),
      check('บันทึก "รถใกล้ถึง" ครั้งเดียวต่อเคส', nearTwice.length === 0,
        nearTwice.join(', ') || `บันทึก ${ids.filter((id) => (history.get(id) ?? []).some((e) => e.near)).length}/${C} เคส ไม่มีเคสที่บันทึกซ้ำ`, 'assert', ['S15', 'G16']),
      // GPS รถเข้าใกล้ รพ. ≤ 1.5 กม. ระหว่างนำส่ง → สถานะ "ใกล้ถึง รพ." อัตโนมัติ (ตรวจเฉพาะเคสที่ช่วงนำส่งยาวพอให้ผ่านแนว 1.5 กม.)
      (() => {
        const long = created.filter((c) => (c.map.hospitalDistanceKm ?? 0) >= 2);
        const hit = long.filter((c) => (history.get(c.id) ?? []).some((e) => e.status === 'approaching_er'));
        return long.length
          ? check('GPS รถเข้าใกล้โรงพยาบาล ≤ 1.5 กม. ระหว่างนำส่ง: เปลี่ยนเป็น "ใกล้ถึง รพ." อัตโนมัติก่อนถึง', hit.length === long.length,
            `${hit.length}/${long.length} เคส (ช่วงนำส่ง ≥ 2 กม.)`, 'assert', ['G17'])
          : check('GPS รถเข้าใกล้โรงพยาบาล ≤ 1.5 กม. ระหว่างนำส่ง', null, 'ไม่มีเคสที่ช่วงนำส่งยาวพอในรอบนี้', 'measure', ['G17']);
      })(),
      check('เครื่องของผู้แจ้งแต่ละคนเห็นเคสตัวเองครบทุกสัญญาณ (มีรถรับ/ETA/ใกล้ถึง/จบ)',
        ownersCaughtUp,
        `${ownerMissing.length ? `${ownerMissing.join('; ')} · ` : ''}มีรถรับ ${created.filter((c) => seen.get(c.id)?.assigned).length}/${C} · ETA ${etaSeen}/${C} · ใกล้ถึง ${nearSeen}/${C} · จบ ${created.filter((c) => seen.get(c.id)?.resolved).length}/${C}`),
      cfg.appLogic === 'legacy'
        ? check('รถ 1 คันถือเคสค้างพร้อมกันเกิน 1 เคส (ตรรกะก่อนแก้ ไม่กันฝั่งเซิร์ฟเวอร์)', true, `สูงสุด ${maxOpenPerUnit} เคสต่อคัน${doubleAssign.size ? ` — ${[...doubleAssign].slice(0, 3).join(' | ')}` : ''}`, 'measure')
        : check('รถ 1 คันถือเคสที่ยังไม่จบได้ทีละเคส (ล็อกรถใน transaction)', maxOpenPerUnit <= 1, `สูงสุด ${maxOpenPerUnit} เคสต่อคัน${doubleAssign.size ? ` — ${[...doubleAssign].slice(0, 3).join(' | ')}` : ''} · สั่งจ่ายแล้วเจอรถไม่ว่าง ${agencies.flatMap((g) => g.dispatches).filter((d) => d.outcome === 'busy').length} ครั้ง (เลือกคันถัดไปแทน)`, 'assert', ['S15', 'S10']),
    ],
    metrics: {
      createToAssignedMs: msStats(toAssigned),
      createToResolvedMs: msStats(e2e),
      dispatchTxMs: msStats(agencies.flatMap((g) => g.dispatches.filter((d) => d.attempts > 0 && d.txMs != null).map((d) => d.txMs))),
      mqttDeliveryMs: msStats(mqttLatency),
      mqttMessages: ambulances.reduce((s, a) => s + (a.publisher?.sent ?? 0), 0),
      ambulanceWrites: ambulances.reduce((s, a) => s + a.writes, 0),
      maxOpenCasesPerUnit: maxOpenPerUnit,
    },
  };
}

// ---------------------------------------------------------------- 5. risks (หาช่วงเวลาเสี่ยงจากโค้ดแอป)
// ทุกเครื่องมี cache จาก listener และตัดสินใจจากสิ่งที่ตัวเองเห็นเท่านั้น (เหมือนแอป) แล้วไล่ระยะห่าง
// ระหว่างสองการกระทำ d — ผลคือ "ช่วงเวลาเสี่ยง": ถ้าสองฝั่งกดห่างกันน้อยกว่านี้ ปัญหาเกิดได้
export async function risks(ctx) {
  const { backend, cfg, hospitals, runId } = ctx;
  backend.scope = 'risks';
  const rng = makeRng(cfg.seed + 5);
  const legacy = cfg.appLogic === 'legacy';
  const delays = cfg.riskDelays;
  const trials = cfg.riskTrials;
  let seq = 0;
  const newCase = async (hospital) => {
    // ผู้แจ้งคนละเครื่องทุกเคส (แอปมี cooldown 2 นาทีต่อเครื่อง)
    const dev = backend.device(`risk-reporter-${++seq}`);
    const c = await createIncident(dev, {
      rng, point: randomPointNear(rng, hospital, 3000), hospitals, runId,
      reporter: { email: `sim-reporter-risk-${seq}@routealert.test`, name: 'ผู้แจ้งทดสอบ' }, extra: { simScenario: 'risks' },
    });
    await backend.closeDevice(dev);
    return c;
  };
  const hospA = backend.device('risk-hospital-a');
  const hospB = backend.device('risk-hospital-b');
  const ambDev = backend.device('risk-ambulance');
  const cacheA = attachIncidentCache(hospA, { runId, scenario: 'risks' });
  // เวลาที่อีกเครื่อง "เห็น" การเปลี่ยนแปลงจริง (จาก listener) — ไม่ขึ้นกับช่วงหน่วง d ที่ตั้งไว้
  const assignSeenAt = new Map();
  const closeSeenAt = new Map();
  const cacheB = attachIncidentCache(hospB, {
    runId, scenario: 'risks',
    onChange: (id, inc, raw, t) => { if (inc.units.length && !assignSeenAt.has(id)) assignSeenAt.set(id, t); },
  });
  const cacheAmb = attachIncidentCache(ambDev, {
    runId, scenario: 'risks',
    onChange: (id, inc, raw, t) => { if (isClosed(inc) && !closeSeenAt.has(id)) closeSeenAt.set(id, t); },
  });
  await sleep(1500);
  const unit = { id: 'SIM-AMB-RISK', plateNumber: 'ทด 9999', callSign: 'กู้ชีพทดสอบความเสี่ยง' };
  const seenIn = (cache, id, pred) => waitFor(() => { const i = cache.cache.get(id); return i && pred(i); }, { timeoutMs: 10000, intervalMs: 5 });

  // (ก) โรงพยาบาล A สั่งรถคันเดียวไปเคส 1 → โรงพยาบาล B ตัดสินใจหลัง d ms จาก cache ของตัวเอง
  //     ถ้า B ยังไม่เห็นว่ารถติดเคส (busy set) จะสั่งรถคันเดิมไปเคส 2 → รถถือ 2 เคส
  const doubleRows = [];
  const propagationToOtherHospital = [];
  for (const d of delays) {
    let hits = 0;
    for (let t = 0; t < trials; t++) {
      const [c1, c2] = await Promise.all([newCase(hospitals[0]), newCase(hospitals[1 % hospitals.length])]);
      await seenIn(cacheA, c1.id, () => true);
      await seenIn(cacheB, c2.id, () => true);
      const T = nowMs();
      const r1 = await dispatchIncident(hospA, c1.id, { ambulanceId: unit.id, ambulancePlate: unit.plateNumber, ambulanceCallSign: unit.callSign });
      await atTime(T + d);
      let r2 = { ok: false };
      if (!busyIdsFrom(cacheB.cache).has(unit.id)) {
        r2 = await dispatchIncident(hospB, c2.id, { ambulanceId: unit.id, ambulancePlate: unit.plateNumber, ambulanceCallSign: unit.callSign });
      }
      if (r1.ok && r2.ok) hits++;
      if (await seenIn(cacheB, c1.id, (i) => i.assignedAmbulanceId === unit.id) && assignSeenAt.has(c1.id)) {
        propagationToOtherHospital.push(assignSeenAt.get(c1.id) - T);
      }
      for (const c of [c1, c2]) await updateStep(ambDev, c.id, 'resolved', 5);
      await seenIn(cacheB, c2.id, (i) => isClosed(i));
      await seenIn(cacheA, c1.id, (i) => isClosed(i));
    }
    doubleRows.push({ delayMs: d, hits, trials });
  }

  // (ข) โรงพยาบาลปิดเคส → รถกดเลื่อนสถานะหลัง d ms เฉพาะถ้า cache ของรถยังเห็นว่าเคสเปิดอยู่
  //     (แอปตัดเคสที่ปิดแล้วออกจาก _activeIncident) ถ้ายังไม่เห็น การเขียนจะทับสถานะ cancelled
  const closeRows = [];
  const closeToAmbulance = [];
  for (const d of delays) {
    let hits = 0;
    for (let t = 0; t < trials; t++) {
      const c = await newCase(hospitals[0]);
      await dispatchIncident(hospA, c.id, { ambulanceId: unit.id, ambulancePlate: unit.plateNumber, ambulanceCallSign: unit.callSign });
      await updateStep(ambDev, c.id, 'at_scene', 2);
      await seenIn(cacheAmb, c.id, (i) => i.statusStep === 2);
      const T = nowMs();
      await closeByHospital(hospA, c.id);
      await atTime(T + d);
      const view = cacheAmb.cache.get(c.id);
      if (view && !isClosed(view)) await updateStep(ambDev, c.id, 'transporting', 3);
      await seenIn(cacheAmb, c.id, (i) => isClosed(i) || i.statusStep === 3);
      const final = (await ambDev.get(COLL.incidents, c.id, { server: true })).data();
      if (final.status !== 'cancelled') {
        hits++;
        await updateStep(ambDev, c.id, 'resolved', 5);
      }
      if (final.status === 'cancelled' && (await seenIn(cacheAmb, c.id, (i) => i.status === 'cancelled')) && closeSeenAt.has(c.id)) {
        closeToAmbulance.push(closeSeenAt.get(c.id) - T);
      }
    }
    closeRows.push({ delayMs: d, hits, trials });
  }

  const windowOf = (rows) => {
    const hit = rows.filter((r) => r.hits > 0).map((r) => r.delayMs);
    return hit.length ? Math.max(...hit) : null;
  };
  const table = (rows) => rows.map((r) => `${r.delayMs}ms:${r.hits}/${r.trials}`).join(' · ');
  const wDouble = windowOf(doubleRows);
  const wClose = windowOf(closeRows);
  return {
    name: 'risks',
    title: legacy
      ? 'ช่วงเวลาเสี่ยงจากการใช้งานพร้อมกัน — ตรรกะแอปก่อนแก้'
      : 'ช่วงเวลาเสี่ยงจากการใช้งานพร้อมกัน — ตรรกะแอปหลังแก้ (ล็อกรถ + เลื่อนสถานะแบบมีเงื่อนไข)',
    params: { delaysMs: delays.join('/'), trialsPerDelay: trials, appLogic: cfg.appLogic },
    checks: [
      check('สองโรงพยาบาลสั่งรถคันเดียวกันให้คนละเคส (B ตัดสินใจจากข้อมูลในเครื่องหลัง A d ms)',
        legacy ? true : wDouble == null,
        `${wDouble == null ? 'ไม่เกิดเลยทุกช่วงเวลาที่ทดสอบ' : `เกิดได้เมื่อห่างกัน ≤ ${wDouble} ms`} — ${table(doubleRows)}`,
        legacy ? 'measure' : 'assert', ['S10']),
      check('รถกดเลื่อนสถานะหลังโรงพยาบาลปิดเคส d ms → เคสถูกเปิดกลับ',
        legacy ? true : wClose == null,
        `${wClose == null ? 'ไม่เกิดเลยทุกช่วงเวลาที่ทดสอบ' : `เกิดได้เมื่อห่างกัน ≤ ${wClose} ms`} — ${table(closeRows)}`,
        legacy ? 'measure' : 'assert', ['S17']),
    ],
    metrics: {
      doubleAssign: doubleRows,
      closeResurrection: closeRows,
      assignmentReachesOtherHospitalMs: msStats(propagationToOtherHospital),
      closeReachesAmbulanceMs: msStats(closeToAmbulance),
    },
    notes: legacy
      ? [
          'ช่วงเวลาเสี่ยงเท่ากับเวลาที่ข้อมูลใช้เดินทางไปถึงอีกเครื่อง (ดูตัวชี้วัดด้านบน) — บนเครือข่ายมือถือจริงจะนานกว่า emulator จึงเสี่ยงกว่านี้',
          'สาเหตุ (ตรรกะก่อนแก้): transaction รับเคสอ่านแค่เอกสารเคส ไม่ได้เช็คว่ารถคันนั้นมีเคสค้างอยู่ และการเลื่อนสถานะเขียนทับโดยไม่เช็คว่าเคสถูกปิดไปแล้ว',
        ]
      : [
          'หลังแก้: transaction รับเคสอ่านล็อกของรถ (ambulance_locks/{ทะเบียน}) คู่กับเอกสารเคส และการเลื่อนสถานะเป็น transaction ที่ปฏิเสธเคสที่ปิดแล้ว — ไม่ขึ้นกับว่าอีกเครื่องเห็นข้อมูลช้าแค่ไหน',
          'เปรียบเทียบกับตรรกะก่อนแก้: รันซ้ำด้วย --app-logic=legacy',
        ],
  };
}

// ---------------------------------------------------------------- cleanup
export async function cleanup(ctx, { runOnly = null } = {}) {
  const dev = ctx.backend.device('cleanup');
  ctx.backend.scope = 'cleanup';
  const targets = [];
  for (const coll of [COLL.incidents, COLL.hospitals, COLL.fleet, COLL.locks]) {
    const snap = await dev.getAll(query(collection(dev.db, coll), where('simulation', '==', true)));
    for (const d of snap.docs) {
      if (!d.id.startsWith('SIM-')) continue; // ต้องตรงทั้งสองเงื่อนไขเท่านั้น
      if (runOnly && d.data().simRun !== runOnly) continue;
      targets.push({ coll, id: d.id });
    }
  }
  ctx.log(`จะลบเอกสารจำลอง ${targets.length} รายการ: ${JSON.stringify(Object.fromEntries([COLL.incidents, COLL.hospitals, COLL.fleet, COLL.locks].map((c) => [c, targets.filter((t) => t.coll === c).length])))}`);
  for (const t of targets) await dev.remove(t.coll, t.id);
  // ยืนยันว่าไม่เหลือ
  let remaining = 0;
  for (const coll of [COLL.incidents, COLL.hospitals, COLL.fleet, COLL.locks]) {
    const snap = await dev.getAll(query(collection(dev.db, coll), where('simulation', '==', true)));
    remaining += snap.docs.filter((d) => d.id.startsWith('SIM-') && (!runOnly || d.data().simRun === runOnly)).length;
  }
  await ctx.backend.closeDevice(dev);
  return { deleted: targets.length, remaining };
}

import { edge } from './scenarios_edge.mjs';
export const SCENARIOS = { burst, race, isolation, lifecycle, risks, edge };
