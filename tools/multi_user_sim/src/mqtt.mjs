// กองรถพยาบาลผ่าน MQTT แบบเดียวกับ EmergencyMqttService: MQTT 3.1 (MQIsdp), QoS 1, ไม่ retain,
// payload = EmergencyVehicleData.toMap, ฝั่งรับลบรถที่เงียบเกิน 12 วิ (เช็คทุก 5 วิ)
import net from 'node:net';
import { createRequire } from 'node:module';
import mqtt from 'mqtt';
import { vehicleToMap, parseVehicle } from './model.mjs';
import { nowMs } from './util.mjs';

const require = createRequire(import.meta.url);

export const APP_TOPIC = 'routealert-ccf91/emergency/ambulance';
export const APP_BROKER = 'mqtt://broker.emqx.io:1883';

/** topic ที่ใช้ตามเป้าหมาย — ระบบจริงใช้ topic แยกเป็นค่าเริ่มต้น (มือถือจริงไม่ฟัง) */
export function topicFor(cfg, runId) {
  if (cfg.target === 'emulator') return APP_TOPIC; // broker ในเครื่อง ไม่มีใครอื่นฟัง
  return cfg.realTopic ? APP_TOPIC : `routealert-sim/${runId}/emergency/ambulance`;
}

export async function startLocalBroker() {
  const { Aedes } = require('aedes');
  const aedes = await Aedes.createBroker();
  const server = net.createServer(aedes.handle);
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const { port } = server.address();
  return {
    url: `mqtt://127.0.0.1:${port}`,
    async close() {
      await new Promise((r) => server.close(() => r()));
      await new Promise((r) => aedes.close(() => r()));
    },
  };
}

let clientSeq = 0;
function connect(url, runId) {
  return new Promise((resolve, reject) => {
    const client = mqtt.connect(url, {
      // MQTT 3.1 จำกัด client id ไม่เกิน 23 ตัวอักษร
      clientId: `RASIM${String(runId).replace(/\D/g, '').slice(-6)}_${++clientSeq}`,
      protocolId: 'MQIsdp',
      protocolVersion: 3,
      clean: true,
      keepalive: 20,
      connectTimeout: 8000,
      reconnectPeriod: 0,
    });
    client.once('connect', () => resolve(client));
    client.once('error', reject);
  });
}

/** รถพยาบาล 1 คัน = 1 client (เหมือนมือถือ 1 เครื่อง) */
export class FleetPublisher {
  static async create(url, topic, runId) {
    return new FleetPublisher(await connect(url, runId), topic);
  }

  constructor(client, topic) {
    this.client = client;
    this.topic = topic;
    this.sent = 0;
  }

  publish(vehicle) {
    this.sent++;
    // simSentAtMs ไว้วัด latency เท่านั้น — แอปไม่อ่านคีย์ที่ไม่รู้จัก
    const payload = { ...vehicleToMap(vehicle), simSentAtMs: nowMs() };
    return new Promise((resolve) => {
      this.client.publish(this.topic, JSON.stringify(payload), { qos: 1, retain: false }, () => resolve());
    });
  }

  async close() {
    await new Promise((r) => this.client.end(false, {}, () => r()));
  }
}

/** activeFleet ของเครื่องโรงพยาบาล — sirenActive:false ลบทันที, เงียบเกิน 12 วิลบทิ้ง */
export class FleetSubscriber {
  static async create(url, topic, runId) {
    const client = await connect(url, runId);
    const sub = new FleetSubscriber(client);
    await new Promise((resolve, reject) =>
      client.subscribe(topic, { qos: 1 }, (err) => (err ? reject(err) : resolve())),
    );
    return sub;
  }

  constructor(client) {
    this.client = client;
    this.fleet = new Map(); // id -> vehicle (ลำดับที่เห็นครั้งแรก เหมือน LinkedHashMap)
    this.lastReceivedAt = new Map();
    this.received = 0;
    this.parseErrors = 0;
    this.latencies = [];
    client.on('message', (_topic, payload) => {
      this.received++;
      let v;
      let raw;
      try {
        raw = JSON.parse(payload.toString('utf8'));
        v = parseVehicle(raw);
      } catch {
        this.parseErrors++;
        return;
      }
      if (v.sirenActive) {
        this.fleet.set(v.id, v);
        this.lastReceivedAt.set(v.id, nowMs());
      } else {
        this.fleet.delete(v.id);
        this.lastReceivedAt.delete(v.id);
      }
      if (typeof raw.simSentAtMs === 'number') this.latencies.push(nowMs() - raw.simSentAtMs);
    });
    this.purgeTimer = setInterval(() => {
      const t = nowMs();
      for (const [id, at] of this.lastReceivedAt) {
        if (t - at > 12000) {
          this.fleet.delete(id);
          this.lastReceivedAt.delete(id);
        }
      }
    }, 5000);
  }

  activeFleet() {
    return [...this.fleet.values()];
  }

  async close() {
    clearInterval(this.purgeTimer);
    await new Promise((r) => this.client.end(false, {}, () => r()));
  }
}
