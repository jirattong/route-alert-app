// คำนวณระยะทางให้ได้ผลเหมือนแอปทุกบิต
// - เลือกโรงพยาบาล: latlong2 0.9.1 `const Distance().as(LengthUnit.Kilometer, …)`
//   = Vincenty บน WGS-84 แล้ว "ปัดเป็นกิโลเมตรเต็ม" (roundResult=true) ไม่ใช่ Haversine
//   ตามที่คอมเมนต์ในแอปเขียนไว้ (ตรวจกับค่าจริงจาก Dart ใน test/fixtures)
// - เลือกรถพยาบาลใกล้สุด: Haversine R=6,371,000 ม. (EmergencyMqttService.calculateDistanceInMeters)

const A = 6378137.0;
const B = 6356752.314245;
const F = 1 / 298.257223563;
const degToRad = (d) => d * (Math.PI / 180.0);

/** latlong2 Vincenty.distance (เมตร, ไม่ปัด) — แปลงบรรทัดต่อบรรทัดจาก Dart */
export function vincentyMeters(lat1, lng1, lat2, lng2) {
  const l = degToRad(lng2) - degToRad(lng1);
  const u1 = Math.atan((1 - F) * Math.tan(degToRad(lat1)));
  const u2 = Math.atan((1 - F) * Math.tan(degToRad(lat2)));
  const sinU1 = Math.sin(u1);
  const cosU1 = Math.cos(u1);
  const sinU2 = Math.sin(u2);
  const cosU2 = Math.cos(u2);

  let sinLambda, cosLambda, sinSigma, cosSigma, sigma, sinAlpha, cosSqAlpha, cos2SigmaM;
  let lambda = l;
  let lambdaP;
  let maxIterations = 200;
  do {
    sinLambda = Math.sin(lambda);
    cosLambda = Math.cos(lambda);
    sinSigma = Math.sqrt(
      cosU2 * sinLambda * (cosU2 * sinLambda) +
        (cosU1 * sinU2 - sinU1 * cosU2 * cosLambda) * (cosU1 * sinU2 - sinU1 * cosU2 * cosLambda),
    );
    if (sinSigma === 0) return 0.0;
    cosSigma = sinU1 * sinU2 + cosU1 * cosU2 * cosLambda;
    sigma = Math.atan2(sinSigma, cosSigma);
    sinAlpha = (cosU1 * cosU2 * sinLambda) / sinSigma;
    cosSqAlpha = 1 - sinAlpha * sinAlpha;
    cos2SigmaM = cosSigma - (2 * sinU1 * sinU2) / cosSqAlpha;
    if (Number.isNaN(cos2SigmaM)) cos2SigmaM = 0.0;
    const C = (F / 16) * cosSqAlpha * (4 + F * (4 - 3 * cosSqAlpha));
    lambdaP = lambda;
    lambda =
      l +
      (1 - C) *
        F *
        sinAlpha *
        (sigma + C * sinSigma * (cos2SigmaM + C * cosSigma * (-1 + 2 * cos2SigmaM * cos2SigmaM)));
  } while (Math.abs(lambda - lambdaP) > 1e-12 && --maxIterations > 0);
  if (maxIterations === 0) throw new Error('Distance calculation faild to converge!');

  const uSq = (cosSqAlpha * (A * A - B * B)) / (B * B);
  const AA = 1 + (uSq / 16384) * (4096 + uSq * (-768 + uSq * (320 - 175 * uSq)));
  const BB = (uSq / 1024) * (256 + uSq * (-128 + uSq * (74 - 47 * uSq)));
  const deltaSigma =
    BB *
    sinSigma *
    (cos2SigmaM +
      (BB / 4) *
        (cosSigma * (-1 + 2 * cos2SigmaM * cos2SigmaM) -
          (BB / 6) * cos2SigmaM * (-3 + 4 * sinSigma * sinSigma) * (-3 + 4 * cos2SigmaM * cos2SigmaM)));
  return B * AA * (sigma - deltaSigma);
}

/** HospitalLocationService.calculateDistanceKm — กิโลเมตรเต็ม (ปัดแล้ว) */
export function appHospitalDistanceKm(p, h) {
  const dist = vincentyMeters(p.latitude, p.longitude, h.latitude, h.longitude);
  if (Number.isNaN(dist) || !Number.isFinite(dist)) return 0.0;
  // LengthUnit.Meter.to(Kilometer) = (value / 1.0) * 0.001 แล้ว .round()
  return Math.round((dist / 1.0) * 0.001);
}

/** EmergencyMqttService.calculateDistanceInMeters */
export function haversineMeters(a, b) {
  const r = 6371000;
  const lat1Rad = (a.latitude * Math.PI) / 180;
  const lat2Rad = (b.latitude * Math.PI) / 180;
  const dLat = ((b.latitude - a.latitude) * Math.PI) / 180;
  const dLon = ((b.longitude - a.longitude) * Math.PI) / 180;
  const x =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1Rad) * Math.cos(lat2Rad) * Math.sin(dLon / 2) * Math.sin(dLon / 2);
  return r * (2 * Math.atan2(Math.sqrt(x), Math.sqrt(1 - x)));
}

const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));

/**
 * HospitalLocationService.getHospitalsSortedByDistance
 * ER ว่างก่อน แล้วเรียงระยะ (กม.เต็ม) — sort ของ Dart กับ list ≤ 32 ตัวเป็น insertion
 * sort (stable) ค่าเท่ากันจึงคงลำดับเดิม = ลำดับ doc id ใน snapshot; Array.sort ของ JS stable เหมือนกัน
 */
export function hospitalsSortedByDistance(hospitals, p) {
  const result = hospitals.map((h) => {
    const distKm = appHospitalDistanceKm(p, h);
    return {
      profile: h,
      distanceKm: Number(distKm.toFixed(2)),
      etaMinutes: Math.round(clamp(distKm * 1.0, 2.0, 60.0)),
    };
  });
  result.sort((a, b) => {
    if (a.profile.isErAvailable !== b.profile.isErAvailable) return a.profile.isErAvailable ? -1 : 1;
    return a.distanceKm - b.distanceKm;
  });
  return result;
}

/** findNearestHospital — list ไม่มีวันว่างในแอปจริง (มี 4 รพ. ตั้งต้นเสมอ) */
export function findNearestHospital(hospitals, p) {
  const list = hospitalsSortedByDistance(hospitals, p);
  if (list.length > 0) return list[0];
  throw new Error('hospital list is empty');
}

/** ขยับจุดตามทิศ/ระยะ (ทรงกลม) ใช้แค่วางตำแหน่งจำลอง ไม่เกี่ยวกับการคำนวณของแอป */
export function offsetPoint(p, bearingDeg, meters) {
  const R = 6371000;
  const br = degToRad(bearingDeg);
  const lat1 = degToRad(p.latitude);
  const lng1 = degToRad(p.longitude);
  const d = meters / R;
  const lat2 = Math.asin(Math.sin(lat1) * Math.cos(d) + Math.cos(lat1) * Math.sin(d) * Math.cos(br));
  const lng2 =
    lng1 + Math.atan2(Math.sin(br) * Math.sin(d) * Math.cos(lat1), Math.cos(d) - Math.sin(lat1) * Math.sin(lat2));
  return { latitude: (lat2 * 180) / Math.PI, longitude: (lng2 * 180) / Math.PI };
}

/** LocationService.calculateBearingDeg (0-360) */
export function bearingDeg(a, b) {
  const lat1 = degToRad(a.latitude);
  const lat2 = degToRad(b.latitude);
  const dLon = degToRad(b.longitude - a.longitude);
  const y = Math.sin(dLon) * Math.cos(lat2);
  const x = Math.cos(lat1) * Math.sin(lat2) - Math.sin(lat1) * Math.cos(lat2) * Math.cos(dLon);
  return ((Math.atan2(y, x) * 180) / Math.PI + 360) % 360;
}

/**
 * เส้นทางสำรองของ OsrmRoutingService: 13 จุดเส้นตรง, ระยะ = Distance().as(Meter) (Vincenty
 * ปัดเป็นเมตรเต็ม), เวลา = ระยะ×1.4/12.5 — ตัวจำลองไม่เรียก OSRM สาธารณะ (โดนจำกัดอัตรา)
 */
export function fallbackRoute(start, dest) {
  const points = [];
  for (let i = 0; i <= 12; i++) {
    const t = i / 12;
    points.push({
      latitude: start.latitude + (dest.latitude - start.latitude) * t,
      longitude: start.longitude + (dest.longitude - start.longitude) * t,
    });
  }
  const raw = vincentyMeters(start.latitude, start.longitude, dest.latitude, dest.longitude);
  const distanceMeters = Number.isFinite(raw) ? Math.round(raw) : 0;
  return {
    points,
    distanceMeters,
    durationSeconds: (distanceMeters * 1.4) / 12.5,
    nextTurnInstruction: 'กำลังนำทางตามเส้นทางตรง',
  };
}

/** ก้าวเข้าหาเป้าหมายไม่เกิน stepMeters (เส้นตรง) */
export function moveToward(pos, dest, stepMeters) {
  const d = haversineMeters(pos, dest);
  if (d <= stepMeters || d === 0) return { ...dest };
  const t = stepMeters / d;
  return {
    latitude: pos.latitude + (dest.latitude - pos.latitude) * t,
    longitude: pos.longitude + (dest.longitude - pos.longitude) * t,
  };
}
