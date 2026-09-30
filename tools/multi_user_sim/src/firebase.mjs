// "อุปกรณ์เสมือน" = Firebase app instance แยกกันต่อเครื่อง (initializeApp(config, ชื่อไม่ซ้ำ))
// แต่ละตัวมี connection/listener/cache ของตัวเอง เหมือนมือถือคนละเครื่อง
// ทุกการเขียนผ่าน guard: แก้/ลบได้เฉพาะ doc id ที่ขึ้นต้น SIM- เท่านั้น
import { readFileSync } from 'node:fs';
import { initializeApp, deleteApp } from 'firebase/app';
import {
  getFirestore,
  connectFirestoreEmulator,
  terminate,
  setLogLevel,
  collection,
  doc,
  query,
  where,
  onSnapshot,
  getDoc,
  getDocFromServer,
  getDocs,
  setDoc,
  updateDoc,
  deleteDoc,
  runTransaction,
} from 'firebase/firestore';
import { COLL, SIM_PREFIX } from './model.mjs';

setLogLevel('error');

export const EMULATOR_PROJECT_ID = 'demo-routealert';
export const PROD_PROJECT_ID = 'route-alert-ccf91';

/** อ่าน web config สาธารณะจาก route-alert-data-web/js/firebase-config.js (ใช้เฉพาะ --target=prod) */
export function loadProdWebConfig(path) {
  const src = readFileSync(path, 'utf8');
  const block = /const\s+firebaseConfig\s*=\s*\{([\s\S]*?)\};/.exec(src);
  if (!block) throw new Error(`อ่าน firebaseConfig ไม่ได้จาก ${path}`);
  const cfg = {};
  for (const m of block[1].matchAll(/(\w+)\s*:\s*"([^"]*)"/g)) cfg[m[1]] = m[2];
  if (cfg.projectId !== PROD_PROJECT_ID) throw new Error(`projectId ไม่ตรง (${cfg.projectId})`);
  return cfg;
}

export class SafetyError extends Error {}

export function assertSimId(coll, id) {
  if (typeof id !== 'string' || !id.startsWith(SIM_PREFIX)) {
    throw new SafetyError(`ปฏิเสธการเขียน ${coll}/${id}: แตะได้เฉพาะเอกสารที่ขึ้นต้น ${SIM_PREFIX}`);
  }
}

export class Backend {
  constructor(cfg) {
    this.cfg = cfg;
    this.devices = [];
    this.seq = 0;
    this.scope = 'setup';
    this.counts = {};
    if (cfg.target === 'emulator') {
      const host = process.env.FIRESTORE_EMULATOR_HOST;
      if (!host) throw new Error('ไม่พบ FIRESTORE_EMULATOR_HOST — รันผ่าน npm run emu -- <คำสั่ง> (firebase emulators:exec)');
      const [h, p] = host.split(':');
      this.emulator = { host: h, port: Number(p) };
      this.firebaseConfig = { projectId: EMULATOR_PROJECT_ID, apiKey: 'demo-key', appId: 'demo-app' };
    } else if (cfg.target === 'prod') {
      if (!cfg.prodOptIn) throw new SafetyError('prod ต้องใส่ --i-understand-this-writes-to-production');
      if (process.env.FIRESTORE_EMULATOR_HOST) {
        throw new SafetyError('ตั้ง FIRESTORE_EMULATOR_HOST อยู่ แต่เลือก --target=prod — ยกเลิกเพื่อความปลอดภัย');
      }
      this.firebaseConfig = loadProdWebConfig(cfg.prodConfigPath);
    } else {
      throw new Error(`target ไม่รู้จัก: ${cfg.target}`);
    }
  }

  get projectId() {
    return this.firebaseConfig.projectId;
  }

  count(kind, n = 1) {
    const c = (this.counts[this.scope] ??= { reads: 0, writes: 0, deletes: 0 });
    c[kind] += n;
  }

  device(name, meta = {}) {
    const app = initializeApp(this.firebaseConfig, `${name}#${++this.seq}`);
    const db = getFirestore(app);
    if (this.emulator) connectFirestoreEmulator(db, this.emulator.host, this.emulator.port);
    const d = new Device(this, name, app, db, meta);
    this.devices.push(d);
    return d;
  }

  async closeDevice(d) {
    d.closed = true;
    for (const u of d.unsubs.splice(0)) {
      try {
        u();
      } catch {
        // ignore
      }
    }
    try {
      await terminate(d.db);
      await deleteApp(d.app);
    } catch {
      // ignore
    }
    this.devices = this.devices.filter((x) => x !== d);
  }

  async closeAll() {
    for (const d of [...this.devices]) await this.closeDevice(d);
  }
}

export class Device {
  constructor(backend, name, app, db, meta) {
    this.backend = backend;
    this.name = name;
    this.app = app;
    this.db = db;
    this.meta = meta;
    this.unsubs = [];
    this.closed = false;
  }

  ref(coll, id) {
    return doc(this.db, coll, id);
  }

  /** query ที่ listener ของแอปใช้: แอปฟังทั้ง collection; โหมด sim กรองเฉพาะเอกสารจำลอง (ประหยัด read บน prod) */
  incidentsQuery() {
    const c = collection(this.db, COLL.incidents);
    return this.backend.cfg.listen === 'full' ? c : query(c, where('simulation', '==', true));
  }

  fleetQuery() {
    const c = collection(this.db, COLL.fleet);
    return this.backend.cfg.listen === 'full' ? c : query(c, where('simulation', '==', true));
  }

  hospitalsQuery() {
    return collection(this.db, COLL.hospitals);
  }

  listen(q, onNext, onError) {
    let first = true;
    const unsub = onSnapshot(
      q,
      (snap) => {
        const changes = snap.docChanges().length;
        this.backend.count('reads', first ? Math.max(1, changes) : changes);
        first = false;
        onNext(snap);
      },
      (err) => {
        if (onError) onError(err);
        else console.error(`[${this.name}] listener error: ${err.message}`);
      },
    );
    this.unsubs.push(unsub);
    return unsub;
  }

  async get(coll, id, { server = false } = {}) {
    this.backend.count('reads');
    const r = this.ref(coll, id);
    return server ? getDocFromServer(r) : getDoc(r);
  }

  async getAll(q) {
    const snap = await getDocs(q);
    this.backend.count('reads', Math.max(1, snap.size));
    return snap;
  }

  async set(coll, id, data, options) {
    assertSimId(coll, id);
    if (data.simulation !== true && !(options && options.merge)) {
      throw new SafetyError(`${coll}/${id}: เอกสารใหม่ต้องมี simulation: true`);
    }
    this.backend.count('writes');
    return options ? setDoc(this.ref(coll, id), data, options) : setDoc(this.ref(coll, id), data);
  }

  async update(coll, id, data) {
    assertSimId(coll, id);
    this.backend.count('writes');
    return updateDoc(this.ref(coll, id), data);
  }

  async remove(coll, id) {
    assertSimId(coll, id);
    this.backend.count('deletes');
    return deleteDoc(this.ref(coll, id));
  }

  /**
   * transaction หลายเอกสาร (ใช้กับการรับเคสแบบล็อกรถ) — อ่านได้ทุกเอกสาร เขียนได้เฉพาะ SIM-
   * tx: { get(coll, id), update(coll, id, data), set(coll, id, data) }
   */
  async transactionMulti(fn) {
    return runTransaction(
      this.db,
      async (tx) =>
        fn({
          get: (coll, id) => {
            this.backend.count('reads');
            return tx.get(this.ref(coll, id));
          },
          update: (coll, id, data) => {
            assertSimId(coll, id);
            this.backend.count('writes');
            tx.update(this.ref(coll, id), data);
          },
          set: (coll, id, data) => {
            assertSimId(coll, id);
            if (data.simulation !== true) throw new SafetyError(`${coll}/${id}: เอกสารใหม่ต้องมี simulation: true`);
            this.backend.count('writes');
            tx.set(this.ref(coll, id), data);
          },
        }),
      { maxAttempts: 5 },
    );
  }

  /** runTransaction ของ JS SDK = optimistic (อ่าน version แล้ว commit แบบมี precondition, maxAttempts 5) เหมือน SDK มือถือ */
  async transaction(coll, id, fn) {
    assertSimId(coll, id);
    const r = this.ref(coll, id);
    return runTransaction(
      this.db,
      async (tx) => {
        this.backend.count('reads');
        return fn({
          get: () => tx.get(r),
          update: (data) => {
            this.backend.count('writes');
            tx.update(r, data);
          },
        });
      },
      { maxAttempts: 5 },
    );
  }
}
