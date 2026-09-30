#!/usr/bin/env node
// สร้างเอกสาร "ผลการทดลอง" จากผลการรันจริง 1 ชุด (tools/run_all_scenarios.sh --results)
//   node src/results_doc.mjs --batch=results/batch-<เวลา> --out=../../docs/TEST_RESULTS.md
// ในโฟลเดอร์ batch: env.json, flutter.jsonl, worker.tap, sim-fixed-<n>.json (หลายรอบ), sim-legacy.json (ถ้ามี)
import { readFileSync, writeFileSync, readdirSync, existsSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { CATALOG, GROUPS, SOURCE_LABEL } from './catalog.mjs';

const TAG = /\[([SG]\d{2})\]/g;
const tagsOf = (name) => [...String(name).matchAll(TAG)].map((m) => m[1]);
const clean = (name) => String(name).replace(TAG, '').trim();
const cell = (s) => String(s ?? '').replace(/\|/g, '/').replace(/\n/g, ' ');
const r0 = (x) => (x == null || Number.isNaN(x) ? '–' : Math.round(x).toLocaleString('en-US'));
const r1 = (x) => (x == null || Number.isNaN(x) ? '–' : (Math.round(x * 10) / 10).toLocaleString('en-US'));
const mean = (a) => a.reduce((s, x) => s + x, 0) / a.length;
const sd = (a) => (a.length < 2 ? 0 : Math.sqrt(a.reduce((s, x) => s + (x - mean(a)) ** 2, 0) / (a.length - 1)));

// ------------------------------------------------------------------ อ่านผล
function readFlutter(file) {
  const names = new Map();
  const status = new Map();
  const results = [];
  for (const line of readFileSync(file, 'utf8').split('\n')) {
    if (!line.startsWith('{')) continue;
    let e;
    try { e = JSON.parse(line); } catch { continue; }
    if (e.type === 'testStart') names.set(e.test.id, e.test.name);
    if (e.type === 'testDone' && !e.hidden) status.set(e.testID, e.result === 'success');
    if (e.type === 'print' && String(e.message).startsWith('@@RESULT ')) {
      try { results.push({ testID: e.testID, ...JSON.parse(e.message.slice(9)) }); } catch { /* ข้ามบรรทัดเสีย */ }
    }
  }
  const tests = [...status].map(([id, ok]) => ({ name: names.get(id) ?? '', ok }));
  const rows = results.map((r) => {
    const name = names.get(r.testID) ?? '';
    return { source: 'dart', sid: tagsOf(name), test: clean(name), condition: r.condition, expected: r.expected, actual: r.actual, ok: status.get(r.testID) ?? false };
  });
  return { tests, rows };
}

function readWorker(file) {
  const text = readFileSync(file, 'utf8');
  const tests = [];
  const rows = [];
  for (const line of text.split('\n')) {
    const t = /^\s*(not )?ok \d+ - (.*?)(?:\s+#.*)?$/.exec(line);
    if (t) tests.push({ name: t[2], ok: !t[1] });
    const m = /^\s*#\s*@@RESULT (.*)$/.exec(line);
    if (m) {
      try { rows.push({ source: 'worker', ...JSON.parse(m[1].replace(/\\\\/g, '\\')) }); } catch { /* ข้าม */ }
    }
  }
  const okBySid = (sid) => tests.filter((t) => tagsOf(t.name).includes(sid)).every((t) => t.ok);
  for (const r of rows) { r.sid = [r.sid]; r.ok = okBySid(r.sid[0]); }
  return { tests, rows };
}

const readSim = (file) => JSON.parse(readFileSync(file, 'utf8'));
const simChecks = (run) => run.results.flatMap((r) => r.checks.filter((c) => c.kind !== 'integrity').map((c) => ({ ...c, scenario: r.name })));

// ------------------------------------------------------------------ สร้างเอกสาร
export function buildResults({ env, flutter, worker, simRuns, legacy }) {
  const L = [];
  const push = (...x) => L.push(...x);
  const N = simRuns.length;

  // ตรวจรายสถานการณ์: ผ่านเมื่อทุกข้อที่ติดรหัสผ่าน (ตัวจำลองต้องผ่านครบทุกรอบ) และมีผลครบทุกชุดที่ระบุ
  const simBySid = new Map();
  simRuns.forEach((run, i) => {
    for (const c of simChecks(run)) {
      for (const sid of c.sid ?? []) {
        const key = `${sid}|${clean(c.name)}`;
        const e = simBySid.get(key) ?? { sid, name: clean(c.name), runs: [] };
        e.runs[i] = c;
        simBySid.set(key, e);
      }
    }
  });
  const scen = CATALOG.map((s) => {
    const dartTests = flutter.tests.filter((t) => tagsOf(t.name).includes(s.id));
    const workerTests = worker.tests.filter((t) => tagsOf(t.name).includes(s.id));
    const sims = [...simBySid.values()].filter((e) => e.sid === s.id);
    const graded = sims.filter((e) => e.runs.some((c) => c && c.ok !== null));
    const simPassRuns = N ? [...Array(N).keys()].filter((i) => graded.every((e) => e.runs[i]?.ok !== false)).length : 0;
    const have = { dart: dartTests.length > 0, worker: workerTests.length > 0, sim: sims.length > 0 };
    const failed = dartTests.some((t) => !t.ok) || workerTests.some((t) => !t.ok) || (graded.length && simPassRuns < N);
    const missing = s.automated.filter((src) => !have[src]);
    const results = [
      ...flutter.rows.filter((r) => r.sid.includes(s.id)),
      ...worker.rows.filter((r) => r.sid.includes(s.id)),
    ];
    return { ...s, dartTests, workerTests, sims, graded, simPassRuns, failed, missing, results, pass: !failed && !missing.length };
  });
  const nPass = scen.filter((s) => s.pass).length;

  push('# ผลการทดลอง: การทดสอบระบบ RouteAlert ตามสถานการณ์', '');
  push(`เอกสารนี้สร้างอัตโนมัติจากการรันทดสอบจริงเมื่อ **${env.when}** (เวลาไทย) ด้วยคำสั่ง \`tools/run_all_scenarios.sh --results\``);
  push('ตัวเลขทุกค่าในเอกสารเป็นค่าที่วัดได้จากการรันครั้งนั้น ไม่ได้แก้ไขด้วยมือ — รายการสถานการณ์และวิธีทดสอบดูที่ [TEST_SCENARIOS.md](TEST_SCENARIOS.md)', '');

  // 1. สภาพแวดล้อม
  const cfg = simRuns[0]?.config ?? {};
  push('## 1. สภาพแวดล้อมและวิธีการทดลอง', '');
  push('| รายการ | ค่า |', '|---|---|');
  push(`| เครื่องที่ใช้ทดสอบ | ${cell(env.cpu)} · RAM ${env.ramGb} GB · ${cell(env.os)} |`);
  push(`| ซอฟต์แวร์ | ${cell(env.flutter)} · Node ${env.node} · Firestore Emulator ${cell(env.emulator)} |`);
  push(`| ฐานข้อมูล | Firestore Emulator ในเครื่อง (ไม่มีเครือข่ายจริง) — ผู้ใช้จำลองแต่ละคนเชื่อมต่อแยกกันเหมือนมือถือคนละเครื่อง |`);
  push(`| จำนวนรอบของตัวจำลอง | ${N} รอบ (ทุกรอบใช้ค่าตั้งต้นเดียวกัน seed ${cfg.seed})${legacy ? ' + 1 รอบด้วยตรรกะก่อนแก้ (ใช้เปรียบเทียบ)' : ''} |`);
  push(`| ผู้ใช้จำลองต่อรอบ | ${simRuns.map((r) => r.devices).join(' / ')} เครื่องเสมือน (ผู้แจ้ง, โรงพยาบาล, รถพยาบาล, ผู้เฝ้าดู) |`);
  push(`| พารามิเตอร์หลัก | ผู้แจ้งพร้อมกัน ${cfg.reporters} คน · โรงพยาบาล ${cfg.hospitals} แห่ง · รถแย่งรับเคส ${cfg.ambulances} คัน × ${cfg.rounds} รอบ · เคสครบวงจร ${cfg.cases} เคส (เวลาจำลองเร่ง ${cfg.timeScale} เท่า) · เจ้าหน้าที่ใช้เวลาตัดสินใจ ${cfg.dispatchDelayMs / 2000}–${cfg.dispatchDelayMs * 1.5 / 1000} วิ · ช่วงหน่วงทดสอบจุดเสี่ยง ${(cfg.riskDelays ?? []).join('/')} ms × ${cfg.riskTrials} ครั้ง |`);
  const cost = simRuns.map((r) => r.results.reduce((a, x) => ({ reads: a.reads + (x.cost?.reads ?? 0), writes: a.writes + (x.cost?.writes ?? 0) }), { reads: 0, writes: 0 }));
  push(`| ปริมาณการใช้ฐานข้อมูลต่อรอบ | อ่าน ${cost.map((c) => r0(c.reads)).join(' / ')} · เขียน ${cost.map((c) => r0(c.writes)).join(' / ')} ครั้ง |`);
  push(`| ชุดทดสอบ | ${SOURCE_LABEL.dart} ${flutter.tests.filter((t) => t.ok).length}/${flutter.tests.length} ข้อ · ${SOURCE_LABEL.worker} ${worker.tests.filter((t) => t.ok).length}/${worker.tests.length} ข้อ · ${SOURCE_LABEL.sim} ${simRuns.map((r) => { const c = simChecks(r).filter((x) => x.ok !== null); return `${c.filter((x) => x.ok).length}/${c.length}`; }).join(' / ')} ข้อต่อรอบ |`);
  push('', 'เกณฑ์: สถานการณ์ **ผ่าน** เมื่อทุกข้อทดสอบที่ติดรหัสของสถานการณ์นั้นผ่าน (ข้อในตัวจำลองต้องผ่านครบทุกรอบ) และมีผลจากทุกชุดทดสอบที่กำหนดไว้', '');

  // 2. สรุป
  push('## 2. สรุปผล', '');
  push(`**ผ่าน ${nPass} จาก ${scen.length} สถานการณ์**`, '');
  push('| กลุ่ม | จำนวนสถานการณ์ | ผ่าน | ไม่ผ่าน |', '|---|---|---|---|');
  for (const [g, label] of Object.entries(GROUPS)) {
    const xs = scen.filter((s) => s.group === g);
    push(`| ${label} | ${xs.length} | ${xs.filter((s) => s.pass).length} | ${xs.filter((s) => !s.pass).length} |`);
  }
  push('', '| รหัส | สถานการณ์ | ผลที่ต้องได้ | ผลที่ได้จริง (ตัวอย่าง) | ผล |', '|---|---|---|---|---|');
  for (const s of scen) {
    const sample = s.results[0]?.actual ?? s.sims.find((e) => e.runs[0])?.runs[0]?.detail ?? '';
    const verdict = s.pass ? `✅ ผ่าน${s.graded.length ? ` (${s.simPassRuns}/${N} รอบ)` : ''}` : s.missing.length ? '⏸️ ไม่มีผล' : `❌ ไม่ผ่าน${s.graded.length ? ` (${s.simPassRuns}/${N} รอบ)` : ''}`;
    push(`| ${s.id} | ${cell(s.title)} | ${cell(s.expected)} | ${cell(String(sample).slice(0, 180))} | ${verdict} |`);
  }

  // 3. ประสิทธิภาพ
  push('', '## 3. ผลการวัดเวลา', '');
  push(`ค่าที่ได้จากตัวจำลอง ${N} รอบ — "มัธยฐาน" คือค่าเฉลี่ยของมัธยฐานแต่ละรอบ ± ส่วนเบี่ยงเบนมาตรฐานระหว่างรอบ, p95/ต่ำสุด/สูงสุด รวมทุกรอบ`, '');
  push('| ตัวชี้วัด | สถานการณ์ | จำนวนตัวอย่าง | มัธยฐาน (ms) | p95 (ms) | ต่ำสุด (ms) | สูงสุด (ms) |', '|---|---|---|---|---|---|---|');
  const METRICS = [
    ['burst', 'writeLatencyMs', 'บันทึกเคสลงฐานข้อมูล (ผู้แจ้ง 20 คนพร้อมกัน)', 'S01'],
    ['burst', 'propagationMs', 'ผู้แจ้งกดส่ง → เครื่องโรงพยาบาลเห็นเคส', 'S01'],
    ['race', 'transactionMs', 'transaction รับเคส (5 คันกดพร้อมกัน)', 'S09'],
    ['lifecycle', 'dispatchTxMs', 'transaction สั่งจ่ายรถ (พร้อมล็อกรถ)', 'S10, S15'],
    ['lifecycle', 'createToAssignedMs', 'แจ้งเหตุ → ผู้แจ้งเห็นว่ามีรถรับ (รวมเวลาเจ้าหน้าที่ตัดสินใจ)', 'S15'],
    ['lifecycle', 'mqttDeliveryMs', 'ส่งตำแหน่งรถผ่าน MQTT → เครื่องโรงพยาบาลได้รับ', 'S15, G19'],
    ['risks', 'assignmentReachesOtherHospitalMs', 'สั่งจ่ายรถ → อีกโรงพยาบาลเห็นว่ารถไม่ว่าง', 'S10'],
    ['risks', 'closeReachesAmbulanceMs', 'โรงพยาบาลปิดเคส → เครื่องรถเห็นว่าเคสปิด', 'S17'],
    ['lifecycle', 'createToResolvedMs', 'แจ้งเหตุ → ผู้แจ้งเห็นว่าเคสจบ (เวลาจำลองเร่ง 20 เท่า)', 'S15'],
  ];
  for (const [scn, key, label, sid] of METRICS) {
    const st = simRuns.map((r) => r.results.find((x) => x.name === scn)?.metrics?.[key]).filter((x) => x && x.n);
    if (!st.length) continue;
    const med = st.map((x) => x.p50);
    push(`| ${label} | ${sid} | ${st.reduce((a, x) => a + x.n, 0).toLocaleString('en-US')} | ${r1(mean(med))} ± ${r1(sd(med))} | ${r1(Math.max(...st.map((x) => x.p95)))} | ${r1(Math.min(...st.map((x) => x.min)))} | ${r1(Math.max(...st.map((x) => x.max)))} |`);
  }
  // ค่าที่อยู่ในรายละเอียดของข้อทดสอบ (สถานการณ์เฉพาะ)
  const fromDetail = (sid, re) => simRuns.map((run) => simChecks(run).find((c) => (c.sid ?? []).includes(sid) && re.test(c.detail ?? ''))).map((c) => c && Number(re.exec(c.detail)[1])).filter((x) => Number.isFinite(x));
  const extra = [
    ['เครื่องโรงพยาบาลที่เปิดทีหลังเห็นเคสค้างครบ', 'S07', /เห็นครบใน (\d+) ms/],
    ['รถหยุดส่งตำแหน่ง → หายจากรายการของโรงพยาบาล', 'G19', /หายหลังส่งครั้งสุดท้าย (\d+) ms/],
    ['รถปิดไซเรน/พักเวร → หายจากรายการของโรงพยาบาล', 'G20', /หายใน (\d+) ms/],
  ];
  for (const [label, sid, re] of extra) {
    const xs = fromDetail(sid, re);
    if (!xs.length) continue;
    push(`| ${label} | ${sid} | ${xs.length} | ${r1(mean(xs))} ± ${r1(sd(xs))} | – | ${r1(Math.min(...xs))} | ${r1(Math.max(...xs))} |`);
  }
  push('', '> Emulator อยู่ในเครื่องเดียวกัน ไม่มีความหน่วงของเครือข่ายมือถือ ตัวเลขเวลาจึงต่ำกว่าการใช้งานจริง ใช้ยืนยันความถูกต้องและเปรียบเทียบกันเอง');

  // 4. ก่อน/หลังแก้
  if (legacy) {
    push('', '## 4. เปรียบเทียบก่อนและหลังแก้ไข', '');
    push('รันตัวจำลองชุดเดียวกันด้วยตรรกะก่อนแก้ (`--app-logic=legacy`) เทียบกับตรรกะปัจจุบัน (รอบที่ 1)', '');
    const lr = (name) => legacy.results.find((x) => x.name === name);
    const fr = (name) => simRuns[0].results.find((x) => x.name === name);
    const riskTable = (label, key, sid) => {
      const a = lr('risks')?.metrics?.[key] ?? [];
      const b = fr('risks')?.metrics?.[key] ?? [];
      push(`**${sid} ${label}** — จำนวนครั้งที่เกิดปัญหา / จำนวนครั้งที่ทดลอง แยกตามช่วงห่างระหว่างสองฝ่าย`, '');
      push(`| ห่างกัน (ms) | ${a.map((x) => x.delayMs).join(' | ')} |`, `|---|${a.map(() => '---').join('|')}|`);
      push(`| ก่อนแก้ | ${a.map((x) => `${x.hits}/${x.trials}`).join(' | ')} |`);
      push(`| หลังแก้ | ${b.map((x) => `${x.hits}/${x.trials}`).join(' | ')} |`, '');
    };
    riskTable('โรงพยาบาล 2 แห่งส่งรถคันเดียวกันไปคนละเคส', 'doubleAssign', 'S10');
    riskTable('เคสที่โรงพยาบาลปิดแล้วถูกเปิดกลับ', 'closeResurrection', 'S17');
    push('| สถานการณ์ | ตัววัด | ก่อนแก้ | หลังแก้ |', '|---|---|---|---|');
    push(`| S15 | รถ 1 คันถือเคสค้างพร้อมกันสูงสุด | ${lr('lifecycle')?.metrics?.maxOpenCasesPerUnit ?? '–'} เคส | ${fr('lifecycle')?.metrics?.maxOpenCasesPerUnit ?? '–'} เคส |`);
    const vehicles = (r) => (r?.metrics?.rounds ?? []).map((x) => x.vehicles ?? x.winners ?? 1);
    push(`| S09 | รถที่เข้าเคสได้เมื่อ ${cfg.ambulances} คันกดรับพร้อมกัน (ต่อรอบ) | ${vehicles(lr('race')).join('/') || '1'} คัน | ${vehicles(fr('race')).join('/')} คัน |`);
    const edgeDetail = (run, sid, re) => simChecks(run).filter((c) => (c.sid ?? []).includes(sid) && re.test(c.name)).map((c) => `${c.ok ? '✅' : '❌'} ${c.detail}`).join('<br>');
    for (const [sid, re, label] of [
      ['S11', /นับเป็น 1 คัน|รับเคสอื่นไม่ได้/, 'หลายบัญชีบนรถคันเดียวกัน'],
      ['S12', /ถอยหลัง/, 'บัญชีเดียวกัน 2 เครื่อง กดปุ่มค้าง'],
      ['S14', /ร่วมรับ|ส่งรถเพิ่ม/, 'ร่วมรับเคส / ส่งรถเพิ่ม'],
      ['S16', /ถอยหลัง/, 'หลายคันเลื่อนสถานะสลับกัน (ประวัติขั้นสถานะ)'],
      ['S18', /ยกเลิก/, 'ผู้แจ้งยกเลิกพร้อมกับที่รถรับ'],
    ]) {
      push(`| ${sid} | ${label} | ${cell(edgeDetail(legacy, sid, re))} | ${cell(edgeDetail(simRuns[0], sid, re))} |`);
    }
    push('', 'บั๊กที่แก้ในโค้ดแอปโดยตรง (ทดสอบด้วยโค้ดจริง ไม่ผ่านตัวจำลอง) — ผลก่อนแก้ยืนยันด้วยการย้อนโค้ดทีละจุดแล้วรันเทสต์ (mutation test) เทสต์ของสถานการณ์นั้นไม่ผ่านทุกครั้ง:', '');
    for (const s of CATALOG.filter((x) => x.fixed && !['S10', 'S17', 'S18'].includes(x.id))) push(`- **${s.id} ${s.title}** — ก่อนแก้: ${s.fixed}`);
  }

  // 5. รายละเอียด
  push('', `## ${legacy ? 5 : 4}. ผลรายสถานการณ์`, '');
  for (const [g, label] of Object.entries(GROUPS)) {
    push(`### กลุ่ม: ${label}`, '');
    for (const s of scen.filter((x) => x.group === g)) {
      push(`#### ${s.id} ${s.title} — ${s.pass ? '✅ ผ่าน' : '❌ ไม่ผ่าน'}`, '');
      push(`ผลที่ต้องได้: ${s.expected}`, '');
      push('| ชุดทดสอบ | เงื่อนไขการทดลอง | ผลที่คาด | ผลที่ได้จริง | ผล |', '|---|---|---|---|---|');
      for (const r of s.results) push(`| ${SOURCE_LABEL[r.source]} | ${cell(r.condition)} | ${cell(r.expected)} | ${cell(r.actual)} | ${r.ok ? '✅' : '❌'} |`);
      for (const e of s.sims) {
        const runs = e.runs.filter(Boolean);
        const okRuns = runs.filter((c) => c.ok === true).length;
        const measured = runs.every((c) => c.ok === null);
        const uniq = [...new Set(runs.map((c) => c.detail || ''))];
        const details = uniq.length === 1
          ? `${uniq[0] || (okRuns === runs.length ? 'เป็นไปตามที่คาด' : 'ไม่เป็นไปตามที่คาด')}${runs.length > 1 ? ` (เหมือนกันทั้ง ${runs.length} รอบ)` : ''}`
          : runs.map((c, i) => `รอบ ${i + 1}: ${c.detail}`).join('<br>');
        push(`| ${SOURCE_LABEL.sim} | ${cell(e.name)} | ตามเงื่อนไขในข้อทดสอบ | ${cell(details)} | ${measured ? '📊 วัดค่า' : okRuns === runs.length ? `✅ ${okRuns}/${runs.length} รอบ` : `❌ ${okRuns}/${runs.length} รอบ`} |`);
      }
      const plain = [...s.dartTests, ...s.workerTests].filter((t) => !s.results.some((r) => r.test === clean(t.name)));
      for (const t of plain) push(`| ${s.workerTests.includes(t) ? SOURCE_LABEL.worker : SOURCE_LABEL.dart} | ${cell(clean(t.name))} | ตามชื่อข้อทดสอบ | ${t.ok ? 'เป็นไปตามที่คาดทุกข้อตรวจ' : 'ไม่เป็นไปตามที่คาด'} | ${t.ok ? '✅' : '❌'} |`);
      push('');
    }
  }

  push(`## ${legacy ? 6 : 5}. ข้อจำกัดของการทดลอง`, '');
  push('- ฐานข้อมูลเป็น Firestore Emulator ในเครื่องเดียวกัน ไม่มีความหน่วงและการหลุดของเครือข่ายมือถือจริง ตัวเลขเวลาจึงต่ำกว่าการใช้งานจริง และช่วงเวลาเสี่ยงของตรรกะก่อนแก้บนเครือข่ายจริงน่าจะกว้างกว่าที่วัดได้');
  push('- ตำแหน่ง GPS เป็นค่าที่ป้อนให้โค้ดจริงของแอป (จำลองสัญญาณดี/อ่อน/กระโดด/ขัดข้อง) ไม่ได้รับจากดาวเทียมจริง');
  push('- การเคลื่อนที่ของรถในสถานการณ์ครบวงจรเร่งเวลา 20 เท่า และระยะทางใช้เส้นตรงแทนเส้นทางถนนจริง');
  push('- การแสดงผลบนหน้าจอ แจ้งเตือนของระบบปฏิบัติการ และ Dynamic Island ทดสอบด้วยมือถือจริงตามตารางใน tools/multi_user_sim/README.md');
  return { md: L.join('\n') + '\n', nPass, total: scen.length };
}

function main() {
  const flags = Object.fromEntries(process.argv.slice(2).map((a) => {
    const m = /^--([^=]+)(?:=(.*))?$/.exec(a);
    return m ? [m[1], m[2] ?? true] : [a, true];
  }));
  const dir = resolve(flags.batch);
  const files = readdirSync(dir);
  const env = existsSync(join(dir, 'env.json')) ? JSON.parse(readFileSync(join(dir, 'env.json'), 'utf8')) : {};
  const flutter = readFlutter(join(dir, 'flutter.jsonl'));
  const worker = existsSync(join(dir, 'worker.tap')) ? readWorker(join(dir, 'worker.tap')) : { tests: [], rows: [] };
  const simRuns = files.filter((f) => /^sim-fixed-\d+\.json$/.test(f)).sort().map((f) => readSim(join(dir, f)));
  const legacy = files.includes('sim-legacy.json') ? readSim(join(dir, 'sim-legacy.json')) : null;
  const { md, nPass, total } = buildResults({ env, flutter, worker, simRuns, legacy });
  const out = resolve(flags.out ?? join(dir, 'TEST_RESULTS.md'));
  writeFileSync(out, md);
  writeFileSync(join(dir, 'TEST_RESULTS.md'), md);
  console.log(`ผลการทดลอง: ผ่าน ${nPass}/${total} สถานการณ์ → ${out}`);
  if (nPass !== total) process.exitCode = 1;
}

main();
