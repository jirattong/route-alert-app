#!/usr/bin/env node
// รวมผลการทดสอบอัตโนมัติทุกชุดเข้ากับรายการสถานการณ์ (catalog.mjs) → รายงานภาษาไทยรายสถานการณ์
//   node src/scenario_report.mjs --flutter=<flutter --reporter json> --worker=<node --test tap> --sim=<report-*.json|latest>
//   node src/scenario_report.mjs --doc=../../docs/TEST_SCENARIOS.md   (เขียนเอกสารรายการสถานการณ์อย่างเดียว)
import { readFileSync, writeFileSync, readdirSync, statSync, existsSync, mkdirSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { CATALOG, GROUPS, SOURCE_LABEL } from './catalog.mjs';

const TOOL_DIR = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const RESULTS = join(TOOL_DIR, 'results');
const TAG = /\[([SG]\d{2})\]/g; // S = ระบบหลายผู้ใช้, G = GPS และตำแหน่ง
const tagsOf = (name) => [...name.matchAll(TAG)].map((m) => m[1]);
const clean = (name) => name.replace(TAG, '').trim();
const cell = (s) => String(s ?? '').replace(/\|/g, '/').replace(/\n/g, ' ');

/** flutter test --reporter json: testStart (ชื่อ) + testDone (ผล) */
export function parseFlutter(text) {
  const names = new Map();
  const out = [];
  for (const line of text.split('\n')) {
    if (!line.startsWith('{')) continue;
    let e;
    try { e = JSON.parse(line); } catch { continue; }
    if (e.type === 'testStart') names.set(e.test.id, e.test.name);
    if (e.type === 'testDone' && !e.hidden && !e.skipped) {
      const name = names.get(e.testID) ?? '';
      out.push({ source: 'dart', name, ok: e.result === 'success' });
    }
  }
  return out;
}

/** node --test --test-reporter=tap */
export function parseTap(text) {
  const out = [];
  for (const line of text.split('\n')) {
    const m = /^\s*(not )?ok \d+ - (.*?)(?:\s+#.*)?$/.exec(line);
    if (m) out.push({ source: 'worker', name: m[2], ok: !m[1] });
  }
  return out;
}

/** รายงานของตัวจำลอง: check ที่ติด sid (ไม่นับข้อ integrity ที่ตรวจข้อมูลของตัวจำลองเอง) */
export function parseSim(run) {
  const out = [];
  for (const r of run.results ?? []) {
    for (const c of r.checks ?? []) {
      if (c.kind === 'integrity') continue;
      out.push({ source: 'sim', name: c.name, ok: c.ok, detail: c.detail, sid: c.sid ?? [], scenario: r.name });
    }
  }
  return out;
}

export function evaluate(evidence) {
  return CATALOG.map((s) => {
    const mine = evidence.filter((e) => (e.sid ?? tagsOf(e.name)).includes(s.id));
    const graded = mine.filter((e) => e.ok !== null);
    const missing = s.automated.filter((src) => !mine.some((e) => e.source === src));
    const failed = graded.filter((e) => e.ok === false);
    const status = failed.length ? 'fail' : missing.length ? 'missing' : 'pass';
    return { ...s, evidence: mine, missing, failed, status };
  });
}

const VERDICT = { pass: '✅ ผ่าน', fail: '❌ ไม่ผ่าน', missing: '⏸️ ยังไม่ได้รัน' };

export function renderReport(rows, meta) {
  const L = [];
  const n = (st) => rows.filter((r) => r.status === st).length;
  L.push('# ผลการทดสอบอัตโนมัติตามสถานการณ์ — RouteAlert', '');
  L.push(`- วันเวลา: ${meta.when} (เวลาไทย)`);
  L.push(`- สรุป: ผ่าน ${n('pass')}/${rows.length} สถานการณ์ · ไม่ผ่าน ${n('fail')} · ยังไม่ได้รัน ${n('missing')}`);
  L.push(`- ชุดทดสอบ: ${meta.sources.map((s) => `${SOURCE_LABEL[s.key]} ${s.passed}/${s.total} ข้อผ่าน${s.file ? ` (\`${s.file}\`)` : ''}`).join(' · ')}`);
  if (meta.appLogic === 'legacy') L.push('- ⚠️ ตัวจำลองรันด้วยตรรกะก่อนแก้ (`--app-logic=legacy`) — ไว้แสดงว่าชุดทดสอบจับบั๊กเดิมได้');
  L.push('', 'แต่ละสถานการณ์ผ่านเมื่อ **ทุกข้อทดสอบที่ติดรหัสนั้นผ่าน** และมีผลจากทุกชุดทดสอบที่ระบุไว้', '');
  L.push('| รหัส | สถานการณ์ | ผลที่ต้องได้ | ทดสอบโดย | ผล |', '|---|---|---|---|---|');
  for (const r of rows) {
    const by = r.automated.map((src) => `${SOURCE_LABEL[src]} (${r.evidence.filter((e) => e.source === src).length})`).join('<br>');
    L.push(`| ${r.id} | ${cell(r.title)} | ${cell(r.expected)} | ${by} | ${VERDICT[r.status]} |`);
  }
  const fixed = rows.filter((r) => r.fixed);
  if (fixed.length) {
    L.push('', '## บั๊กที่พบจากสถานการณ์เหล่านี้ (แก้แล้ว)', '');
    for (const r of fixed) L.push(`- **${r.id} ${r.title}** — ${r.fixed}`);
  }
  for (const [g, label] of Object.entries(GROUPS)) {
    L.push('', `## กลุ่ม ${g}: ${label}`);
    for (const r of rows.filter((x) => x.group === g)) {
      L.push('', `### ${r.id} ${r.title} — ${VERDICT[r.status]}`, '');
      L.push(`- โอกาสเกิดจริง: ${r.why}`, `- ผู้ใช้ที่เกี่ยวข้อง: ${r.actors}`, `- ผลที่ต้องได้: ${r.expected}`);
      if (r.missing.length) L.push(`- ยังไม่มีผลจาก: ${r.missing.map((m) => SOURCE_LABEL[m]).join(', ')}`);
      L.push('', '| ชุดทดสอบ | ข้อทดสอบ | ผล |', '|---|---|---|');
      for (const e of r.evidence) {
        const v = e.ok === null ? '📊 วัดค่า' : e.ok ? '✅' : '❌';
        L.push(`| ${SOURCE_LABEL[e.source]} | ${cell(clean(e.name))}${e.detail ? ` — ${cell(e.detail)}` : ''} | ${v} |`);
      }
    }
  }
  return L.join('\n') + '\n';
}

export function renderCatalogDoc() {
  const L = [];
  const nS = CATALOG.filter((c) => c.id.startsWith('S')).length;
  const nG = CATALOG.filter((c) => c.id.startsWith('G')).length;
  L.push(`# สถานการณ์ทดสอบ RouteAlert (${CATALOG.length} สถานการณ์)`, '');
  L.push(`- **S01–S${String(nS).padStart(2, '0')}** (${nS} ข้อ) การใช้งานหลายผู้ใช้พร้อมกัน: แจ้งเหตุ, โรงพยาบาลหลายแห่ง, รับเคส, ปฏิบัติงาน, แจ้งเตือน`);
  L.push(`- **G01–G${String(nG).padStart(2, '0')}** (${nG} ข้อ) GPS และตำแหน่ง: ตำแหน่งผู้แจ้ง, คุณภาพสัญญาณ, เรดาร์ผู้ขับขี่, ตำแหน่งรถพยาบาล`, '');
  L.push('เอกสารนี้สร้างจาก `tools/multi_user_sim/src/catalog.mjs` — แก้ที่ไฟล์นั้นแล้วรัน `node src/scenario_report.mjs --doc=../../docs/TEST_SCENARIOS.md`', '');
  L.push('ทุกสถานการณ์ทดสอบอัตโนมัติ รันทั้งหมดด้วยคำสั่งเดียว: `tools/run_all_scenarios.sh` (ดูหัวข้อท้ายเอกสาร)', '');
  L.push('ชุดทดสอบที่ใช้:', '');
  L.push(`- **${SOURCE_LABEL.sim}** — ผู้ใช้จำลองแต่ละคนใช้การเชื่อมต่อ Firebase แยกกันเหมือนมือถือคนละเครื่อง ทำงานพร้อมกันจริงบนฐานข้อมูลจำลอง`);
  L.push(`- **${SOURCE_LABEL.dart}** — \`flutter test\` เรียก service จริงของแอป (IncidentService, ตัวแจ้งเตือน, เรดาร์) กับ Firestore จำลองที่มี transaction แบบเดียวกับของจริง`);
  L.push(`- **${SOURCE_LABEL.worker}** — ตัวส่ง push จริงกับ Firestore/FCM จำลอง`, '');
  L.push('| รหัส | กลุ่ม | สถานการณ์ | โอกาสเกิดจริง | ผู้ใช้ที่เกี่ยวข้อง | ผลที่ต้องได้ | ทดสอบโดย |', '|---|---|---|---|---|---|---|');
  for (const s of CATALOG) {
    L.push(`| ${s.id} | ${GROUPS[s.group]} | ${cell(s.title)} | ${cell(s.why)} | ${cell(s.actors)} | ${cell(s.expected)} | ${s.automated.map((x) => SOURCE_LABEL[x]).join('<br>')} |`);
  }
  L.push('', '## บั๊กที่พบจากการคิดสถานการณ์เหล่านี้ (แก้แล้ว)', '');
  for (const s of CATALOG.filter((x) => x.fixed)) L.push(`- **${s.id} ${s.title}** — ${s.fixed}`);
  L.push('', '## วิธีรัน', '');
  L.push('```bash', 'cd route-alert-app', 'tools/run_all_scenarios.sh             # ทุกชุด (~10–20 นาที) → tools/multi_user_sim/results/scenarios-*.md',
    'tools/run_all_scenarios.sh --quick     # เฉพาะ Dart + Worker (~1 นาที, ไม่ต้องมี Java)',
    'tools/run_all_scenarios.sh --legacy    # ตัวจำลองใช้ตรรกะก่อนแก้ ไว้แสดงว่าจับบั๊กเดิมได้',
    'tools/run_all_scenarios.sh --results   # เก็บผลการทดลอง (ตัวจำลอง 3 รอบ + ก่อนแก้ 1 รอบ) → docs/TEST_RESULTS.md', '```', '');
  L.push('ผลการทดลองจริง (ตัวเลขที่วัดได้ เปรียบเทียบก่อน/หลังแก้ ผลรายกรณี): [TEST_RESULTS.md](TEST_RESULTS.md)', '');
  L.push('ตัวจำลองต้องมี Node 20+, Java 11+ และไฟล์ Firestore emulator (`firebase emulators:start --only firestore` ครั้งแรกจะดาวน์โหลดให้)');
  return L.join('\n') + '\n';
}

function latestSimReport() {
  if (!existsSync(RESULTS)) return null;
  const files = readdirSync(RESULTS).filter((f) => /^report-.*\.json$/.test(f)).map((f) => join(RESULTS, f));
  files.sort((a, b) => statSync(b).mtimeMs - statSync(a).mtimeMs);
  return files[0] ?? null;
}

function bangkokNow() {
  const d = new Date(Date.now() + 7 * 3600e3).toISOString();
  return d.slice(0, 19).replace('T', ' ');
}

function main() {
  const flags = Object.fromEntries(process.argv.slice(2).map((a) => {
    const m = /^--([^=]+)(?:=(.*))?$/.exec(a);
    return m ? [m[1], m[2] ?? true] : [a, true];
  }));
  if (flags.doc) {
    writeFileSync(resolve(flags.doc), renderCatalogDoc());
    console.log(`เขียน ${flags.doc}`);
    return;
  }
  const evidence = [];
  const sources = [];
  const add = (key, file, parse) => {
    if (!file || !existsSync(file)) return;
    const items = parse(file);
    evidence.push(...items);
    const graded = items.filter((e) => e.ok !== null);
    sources.push({ key, file: file.replace(`${TOOL_DIR}/`, ''), total: graded.length, passed: graded.filter((e) => e.ok).length });
  };
  add('dart', flags.flutter, (f) => parseFlutter(readFileSync(f, 'utf8')));
  add('worker', flags.worker, (f) => parseTap(readFileSync(f, 'utf8')));
  const simFile = flags.sim === 'latest' ? latestSimReport() : flags.sim;
  let appLogic = null;
  add('sim', simFile, (f) => {
    const run = JSON.parse(readFileSync(f, 'utf8'));
    appLogic = run.config?.appLogic ?? null;
    return parseSim(run);
  });
  const rows = evaluate(evidence);
  const stamp = new Date(Date.now() + 7 * 3600e3).toISOString().slice(0, 19).replace(/[-:]/g, '').replace('T', '-');
  mkdirSync(RESULTS, { recursive: true });
  const md = join(RESULTS, `scenarios-${stamp}.md`);
  writeFileSync(md, renderReport(rows, { when: bangkokNow(), sources, appLogic }));
  writeFileSync(md.replace(/\.md$/, '.json'), JSON.stringify({ rows, sources }, null, 2));
  for (const r of rows) {
    const extra = r.status === 'fail' ? ` — ${r.failed.map((e) => clean(e.name)).slice(0, 2).join('; ')}`
      : r.status === 'missing' ? ` — ยังไม่มีผลจาก ${r.missing.join(', ')}` : '';
    console.log(`  ${VERDICT[r.status]}  ${r.id} ${r.title}${extra}`);
  }
  const pass = rows.filter((r) => r.status === 'pass').length;
  console.log(`\nผ่าน ${pass}/${rows.length} สถานการณ์ · รายงาน: ${md}`);
  if (rows.some((r) => r.status !== 'pass')) process.exitCode = 1;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
