// รายงานผลภาษาไทยพร้อมใช้ในเล่มวิทยานิพนธ์ (Markdown) + ข้อมูลดิบ (JSON)
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { round1 } from './util.mjs';

const fmtStats = (s) =>
  !s || s.n === 0
    ? '–'
    : `n=${s.n} · ต่ำสุด ${round1(s.min)} · มัธยฐาน ${round1(s.p50)} · p95 ${round1(s.p95)} · สูงสุด ${round1(s.max)}`;

const STAT_LABELS = {
  writeLatencyMs: 'เวลาบันทึกเคส (ms)',
  propagationMs: 'เวลาตั้งแต่แจ้งจนเครื่องโรงพยาบาลเห็น (ms)',
  transactionMs: 'เวลา transaction รับเคส (ms)',
  createToAssignedMs: 'แจ้งเหตุ → ผู้แจ้งเห็นว่ามีรถรับ (ms)',
  createToResolvedMs: 'แจ้งเหตุ → ผู้แจ้งเห็นว่าเคสจบ (ms, เวลาจำลองเร่งขึ้น)',
  dispatchTxMs: 'เวลา transaction สั่งจ่ายรถ (ms)',
  mqttDeliveryMs: 'เวลาส่งตำแหน่งรถผ่าน MQTT (ms)',
  assignmentReachesOtherHospitalMs: 'สั่งจ่ายรถ → อีกโรงพยาบาลเห็นว่ารถไม่ว่าง (ms)',
  closeReachesAmbulanceMs: 'โรงพยาบาลปิดเคส → เครื่องรถเห็นว่าเคสปิด (ms)',
};

export function renderMarkdown(run) {
  const lines = [];
  const all = run.results.flatMap((r) => r.checks);
  // ข้อ "ตรวจข้อมูล" (integrity) ยืนยันว่าตัวจำลองสร้างข้อมูลถูกรูปแบบ ไม่ได้ทดสอบพฤติกรรมของระบบ จึงไม่นับเป็น "ผ่าน"
  const passCount = all.filter((c) => c.ok === true && c.kind !== 'integrity').length;
  const integrityCount = all.filter((c) => c.ok === true && c.kind === 'integrity').length;
  const failCount = all.filter((c) => c.ok === false).length;
  lines.push(`# ผลการทดสอบระบบ RouteAlert แบบหลายผู้ใช้พร้อมกัน`);
  lines.push('');
  lines.push(`- วันเวลา: ${run.startedAtBangkok} (เวลาไทย)`);
  lines.push(`- เป้าหมาย: ${run.target === 'emulator' ? 'Firestore Emulator ในเครื่อง (ไม่ใช่เซิร์ฟเวอร์จริง)' : `Firebase จริง (${run.projectId})`}`);
  lines.push(`- ตรรกะแอปที่จำลอง: ${run.config?.appLogic === 'legacy' ? 'ก่อนแก้ (legacy — รถคันเดียวต่อเคส ไม่มีล็อกรถ เลื่อนสถานะไม่มีเงื่อนไข)' : 'ปัจจุบัน (เคสเดียวหลายคัน + ล็อกรถ + เลื่อนสถานะแบบมีเงื่อนไข)'}`);
  lines.push(`- รหัสรอบทดสอบ: \`${run.runId}\` · Node ${run.node} · ผู้ใช้จำลองทั้งหมด ${run.devices} เครื่องเสมือน`);
  lines.push(`- สรุป: ผ่าน ${passCount} ข้อ · ไม่ผ่าน ${failCount} ข้อ · วัดค่า ${all.filter((c) => c.ok === null).length} ข้อ · ตรวจความถูกต้องของข้อมูลจำลอง ${integrityCount} ข้อ (ไม่นับเป็นผลทดสอบ)`);
  if (run.target === 'emulator') {
    lines.push('');
    lines.push('> หมายเหตุ: ตัวเลขเวลาวัดบน emulator ในเครื่องเดียว ไม่มีเครือข่ายจริง จึงเร็วกว่าการใช้งานจริง — ใช้ยืนยันความถูกต้องของตรรกะ ส่วนตัวเลขเวลาที่ใช้อ้างอิงควรมาจากการรันกับ Firebase จริง');
  }
  lines.push('');
  lines.push('ผู้ใช้จำลองแต่ละคนใช้ Firebase app แยกกัน (การเชื่อมต่อ/listener/cache ของตัวเอง) เหมือนมือถือคนละเครื่อง และทำงานตามตรรกะเดียวกับโค้ดแอปทุกขั้น (เลือกโรงพยาบาลใกล้สุด, transaction รับเคส, การเลื่อนสถานะ, ETA, ใกล้ถึงจุดเกิดเหตุ)');
  for (const r of run.results) {
    lines.push('');
    lines.push(`## ${r.title}`);
    lines.push('');
    lines.push(`พารามิเตอร์: ${Object.entries(r.params).map(([k, v]) => `${k}=${v}`).join(', ')}`);
    lines.push('');
    lines.push('| ข้อทดสอบ | ผล | รายละเอียด |');
    lines.push('|---|---|---|');
    for (const c of r.checks) {
      const verdict = c.ok === null ? '📊 วัดค่า' : !c.ok ? '❌ ไม่ผ่าน' : c.kind === 'integrity' ? '☑️ ตรวจข้อมูล' : '✅ ผ่าน';
      lines.push(`| ${c.name} | ${verdict} | ${(c.detail || '').replace(/\|/g, '/') || '–'} |`);
    }
    const statRows = Object.entries(r.metrics ?? {}).filter(([k]) => STAT_LABELS[k]);
    if (statRows.length) {
      lines.push('');
      lines.push('| ตัวชี้วัดเวลา | ค่า |');
      lines.push('|---|---|');
      for (const [k, v] of statRows) lines.push(`| ${STAT_LABELS[k]} | ${fmtStats(v)} |`);
    }
    const other = Object.entries(r.metrics ?? {}).filter(([k]) => !STAT_LABELS[k] && k !== 'rounds');
    if (other.length) {
      lines.push('');
      for (const [k, v] of other) lines.push(`- ${k}: \`${typeof v === 'object' ? JSON.stringify(v) : v}\``);
    }
    if (r.cost) lines.push(`- จำนวนการอ่าน/เขียน Firestore (ประมาณ): อ่าน ${r.cost.reads} · เขียน ${r.cost.writes} · ลบ ${r.cost.deletes}`);
    for (const n of r.notes ?? []) lines.push(`- ${n}`);
  }
  if (run.cleanup) {
    lines.push('');
    lines.push(`## ล้างข้อมูลจำลอง`);
    lines.push('');
    lines.push(`ลบ ${run.cleanup.deleted} เอกสาร · เหลือ ${run.cleanup.remaining} (ต้องเป็น 0)`);
  }
  return lines.join('\n') + '\n';
}

export function writeReport(dir, run) {
  mkdirSync(dir, { recursive: true });
  const stamp = run.runId;
  const md = join(dir, `report-${stamp}.md`);
  const json = join(dir, `report-${stamp}.json`);
  writeFileSync(md, renderMarkdown(run));
  writeFileSync(json, JSON.stringify(run, null, 2));
  return { md, json };
}
