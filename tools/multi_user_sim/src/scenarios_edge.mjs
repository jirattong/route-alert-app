// สถานการณ์ขอบ (S03, S05, S07, S08, S11–S14, S16, S18) — แต่ละข้อใช้ "มือถือ" จำลองแยกกันเหมือนสถานการณ์อื่น
// และเรียกตรรกะเดียวกับแอป (ops.mjs) ผลแต่ละข้อติดรหัสสถานการณ์ (sid) ไว้ให้รายงานรวมจับคู่กับรายการสถานการณ์
import { COLL, parseHospital, parseIncident, isClosed, unitsOf, vehicleCountOf, agencyCaseVisible, vehicleKeyFor } from './model.mjs';
import { offsetPoint, haversineMeters } from './geo.mjs';
import {
  createIncident,
  dispatchIncident,
  selfAccept,
  updateStep,
  closeByHospital,
  cancelByReporter,
  busyIdsFrom,
  attachIncidentCache,
} from './ops.mjs';
import { FleetPublisher, FleetSubscriber, startLocalBroker, topicFor, APP_BROKER } from './mqtt.mjs';
import { nowMs, sleep, atTime, waitFor, makeRng } from './util.mjs';
import { bangkokIso } from './timefmt.mjs';
import { collection } from 'firebase/firestore';

const check = (sid, name, ok, detail = '', kind = 'assert') => {
  const sids = Array.isArray(sid) ? sid : [sid];
  return { sid: sids, name: `[${sids.join('][')}] ${name}`, kind, ok: kind === 'measure' ? null : Boolean(ok), detail };
};
const SCOPE = 'edge';

export async function edge(ctx) {
  const { backend, cfg, hospitals, runId } = ctx;
  backend.scope = SCOPE;
  const rng = makeRng(cfg.seed + 7);
  const checks = [];
  const notes = [];
  let seq = 0;

  const reporterDevice = () => {
    const n = ++seq;
    return {
      device: backend.device(`edge-reporter-${n}`),
      reporter: { email: `sim-reporter-edge-${n}@routealert.test`, name: `ผู้แจ้งขอบ ${n}` },
    };
  };
  // ผู้แจ้งคนละเครื่องทุกเคส (แอปมี cooldown 2 นาทีต่อเครื่อง)
  const report = async (point, list = hospitals) => {
    const r = reporterDevice();
    const c = await createIncident(r.device, { rng, point, hospitals: list, reporter: r.reporter, runId, extra: { simScenario: SCOPE } });
    await backend.closeDevice(r.device);
    return c;
  };
  const cacheOf = (name) => {
    const device = backend.device(name);
    return { device, ...attachIncidentCache(device, { runId, scenario: SCOPE }) };
  };
  const read = async (dev, id) => (await dev.get(COLL.incidents, id, { server: true })).data();
  const unit = (id, plate) => ({ id: `SIM-AMB-${id}`, plateNumber: plate, callSign: `กู้ชีพขอบ ${id}` });
  const assign = (dev, id, u, opts = {}) =>
    dispatchIncident(dev, id, { ambulanceId: u.id, ambulancePlate: u.plateNumber, ambulanceCallSign: u.callSign, ...opts });
  const finish = async (dev, id) => {
    for (const st of ['at_scene', 'transporting', 'resolved']) await updateStep(dev, id, st);
  };

  // ผู้เฝ้าดู: ประวัติสถานะทุกเคสของสถานการณ์นี้ (ใช้ตรวจ "สถานะถอยหลัง")
  const history = new Map();
  const monitor = backend.device('edge-monitor');
  attachIncidentCache(monitor, {
    runId,
    scenario: SCOPE,
    onChange: (id, inc) => history.set(id, [...(history.get(id) ?? []), inc.statusStep]),
  });
  const regressed = (id) => {
    const h = history.get(id) ?? [];
    return h.some((s, i) => i > 0 && s < h[i - 1]);
  };
  const admin = backend.device('edge-admin');
  await sleep(800);
  const [H1, H2] = hospitals;

  // ---------------------------------------------------------- S03 แจ้งเหตุเดียวกันหลายคน
  {
    const spot = offsetPoint(H1, 45, 1500);
    const dups = await Promise.all([0, 1, 2].map((k) => report(offsetPoint(spot, k * 120, 15))));
    const hosp = cacheOf('edge-s03-hospital');
    const amb = cacheOf('edge-s03-ambulance');
    const docs0 = await Promise.all(dups.map((d) => read(admin, d.id)));
    const targets = new Set(docs0.map((d) => d.targetHospitalId));
    const seenAll = await waitFor(() => dups.every((d) => hosp.cache.has(d.id)), { timeoutMs: 15000 });
    const [main, ...extra] = dups;
    const v = unit('E3', 'ดซ 3001');
    const r = await assign(hosp.device, main.id, v, { onlyIfUnassigned: true });
    for (const d of extra) await closeByHospital(hosp.device, d.id);
    await finish(amb.device, main.id);
    const [m, ...x] = await Promise.all(dups.map((d) => read(admin, d.id)));
    checks.push(
      check('S03', 'หลายคนแจ้งเหตุเดียวกัน: ทุกเคสไปโรงพยาบาลเดียวกันและเครื่องโรงพยาบาลเห็นครบ', targets.size === 1 && seenAll,
        `${dups.length} เคส → ${[...targets].join(', ')}`),
      check('S03', 'ปิดเคสซ้ำแล้วเคสหลักยังดำเนินต่อจนจบ และเคสที่ปิดไม่มีรถค้าง', r.ok && m.status === 'resolved' &&
        x.every((d) => d.status === 'cancelled' && unitsOf(d).length === 0),
        `เคสหลัก ${m.status}, เคสซ้ำ ${x.map((d) => d.status).join('/')}`),
    );
    await backend.closeDevice(hosp.device);
    await backend.closeDevice(amb.device);
  }

  // ---------------------------------------------------------- S05 ER ใกล้สุดเต็ม / เคสไกล
  if (cfg.target === 'emulator' && hospitals.every((h) => h.hospitalId.startsWith('SIM-HOSP-'))) {
    await admin.update(COLL.hospitals, H1.hospitalId, { isErAvailable: false });
    try {
      // แอปผู้แจ้งอ่านรายชื่อโรงพยาบาลสดจาก hospital_profiles
      const fresh = (await admin.getAll(collection(admin.db, COLL.hospitals))).docs
        .map((d) => parseHospital(d.data()))
        .filter((h) => hospitals.some((x) => x.hospitalId === h.hospitalId));
      const c = await report(offsetPoint(H1, 90, 800), fresh);
      const doc = await read(admin, c.id);
      const target = fresh.find((h) => h.hospitalId === doc.targetHospitalId);
      const inc = parseIncident(doc);
      const oldFilterHides = inc.hospitalDistanceKm > 5;
      checks.push(
        check('S05', 'ER ของโรงพยาบาลที่ใกล้สุดเต็ม: เคสไปโรงพยาบาลที่ ER ว่าง', target && target.hospitalId !== H1.hospitalId && target.isErAvailable,
          `เกิดเหตุห่าง ${H1.hospitalId} 0.8 กม. → ${doc.targetHospitalId} (${inc.hospitalDistanceKm} กม.)`),
        check('S05', 'โรงพยาบาลปลายทางเห็นเคสในรายการแม้ไกลเกินระยะกรอง 5 กม.', agencyCaseVisible(inc, { myHospitalId: doc.targetHospitalId }),
          oldFilterHides ? 'ตัวกรองก่อนแก้จะซ่อนเคสนี้ (ไม่มีโรงพยาบาลไหนเห็นเลย)' : 'ระยะไม่เกิน 5 กม.'),
      );
    } finally {
      await admin.update(COLL.hospitals, H1.hospitalId, { isErAvailable: true });
    }
  } else {
    notes.push('S05 ข้าม: ต้องใช้โรงพยาบาลจำลองบน emulator (ไม่แก้สถานะ ER ของโรงพยาบาลจริง)');
  }

  // ---------------------------------------------------------- S07 เครื่องโรงพยาบาลเปิดทีหลัง
  {
    const cs = await Promise.all([0, 1, 2, 3].map((k) => report(offsetPoint(H2, k * 90, 1200))));
    await closeByHospital(admin, cs[3].id); // ถูกปิดไประหว่างที่เครื่องนี้ปิดอยู่
    await sleep(500);
    const t0 = nowMs();
    const late = cacheOf('edge-s07-late-hospital');
    const ok = await waitFor(
      () => cs.slice(0, 3).every((c) => late.cache.get(c.id)?.status === 'pending') && isClosed(late.cache.get(cs[3].id) ?? { status: 'x' }),
      { timeoutMs: 15000 },
    );
    const ms = Math.round(nowMs() - t0);
    const listOk = cs.slice(0, 3).every((c) => {
      const i = late.cache.get(c.id);
      return i && agencyCaseVisible(i, { myHospitalId: i.targetHospitalId });
    }) && !agencyCaseVisible(late.cache.get(cs[3].id) ?? { status: 'cancelled' }, {});
    checks.push(check('S07', 'เปิดแอปโรงพยาบาลทีหลัง: เห็นเคสที่รอครบ และเคสที่ถูกปิดระหว่างนั้นไม่ขึ้นในรายการ', ok && listOk,
      `เห็นครบใน ${ms} ms`));
    for (const c of cs.slice(0, 3)) await closeByHospital(admin, c.id);
    await backend.closeDevice(late.device);
  }

  // ---------------------------------------------------------- S08 เจ้าหน้าที่ รพ. เดียวกัน 2 เครื่อง
  {
    const d1 = cacheOf('edge-s08-staff-1');
    const d2 = cacheOf('edge-s08-staff-2');
    const trials = 5;
    let single = 0;
    const outcomes = {};
    for (let t = 0; t < trials; t++) {
      const c = await report(offsetPoint(H1, t * 60, 1800));
      await waitFor(() => d1.cache.has(c.id) && d2.cache.has(c.id), { timeoutMs: 15000 });
      const fireAt = nowMs() + 200;
      const rs = await Promise.all([[d1, 1], [d2, 2]].map(async ([d, k]) => {
        await atTime(fireAt);
        return assign(d.device, c.id, unit(`E8${t}${k}`, `ชซ 8${t}${k}`), { onlyIfUnassigned: true });
      }));
      for (const r of rs) outcomes[r.outcome] = (outcomes[r.outcome] ?? 0) + 1;
      const doc = await read(admin, c.id);
      if (vehicleCountOf(doc) === 1 && rs.filter((r) => r.ok).length === 1) single++;
      await updateStep(admin, c.id, 'resolved');
    }
    checks.push(check('S08', 'เจ้าหน้าที่ 2 คนของโรงพยาบาลเดียวกันกดส่งรถพร้อมกัน: ได้รถคันเดียว', single === trials,
      `${single}/${trials} เคส · ${JSON.stringify(outcomes)}`));
    await backend.closeDevice(d1.device);
    await backend.closeDevice(d2.device);
  }

  // ---------------------------------------------------------- S11 หลายบัญชีบนรถคันเดียวกัน
  {
    const [a, b] = await Promise.all([report(offsetPoint(H1, 180, 1300)), report(offsetPoint(H1, 200, 1600))]);
    const x1 = { ...unit('E111', 'ทด 1111'), dev: cacheOf('edge-s11-crew-1') };
    const x2 = { ...unit('E112', 'ทด-1111'), dev: cacheOf('edge-s11-crew-2') };
    await waitFor(() => x1.dev.cache.has(a.id) && x2.dev.cache.has(b.id), { timeoutMs: 15000 });
    const r1 = await selfAccept(x1.dev.device, a.id, x1, busyIdsFrom(x1.dev.cache));
    const r2 = await selfAccept(x2.dev.device, a.id, x2, busyIdsFrom(x2.dev.cache));
    const docA = await read(admin, a.id);
    // บัญชีที่สองพยายามรับอีกเคส ผ่าน transaction ตรง (ข้ามการเช็คใน cache) — ต้องโดนล็อกรถ
    const r3 = await assign(x2.dev.device, b.id, x2, { selfAccepted: true });
    const docB = await read(admin, b.id);
    await finish(x1.dev.device, a.id);
    const r4 = await assign(x2.dev.device, b.id, x2, { selfAccepted: true });
    checks.push(
      check('S11', 'สองบัญชีทะเบียนเดียวกัน (พิมพ์ต่างกัน) อยู่ในเคสเดียว นับเป็น 1 คัน', r1.ok && r2.ok && unitsOf(docA).length === 2 && vehicleCountOf(docA) === 1,
        `${r1.outcome}/${r2.outcome} → ${unitsOf(docA).length} บัญชี ${vehicleCountOf(docA)} คัน`),
      check('S11', 'บัญชีที่สองรับเคสอื่นไม่ได้ระหว่างที่รถคันนั้นยังไม่จบเคส และรับได้เมื่อจบแล้ว', !r3.ok && unitsOf(docB).length === 0 && r4.ok,
        `ระหว่างเคส: ${r3.outcome} · หลังจบ: ${r4.outcome}`),
    );
    await updateStep(admin, b.id, 'resolved');
    await backend.closeDevice(x1.dev.device);
    await backend.closeDevice(x2.dev.device);
  }

  // ---------------------------------------------------------- S12 บัญชีรถเดียวกันเปิด 2 เครื่อง
  {
    const c = await report(offsetPoint(H2, 30, 1500));
    const y = unit('E12', 'ทด 1212');
    const phone = cacheOf('edge-s12-phone');
    const tablet = cacheOf('edge-s12-tablet');
    await waitFor(() => phone.cache.has(c.id) && tablet.cache.has(c.id), { timeoutMs: 15000 });
    const acc = await selfAccept(phone.device, c.id, y, busyIdsFrom(phone.cache));
    const tabletSeesMine = await waitFor(() => tablet.cache.get(c.id)?.units.some((u) => u.unitId === y.id), { timeoutMs: 10000 });
    const s1 = await updateStep(tablet.device, c.id, 'at_scene');
    await waitFor(() => phone.cache.get(c.id)?.status === 'at_scene', { timeoutMs: 10000 });
    await updateStep(tablet.device, c.id, 'transporting');
    const stale = await updateStep(phone.device, c.id, 'at_scene'); // ปุ่มบนเครื่องที่ยังไม่อัปเดต
    const end = await updateStep(phone.device, c.id, 'resolved');
    const doc = await read(admin, c.id);
    checks.push(
      check('S12', 'บัญชีเดียวกันอีกเครื่องเห็นเป็นเคสของตัวเองและเลื่อนสถานะได้', acc.ok && tabletSeesMine && s1 === 'updated',
        `รับเคสจากมือถือ ${acc.outcome} · แท็บเล็ตเลื่อนเป็นถึงจุดเกิดเหตุ ${s1}`),
      check('S12', 'กดปุ่มค้างจากอีกเครื่องไม่ทำให้สถานะถอยหลัง และจบเคสจากเครื่องไหนก็ได้', stale !== 'updated' && end === 'updated' && doc.status === 'resolved' && !regressed(c.id),
        `ปุ่มค้าง: ${stale} · จบ: ${end} · ประวัติขั้น ${(history.get(c.id) ?? []).join('→')}`),
    );
    await backend.closeDevice(phone.device);
    await backend.closeDevice(tablet.device);
  }

  // ---------------------------------------------------------- S13 รถออฟไลน์ / ไม่มีรถว่าง (MQTT)
  if (cfg.withMqtt) {
    const localBroker = cfg.target === 'emulator' && !cfg.brokerUrl ? await startLocalBroker() : null;
    const url = localBroker?.url ?? cfg.brokerUrl ?? APP_BROKER;
    const topic = topicFor(cfg, runId);
    const sub = await FleetSubscriber.create(url, topic, runId);
    const hosp = cacheOf('edge-s13-hospital');
    const A = { ...unit('E13A', 'ออ 1301'), pos: offsetPoint(H1, 0, 600) };
    const B = { ...unit('E13B', 'ออ 1302'), pos: offsetPoint(H1, 180, 2500) };
    const vehicleOf = (v) => ({
      id: v.id, callSign: v.callSign, latitude: v.pos.latitude, longitude: v.pos.longitude, speed: 40, heading: 0,
      plateNumber: v.plateNumber, emergencyType: 'ลาดตระเวน', sirenActive: true, timestamp: bangkokIso(new Date()),
      routePoints: null, turnIntent: null, destinationName: 'ลาดตระเวน (ยังไม่มีเคส)', simulation: true,
    });
    const pubs = await Promise.all([A, B].map(() => FleetPublisher.create(url, topic, runId)));
    const online = { [A.id]: true, [B.id]: true };
    let lastA = nowMs();
    let publishing = true;
    const loop = (async () => {
      while (publishing) {
        if (online[A.id]) { pubs[0].publish(vehicleOf(A)).catch(() => {}); lastA = nowMs(); }
        if (online[B.id]) pubs[1].publish(vehicleOf(B)).catch(() => {});
        await sleep(1000);
      }
    })();
    // หน้าส่งรถของโรงพยาบาล: คันว่างที่ใกล้ที่สุดจากกองรถที่ออนไลน์ (หักรถที่มีเคสค้าง)
    const pick = (inc) => {
      const busy = busyIdsFrom(hosp.cache);
      const free = sub.activeFleet().filter((v) => !busy.has(v.id));
      return free.sort((p, q) => haversineMeters(inc, p) - haversineMeters(inc, q))[0] ?? null;
    };
    const bothOnline = await waitFor(() => sub.activeFleet().length >= 2, { timeoutMs: 10000 });
    online[A.id] = false; // A ปิดแอป/สัญญาณหาย
    const purged = await waitFor(() => !sub.activeFleet().some((v) => v.id === A.id), { timeoutMs: 25000, intervalMs: 200 });
    const goneAfter = Math.round(nowMs() - lastA);
    const c1 = await report(offsetPoint(H1, 0, 700)); // ใกล้ A (ที่ออฟไลน์) มากกว่า B
    await waitFor(() => hosp.cache.has(c1.id), { timeoutMs: 10000 });
    const inc1 = hosp.cache.get(c1.id);
    const first = pick(inc1);
    const r1 = first ? await assign(hosp.device, c1.id, { ...first, plateNumber: first.plateNumber }, { onlyIfUnassigned: true }) : { ok: false };
    const c2 = await report(offsetPoint(H1, 90, 900));
    await waitFor(() => hosp.cache.has(c2.id) && busyIdsFrom(hosp.cache).has(B.id), { timeoutMs: 10000 });
    const noneFree = pick(hosp.cache.get(c2.id)) === null;
    await sleep(1500);
    const stillPending = (await read(admin, c2.id)).status === 'pending';
    await finish(admin, c1.id);
    await waitFor(() => !busyIdsFrom(hosp.cache).has(B.id), { timeoutMs: 10000 });
    const later = pick(hosp.cache.get(c2.id));
    const r2 = later ? await assign(hosp.device, c2.id, later, { onlyIfUnassigned: true }) : { ok: false };
    checks.push(
      check(['S13', 'G19'], 'รถที่หยุดส่งตำแหน่ง (ปิดแอป/สัญญาณหาย) หายจากรายการรถของโรงพยาบาลภายใน ~17 วิ', bothOnline && purged && goneAfter <= 18000,
        `หายหลังส่งครั้งสุดท้าย ${goneAfter} ms (แอปลบรถที่เงียบเกิน 12 วิ ตรวจทุก 5 วิ)`),
      check(['S13', 'G19'], 'รถที่ออฟไลน์ไม่ถูกเลือก แม้อยู่ใกล้กว่า', r1.ok && first?.id === B.id, `เลือก ${first?.id ?? 'ไม่มี'}`),
      check('S13', 'ไม่มีรถว่าง: เคสรอโดยไม่ถูกส่งซ้อน แล้วส่งได้เมื่อรถว่าง', noneFree && stillPending && r2.ok && later?.id === B.id,
        `ไม่มีรถว่าง=${noneFree} · เคสยังรอ=${stillPending} · หลังรถว่าง: ${r2.outcome ?? '-'}`),
    );
    await finish(admin, c2.id);

    // G20: รถกดพักเวร/ปิดไซเรน → แอปส่ง sirenActive:false แล้วหยุดส่งตำแหน่ง ต้องหายจากรายการทันที ไม่ต้องรอ 12 วิ
    await waitFor(() => !busyIdsFrom(hosp.cache).has(B.id), { timeoutMs: 10000 });
    online[B.id] = false;
    const offAt = nowMs();
    await pubs[1].publish({ ...vehicleOf(B), sirenActive: false });
    const goneNow = await waitFor(() => !sub.activeFleet().some((v) => v.id === B.id), { timeoutMs: 5000, intervalMs: 50 });
    const offMs = Math.round(nowMs() - offAt);
    const c3 = await report(offsetPoint(H1, 180, 700));
    await waitFor(() => hosp.cache.has(c3.id), { timeoutMs: 10000 });
    const afterOff = pick(hosp.cache.get(c3.id));
    checks.push(check('G20', 'รถกดพักเวร/ปิดไซเรน: หายจากรายการรถของโรงพยาบาลทันทีและไม่ถูกเลือก', goneNow && offMs < 3000 && afterOff === null,
      `หายใน ${offMs} ms · ไม่มีรถให้เลือก=${afterOff === null}`));
    await closeByHospital(admin, c3.id);
    publishing = false;
    await loop;
    for (const [i, v] of [A, B].entries()) {
      await pubs[i].publish({ ...vehicleOf(v), sirenActive: false });
      await pubs[i].close();
    }
    await sub.close();
    if (localBroker) await localBroker.close();
    await backend.closeDevice(hosp.device);
  } else {
    notes.push('S13 ข้าม: ต้องเปิด MQTT (emulator เปิดให้อัตโนมัติ, ระบบจริงใส่ --with-mqtt)');
  }

  // ---------------------------------------------------------- S14 ร่วมรับเคส/ส่งรถเพิ่ม หลังเริ่มนำส่ง
  {
    const c = await report(offsetPoint(H2, 120, 1400));
    const hosp = cacheOf('edge-s14-hospital');
    const v1 = { ...unit('E141', 'ซซ 1401'), dev: cacheOf('edge-s14-v1') };
    const v2 = { ...unit('E142', 'ซซ 1402'), dev: cacheOf('edge-s14-v2') };
    const v3 = { ...unit('E143', 'ซซ 1403'), dev: cacheOf('edge-s14-v3') };
    await waitFor(() => [hosp, v1.dev, v2.dev, v3.dev].every((d) => d.cache.has(c.id)), { timeoutMs: 15000 });
    const first = await assign(hosp.device, c.id, v1, { onlyIfUnassigned: true });
    await waitFor(() => v2.dev.cache.get(c.id)?.units.length === 1, { timeoutMs: 10000 });
    const join = await selfAccept(v2.dev.device, c.id, v2, busyIdsFrom(v2.dev.cache));
    const count2 = vehicleCountOf(await read(admin, c.id));
    await updateStep(v1.dev.device, c.id, 'at_scene');
    await updateStep(v1.dev.device, c.id, 'transporting');
    const lateJoin = await selfAccept(v3.dev.device, c.id, v3, busyIdsFrom(v3.dev.cache));
    const lateSend = await assign(hosp.device, c.id, v3); // ปุ่ม "ส่งรถเพิ่ม"
    const doc = await read(admin, c.id);
    checks.push(
      check('S14', 'ก่อนเริ่มนำส่ง: รถคันที่สองร่วมรับเคสได้ นับเป็น 2 คัน', first.ok && join.ok && count2 === 2, `${first.outcome} → ${join.outcome} · ${count2} คัน`),
      check('S14', 'เริ่มนำส่งแล้ว: รถกดร่วมรับ และโรงพยาบาลส่งรถเพิ่ม ไม่ได้', !lateJoin.ok && !lateSend.ok && vehicleCountOf(doc) === 2,
        `รถกดร่วม: ${lateJoin.outcome} · รพ. ส่งเพิ่ม: ${lateSend.outcome}`),
    );
    await updateStep(admin, c.id, 'resolved');
    for (const d of [hosp, v1.dev, v2.dev, v3.dev]) await backend.closeDevice(d.device);
  }

  // ---------------------------------------------------------- S16 หลายคันในเคสเดียวกดเลื่อนสถานะสลับกัน
  {
    const cases = 5;
    const perCase = 3;
    const ids = [];
    const tasks = [];
    for (let k = 0; k < cases; k++) {
      const c = await report(offsetPoint(H1, k * 72, 2000));
      ids.push(c.id);
      const crews = Array.from({ length: perCase }, (_, j) => ({ ...unit(`E16${k}${j}`, `ฟฟ 16${k}${j}`), dev: backend.device(`edge-s16-${k}-${j}`) }));
      for (const [j, v] of crews.entries()) {
        const r = await assign(v.dev, c.id, v, j === 0 ? { onlyIfUnassigned: true } : { selfAccepted: true });
        if (!r.ok) notes.push(`S16 ${v.id} เข้าเคสไม่สำเร็จ (${r.outcome})`);
      }
      // แต่ละคันกดตามลำดับของตัวเอง (ถึงจุดเกิดเหตุ → นำส่ง → ถึง รพ.) คนละจังหวะ จึงสลับกันระหว่างคัน
      for (const v of crews) {
        const times = [rng.range(0, 900), rng.range(0, 900), rng.range(0, 900)].sort((p, q) => p - q);
        tasks.push((async () => {
          const t0 = nowMs();
          for (const [n, st] of ['at_scene', 'transporting', 'resolved'].entries()) {
            await atTime(t0 + times[n]);
            await updateStep(v.dev, c.id, st);
          }
          await backend.closeDevice(v.dev);
        })());
      }
    }
    await Promise.all(tasks);
    await sleep(1500);
    const finals = await Promise.all(ids.map((id) => read(admin, id)));
    checks.push(
      check('S16', `รถ ${perCase} คันในเคสเดียวกดเลื่อนสถานะสลับกัน (${cases} เคสพร้อมกัน): สถานะไม่ถอยหลัง`, ids.every((id) => !regressed(id)),
        ids.map((id) => (history.get(id) ?? []).join('→')).join(' | ')),
      check('S16', 'ทุกเคสจบที่ "ถึงโรงพยาบาล" ขั้น 5', finals.every((d) => d.status === 'resolved' && d.statusStep === 5),
        finals.map((d) => `${d.status}/${d.statusStep}`).join(', ')),
    );
  }

  // ---------------------------------------------------------- S18 ผู้แจ้งยกเลิกพร้อมกับที่รถกดรับ
  {
    const trials = 8;
    let bad = 0;
    const result = { ยกเลิกก่อน: 0, รถรับก่อน: 0 };
    for (let t = 0; t < trials; t++) {
      const r = reporterDevice();
      const rc = attachIncidentCache(r.device, { runId, scenario: SCOPE });
      const c = await createIncident(r.device, {
        rng, point: offsetPoint(H2, t * 45, 1800), hospitals, reporter: r.reporter, runId, extra: { simScenario: SCOPE },
      });
      const v = { ...unit(`E18${t}`, `ยย 18${t}`), dev: cacheOf(`edge-s18-amb-${t}`) };
      await waitFor(() => rc.cache.has(c.id) && v.dev.cache.has(c.id), { timeoutMs: 15000 });
      const fireAt = nowMs() + 200;
      const [cancel] = await Promise.all([
        (async () => { await atTime(fireAt + rng.int(0, 40)); return cancelByReporter(r.device, c.id, rc.cache.get(c.id)); })(),
        (async () => { await atTime(fireAt + rng.int(0, 40)); return selfAccept(v.dev.device, c.id, v, busyIdsFrom(v.dev.cache)); })(),
      ]);
      const doc = await read(admin, c.id);
      if (doc.status === 'cancelled' && unitsOf(doc).length > 0) bad++;
      if (cancel === 'cancelled' && doc.status === 'cancelled') result.ยกเลิกก่อน++;
      else result.รถรับก่อน++;
      if (!isClosed(doc)) await updateStep(admin, c.id, 'resolved');
      await backend.closeDevice(r.device);
      await backend.closeDevice(v.dev.device);
    }
    checks.push(check('S18', 'ผู้แจ้งกดยกเลิกพร้อมกับที่รถกดรับ: ไม่มีเคสที่ถูกยกเลิกทั้งที่มีรถรับ', bad === 0,
      `${trials} ครั้ง · ยกเลิกทับรถ ${bad} ครั้ง · ยกเลิกก่อน ${result.ยกเลิกก่อน} · รถรับก่อน ${result.รถรับก่อน}`));
  }

  await backend.closeDevice(admin);
  return {
    name: 'edge',
    title: 'สถานการณ์เฉพาะ: แจ้งซ้ำ, ER เต็ม, เครื่องเปิดทีหลัง, หลายเครื่อง/หลายบัญชี, รถออฟไลน์, ร่วมรับเคส, ยกเลิกชนการรับเคส',
    params: { appLogic: cfg.appLogic, mqtt: Boolean(cfg.withMqtt) },
    checks,
    metrics: {},
    notes,
  };
}
