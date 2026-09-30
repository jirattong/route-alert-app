// รูปร่างเอกสารให้ตรงกับ IncidentReport.toMap/fromMap, HospitalProfile, EmergencyVehicleData
// ของแอป — ตัวจำลองต้องเขียน/อ่านข้อมูลแบบเดียวกับมือถือจริงทุกฟิลด์
import { bangkokIso, parseDartIso, isLocalNoOffset, isUtcZ } from './timefmt.mjs';

export const SIM_PREFIX = 'SIM-';
export const COLL = {
  incidents: 'incident_reports',
  hospitals: 'hospital_profiles',
  fleet: 'emergency_fleet',
  locks: 'ambulance_locks',
};

// ---- เคสเดียวรับได้หลายคัน (ตรงกับ AssignedUnit ใน incident_report.dart) ----
export const UNSET_PLATE = 'ยังไม่ระบุทะเบียน';

/** กุญแจ "รถ 1 คัน" = ทะเบียนที่ตัดช่องว่าง/ขีด/จุด ถ้าไม่มีทะเบียนใช้รหัสหน่วย */
export function vehicleKeyFor(plate, unitId) {
  const p = String(plate ?? '').toLowerCase().replace(/[\s\-./_#]/g, '');
  if (!p || p === UNSET_PLATE) return `unit_${unitId}`;
  return `plate_${p}`;
}

/** ทุกหน่วยในเคส (เคสเก่ามีแค่ assignedAmbulanceId) */
export function unitsOf(map) {
  const list = Array.isArray(map?.assignedUnits) ? map.assignedUnits.filter((u) => u && u.unitId) : [];
  if (list.length) return list;
  if (!map?.assignedAmbulanceId) return [];
  return [{
    unitId: map.assignedAmbulanceId,
    plate: map.assignedAmbulancePlate ?? '',
    callSign: map.assignedAmbulanceCallSign ?? '',
    vehicleKey: vehicleKeyFor(map.assignedAmbulancePlate, map.assignedAmbulanceId),
    assignedBy: map.assignedBy ?? 'hospital',
  }];
}

export const vehicleCountOf = (map) => new Set(unitsOf(map).map((u) => u.vehicleKey)).size;

/** ฟิลด์ที่คำนวณจากรายชื่อหน่วย (AssignedUnit.fieldsFor) */
export function unitFields(units) {
  const keys = [...new Set(units.map((u) => u.vehicleKey))];
  return {
    assignedUnits: units,
    assignedUnitIds: units.map((u) => u.unitId),
    assignedVehicleKeys: keys,
    assignedVehicleCount: keys.length,
  };
}

export const STATUS_RANK = { pending: 0, assigned: 1, at_scene: 2, transporting: 3, approaching_er: 4, resolved: 5 };
export const isJoinable = (map) => map.archived !== true && ['pending', 'assigned', 'at_scene'].includes(map.status);

export const INCIDENT_TYPES = [
  'อุบัติเหตุทางรถยนต์',
  'ผู้ป่วยหมดสติ / หัวใจหยุดเต้น',
  'ไฟไหม้ / สารเคมีรั่วไหล',
  'เหตุฉุกเฉินอื่นๆ',
];
export const SEVERITIES = [
  'วิกฤต (Code Red - หมดสติ / บาดเจ็บสาหัส)',
  'ปานกลาง (Medium - บาดเจ็บแต่รู้สึกตัว)',
  'เล็กน้อย (Low - บาดเจ็บเล็กน้อย)',
];
export const STATUSES = ['pending', 'assigned', 'at_scene', 'transporting', 'approaching_er', 'resolved', 'cancelled'];
export const TERMINAL = new Set(['resolved', 'cancelled']);
export const isClosed = (i) => i.status === 'resolved' || i.status === 'cancelled';

/** คู่ (status, statusStep) ที่แอปเขียนได้ — (resolved,4) มาจากหน้ารายละเอียดเคสของรถพยาบาล */
export const VALID_PAIRS = new Set([
  'pending|0',
  'assigned|1',
  'at_scene|2',
  'transporting|3',
  'approaching_er|4',
  'resolved|5',
  'resolved|4',
]);
export const isValidPair = (status, step) => status === 'cancelled' || VALID_PAIRS.has(`${status}|${step}`);

export const INCIDENT_KEYS = [
  'id', 'type', 'severity', 'description', 'latitude', 'longitude', 'province', 'address',
  'photoBase64', 'photosBase64', 'scenePhotosBase64', 'reporterName', 'reporterEmail', 'reporterPhone',
  'status', 'statusStep', 'isErPrepared', 'eta', 'assignedAmbulanceId', 'assignedAmbulancePlate',
  'assignedAmbulanceCallSign', 'targetHospitalId', 'hospitalName', 'hospitalLatitude', 'hospitalLongitude',
  'hospitalDistanceKm', 'assignedBy', 'ambulanceNearSceneAt', 'ambulanceNearEtaMinutes',
  'ambulanceEtaMinutes', 'ambulanceDistanceMeters', 'ambulanceEtaTarget', 'ambulanceEtaUpdatedAt',
  'createdAt', 'archived',
];

/** แอป 4 รพ. ตั้งต้นใน HospitalLocationService (ใช้เมื่อ hospital_profiles ยังว่าง) */
export const HARDCODED_HOSPITALS = [
  { hospitalId: 'HOSP-01', hospitalName: 'โรงพยาบาลมหาราชนครเชียงใหม่ (สวนดอก)', latitude: 19.0284, longitude: 99.8962, address: '110 ถ.อินทวโรรส ต.ศรีภูมิ อ.เมือง จ.เชียงใหม่', erPhone: '053-936150', isErAvailable: true },
  { hospitalId: 'HOSP-02', hospitalName: 'โรงพยาบาลนครพิงค์ (ศูนย์อุบัติเหตุภาคเหนือ)', latitude: 18.8475, longitude: 98.966, address: '159 ม.10 ถ.โชตนา ต.ดอนแก้ว อ.แม่ริม จ.เชียงใหม่', erPhone: '053-999200', isErAvailable: true },
  { hospitalId: 'HOSP-03', hospitalName: 'โรงพยาบาลสันทราย', latitude: 18.892, longitude: 99.043, address: 'ต.หนองหาร อ.สันทราย จ.เชียงใหม่', erPhone: '053-865399', isErAvailable: true },
  { hospitalId: 'HOSP-04', hospitalName: 'โรงพยาบาลฝาง', latitude: 19.916, longitude: 99.213, address: 'ต.เวียง อ.ฝาง จ.เชียงใหม่', erPhone: '053-451151', isErAvailable: true },
];

/** IncidentReport(...) ของหน้า SOS แล้ว toMap() — ใส่ทุกคีย์รวมค่า null เหมือนแอป */
export function buildSosIncidentMap({
  id, type, severity, description, latitude, longitude, address, photos, reporterName,
  reporterEmail, reporterPhone, nearest, createdAt, extra,
}) {
  const map = {
    id,
    type,
    severity,
    description,
    latitude,
    longitude,
    province: 'เชียงใหม่',
    address,
    photoBase64: photos.length > 0 ? photos[0] : null,
    photosBase64: photos,
    scenePhotosBase64: [],
    reporterName,
    reporterEmail,
    reporterPhone,
    status: 'pending',
    statusStep: 0,
    isErPrepared: false,
    eta: `${nearest.etaMinutes} นาที`,
    assignedAmbulanceId: null,
    assignedAmbulancePlate: null,
    assignedAmbulanceCallSign: null,
    targetHospitalId: nearest.profile.hospitalId,
    hospitalName: nearest.profile.hospitalName,
    hospitalLatitude: nearest.profile.latitude,
    hospitalLongitude: nearest.profile.longitude,
    hospitalDistanceKm: nearest.distanceKm,
    assignedBy: null,
    ambulanceNearSceneAt: null,
    ambulanceNearEtaMinutes: null,
    ambulanceEtaMinutes: null,
    ambulanceDistanceMeters: null,
    ambulanceEtaTarget: null,
    ambulanceEtaUpdatedAt: null,
    createdAt: bangkokIso(createdAt),
    archived: false,
  };
  // ฟิลด์ติดป้ายข้อมูลจำลอง — แอปไม่อ่าน (fromMap ข้ามคีย์ที่ไม่รู้จัก)
  return { ...map, ...extra };
}

class DartTypeError extends Error {}
const str = (v, key) => {
  if (v === undefined || v === null) return null;
  if (typeof v !== 'string') throw new DartTypeError(`${key}: expected String, got ${typeof v}`);
  return v;
};
const num = (v, key) => {
  if (v === undefined || v === null) return null;
  if (typeof v !== 'number') throw new DartTypeError(`${key}: expected num, got ${typeof v}`);
  return v;
};
const list = (v, key) => {
  if (v === undefined || v === null) return null;
  if (!Array.isArray(v)) throw new DartTypeError(`${key}: expected List, got ${typeof v}`);
  return v;
};

/**
 * จำลอง IncidentReport.fromMap — throw เมื่อชนิดข้อมูลผิด (ในแอปเคสนั้นจะ "หายเงียบ"
 * จาก listener เพราะ try/catch ต่อเอกสาร) คืนออบเจ็กต์ที่ createdAt เป็น epoch ms
 */
export function parseIncident(map, nowMsFallback = Date.now()) {
  const rawPhotos = list(map.photosBase64, 'photosBase64');
  const photos = rawPhotos ? rawPhotos.map(String) : map.photoBase64 != null ? [String(map.photoBase64)] : [];
  const createdAtMs = map.createdAt != null ? parseDartIso(String(map.createdAt)) : null;
  const nearAt = map.ambulanceNearSceneAt != null ? parseDartIso(String(map.ambulanceNearSceneAt)) : null;
  const etaAt = map.ambulanceEtaUpdatedAt != null ? parseDartIso(String(map.ambulanceEtaUpdatedAt)) : null;
  return {
    id: str(map.id, 'id') ?? '',
    type: str(map.type, 'type') ?? 'อุบัติเหตุทางรถยนต์',
    severity: str(map.severity, 'severity') ?? 'วิกฤต (Code Red)',
    description: str(map.description, 'description') ?? '',
    latitude: num(map.latitude, 'latitude') ?? 19.0284,
    longitude: num(map.longitude, 'longitude') ?? 99.8962,
    province: str(map.province, 'province') ?? 'เชียงใหม่',
    address: str(map.address, 'address') ?? '',
    photosBase64: photos,
    reporterName: str(map.reporterName, 'reporterName') ?? 'ผู้ใช้งาน RouteAlert',
    reporterEmail: str(map.reporterEmail, 'reporterEmail') ?? '',
    reporterPhone: str(map.reporterPhone, 'reporterPhone') ?? '',
    status: str(map.status, 'status') ?? 'pending',
    statusStep: Math.trunc(num(map.statusStep, 'statusStep') ?? 0),
    isErPrepared: map.isErPrepared === true,
    eta: str(map.eta, 'eta') ?? '5 นาที',
    assignedAmbulanceId: str(map.assignedAmbulanceId, 'assignedAmbulanceId'),
    assignedAmbulancePlate: str(map.assignedAmbulancePlate, 'assignedAmbulancePlate'),
    assignedAmbulanceCallSign: str(map.assignedAmbulanceCallSign, 'assignedAmbulanceCallSign'),
    units: unitsOf(map),
    targetHospitalId: str(map.targetHospitalId, 'targetHospitalId'),
    hospitalName: str(map.hospitalName, 'hospitalName'),
    hospitalLatitude: num(map.hospitalLatitude, 'hospitalLatitude'),
    hospitalLongitude: num(map.hospitalLongitude, 'hospitalLongitude'),
    hospitalDistanceKm: num(map.hospitalDistanceKm, 'hospitalDistanceKm'),
    assignedBy: map.assignedBy == null ? null : String(map.assignedBy),
    ambulanceNearSceneAt: nearAt,
    ambulanceNearEtaMinutes: num(map.ambulanceNearEtaMinutes, 'ambulanceNearEtaMinutes'),
    ambulanceEtaMinutes: num(map.ambulanceEtaMinutes, 'ambulanceEtaMinutes'),
    ambulanceDistanceMeters: num(map.ambulanceDistanceMeters, 'ambulanceDistanceMeters'),
    ambulanceEtaTarget: map.ambulanceEtaTarget == null ? null : String(map.ambulanceEtaTarget),
    ambulanceEtaUpdatedAt: etaAt,
    ambulanceEtaUpdatedAtRaw: map.ambulanceEtaUpdatedAt ?? null,
    createdAt: createdAtMs ?? nowMsFallback,
    createdAtValid: createdAtMs != null,
    archived: map.archived === true,
    cancelledBy: map.cancelledBy ?? null,
    simulation: map.simulation === true,
  };
}

export const canBeCancelled = (i) => i.status === 'pending' && i.statusStep === 0;

/** ตรวจเอกสารเคสที่ตัวจำลองสร้าง: คืนรายการปัญหา (ว่าง = ผ่าน) */
export function validateIncidentDoc(docId, map) {
  const problems = [];
  try {
    parseIncident(map);
  } catch (e) {
    problems.push(`fromMap จะ throw (เคสหายจาก listener): ${e.message}`);
  }
  if (map.id !== docId) problems.push(`id field (${map.id}) ≠ doc id (${docId})`);
  for (const k of INCIDENT_KEYS) if (!(k in map)) problems.push(`ขาดคีย์ ${k}`);
  if (!isLocalNoOffset(map.createdAt) || parseDartIso(map.createdAt) == null) {
    problems.push(`createdAt ไม่ใช่ ISO เวลาท้องถิ่น (ไม่มี Z): ${map.createdAt}`);
  }
  if (!STATUSES.includes(map.status)) problems.push(`status แปลก: ${map.status}`);
  if (!isValidPair(map.status, map.statusStep)) problems.push(`คู่ status/step ไม่ถูก: ${map.status}/${map.statusStep}`);
  if (!INCIDENT_TYPES.includes(map.type)) problems.push(`type ไม่อยู่ในตัวเลือกของแอป: ${map.type}`);
  if (!SEVERITIES.includes(map.severity)) problems.push(`severity ไม่อยู่ในตัวเลือกของแอป: ${map.severity}`);
  if (!Array.isArray(map.photosBase64) || map.photosBase64.length > 5) problems.push('photosBase64 ต้องเป็น list 0-5 รูป');
  if (map.photosBase64?.length > 0 && map.photoBase64 !== map.photosBase64[0]) problems.push('photoBase64 ≠ รูปแรก');
  if (!/^\d+ นาที$/.test(map.eta ?? '')) problems.push(`eta รูปแบบผิด: ${map.eta}`);
  if (map.ambulanceEtaUpdatedAt != null && !isUtcZ(map.ambulanceEtaUpdatedAt)) {
    problems.push(`ambulanceEtaUpdatedAt ต้องเป็น UTC ลงท้าย Z: ${map.ambulanceEtaUpdatedAt}`);
  }
  if (map.ambulanceNearSceneAt != null && !isLocalNoOffset(map.ambulanceNearSceneAt)) {
    problems.push(`ambulanceNearSceneAt ต้องเป็นเวลาท้องถิ่นไม่มี Z: ${map.ambulanceNearSceneAt}`);
  }
  if (map.cancelledAt != null && !isLocalNoOffset(map.cancelledAt)) problems.push('cancelledAt ต้องเป็นเวลาท้องถิ่นไม่มี Z');
  if (map.simulation !== true) problems.push('ไม่มีป้าย simulation: true');
  if (!String(docId).startsWith(SIM_PREFIX)) problems.push('doc id ไม่ขึ้นต้นด้วย SIM-');
  return problems;
}

// ---------- hospital_profiles ----------
export function hospitalToMap(h, extra = {}) {
  return {
    hospitalId: h.hospitalId,
    hospitalName: h.hospitalName,
    latitude: h.latitude,
    longitude: h.longitude,
    address: h.address,
    erPhone: h.erPhone,
    isErAvailable: h.isErAvailable,
    lastUpdated: bangkokIso(new Date()),
    ...extra,
  };
}

/** HospitalProfile.fromMap (ค่าตั้งต้นแบบเดียวกับแอป) */
export function parseHospital(map) {
  return {
    hospitalId: str(map.hospitalId, 'hospitalId') ?? 'HOSP-01',
    hospitalName: str(map.hospitalName, 'hospitalName') ?? 'ศูนย์การแพทย์ฉุกเฉิน มหาราชนคร',
    latitude: num(map.latitude, 'latitude') ?? 19.0284,
    longitude: num(map.longitude, 'longitude') ?? 99.8962,
    address: str(map.address, 'address') ?? 'อำเภอเมือง จังหวัดเชียงใหม่',
    erPhone: str(map.erPhone, 'erPhone') ?? '053-936150 (สายด่วน ER)',
    isErAvailable: map.isErAvailable ?? true,
    simulation: map.simulation === true,
  };
}

// ---------- EmergencyVehicleData (MQTT payload / emergency_fleet) ----------
export function vehicleToMap(v) {
  const m = {
    id: v.id,
    callSign: v.callSign,
    latitude: v.latitude,
    longitude: v.longitude,
    speed: v.speed,
    heading: v.heading,
    plateNumber: v.plateNumber,
    emergencyType: v.emergencyType,
    sirenActive: v.sirenActive,
    timestamp: v.timestamp,
  };
  if (v.routePoints != null) m.routePoints = v.routePoints.map((p) => [p.latitude, p.longitude]);
  if (v.turnIntent != null) m.turnIntent = v.turnIntent;
  if (v.destinationName != null) m.destinationName = v.destinationName;
  if (v.simulation) m.simulation = true;
  return m;
}

/** EmergencyMqttService.firestoreMapFor — Firestore ห้าม array ซ้อน array จึงเก็บ {lat,lng} ≤ ~200 จุด */
export function firestoreMapFor(v) {
  const map = vehicleToMap(v);
  const route = v.routePoints;
  if (route != null && route.length > 0) {
    const step = Math.min(route.length, Math.max(1, Math.ceil(route.length / 200)));
    const sampled = [];
    for (let i = 0; i < route.length; i += step) sampled.push(route[i]);
    if ((route.length - 1) % step !== 0) sampled.push(route[route.length - 1]);
    map.routePoints = sampled.map((p) => ({ lat: p.latitude, lng: p.longitude }));
  }
  return map;
}

/** EmergencyVehicleData.fromMap — throw เมื่อชนิดผิด/timestamp parse ไม่ได้ (ข้อความถูกทิ้ง) */
export function parseVehicle(map) {
  let routePoints = null;
  if (Array.isArray(map.routePoints)) {
    routePoints = map.routePoints.map((pt) => {
      if (Array.isArray(pt) && pt.length >= 2) return { latitude: num(pt[0], 'lat'), longitude: num(pt[1], 'lng') };
      if (pt && typeof pt === 'object' && typeof pt.lat === 'number' && typeof pt.lng === 'number') {
        return { latitude: pt.lat, longitude: pt.lng };
      }
      return { latitude: 13.7563, longitude: 100.5018 };
    });
  }
  const sirenRaw = map.sirenActive;
  if (sirenRaw != null && typeof sirenRaw !== 'boolean') throw new DartTypeError('sirenActive: expected bool');
  let ts = null;
  if (map.timestamp != null) {
    if (typeof map.timestamp !== 'string') throw new DartTypeError('timestamp: expected String');
    ts = parseDartIso(map.timestamp);
    if (ts == null) throw new Error(`Invalid date format ${map.timestamp}`);
  }
  return {
    id: str(map.id, 'id') ?? 'AMB_01',
    callSign: str(map.callSign, 'callSign') ?? 'Ambulance 1669',
    latitude: num(map.latitude, 'latitude') ?? 13.7563,
    longitude: num(map.longitude, 'longitude') ?? 100.5018,
    speed: num(map.speed, 'speed') ?? 60.0,
    heading: num(map.heading, 'heading') ?? 0.0,
    plateNumber: str(map.plateNumber, 'plateNumber') ?? '',
    emergencyType: str(map.emergencyType, 'emergencyType') ?? 'ผู้ป่วยวิกฤตฉุกเฉิน (Red Code)',
    sirenActive: sirenRaw ?? true,
    timestampMs: ts ?? Date.now(),
    routePoints,
    turnIntent: str(map.turnIntent, 'turnIntent'),
    destinationName: str(map.destinationName, 'destinationName'),
    simulation: map.simulation === true,
  };
}

export const isSimUnit = (id) => typeof id === 'string' && id.startsWith('SIM-AMB-');

/** agency_case_filter.dart — เคสที่ส่งมาที่ รพ. นี้ไม่ถูกซ่อนเพราะระยะ (บัญชีเก่าที่ไม่ผูก รพ. ยังกรองระยะ) */
export function agencyCaseVisible(i, { myHospitalId = null, alertDistanceKm = 5 } = {}) {
  if (isClosed(i)) return false;
  if (myHospitalId != null && i.targetHospitalId !== myHospitalId) return false;
  const routedHere = myHospitalId != null && i.targetHospitalId === myHospitalId;
  if (!routedHere && i.hospitalDistanceKm != null && i.hospitalDistanceKm > alertDistanceKm) return false;
  return true;
}
