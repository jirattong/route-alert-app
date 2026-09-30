#!/usr/bin/env node
// ตัวสั่งรัน: node src/cli.mjs <burst|race|isolation|lifecycle|risks|all|cleanup> [--ตัวเลือก]
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';
import { Backend, SafetyError } from './firebase.mjs';
import { SCENARIOS, DEFAULT_SID, prepareHospitals, cleanup } from './scenarios.mjs';
import { writeReport, renderMarkdown } from './report.mjs';
import { bangkokIso } from './timefmt.mjs';
import { pad } from './util.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const TOOL_DIR = resolve(here, '..');

function parseArgs(argv) {
  const [command = 'help', ...rest] = argv;
  const flags = {};
  for (const a of rest) {
    const m = /^--([^=]+)(?:=(.*))?$/.exec(a);
    if (m) flags[m[1]] = m[2] ?? true;
  }
  return { command, flags };
}

const int = (v, d) => (v === undefined ? d : Number.parseInt(v, 10));

export function buildConfig(flags) {
  const target = flags.target ?? 'emulator';
  return {
    target,
    prodOptIn: flags['i-understand-this-writes-to-production'] === true,
    prodConfigPath: flags['prod-config'] ?? resolve(TOOL_DIR, '../../../route-alert-data-web/js/firebase-config.js'),
    seedHospitals: flags['seed-hospitals'] === true,
    listen: flags.listen === 'full' ? 'full' : 'sim',
    withMqtt: flags['with-mqtt'] === true || (target === 'emulator' && flags['no-mqtt'] !== true),
    realTopic: flags['real-topic'] === true && flags['i-understand-real-phones-will-alert'] === true,
    brokerUrl: flags.broker,
    dispatch: flags.dispatch === 'web' ? 'web' : 'mobile',
    seed: int(flags.seed, 20260929),
    hospitals: int(flags.hospitals, 3),
    reporters: int(flags.reporters, 20),
    observers: int(flags.observers, 3),
    ambulances: int(flags.ambulances, 5),
    rounds: int(flags.rounds, 10),
    casesPerHospital: int(flags['cases-per-hospital'], 4),
    cases: int(flags.cases, 10),
    lifecycleAmbulances: flags['lifecycle-ambulances'] ? int(flags['lifecycle-ambulances']) : undefined,
    riskTrials: int(flags['risk-trials'], 3),
    riskDelays: (flags['risk-delays'] ?? '0,25,50,100,200,400,800,1600').split(',').map(Number),
    dispatchDelayMs: int(flags['dispatch-delay-ms'], 1500),
    routeMode: flags['route-mode'] === 'fallback' ? 'fallback' : 'osrm',
    // ตรรกะรับเคส/เลื่อนสถานะของแอป: fixed = ปัจจุบัน, legacy = ก่อนแก้ (ไว้เทียบผลก่อน/หลัง)
    appLogic: flags['app-logic'] === 'legacy' ? 'legacy' : 'fixed',
    timeScale: int(flags['time-scale'], 20),
    tickMs: int(flags['tick-ms'], 150),
    stepMeters: int(flags['step-meters'], 250),
    sceneMs: int(flags['scene-ms'], 20000),
    lifecycleTimeoutMs: int(flags['lifecycle-timeout-ms'], 180000),
    keep: flags.keep === true,
  };
}

/** ประมาณการอ่าน/เขียนก่อนรันกับระบบจริง (โควตาฟรี: เขียน 20,000 / อ่าน 50,000 ต่อวัน) */
export function estimateCost(cfg, command) {
  const h = cfg.hospitals;
  // ค่าที่วัดจริงบน emulator (ค่าเริ่มต้น) แล้วเผื่อไว้ — listener ทุกเครื่องอ่านทุกการเขียน
  const A = cfg.lifecycleAmbulances ?? cfg.cases;
  const est = {
    burst: { writes: cfg.reporters, reads: cfg.reporters * (cfg.observers + 2) },
    race: { writes: cfg.rounds * (cfg.ambulances * 2 + 12), reads: cfg.rounds * (cfg.ambulances * 18 + 10) },
    isolation: { writes: h * cfg.casesPerHospital, reads: h * cfg.casesPerHospital * (h + 2) * 5 },
    lifecycle: { writes: cfg.cases * 22, reads: cfg.cases * 40 * (cfg.cases + A + h + 1) },
    risks: { writes: cfg.riskTrials * cfg.riskDelays.length * 12, reads: cfg.riskTrials * cfg.riskDelays.length * 45 },
    edge: { writes: 220, reads: 3500 },
  };
  const names = command === 'all' ? Object.keys(est) : [command];
  const total = names.reduce((s, n) => ({ writes: s.writes + (est[n]?.writes ?? 0), reads: s.reads + (est[n]?.reads ?? 0) }), { writes: 0, reads: 0 });
  return { perScenario: Object.fromEntries(names.map((n) => [n, est[n]])), total };
}

function runIdNow() {
  const d = new Date(Date.now() + 7 * 3600e3);
  return `${d.getUTCFullYear()}${pad(d.getUTCMonth() + 1)}${pad(d.getUTCDate())}-${pad(d.getUTCHours())}${pad(d.getUTCMinutes())}${pad(d.getUTCSeconds())}`;
}

const HELP = `
ตัวจำลองผู้ใช้หลายคนพร้อมกัน — RouteAlert
  node src/cli.mjs <คำสั่ง> [ตัวเลือก]

คำสั่ง: burst | race | isolation | lifecycle | risks | edge | all | cleanup
ตัวเลือกหลัก:
  --target=emulator (ค่าเริ่มต้น) | --target=prod --i-understand-this-writes-to-production
  --reporters=20 --ambulances=5 --rounds=10 --hospitals=3 --cases=10 --cases-per-hospital=4
  --with-mqtt (prod) --real-topic --i-understand-real-phones-will-alert (topic จริง — มือถือจริงจะแจ้งเตือน)
  --dispatch=mobile|web  --seed-hospitals  --listen=sim|full  --keep (ไม่ล้างข้อมูลหลังรัน)
  --app-logic=fixed|legacy (legacy = ตรรกะก่อนแก้ ไว้เทียบผล)
  --dispatch-delay-ms=1500 --route-mode=osrm|fallback --risk-trials=3 --risk-delays=0,25,50,100,200,400,800,1600
ดู README.md สำหรับรายละเอียดและค่าใช้จ่ายโดยประมาณ
`;

async function main() {
  const { command, flags } = parseArgs(process.argv.slice(2));
  if (command === 'help' || flags.help) {
    console.log(HELP);
    return;
  }
  const cfg = buildConfig(flags);
  const runId = runIdNow();
  const ctx = { cfg, runId, log: (m) => console.log(`  · ${m}`) };

  if (cfg.target === 'prod') {
    const est = estimateCost(cfg, command);
    console.log('⚠️  กำลังรันกับ Firebase จริง (route-alert-ccf91) — ข้อมูลจำลองจะขึ้นต้นด้วย SIM- และติด simulation: true');
    console.log(`   ประมาณการ: เขียน ~${est.total.writes} · อ่าน ~${est.total.reads} (โควตาฟรีต่อวัน: เขียน 20,000 / อ่าน 50,000)`);
    if (cfg.withMqtt) {
      console.log(cfg.realTopic
        ? '🚨 ใช้ topic MQTT จริง: รถจำลองจะขึ้นบนเรดาร์ของมือถือจริงทุกเครื่องและทำให้เกิดการแจ้งเตือนจริง'
        : '   MQTT ใช้ topic แยกของรอบนี้ (มือถือจริงไม่เห็นรถจำลอง)');
    }
    if (cfg.seedHospitals) console.log('   --seed-hospitals: โรงพยาบาลจำลองจะอยู่ในรายชื่อของแอปจริงระหว่างรัน (อาจดึงเคสจริงไปหา) — ล้างด้วย cleanup ทันทีหลังจบ');
  }

  const backend = new Backend(cfg);
  ctx.backend = backend;
  backend.runId = runId; // ล็อกรถจำลองติด simRun ไว้ให้ cleanup ล้างเฉพาะรอบนี้ได้
  let needsCleanup = false;
  let cleaned = false;
  const doCleanup = async () => {
    if (!needsCleanup || cleaned || cfg.keep) return null;
    cleaned = true;
    try {
      return await cleanup(ctx, { runOnly: runId });
    } catch (e) {
      console.error(`ล้างข้อมูลจำลองไม่สำเร็จ — รัน cleanup อีกครั้ง: ${e.message}`);
      return null;
    }
  };
  // กด Ctrl-C กลางคัน ต้องล้างข้อมูลจำลองก่อนออก (สำคัญมากตอนรันกับระบบจริง)
  process.once('SIGINT', async () => {
    console.error('\nหยุดกลางคัน — กำลังล้างข้อมูลจำลอง…');
    await doCleanup();
    process.exit(130);
  });
  try {
    if (command === 'cleanup') {
      const r = await cleanup(ctx);
      console.log(`ลบแล้ว ${r.deleted} · เหลือ ${r.remaining}`);
      if (r.remaining !== 0) process.exitCode = 1;
      return;
    }
    const names = command === 'all' ? ['burst', 'race', 'isolation', 'lifecycle', 'risks', 'edge'] : [command];
    for (const n of names) if (!SCENARIOS[n]) throw new Error(`ไม่รู้จักคำสั่ง: ${n}\n${HELP}`);

    needsCleanup = true;
    await prepareHospitals(ctx);
    console.log(`รอบทดสอบ ${runId} · โรงพยาบาล ${ctx.hospitals.length} แห่ง: ${ctx.hospitals.map((h) => h.hospitalId).join(', ')}`);
    const run = {
      runId,
      target: cfg.target,
      projectId: backend.projectId,
      node: process.version,
      startedAtBangkok: bangkokIso(new Date()).slice(0, 19).replace('T', ' '),
      config: cfg,
      results: [],
    };
    for (const n of names) {
      console.log(`\n▶ ${n}`);
      const t0 = Date.now();
      const r = await SCENARIOS[n](ctx);
      r.durationMs = Date.now() - t0;
      for (const c of r.checks) c.sid ??= DEFAULT_SID[n] ?? [];
      // ปิด "มือถือ" ของสถานการณ์นี้ทั้งหมด ไม่ให้ listener ค้างไปอ่านการเขียนของสถานการณ์ถัดไป
      await backend.closeAll();
      r.cost = backend.counts[n] ?? null;
      run.results.push(r);
      for (const c of r.checks) {
        const icon = c.kind === 'integrity' ? (c.ok ? '☑️' : '❌') : c.ok === null ? '📊' : c.ok ? '✅' : '❌';
        const tag = c.sid?.length && !c.name.startsWith('[') ? `[${c.sid.join('][')}] ` : '';
        console.log(`  ${icon} ${tag}${c.name}${c.detail ? ` — ${c.detail}` : ''}`);
      }
    }
    run.devices = backend.seq;
    run.cleanup = await doCleanup();
    const files = writeReport(join(TOOL_DIR, 'results'), run);
    console.log(`\nรายงาน: ${files.md}`);
    const failed = run.results.flatMap((r) => r.checks).filter((c) => c.ok === false);
    if (failed.length || (run.cleanup && run.cleanup.remaining !== 0)) process.exitCode = 1;
    if (flags.print) console.log(renderMarkdown(run));
  } catch (e) {
    if (e instanceof SafetyError) console.error(`🛑 ${e.message}`);
    else console.error(e);
    process.exitCode = 1;
  } finally {
    await doCleanup(); // สถานการณ์ล้ม/throw กลางทางก็ต้องล้าง
    await backend.closeAll();
    // firebase SDK ค้าง handle ไว้ — ออกเองเมื่อทุกอย่างปิดแล้ว
    setTimeout(() => process.exit(process.exitCode ?? 0), 200).unref();
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
