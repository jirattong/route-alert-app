# สรุปทุกอย่างที่แก้ไขในโปรเจกต์ RouteAlert

เอกสารนี้รวมทุกการแก้ไขโค้ดที่เกิดขึ้น พร้อมอธิบายว่า **ก่อนแก้เป็นยังไง** และ **หลังแก้ทำงานยังไง** เพื่อใช้ศึกษาเข้าใจระบบทั้งหมด เรียงตามหมวดหมู่ ไม่เรียงตามลำดับเวลา

---

## 1. ความปลอดภัย (Security)

### 1.1 ลบรหัสผ่าน Gmail ที่ hardcode ในซอร์สโค้ด
**ไฟล์:** `lib/core/services/email_otp_service.dart`

**ก่อนแก้:** ฟังก์ชัน `_sendViaGmailSmtp()` มีโค้ดแบบนี้:
```dart
final gmailUser = dotenv.env['GMAIL_USER'] ?? 'yuttapatandy@gmail.com';
final gmailPassword = dotenv.env['GMAIL_APP_PASSWORD'] ?? 'xolczbxknghltkqx';
```
ถ้าไม่มีไฟล์ `.env` มันจะใช้รหัสผ่าน Gmail จริงที่ hardcode ไว้ในโค้ด — รหัสนี้ถูก commit ขึ้น GitHub public repo ไปแล้ว (commit `5c6dc9d`) ถือว่าหลุดออกไปแล้วจริง

**หลังแก้:** ลบ fallback ค่า hardcode ออก ถ้าไม่มี `.env` จะแค่ log ข้อความแล้วข้ามการส่งอีเมลผ่าน Gmail ไป (ไป fallback ที่ Resend API แทน) ไม่มีการใช้รหัสหลุดอีกต่อไป

**สิ่งที่คุณต้องทำเอง (นอกเหนือจากโค้ด):** ไปที่ Google Account Security → App Passwords → ลบรหัสเก่าทิ้ง สร้างใหม่ เพราะรหัสเก่าหลุดไปแล้วในประวัติ git ลบจากโค้ดตอนนี้ไม่ได้ทำให้รหัสเก่าใช้ไม่ได้

---

### 1.2 เข้ารหัสรหัสผ่านผู้ใช้ด้วย SHA-256 + Salt
**ไฟล์:** `lib/features/auth_face_login/data/services/face_auth_repository.dart`

**ก่อนแก้:** ฟังก์ชัน `updateUserPassword()` เก็บรหัสผ่านแบบ plaintext ตรงๆ ลง Firestore และ SharedPreferences:
```dart
await prefs.setString('pwd_$cleanEmail', newPassword); // เก็บตรงๆ ไม่เข้ารหัส
```
ใครก็ตามที่เข้าถึง database ได้ จะเห็นรหัสผ่านทุกคนเป็นตัวอักษรธรรมดา

**หลังแก้:** เพิ่มฟังก์ชัน `_generateSalt()` (สุ่ม 16 ไบต์ด้วย `math.Random.secure()`) และ `_hashPassword(password, salt)` (แฮชด้วย `sha256` จาก package `crypto`) เก็บเป็นรูปแบบ `"salt:hash"` แทน เวลาตรวจสอบรหัสผ่านตอน login ใช้ `_verifyPassword()` แยก salt ออกมาแฮชรหัสที่กรอกด้วย salt เดียวกันแล้วเทียบผลลัพธ์ ไม่มีทางย้อนกลับไปหารหัสผ่านจริงจากค่าที่เก็บได้เลย

---

### 1.3 แก้ Firestore Security Rules จาก "เปิดโล่งทั้งหมด" เป็น "ปิดช่องโหว่ร้ายแรงที่สุด"
**ไฟล์:** `firestore.rules`

**ก่อนแก้:** เช็คจาก Firebase Console จริงพบว่า rules ที่ deploy อยู่คือ:
```
allow read, write: if true;
```
ใครก็ได้ในโลกอ่าน/เขียน/**ลบ**ข้อมูลทั้งฐานข้อมูลได้หมด รวมถึงรหัสผ่าน (แม้จะแฮชแล้ว) และข้อมูลใบหน้า (face embeddings) ของผู้ใช้ทุกคน

**หลังแก้:** เขียน rules ใหม่ทั้งหมด (ดูรายละเอียดเต็มในไฟล์) หลักการคือ:
- `incident_reports`: อ่านได้เปิด (ทุก role ต้องเห็นร่วมกัน), สร้างต้องมี field ที่จำเป็นครบ, แก้ไขได้แต่ **ห้ามสลับ `id`**, **ห้ามลบเด็ดขาด**
- `users`: อ่านยังเปิดอยู่ (จำเป็นเพราะระบบ Face Login เทียบใบหน้ากับทุกคนฝั่ง client เอง ไม่มี server ทำให้), แก้ไขได้แต่ **ห้ามสลับ email**, **อนุญาตให้ลบได้** (เพื่อรองรับฟีเจอร์ลบบัญชีเอง PDPA)
- `hospital_profiles`: อ่านเปิด, เขียนต้องมี `hospitalName` เป็น string, ห้ามลบ
- `emergency_fleet`: ปิดทั้งหมด (ไม่ได้ใช้จริงในแอป ตำแหน่งรถพยาบาลส่งผ่าน MQTT ไม่ใช่ Firestore)

**หมายเหตุสำคัญ:** แอปนี้ไม่มี Firebase Authentication จริง จึงยังไม่สามารถแยกสิทธิ์ตาม role (agency/ambulance/citizen) ได้ 100% เหมือนระบบที่มี login จริง — rules นี้เป็นแค่ "ด่านขั้นต่ำ" ปิดการทำลายข้อมูลแบบสุ่มสี่สุ่มห้า ไม่ใช่ระบบสิทธิ์ที่สมบูรณ์

**สิ่งที่คุณต้องทำเอง:** ต้อง copy เนื้อหาไฟล์นี้ไป paste ทับใน Firebase Console → Firestore → Rules → กด Publish เอง (ผมแก้แค่ไฟล์ในโปรเจกต์ ไม่ได้ deploy ให้อัตโนมัติ)

---

### 1.4 เปลี่ยน MQTT Topic กันชนกับคนอื่น
**ไฟล์:** `lib/core/services/emergency_mqtt_service.dart`

**ก่อนแก้:** ใช้ broker สาธารณะ `broker.emqx.io` กับ topic ชื่อ `routealert/emergency/ambulance` — ถ้ามีคนอื่น clone repo นี้ไปทดสอบพร้อมกัน จะเห็นข้อมูลปนกัน (รถพยาบาลของคนอื่นโผล่ในแผนที่คุณ)

**หลังแก้:** เปลี่ยน topic เป็น `routealert-ccf91/emergency/ambulance` (ใส่ Firebase project ID ที่ไม่ซ้ำใครเข้าไปด้วย)

---

### 1.5 เพิ่มการตรวจรหัสผ่านเดิมก่อนอนุญาตให้เปลี่ยน
**ไฟล์:** `lib/features/driver_radar/presentation/driver_profile_screen.dart`, `lib/features/ambulance/presentation/ambulance_profile_screen.dart`, `lib/features/agency/presentation/agency_profile_screen.dart`

**ก่อนแก้:** หน้า "เปลี่ยนรหัสผ่าน" ทั้ง 3 role มีช่องให้กรอก "รหัสผ่านเดิม" แต่**ไม่เคยเช็คว่าตรงจริงไหมเลย** แค่เช็คว่ารหัสใหม่ยาวพอ + ตรงกับช่องยืนยัน แล้วก็ปิดหน้าต่างพร้อมโชว์ "สำเร็จ" — **ไม่เคยเรียก `updateUserPassword()` เลยด้วยซ้ำ** (ฝั่ง Ambulance แย่สุด ไม่เช็คอะไรเลยแม้แต่ความยาว)

**หลังแก้:** เพิ่มการเรียก `FaceAuthRepository.authenticateWithPassword(email, oldPassword)` ก่อนเสมอ ถ้าไม่ผ่านจะขึ้น "รหัสผ่านเดิมไม่ถูกต้อง" แล้วไม่ทำอะไรต่อ ถ้าผ่านถึงจะเรียก `updateUserPassword()` บันทึกรหัสใหม่จริง

---

## 2. ฟีเจอร์หลักที่แก้จาก "ของปลอม/Hardcode" เป็น "ของจริง"

### 2.1 มอบหมายรถพยาบาลที่ใกล้ที่สุด (Nearest Ambulance Dispatch)
**ไฟล์:** `lib/features/agency/presentation/agency_incident_detail_screen.dart`

**ก่อนแก้:** ปุ่ม "ยืนยันรับเคส & ส่งรถพยาบาลออกปฏิบัติการ" เรียก:
```dart
IncidentService().dispatchIncidentByHospital(
  ambulanceId: 'AMB-1669-01',       // hardcode ตายตัวเสมอ
  ambulancePlate: 'กขค123 (เชียงใหม่)',
  ambulanceCallSign: 'หน่วยกู้ชีพนครพิงค์ 01',
  ...
);
```
ไม่มีการคำนวณระยะทางอะไรเลย ยิงหน่วยเดียวกันทุกครั้งไม่ว่าจะมีรถพยาบาลกี่คันออนไลน์อยู่

**หลังแก้:** ดึงรายชื่อรถพยาบาลที่ออนไลน์จริงจาก `EmergencyMqttService().activeFleet` (ข้อมูลจริงจาก MQTT) วนลูปคำนวณระยะทางแต่ละคันด้วย `EmergencyMqttService.calculateDistanceInMeters()` (สูตร Haversine) แล้วเลือกคันที่ใกล้ที่สุดจริงๆ มาส่งเคสให้ ถ้าไม่มีรถพยาบาลออนไลน์เลยจะแจ้งเตือนแทนที่จะยิงเคสไปหาหน่วยที่ไม่มีตัวตน

---

### 2.2 ระบบระบุตัวตนรถพยาบาล (Ambulance Identity)
**ไฟล์ใหม่:** `lib/core/services/ambulance_storage_service.dart`
**ไฟล์ที่แก้:** `lib/features/ambulance/presentation/ambulance_home_screen.dart`, `lib/features/ambulance/presentation/ambulance_incident_list_screen.dart`, `lib/features/ambulance/presentation/ambulance_profile_screen.dart`

**ก่อนแก้:** ทุกที่ในแอปที่ต้องระบุตัวตนรถพยาบาล (broadcast พิกัด, กดรับเคส) ใช้ค่า hardcode `'AMB-1669-01'` / `'กู้ชีพนครพิงค์ 01'` เหมือนกันหมด ถ้ามีรถพยาบาล 2 เครื่องรันแอปพร้อมกัน ทั้งคู่จะรายงานตัวเป็น ID เดียวกัน ระบบแยกไม่ออกว่าใครเป็นใคร

**หลังแก้:** สร้าง `AmbulanceStorageService` ใหม่ — ตอนเปิดแอปครั้งแรกจะ**สุ่มสร้างรหัสหน่วยที่ไม่ซ้ำ**อัตโนมัติ (เช่น `AMB-4521`) เก็บถาวรผ่าน `SharedPreferences` แก้ไขทะเบียน/ชื่อเรียกขานได้ในหน้าโปรไฟล์ ทุกจุดที่เคย hardcode เปลี่ยนมาดึงค่าจาก service นี้แทน

---

### 2.3 คำนวณทิศทาง (Heading) จริงจาก GPS แทนค่าคงที่
**ไฟล์:** `lib/core/services/location_service.dart` (เพิ่ม `calculateBearingDeg()`), `lib/features/ambulance/presentation/ambulance_home_screen.dart`, `lib/features/driver_radar/presentation/driver_home_screen.dart`, `lib/core/services/emergency_mqtt_service.dart` (เพิ่ม field `heading`)

**ก่อนแก้:** `_driverHeading` เป็น `final double = 45.0` ตายตัวตลอดการทำงาน และ `_ambulanceHeading` ก็เริ่มที่ 45.0 เปลี่ยนได้แค่ตอนกด simulation panel เท่านั้น โมเดลข้อมูลที่ส่งผ่าน MQTT (`EmergencyVehicleData`) ก็**ไม่มี field heading เลย** ผลคือฟีเจอร์ตรวจจับ "รถสวนเลน ไม่ต้องแจ้งเตือน" ใช้งานไม่ได้จริงตอนทดสอบข้าม 2 เครื่อง เพราะ heading ทั้งคู่เท่ากันเสมอ (45-45=0)

**หลังแก้:** เพิ่ม `LocationService.calculateBearingDeg(pointA, pointB)` คำนวณทิศทางจริงจากพิกัด GPS 2 จุดล่าสุด (ขยับเกิน 2 เมตรถึงจะอัปเดต กันทิศทางกระตุกตอน GPS นิ่ง) ทั้งฝั่ง Driver และ Ambulance คำนวณแบบนี้แล้วส่ง heading จริงผ่าน MQTT ฟีเจอร์ตรวจจับสวนเลน (ที่ใช้ตรรกะ fallback เมื่อไม่มีเส้นทาง) ใช้งานได้จริงแล้ว

---

### 2.4 เปิดสัญญาณเตือนอัตโนมัติเมื่อมีเคสมอบหมาย
**ไฟล์:** `lib/features/ambulance/presentation/ambulance_home_screen.dart`

**ก่อนแก้:** `_isNotificationAlert` (ตัวควบคุมว่าจะ broadcast สัญญาณเตือนไปยังผู้ใช้ถนนไหม) เป็นแค่สวิตช์แยกที่ผู้ขับต้องกดเปิดเอง ไม่มี logic ไหนเปิดให้อัตโนมัติเมื่อมีเคสมอบหมายมาจากโรงพยาบาลเลย — ถ้าปิดสวิตช์ไว้ตอนไม่มีเคส แล้วจู่ๆ มีเคสมา สัญญาณเตือนจะไม่เปิดให้

**หลังแก้:** เพิ่ม logic เช็ค "transition" ในตัวรับฟัง `incidentsStream` — ถ้าเคสที่เพิ่งเข้ามาถูกมอบหมายให้ **หน่วยนี้จริง** (`assignedAmbulanceId == _ambulanceUnitId`) และก่อนหน้านี้ยังไม่เคยถูกมอบหมาย จะสั่ง `_isNotificationAlert = true` อัตโนมัติทันที พร้อม broadcast ออกไปเลย

---

### 2.5 โหมดทดสอบในห้อง (Indoor Test Mode)
**ไฟล์:** `lib/features/ambulance/presentation/ambulance_home_screen.dart`

**ปัญหาที่แก้:** ระบบแจ้งเตือนหลักใช้ "Route-Aware Corridor Matching" เช็คว่าผู้ใช้อยู่ห่างจากเส้นทางถนนจริง (ที่คำนวณจาก OSRM ไปโรงพยาบาล) เกิน 40 เมตรไหม ถ้าเกินจะถือว่า "ไม่เกี่ยว" ไม่แจ้งเตือน ทำให้ทดสอบในห้องเรียน/พื้นที่ปิดไม่ได้เลยเพราะไม่มีถนนจริงให้เดินตาม

**ทางแก้:** เพิ่ม toggle "โหมดทดสอบในห้อง" — เปิดแล้วฝั่ง Ambulance จะ**ไม่ส่งเส้นทางถนนจริง** (`routePoints: null`) ทำให้ฝั่ง Driver เปลี่ยนไปใช้ตรรกะ fallback แบบง่าย (ดูแค่ระยะทาง+ทิศทาง ไม่ต้องอยู่บนถนนจริง) เหมาะกับการเดินเข้าใกล้กันในห้องแทนการขับจริงบนถนน

---

## 3. ระบบ AI/ML — จากที่ overclaim เป็นของจริง หรือติด label ให้ตรงความจริง

### 3.1 เพิ่มเช็คคุณภาพภาพก่อนลงทะเบียนใบหน้า (MobileFaceNet)
**ไฟล์:** `lib/core/ml/image_utils.dart` (เพิ่ม `assessFaceImageQuality()`), `lib/features/auth_face_login/presentation/face_scan_screen.dart`

**ก่อนแก้:** ตอนลงทะเบียนใบหน้า 3 มุม ระบบเก็บทุกเฟรมที่ทำมุมถูกไปคำนวณ embedding ทันที ไม่เช็คว่าภาพเบลอ/มืด/สว่างจ้าไปไหม ถ้าเก็บภาพคุณภาพต่ำเข้าไปในฐานข้อมูล จะทำให้จดจำใบหน้าไม่แม่นในระยะยาว

**หลังแก้:** เพิ่มฟังก์ชันคำนวณ **Laplacian variance** (วัดความคมชัด) และค่าความสว่างเฉลี่ยของภาพ ก่อนบันทึกทุกเฟรมจะเช็คก่อน ถ้าไม่ผ่านเกณฑ์จะแสดงข้อความ "ภาพเบลอเกินไป กรุณาถือกล้องให้นิ่ง" แล้วข้ามเฟรมนั้นไปโดยไม่นับ progress

---

### 3.2 Anti-Spoofing — ปรับให้รองรับโมเดลที่เทรนเองผ่าน Colab
**ไฟล์:** `lib/core/ml/anti_spoofing_service.dart`, **ไฟล์ใหม่:** `scripts/train_anti_spoofing_colab.ipynb`

**ก่อนแก้:** โค้ดคาดหวังไฟล์โมเดล `anti_spoofing.tflite` แบบ 80×80 พิกเซล, 3-class เฉพาะเจาะจง (ที่ไฟล์นี้**ไม่มีอยู่จริง**ในโปรเจกต์) โค้ดคอมเมนต์อ้างว่าเป็น "Deep Learning Anti-Spoofing Model" แต่ในทางปฏิบัติ fallback ไปใช้ ML Kit liveness + texture heuristic เสมอ

**หลังแก้:** ปรับให้อ่านขนาด input/output จากโมเดลแบบไดนามิก (ไม่ hardcode 80×80/3-class อีกต่อไป) และ normalize ภาพแบบ MobileNetV2 (พิกเซล -1 ถึง 1) เพื่อให้รองรับโมเดลที่เทรนเองผ่าน Colab notebook ใหม่ (`train_anti_spoofing_colab.ipynb` — เทรนแยก "หน้าคนจริง" vs "ภาพปลอมแปลง" ด้วย Transfer Learning จาก MobileNetV2) **สถานะปัจจุบัน:** โค้ดพร้อมรับไฟล์แล้ว แต่ยังไม่มีใครเทรน/วางไฟล์จริง (ต้องเก็บข้อมูลรูปแล้วรัน notebook เอง)

---

### 3.3 Accident/Non-Accident Image Classifier (โมเดลที่เทรนเองใหม่)
**ไฟล์ใหม่:** `lib/core/ml/accident_image_classifier_service.dart`, `scripts/train_accident_classifier_colab.ipynb`
**ไฟล์ที่แก้:** `lib/core/services/ai_vision_triage_service.dart`

**ก่อนแก้:** เวลาไม่มี Gemini API key ระบบวิเคราะห์รูปด้วยสถิติพิกเซลล้วนๆ (edge gradient, contrast) ไม่ใช่ AI/ML จริง

**หลังแก้:** สร้าง `AccidentImageClassifierService` ใหม่ — โหลดโมเดล TFLite ที่เทรนเองผ่าน Colab (`train_accident_classifier_colab.ipynb`, Transfer Learning จาก MobileNetV2 บนรูปจริง) อ่าน input/output shape จากโมเดลแบบไดนามิก ผูกเข้ากับ `_analyzeWithLocalEngine()` — ถ้ามีโมเดลจริงจะใช้ผลจากโมเดล**ร่วมกับ**ระบบ heuristic เดิม (OR กัน เพื่อความ lenient) ถ้าไม่มีโมเดลจะ fallback เป็น heuristic เดิมทั้งหมดเหมือนก่อน **สถานะปัจจุบัน:** โค้ดพร้อมใช้ รอแค่คุณเทรน + วางไฟล์ `accident_classifier.tflite` ที่ `assets/models/`

---

### 3.4 แก้ label ให้ตรงความจริง — AI วิเคราะห์ภาพ (เมื่อไม่มี Gemini key)
**ไฟล์:** `lib/features/driver_radar/presentation/sos_report_screen.dart`, `lib/core/services/ai_vision_triage_service.dart`

**ก่อนแก้:** ป้ายในหน้าจอเขียนว่า **"AI Multi-Angle Vision Triage"** ทั้งที่เป็นแค่สถิติพิกเซลธรรมดา ไม่ใช่ AI จริง

**หลังแก้:** เปลี่ยนป้ายเป็น **"วิเคราะห์ภาพเบื้องต้น (Local, ไม่ใช่ AI)"** และแก้ default `modelName` จาก `'ResNet-50 / Emergency Triage Vision'` (ไม่เคยใช้โมเดลนี้จริง) เป็นข้อความที่ตรงความจริง

---

### 3.5 แก้ label ให้ตรงความจริง — AI ตรวจจับเสียงไซเรน
**ไฟล์:** `lib/core/services/ai_acoustic_siren_service.dart`

**ความจริงที่พบ:** คลาสนี้**ไม่ถูกเรียกใช้จากหน้าจอไหนในแอปเลย** (ตรวจสอบด้วย grep ทั้งโปรเจกต์) และค่า dB/ผลตรวจจับทั้งหมดสุ่มด้วย `math.Random()` ไม่มีการเข้าถึงไมโครโฟนจริงแม้แต่นิดเดียว ทั้งที่ comment อ้างว่าเป็น "Mel-Spectrogram 2D-CNN Siren Classifier"

**หลังแก้:** แก้ comment/ชื่อ field ให้บอกตรงๆ ว่าเป็น placeholder ที่ยังไม่เชื่อมกับ UI หรือไมโครโฟนจริง ไม่ได้ทำฟีเจอร์จริงเพิ่ม (ตามที่เลือกไว้ว่าเอาแบบเร็ว ไม่ทำของจริงเพิ่มตอนนี้)

---

### 3.6 แก้สคริปต์ที่อ้างว่า "เทรน AI 3 โมเดลสำเร็จ" ทั้งที่ไม่จริง
**ไฟล์:** `scripts/train_ai_models.py`

**ปัญหาที่พบ:** ไฟล์นี้นิยามโมเดล PyTorch 3 ตัว (`TrajectoryConflictMLP`, `VisionIncidentTriageCNN`, `AcousticSirenCNN`) แต่ใน `__main__` เทรนจริงแค่ตัวเดียวด้วย**ข้อมูลสังเคราะห์ที่เขียนเอง** (ไม่ใช่ข้อมูลจริง) และ**ไม่มีโค้ด export ไปใช้งานจริงเลย** ทั้งที่บรรทัดสุดท้ายพิมพ์ว่า "All 3 Deep Learning models verified and ready for thesis defense"

**หลังแก้:** เขียนใหม่ทั้งไฟล์ ระบุชัดเจนว่าเป็น "Design-Validation Prototype" ไม่ใช่ production pipeline บอกตรงๆ ว่ามีแค่ 1 ใน 3 โมเดลที่เทรนจริง (ด้วยข้อมูลสังเคราะห์) และไม่เชื่อมกับแอปเลย พร้อมชี้ไปที่ Colab notebook 2 ไฟล์ที่เป็นของจริง (ข้อ 3.2, 3.3)

---

## 4. PDPA / การจัดการข้อมูลผู้ใช้

### 4.1 เพิ่มฟีเจอร์ "ลบบัญชีและข้อมูลของฉัน"
**ไฟล์:** `lib/features/auth_face_login/data/services/face_auth_repository.dart` (เพิ่ม `deleteAccount()`), และหน้าโปรไฟล์ทั้ง 3 role

**เหตุผล:** แอปเก็บข้อมูลใบหน้า (face embedding) ซึ่งเป็นข้อมูลชีวมิติที่อ่อนไหวตาม PDPA แต่ไม่เคยมีทางลบบัญชี/ข้อมูลตัวเองได้เลย

**สิ่งที่เพิ่ม:** ปุ่ม "ลบบัญชีและข้อมูลของฉันถาวร" ในหน้าโปรไฟล์ทั้ง Driver/Ambulance/Agency กดแล้วต้อง**กรอกรหัสผ่านยืนยันก่อนเสมอ** (เรียก `authenticateWithPassword` ตรวจสอบก่อน) ถึงจะลบข้อมูลออกจาก local cache และ Firestore จริง (ต้องแก้ `firestore.rules` เปิด `allow delete` ให้ collection `users` ด้วย ซึ่งทำไปพร้อมกันแล้ว)

---

## 5. ฟีเจอร์ใหม่ที่เพิ่มเข้ามา

### 5.1 ถ่วงน้ำหนักเลือกโรงพยาบาลด้วยสถานะ ER ว่าง/เต็ม
**ไฟล์:** `lib/core/services/hospital_location_service.dart`

**ก่อนแก้:** ฟังก์ชัน `getHospitalsSortedByDistance()` เรียงแค่ตามระยะทางอย่างเดียว ไม่สนสถานะ ER เลย

**หลังแก้:** เพิ่ม field `isErAvailable` ใน `HospitalProfile` (sync Firestore จริงผ่าน `updateErAvailability()`) แล้วปรับการเรียงให้เอา รพ. ที่ ER ว่างไว้ก่อนเสมอ ถ้าว่าง/เต็มเท่ากันค่อยเรียงตามระยะทาง

### 5.2 Dashboard กราฟแนวโน้มเคสรายเดือน
**ไฟล์:** `lib/features/agency/presentation/agency_profile_screen.dart` (เพิ่ม package `fl_chart`)

คำนวณจำนวนเคสจริงย้อนหลัง 6 เดือนจาก `IncidentService` แสดงเป็นกราฟแท่ง เดือนปัจจุบันเน้นสีเข้มกว่า กดแตะดูจำนวนได้

### 5.3 Predictive Hotspot Heatmap
**ไฟล์:** `lib/features/agency/presentation/agency_home_screen.dart`

จับกลุ่มเคสสะสมตามกริดพิกัด (~1.1 กม./ช่อง) แล้ว plot เป็นวงกลมสีแดงบนแผนที่ ยิ่งเคสเยอะวงยิ่งใหญ่/เข้ม ไม่ใช่ ML จริงแต่ใช้ข้อมูลเคสจริงทั้งหมด มีปุ่มไฟ 🔥 เปิด/ปิดได้

### 5.4 ระบบสลับภาษาไทย/อังกฤษ (บางส่วน)
**ไฟล์ใหม่:** `lib/core/services/app_language_service.dart`, `lib/core/localization/app_strings.dart`
**ไฟล์ที่แก้:** `lib/features/driver_radar/presentation/sos_report_screen.dart`, `lib/features/driver_radar/presentation/driver_settings_screen.dart`

ระบบ dictionary ธรรมดา (ไม่ใช้ Flutter gen-l10n เพื่อความเสถียร) แปลครบเฉพาะ**หน้าจอแจ้งเหตุ SOS** มีสวิตช์เปิด/ปิดในหน้า Driver Settings **หน้าจออื่นยังเป็นไทยอย่างเดียว** — ขยายเพิ่มได้โดยเพิ่ม key ใหม่ใน `app_strings.dart`

---

## 6. บั๊ก UX เล็กๆ ที่เจอระหว่างทางและแก้ไปด้วย

| จุดที่แก้ | ไฟล์ | ปัญหาเดิม |
|---|---|---|
| ปุ่ม Logout ฝั่ง Agency | `agency_profile_screen.dart` | กด Logout แล้วแค่เปลี่ยนหน้า ไม่เคยเรียก `FaceAuthRepository.logout()` เคลียร์ session จริง |
| ปุ่ม "ยืนยัน ER พร้อม" ในหน้าแผนที่ | `agency_home_screen.dart` | เป็น local state ปิดแอพแล้วหาย ไม่ sync กับปุ่มเดียวกันในหน้า incident list |
| ถ่ายรูปหน้างานฝั่งรถพยาบาล | `ambulance_incident_detail_screen.dart` | กดแล้วสุ่มใส่ URL รูปจาก picsum.photos ไม่ได้เปิดกล้องจริง — แก้เป็นถ่ายรูปจริง + บันทึกเข้าเคสจริง (เพิ่ม field `scenePhotosBase64` ใน `incident_report.dart`) |
| สถิติ Agency/Ambulance Profile | `agency_profile_screen.dart`, `ambulance_profile_screen.dart` | ตัวเลข KPI/เคสสำเร็จเป็นค่า hardcode คงที่ — แก้เป็นคำนวณจากเคสจริงในระบบ |
| หน้า Settings ของ Agency | `agency_settings_screen.dart` + ไฟล์ใหม่ `agency_storage_service.dart` | ปรับ toggle/slider แล้วปิดแอพค่าหาย ไม่ persist เลย |

---

## 7. Branding

### 7.1 ไอคอนแอป
**ไฟล์ใหม่:** `assets/icon/app_icon.png`, `scripts/generate_app_icon.dart`

ไอคอนเดิมเป็น Flutter default logo (โลโก้สีฟ้ารูปตัว F) ทั้ง iOS และ Android — สร้างไอคอนใหม่ (กากบาทการแพทย์สีขาวบนพื้น Teal `#00A896` สีแบรนด์ของแอป) ด้วย package `flutter_launcher_icons` generate ให้ครบทุกขนาดทั้ง 2 แพลตฟอร์มอัตโนมัติ

---

## 8. สิ่งที่ยังไม่ได้แก้ (ทราบแล้วแต่ยังไม่ทำ)

- **Login brute-force protection**: `authenticateWithPassword()` ไม่มีการจำกัดจำนวนครั้งที่พยายามรหัสผ่านผิด (ต่างจาก OTP ที่มี `remainingAttempts` จำกัด 3 ครั้ง)
- **หน้าจออื่นนอกจาก SOS ยังไม่มีภาษาอังกฤษ** (Driver home, Ambulance, Agency ทั้งหมดยังเป็นไทย)
- **Dark mode ยังไม่ครอบคลุมทั้งแอป**: ทำแล้วเฉพาะ 4 หน้าจอ Driver (Map/Incident List/Settings/Profile) — หน้า SOS Report, ทุกหน้าจอ Ambulance, ทุกหน้าจอ Agency ยังไม่มี dark mode เลย
- **โมเดล Anti-Spoofing และ Accident Classifier** โค้ดพร้อมรับแล้ว แต่ยังไม่มีใครเทรน/วางไฟล์จริงลง `assets/models/`

---

## 9. รอบตรวจสอบเพิ่มเติม (Comprehensive Audit) — พบและแก้เพิ่ม

### 9.1 วงรัศมีแจ้งเตือนบนแผนที่ (Radar/Alert Radius Circles)
**ไฟล์:** `lib/features/driver_radar/presentation/driver_home_screen.dart`

เดิมค่าระยะที่ตั้งใน Settings (`_outerRadarMeters`, `_innerAlertMeters`) ถูกใช้แค่คำนวณ logic เบื้องหลัง **ไม่เคยวาดเป็นวงกลมบนแผนที่จริงเลย** เพิ่ม `CircleLayer` วาดวงนอกสีฟ้า (เรดาร์) และวงในสีแดง (แจ้งเตือนวิกฤต) รอบตำแหน่งผู้ใช้ อัปเดตสดตามค่าที่ปรับใน Settings

### 9.2 บั๊ก overflow ซ่อนปุ่มโหมดทดสอบในห้อง
**ไฟล์:** `lib/features/ambulance/presentation/ambulance_home_screen.dart`

การ์ดสถานะด้านล่างของหน้า Ambulance (`_buildAmbulanceStatusCard`) เป็น `Column` แบบไม่มี scroll ลอยอยู่ใน `Positioned` — พอเพิ่มสวิตช์ "โหมดทดสอบในห้อง" เข้าไปหลังสุด เนื้อหารวมยาวเกินจอ การ์ดล้นออกไปพ้นขอบบนของจอจนมองไม่เห็น/กดสวิตช์ไม่ถึง แก้โดยใส่ `SingleChildScrollView` + จำกัด `maxHeight` ไม่เกิน 55% ของความสูงจอ

### 9.3 บั๊ก Contrast ในโหมดมืด (พบจากการตรวจสอบซ้ำหลังทำข้อ 9.1-9.2)
**ไฟล์:** `lib/features/driver_radar/presentation/incident_list_screen.dart`

ตอนเพิ่ม dark mode รอบก่อน พลาด 2 จุด: (1) ข้อความที่อยู่/จังหวัดบนการ์ดเคส ไม่มี color ระบุไว้เลย พอพื้นการ์ดเปลี่ยนเป็นสีเข้ม ข้อความ (สีเข้มตามค่า default) จะกลมกลืนจนอ่านไม่ออก (2) หัวข้อ "RouteAlert" บน header เป็น `const Text` สี navy เข้มตายตัว ไม่สลับสีตาม dark mode เหมือนไฟล์อื่น — แก้ทั้งสองจุดให้สลับสีขาว/ดำตาม `_isNightMode` แล้ว

### 9.4 บั๊กจริง: ระบบระบุ "เคสของฉัน" ใช้เบอร์โทร hardcode เทียบ ไม่ใช่ตัวตนจริงของผู้ใช้
**ไฟล์:** `incident_list_screen.dart`, `sos_report_screen.dart`, `driver_profile_screen.dart`, `user_face_profile.dart`, `face_auth_repository.dart`

**ปัญหาที่พบ:** ระบบตัดสินว่า "เคสนี้เป็นของฉันไหม" (ใช้ตัดสินใจโชว์ป้าย "รายงานของคุณ", จัดเรียงขึ้นบนสุด, และแสดงเสมอไม่ซ่อนตามรัศมี) เทียบจาก `item.reporterPhone == '081-234-5678'` ซึ่งเป็นเบอร์ hardcode ตัวเดียว — ที่ผ่านมามันดูเหมือนใช้งานได้เพราะ `sos_report_screen.dart` เติมเบอร์เดียวกันนี้ให้ทุกคนโดยอัตโนมัติเสมอ (ไม่เคยดึงเบอร์จริงเพราะ `UserFaceProfile` ไม่มี field เบอร์โทรเลยด้วยซ้ำ) **สรุปคือถ้ามี 2 คนใช้แอปพร้อมกัน ทั้งคู่จะเห็นเคสของอีกฝ่ายเป็น "เคสของตัวเอง" ปนกันหมด**

**หลังแก้:**
1. เพิ่ม field `phone` ใน `UserFaceProfile` (model, toMap/fromMap/copyWith) จริง
2. เพิ่ม `FaceAuthRepository.updateUserPhone()` บันทึกเบอร์จริงถาวร (sync Firestore เหมือน field อื่น) และแก้ให้ทุกจุดที่เคยสร้าง `UserFaceProfile` ใหม่ด้วยมือ (เสี่ยงลืม field) เปลี่ยนไปใช้ `copyWith()` แทน กัน bug แบบนี้เกิดซ้ำในอนาคต
3. `driver_profile_screen.dart` โหลด/บันทึกเบอร์จริงแล้ว (เดิมมีแค่ตัวแปร local ไม่เคย sync กับผู้ใช้จริงเลย)
4. `sos_report_screen.dart` ใช้เบอร์จริงของผู้ใช้ถ้ามี ไม่ทับด้วย hardcode เสมอไปแล้ว
5. **ที่สำคัญที่สุด**: เปลี่ยนตรรกะ "เคสของฉัน" ทั้ง 3 จุดใน `incident_list_screen.dart` จากเทียบเบอร์โทร เป็นเทียบ `reporterEmail` กับอีเมลผู้ใช้ที่ล็อกอินจริง (อีเมลเป็นตัวระบุตัวตนที่ถูกต้องอยู่แล้วในระบบ ไม่ต้องพึ่งเบอร์โทรที่เพิ่งมี field จริง)

### 9.5 เสริมความปลอดภัย overflow ฝั่ง Agency (เชิงป้องกัน)
**ไฟล์:** `lib/features/agency/presentation/agency_home_screen.dart`

การ์ดแสดงรายละเอียดรถพยาบาลที่เลือก (`_buildSelectedAmbulanceCard`) มีโครงสร้างเสี่ยง overflow แบบเดียวกับข้อ 9.2 (แม้เนื้อหาสั้นกว่ามากจึงความเสี่ยงต่ำ) เพิ่ม `SingleChildScrollView` + `maxHeight` + `maxLines`/`ellipsis` ให้ข้อความชื่อ/สถานะรถพยาบาลกันไว้ล่วงหน้า เผื่อชื่อเรียกขานยาวผิดปกติ

**ยืนยันด้วย `flutter analyze` (0 errors) และ `flutter test` (27/27 ผ่าน) หลังแก้ทุกข้อ**

---

### 9.6 รอบตรวจสอบละเอียดทั้ง 4 ระบบ (Driver / Ambulance / Agency / Core-Auth) — ตรวจสอบทุกฟังก์ชัน พบและแก้ปัญหาจริงจำนวนมาก

รอบนี้แบ่งตรวจสอบแบบ agent แยกตามระบบ 4 ตัวพร้อมกัน อ่านโค้ดจริงทุกไฟล์ในแต่ละ feature แล้วรายงานเฉพาะบั๊กที่ยืนยันแล้วว่ามีจริง (ไม่ใช่แค่คาดเดา) จากนั้นแก้ไขทุกจุดที่พบ

#### 🔴 ร้ายแรงที่สุด: ช่องโหว่ Auth Bypass ผ่าน Google Sign-In
**ไฟล์:** `lib/features/auth_face_login/presentation/face_login_screen.dart`, `lib/core/services/google_auth_service.dart`

**ปัญหาที่พบ:** เวลา native Google Sign-In ล้มเหลว (ซึ่งเกิดเป็นปกติบน Android/desktop เพราะไม่มี `google-services.json` ตั้งค่า `clientId` ไว้) แอปจะเปิด modal ให้พิมพ์อีเมล Google เอง **โดยไม่ตรวจสอบอะไรเลย** — ไม่มี OAuth token, ไม่มีรหัสผ่าน, ไม่มี OTP, ไม่มี Face ID พิมพ์อีเมลอะไรไปที่ตรงกับผู้ใช้ที่ลงทะเบียนไว้แล้ว ระบบจะ login เป็นบัญชีนั้นทันที **แปลว่าใครก็ตามที่รู้ (หรือเดา) อีเมลของผู้ใช้คนอื่น สามารถปลอมตัวเป็นเขาได้เต็มรูปแบบ ทำลายระบบความปลอดภัย Face ID + รหัสผ่านที่ออกแบบไว้ทั้งหมด**

**หลังแก้:** ก่อนจะ login ด้วยอีเมลที่พิมพ์เอง เช็คก่อนว่าอีเมลนี้มีบัญชีจริงอยู่แล้วหรือไม่ (`FaceAuthRepository.isEmailRegistered()`) ถ้ามีแล้ว **ไม่ login ให้เด็ดขาด** จะสลับไปหน้าล็อกอินปกติพร้อมเติมอีเมลไว้ให้ แล้วเตือนให้ยืนยันตัวตนด้วยรหัสผ่านหรือ Face ID แทน จะปล่อยให้สร้างบัญชีใหม่ได้เฉพาะอีเมลที่ยังไม่เคยลงทะเบียน (ซึ่งยังคงต้องสแกนหน้าจริงก่อนสร้างบัญชีอยู่ดี ไม่ใช่ auto-login)

#### 🔴 ร้ายแรง: รถพยาบาลคันหนึ่งแย่งเคสของอีกคันได้ (Cross-Ambulance Data Bleed)
**ไฟล์:** `lib/features/ambulance/presentation/ambulance_home_screen.dart`

**ปัญหาที่พบ:** ตรรกะจับคู่เคสที่ได้รับมอบหมาย ใช้ `assignedAmbulanceId == _ambulanceUnitId || status == 'assigned' || ...` (เชื่อมด้วย OR) แปลว่าเงื่อนไข "ต้องเป็นของหน่วยตัวเอง" ไม่มีผลจริงเลย — รถพยาบาลคันไหนก็ตามจะไปหยิบเคสที่มีสถานะ assigned/at_scene/transporting/approaching_er ของ**คันอื่น**มาแสดงและควบคุมได้ ซึ่งตรงกับสถานการณ์ทดสอบจริงของโปรเจกต์นี้พอดี (ทดสอบพร้อมกันหลายเครื่อง) — เจอบั๊กนี้ระหว่างการทดสอบจริงได้แน่นอน

**หลังแก้:** เงื่อนไขหลักบังคับให้ต้อง `assignedAmbulanceId == _ambulanceUnitId` เท่านั้นถึงจะจับคู่ ตัดโอกาสที่หน่วยอื่นจะมาปนกันออกทั้งหมด

#### 🔴 ร้ายแรง: ไม่มีการเช็คสิทธิ์ก่อนเลื่อนสถานะเคส (No Ownership Check)
**ไฟล์:** `lib/features/ambulance/presentation/ambulance_incident_detail_screen.dart`

**ปัญหาที่พบ:** ต่อเนื่องจากบั๊กด้านบน แอปแอมบูแลนซ์เครื่องไหนก็ตามสามารถกดปุ่ม "เลื่อนสถานะ" เพื่อเปลี่ยนความคืบหน้าของเคสที่มอบหมายให้หน่วยอื่นได้ ไม่มีการเช็คความเป็นเจ้าของเลย

**หลังแก้:** เพิ่มเช็คว่า `incident.assignedAmbulanceId` ตรงกับ ID หน่วยตัวเองหรือไม่ ถ้าไม่ตรง ปุ่มจะถูกล็อกเป็น "🔒 เคสของหน่วยอื่น" กดแล้วมีคำเตือนแทนที่จะดำเนินการ

#### 🟠 ความเร็วรถพยาบาลที่ broadcast เป็นค่าคงที่ปลอม (65.0 กม./ชม. เสมอ)
**ไฟล์:** `lib/features/ambulance/presentation/ambulance_home_screen.dart`

ค่านี้ไม่ใช่แค่ตัวเลขโชว์เฉยๆ แต่ถูกส่งไปคำนวณ trajectory-conflict จริงฝั่งคนขับ และโชว์เป็นความเร็วจริงให้คนขับเห็นด้วย แก้โดยเพิ่มการคำนวณความเร็วจริงจากตำแหน่ง GPS ที่เปลี่ยนไปเทียบกับเวลาที่ผ่านไป (เหมือนวิธีคำนวณ heading ที่มีอยู่แล้ว)

#### 🟠 บั๊กเดิมที่คิดว่าแก้แล้ว (9.4) จริงๆ ยังไม่ได้แก้ เพราะมี shortcut แอบเลี่ยงอยู่
**ไฟล์:** `incident_list_screen.dart`, `sos_report_screen.dart`

**ปัญหาที่พบ:** ตอนแก้ข้อ 9.4 เปลี่ยนไปเทียบ `reporterEmail` แล้วก็จริง แต่โค้ดจริงเป็น `item.id.startsWith('Case #AVCB') || item.reporterEmail == _currentUserEmail` — และ ID ของ**ทุก**เคสที่สร้างจาก `sos_report_screen.dart` ขึ้นต้นด้วย `'Case #AVCB'` เหมือนกันหมดทุกคน เพราะงั้นเงื่อนไข `startsWith` จะ true เสมอ ทำให้เงื่อนไขอีเมลไม่มีผลอะไรเลยในทางปฏิบัติ **บั๊ก 2 คนเห็นเคสกันปนกันจึงยังคงอยู่จริง แม้จะดูเหมือนแก้ไปแล้วในรอบก่อน**

**หลังแก้:** เปลี่ยนการสร้าง ID ให้ไม่ซ้ำกันจริง (เติมเลขสุ่มต่อท้าย timestamp) และตัดเงื่อนไข `startsWith` ทิ้งทั้ง 3 จุด เหลือแค่เช็คอีเมลอย่างเดียว

#### 🟠 ตั้งค่ารัศมีแจ้งเตือนแล้วรีสตาร์ทแอปค่ากลับไปเป็นค่า default เสมอ
**ไฟล์:** `lib/core/services/driver_storage_service.dart`, `lib/features/driver_radar/presentation/driver_main_screen.dart`

ค่าที่ผู้ใช้ปรับใน Settings ถูกบันทึกลง SharedPreferences จริง แต่ไม่มีใครโหลดค่านั้นกลับมาใส่ตัวแปร in-memory ที่หน้าแผนที่ใช้จริงตอนแอปเปิดใหม่ — แก้โดยให้โหลดค่าที่บันทึกไว้ตอนแอปเริ่มทำงาน

#### 🟡 แก้ไขโปรไฟล์ (ชื่อ, ทะเบียนรถ) กด "บันทึกสำเร็จ" แต่ข้อมูลหายจริงเวลาปิดแอป
**ไฟล์:** `driver_profile_screen.dart`, `user_face_profile.dart`, `face_auth_repository.dart`

เพิ่ม field `carPlate` ให้ `UserFaceProfile` จริง และเพิ่มฟังก์ชันบันทึกชื่อ/ทะเบียนรถถาวรแบบเดียวกับเบอร์โทรที่แก้ไปก่อนหน้า

#### 🟡 ป้าย "✓ Verified from account" โชว์ทั้งที่เบอร์เป็นเบอร์ปลอม hardcode
**ไฟล์:** `sos_report_screen.dart` — ป้ายนี้จะโชว์เฉพาะตอนที่เป็นเบอร์จริงของผู้ใช้เท่านั้นแล้ว

#### 🟡 สถิติ "เปิดทางให้รถฉุกเฉิน" เริ่มต้นที่ 67 ครั้ง + ประวัติปลอม 2 รายการตายตัว
**ไฟล์:** `driver_storage_service.dart`, `driver_profile_screen.dart`, `driver_home_screen.dart`

ค่าเริ่มต้นเปลี่ยนเป็น 0 จริง และเพิ่มระบบบันทึกประวัติจริงแทนข้อมูลปลอม (บั๊กประเภทเดียวกับที่แก้ไปแล้วฝั่ง Agency/Ambulance ในข้อ 2 แต่พลาดฝั่ง Driver)

#### 🟡 หน้าจัดการหน่วยงาน (Agency) — ค่าพร้อม ER และข้อมูลโรงพยาบาลไม่เชื่อมกับระบบจริง
**ไฟล์:** `agency_profile_screen.dart`, `agency_incident_list_screen.dart`, `incident_service.dart`

- สวิตช์ "ER พร้อมรับผู้ป่วย" เป็นตัวแปร local ลอยๆ ไม่เชื่อมกับ `HospitalLocationService` จริง เปลี่ยนแล้วรีสตาร์ทแอปหาย — แก้ให้เชื่อมกับ service จริงทั้งอ่านและเขียน
- Modal "แก้ไขข้อมูลหน่วยงาน" กดบันทึกแล้วไม่ได้เรียก service บันทึกจริง — แก้แล้ว
- ชื่อโรงพยาบาลที่โชว์ถูกทับด้วยชื่อบัญชีส่วนตัวของ dispatcher (คนละอย่างกัน) — แก้ให้โหลดชื่อโรงพยาบาลจริงแยกจากชื่อบัญชี
- ปุ่ม "ยืนยัน ER พร้อม" บนแบนเนอร์รถพยาบาลใกล้ถึง (`agency_home_screen.dart`) เดิมโชว์แค่ข้อความสำเร็จลอยๆ ไม่ได้บันทึกอะไรจริง — แก้ให้เรียก `IncidentService().setErPrepared()` จริงเหมือนปุ่มที่ใช้งานได้อยู่แล้วในการ์ดรายละเอียดรถพยาบาล
- ตั้งค่า "เฉพาะเคสวิกฤต" และ "ระยะแจ้งเตือน" ใน Agency Settings เดิมไม่มีผลอะไรกับแอปเลย — แก้ให้กรองรายการเคสฉุกเฉินขาเข้าจริงตามค่าที่ตั้ง
- ข้อมูลตัวอย่าง (demo) 2 เคสที่ฝังไว้ในโค้ดสำหรับตอนยังไม่มีข้อมูล จะโผล่มาปนกับสถิติ/แผนที่จริงได้ชั่วขณะตอนเปิดแอปใหม่ๆ หรือเน็ตหลุด — ปิดไม่ให้ขึ้นมาปนกับข้อมูลจริงอีกต่อไป

**ยืนยันด้วย `flutter analyze` (0 errors, เหลือแค่ info เดิมที่ไม่เกี่ยวข้อง) และ `flutter test` (27/27 ผ่าน) หลังรวมการแก้ไขทั้งหมดจากทั้ง 4 ระบบเข้าด้วยกัน**

---

### 9.7 บัญชีทดสอบด่วนสำหรับสาธิตวิทยานิพนธ์ (Demo Quick Login)

**ไฟล์ที่แก้:** `lib/features/auth_face_login/presentation/face_login_screen.dart`

**ปัญหา/ความต้องการ:** ตอนสาธิตโปรเจกต์ให้อาจารย์ดู ต้องเดโมครบทั้ง 3 บทบาท (Driver/Ambulance/Agency) แต่ทุกบทบาทต้องผ่านขั้นตอนสมัครสมาชิก + ยืนยัน OTP + สแกนใบหน้า 3 มิติก่อนถึงจะเข้าใช้งานได้ทุกครั้ง ทำให้เสียเวลามากเวลาต้องสลับโชว์หลายบทบาทสดๆ หน้างาน

**ทางแก้:** เพิ่มทางลัดล็อกอินสำหรับ Username พิเศษ 3 ตัวในแท็บ "Sign in" (อีเมล/รหัสผ่าน) เท่านั้น:

| Username | รหัสผ่าน | บทบาทที่เข้า (ค่า `role` จริงในระบบ) |
|---|---|---|
| `admin_1` | `12345` | `driver` (ผู้ใช้ทั่วไป) |
| `admin_2` | `12345` | `ambulance` (รถพยาบาล) |
| `admin_3` | `12345` | `agency` (โรงพยาบาล/ดิสแพตช์) |

กลไก:
1. ก่อนเรียก `FaceAuthRepository.authenticateWithPassword()` ตามปกติ เช็คก่อนว่าค่าที่กรอกตรงกับ username/รหัสผ่านสำรองแบบเป๊ะๆ ไหม (ผ่าน `_kDemoAccounts` + `_kDemoQuickLoginPassword`) ถ้าไม่ตรง ระบบทำงานตามเดิม 100% ไม่กระทบผู้ใช้จริงเลย
2. ถ้าตรง จะเรียก `_handleDemoQuickLogin()`: เช็คว่ามีบัญชีทดสอบนี้ในระบบแล้วหรือยัง (`isEmailRegistered`) ถ้ายังไม่มี จะสร้าง `UserFaceProfile` ใหม่ผ่าน `FaceAuthRepository.registerUser()` (อีเมลปลอม `admin_1@routealert.test` เป็นต้น, ชื่อที่แสดงเช่น "ผู้ใช้ทดสอบ (Admin 1)", `faceEmbedding: []` เพื่อข้ามการสแกนหน้า) พร้อมตั้งรหัสผ่านให้ตรงกันไว้ ถ้ามีอยู่แล้วจะดึงโปรไฟล์เดิมมาแล้ว `setCurrentUser()` ตรงๆ (ไม่สร้างซ้ำ)
3. เติมข้อมูลเริ่มต้นให้หน้าจอไม่ขึ้นค่าว่าง — ทำ**ครั้งเดียวตอนสร้างบัญชีใหม่เท่านั้น** ไม่ทำซ้ำทุกครั้งที่ล็อกอิน:
   - `admin_2` (ambulance): เซ็ต `AmbulanceStorageService.saveProfile()` เป็นทะเบียน "ทดสอบ-001", ชื่อเรียกขาน "หน่วยทดสอบ 1"
   - `admin_3` (agency): เซ็ต `HospitalLocationService().updatePinnedLocation()` ชื่อโรงพยาบาลเป็น "โรงพยาบาลทดสอบ"
4. นำทางเข้าไปหน้าโฮมของบทบาทนั้นด้วย `_navigateToRoleScreen()` เมธอดเดิมที่ใช้ตอนล็อกอินสำเร็จปกติ (ไม่มีโค้ด navigation ซ้ำซ้อน)

**คุมด้วยธง (flag) เดียว:** `kEnableDemoQuickLogin` (ประกาศไว้บนสุดของ `face_login_screen.dart`) — ตั้งเป็น **`false`** เมื่อไหร่ ทางลัดนี้จะถูกปิดสนิททันที กลับไปใช้ `authenticateWithPassword()` ตามปกติสำหรับทุกอีเมลรวมถึง `admin_1/2/3` ด้วย

**⚠️ ข้อควรระวังก่อนปล่อยจริง:** ต้องตั้ง `kEnableDemoQuickLogin = false` ก่อน build/deploy เวอร์ชันจริงให้ผู้ใช้ทั่วไปเสมอ ไม่เช่นนั้นใครก็ตามที่รู้ username/password ทั้ง 3 ชุดนี้จะเข้าระบบได้โดยไม่ต้องยืนยันตัวตนใดๆ เลย (บายพาส Face ID, OTP, และรหัสผ่านจริงทั้งหมด) — ทางลัดนี้ไม่แตะต้อง/ไม่ทำให้อ่อนแอลงแต่อย่างใดกับตรรกะ `authenticateWithPassword()` เดิม, การแฮชรหัสผ่านจริง (SHA-256 + salt), หรือช่องโหว่ Google Sign-In ที่แก้ไปแล้วในข้อ 9.6 — เป็นโค้ดเพิ่มเติมแยกต่างหากทั้งหมด (additive only)

**ยืนยันด้วย `flutter analyze` (0 errors, เหลือแค่ info เดิมที่ไม่เกี่ยวข้อง) และ `flutter test` (27/27 ผ่าน) หลังเพิ่ม Demo Quick Login**

---

## 10. แจ้งเตือนพื้นหลัง (Background Proximity Alert) สำหรับ Driver

**ปัญหาเดิม:** ระบบแจ้งเตือนระยะรถพยาบาลของ Driver ทำงานได้ดีเฉพาะตอนหน้าจอแผนที่ (`driver_home_screen.dart`) เปิดอยู่ตรงหน้าเท่านั้น ถ้าผู้ใช้สลับไปแอปอื่นหรือล็อกหน้าจอ ตัว `CriticalNotificationService` เองรองรับการยิง OS notification เบื้องหลังอยู่แล้ว (channel `Importance.max` + `fullScreenIntent`) แต่ปัญหาจริงคือต้นทาง — `LocationService.getLiveLocationStream()` เดิมใช้ `LocationSettings` ธรรมดาไม่มีการตั้งค่าเฉพาะแพลตฟอร์มเลย ทำให้ Android เข้าสู่ Doze mode แล้วหยุด/หน่วง GPS อัปเดตเมื่อแอปเบื้องหลัง (เพราะไม่มี foreground service ประกาศไว้) และ iOS จะ suspend แอปทั้งตัวไม่นานหลังพับแอป (เพราะไม่ได้ขอ background location capability) — พอ stream หยุด logic ตรวจสอบระยะที่มีอยู่แล้วก็ไม่ถูกเรียกอีกต่อไป แจ้งเตือนจึงหยุดตามไปด้วย

**ไฟล์ที่แก้:**

1. **`lib/core/services/location_service.dart`** — `getLiveLocationStream()` เพิ่มพารามิเตอร์ `bool backgroundMode = false` (default เดิมเป๊ะ ไม่กระทบผู้เรียกเดิม): เมื่อ `true` และเป็น Android จะสร้าง `AndroidSettings(... foregroundNotificationConfig: ForegroundNotificationConfig(...))` ให้ระบบรันเป็น foreground service พร้อม notification ค้างไว้ (คำอธิบายภาษาไทย "กำลังตรวจสอบระยะรถพยาบาลฉุกเฉินใกล้เคียงอยู่เบื้องหลัง") ซึ่งทำให้ Flutter engine ทั้งตัว (รวม MQTT listener และ logic ตรวจระยะที่มีอยู่แล้วใน `driver_home_screen.dart`) ทำงานต่อเนื่องเบื้องหลังปกติ — เมื่อ `true` และเป็น iOS จะสร้าง `AppleSettings(allowBackgroundLocationUpdates: true, pauseLocationUpdatesAutomatically: false, showBackgroundLocationIndicator: true)` แทน ตรวจสอบแล้วว่าผู้เรียกเดิมอีก 2 จุด (`ambulance_home_screen.dart`, และการเรียกครั้งแรกใน `driver_home_screen.dart` ก่อนโหลดค่าที่บันทึกไว้) ยังไม่ส่งพารามิเตอร์นี้ = ใช้ `false` เหมือนเดิมทุกประการ ไม่กระทบ

2. **`lib/core/services/driver_storage_service.dart`** — เพิ่ม `backgroundAlertEnabledNotifier` (`ValueNotifier<bool>`, default `false`) กับ `getBackgroundAlertEnabled()`/`setBackgroundAlertEnabled()` บันทึกลง `SharedPreferences` คีย์ `driver_background_alert_enabled` มิเรอร์ pattern เดียวกับ `sirenDetectionEnabledNotifier` ที่มีอยู่แล้วในไฟล์เดียวกันเป๊ะ — **default ปิด** เพราะมีต้นทุนแบตเตอรี่ (foreground service ค้าง notification) และต้องขอสิทธิ์ตำแหน่งเพิ่ม (`locationAlways`) ซึ่งเป็นสิทธิ์ที่กระทบความเป็นส่วนตัวมากกว่า `whileInUse`

3. **`lib/features/driver_radar/presentation/driver_settings_screen.dart`** — เพิ่มการ์ดสวิตช์ "แจ้งเตือนพื้นหลัง (แจ้งเตือนแม้ล็อกหน้าจอ/สลับแอป)" พร้อมข้อความอธิบายตรงไปตรงมาใต้สวิตช์ (ไม่โอ้อวดว่าทำงานได้สมบูรณ์ทุกแพลตฟอร์ม): _"เปิดแล้วแอปจะแสดงการแจ้งเตือนค้างไว้ (Android) และขอสิทธิ์ตำแหน่งแบบ 'ตลอดเวลา' — บน iOS ระบบปฏิบัติการอาจจำกัดการทำงานเบื้องหลังเป็นบางครั้งตามข้อจำกัดของ Apple เอง"_ — ตอนกดเปิด จะโชว์ dialog อธิบายเหตุผลก่อนเสมอ (`_showBackgroundAlertRationaleDialog`) แล้วค่อยเรียก `Permission.locationAlways.request()` จาก `permission_handler` (มีอยู่แล้วใน `pubspec.yaml` แต่ยังไม่เคยถูกใช้งานจริงที่ไหนมาก่อน) ถ้าได้รับสิทธิ์จริงถึงจะเปิดสวิตช์และบันทึกค่า ถ้าถูกปฏิเสธ (หรือปฏิเสธถาวร) จะ**คืนสวิตช์กลับไปปิดจริง**ทันที พร้อมข้อความแจ้งเหตุผลตรงๆ (ปฏิเสธถาวรจะมีปุ่มลัดเปิดหน้าตั้งค่าระบบให้ด้วย) — ไม่มีการปล่อยให้สวิตช์ค้างเป็น "เปิด" ทั้งที่ไม่มีสิทธิ์จริงเด็ดขาด

4. **`lib/features/driver_radar/presentation/driver_home_screen.dart`** — `_initLiveLocation()` โหลดค่า `DriverStorageService.getBackgroundAlertEnabled()` ก่อนสมัคร location stream ครั้งแรก แล้วส่งเป็น `backgroundMode` ให้ `getLiveLocationStream()` และเพิ่ม listener `_onBackgroundAlertSettingChanged` ฟัง `backgroundAlertEnabledNotifier` (มิเรอร์ pattern `_listenToSettingsChanges()`/`_onSirenToggleChanged` ที่มีอยู่แล้ว) — ถ้าผู้ใช้เปิด/ปิดสวิตช์นี้จากหน้าตั้งค่าระหว่างแอปเปิดอยู่ (หน้าแผนที่ยังไม่ถูก unmount เพราะ `driver_main_screen.dart` ใช้ `IndexedStack`) จะยกเลิก stream เดิมแล้วสมัครใหม่ด้วยค่า `backgroundMode` ล่าสุดทันที ไม่ต้องปิดเปิดแอปใหม่

5. **Android/iOS platform config** — ตรวจสอบแล้วว่า `android/app/src/main/AndroidManifest.xml` มี `ACCESS_BACKGROUND_LOCATION`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION` อยู่แล้ว (ถูกเพิ่มไว้ก่อนหน้านี้ในเซสชันเดียวกันตอนทำฟีเจอร์ตรวจจับเสียงไซเรน) และ `ios/Runner/Info.plist` มี `NSLocationAlwaysAndWhenInUseUsageDescription`/`NSLocationAlwaysUsageDescription` และ `UIBackgroundModes` ที่มี `location` อยู่แล้วเช่นกัน — จึง**ไม่ต้องแก้ไฟล์ platform config เพิ่ม** สำหรับฟีเจอร์นี้

**ความน่าเชื่อถือจริงแต่ละแพลตฟอร์ม (พูดตรงๆ ไม่โอ้อวด):**
- **Android**: เชื่อถือได้สูง เพราะ `ForegroundNotificationConfig` ทำให้ระบบรันเป็น foreground service ตัวจริง (มี notification ค้างแจ้งผู้ใช้ตลอดว่ากำลังทำงานอยู่) ซึ่ง Android รับประกันไม่ฆ่า process ทิ้งตราบใดที่ notification ยังอยู่
- **iOS**: เป็น best-effort เท่านั้น แม้จะขอ `allowBackgroundLocationUpdates` และประกาศ `UIBackgroundModes: location` ครบแล้ว Apple ยังคงมีสิทธิ์ suspend แอปเบื้องหลังตามดุลพินิจของระบบปฏิบัติการเอง (เช่น แบตเตอรี่ต่ำ, ผู้ใช้ไม่ได้เคลื่อนที่นาน, ระบบต้องการทรัพยากรคืน) นี่เป็นข้อจำกัดของแพลตฟอร์ม ไม่ใช่บั๊กของแอปนี้ — จึงต้องบอกผู้ใช้ตรงๆ ในหน้าตั้งค่าไม่ให้คาดหวังว่าจะเหมือน Android 100%

**ไม่ได้เพิ่ม package ใหม่** (ไม่ใช้ `flutter_background_service`/`workmanager` ตามที่ตั้งใจไว้แต่แรก) — ใช้ `geolocator` (`^13.0.2`, มีอยู่แล้ว) ที่รองรับ `AndroidSettings`/`AppleSettings` ในตัว และ `permission_handler` (`^11.3.1`, มีอยู่แล้ว) สำหรับขอสิทธิ์เท่านั้น

**ยืนยันด้วย `flutter analyze` (0 errors, เหลือแค่ info เดิมที่ไม่เกี่ยวข้อง) และ `flutter test` (27/27 ผ่าน) หลังเพิ่มฟีเจอร์แจ้งเตือนพื้นหลัง**

---

## 11. บั๊กจริงที่พบระหว่างทดสอบ 2 เครื่องจริง (real-device testing) — สาเหตุที่ Driver/Ambulance ไม่เจอกันมาตลอด

รอบนี้เจอจากการทดสอบขึ้นเครื่องจริง 2 เครื่องพร้อมกัน (บัญชีทดสอบ `admin_1`/`admin_2`) ไม่ใช่จากการอ่านโค้ดล้วนๆ เหมือนรอบก่อนๆ เป็นบั๊กที่ซ่อนอยู่มาตั้งแต่ต้นโปรเจกต์ เพิ่งเจอเพราะเป็นครั้งแรกที่ทดสอบ 2 เครื่องจริงอย่างละเอียดพร้อมเครื่องมือ debug

### 11.1 แพ็กเก็ต MQTT CONNECT ผิดสเปก ทำให้เชื่อมต่อไม่ติดเลยทุกเครือข่าย
**ไฟล์:** `lib/core/services/emergency_mqtt_service.dart`

**ปัญหาที่พบ:** โค้ดเดิมสร้างข้อความ CONNECT แบบนี้:
```dart
final connMessage = MqttConnectMessage()
    .withClientIdentifier(clientId)
    .startClean()
    .withWillQos(MqttQos.atLeastOnce);
```
`.withWillQos()` ตั้งค่าบิต Will QoS ในแพ็กเก็ต แต่**ไม่เคยตั้ง Will Flag** (ต้องเรียกผ่าน `.withWillTopic()`/`.withWillMessage()` ถึงจะเซ็ต Will Flag ให้ — ตรวจสอบจากซอร์สโค้ดจริงของ package `mqtt_client` ยืนยันแล้ว) เกิดเป็นแพ็กเก็ตที่ผิดสเปก MQTT (Will QoS ถูกตั้งค่าทั้งที่ Will Flag = 0) โบรกเกอร์ที่ตรวจสอบแพ็กเก็ตเข้มงวดอย่าง `broker.emqx.io` จะปิดการเชื่อมต่อเงียบๆ โดยไม่ส่ง CONNACK กลับมาเลย ทำให้ทั้ง Driver และ Ambulance เชื่อมต่อไม่ติดตลอด **ไม่ว่าจะเปลี่ยนเครือข่ายกี่แบบก็ตาม** (ทดสอบแล้วว่าไม่ใช่ปัญหาไฟร์วอลล์บล็อก port — เชื่อมต่อ broker เดียวกันจากเครื่องมือทดสอบแยกต่างหากสำเร็จปกติ)

**หลังแก้:** ตัด `.withWillQos(...)` ออก (ไม่มีการใช้ฟีเจอร์ Will message จริงในระบบนี้อยู่แล้ว)

### 11.2 ข้อความภาษาไทยเพี้ยนระหว่างส่งผ่าน MQTT ทำให้ parse JSON ไม่ผ่าน
**ไฟล์:** `lib/core/services/emergency_mqtt_service.dart`

**ปัญหาที่พบ (เจอหลังแก้ 11.1 แล้ว — เชื่อมต่อติดแล้วแต่ยังไม่เห็นรถพยาบาลอยู่ดี):** ฝั่งส่งใช้ `builder.addString(json)` ซึ่งเรียก `addUTF16String()` ภายใน — เข้ารหัสตัวอักษรที่มี code unit เกิน 255 (ตัวอักษรไทยทุกตัว) เป็น 2 ไบต์แบบ raw 16-bit half-word ไม่ใช่ UTF-8 มาตรฐาน ส่วนฝั่งรับใช้ `MqttPublishPayload.bytesToStringAsString()` ซึ่งถอดรหัสแบบ 1 ไบต์ = 1 ตัวอักษร (ไม่ใช่ UTF-8 เหมือนกัน แต่คนละวิธีกับฝั่งส่ง) สองฝั่งเข้ารหัส/ถอดรหัสไม่ตรงกันเลย ผลคือข้อความที่มีภาษาไทย (เช่น `callSign: "หน่วยทดสอบ 1"`) เพี้ยนเป็นตัวอักษรควบคุมมั่วๆ จน `json.decode()` โยน `FormatException: Control character in string` ทุกครั้ง — เพิ่มตัวนับ `messagesReceivedCount` ยืนยันว่าข้อความมาถึงจริง (6 ข้อความ) แต่ parse ไม่ผ่านสักครั้งเดียว จึงเห็น "รถพยาบาลในระบบ: 0 คัน" ตลอดทั้งที่ MQTT เชื่อมต่อสำเร็จแล้ว

**หลังแก้:** เปลี่ยนฝั่งส่งเป็น `builder.addUTF8String(json)` และฝั่งรับเป็น `utf8.decode(bytes)` (จาก `dart:convert` ที่มีอยู่แล้ว) ให้ตรงกันทั้งสองฝั่ง ทดสอบ roundtrip ด้วยสคริปต์แยกยืนยันแล้วว่าข้อความภาษาไทยเข้ารหัส-ถอดรหัสกลับมาตรงเป๊ะ

### 11.3 หมุดโรงพยาบาลไม่อัปเดตข้ามเครื่องเลย
**ไฟล์:** `lib/features/driver_radar/presentation/driver_home_screen.dart`, `lib/features/ambulance/presentation/ambulance_home_screen.dart`

**ปัญหาที่พบ:** ทั้ง 2 หน้าจอนี้อ่านค่า `HospitalLocationService().hospitalLocation` และ subscribe `profileStream` ไว้ แต่**ไม่เคยเรียก `HospitalLocationService().initialize()` เลย** — เมธอดนี้คือจุดเดียวที่เปิดการเชื่อมต่อ Firestore listener จริง (`_initFirestoreListener()`) ถ้าไม่เรียก จะไม่มีใครยิง event เข้า `profileStream` เลยตลอดไป เห็นแค่พิกัดโรงพยาบาลเริ่มต้นที่ hardcode ไว้ในโค้ด (เชียงใหม่) แม้ Agency จะปักหมุดใหม่จากเครื่องอื่นกี่ครั้งก็ตาม (Agency เองเห็นการเปลี่ยนแปลงถูกต้อง เพราะหน้าจอ Agency เรียก `initialize()` อยู่แล้ว)

**หลังแก้:** เพิ่มการเรียก `await HospitalLocationService().initialize()` ในทั้ง 2 หน้าจอก่อน subscribe `profileStream` ยืนยันจากผู้ใช้แล้วว่าย้ายหมุดจาก Agency ตอนนี้อัปเดต real-time ถึงทั้ง Driver และ Ambulance ถูกต้อง

### 11.4 เพิ่มหมุดโรงพยาบาลให้ฝั่ง Driver (เดิมไม่เคยแสดงเลย)
**ไฟล์:** `lib/features/driver_radar/presentation/driver_home_screen.dart`

เดิมแผนที่ฝั่ง Driver แสดงแค่รถพยาบาล ไม่เคยแสดงหมุดโรงพยาบาลปลายทางเลยทั้งที่ Ambulance/Agency ใช้ข้อมูลชุดเดียวกัน เพิ่มหมุด 🏥 บนแผนที่ Driver แล้ว ใช้ข้อมูลจาก `HospitalLocationService` เดียวกัน อัปเดตสดตามข้อ 11.3

### 11.5 เครื่องมือ debug ชั่วคราวสำหรับวินิจฉัยปัญหาการเชื่อมต่อ
**ไฟล์:** `lib/core/services/emergency_mqtt_service.dart`, `driver_home_screen.dart`, `ambulance_home_screen.dart`

เพิ่มแถบข้อความเล็กๆ ใต้ header ทั้ง Driver และ Ambulance โชว์สถานะ MQTT connected/disconnected จริง, ข้อความ error จริงตอนเชื่อมต่อไม่ติด (`lastError`), จำนวนข้อความที่ได้รับจริง (`messagesReceivedCount`), และ error ตอน parse ไม่ผ่าน (`lastParseError`) — เครื่องมือนี้เป็นตัวช่วยสำคัญที่ทำให้เจอบั๊ก 11.1 และ 11.2 ได้เร็วจากการดูภาพหน้าจอจริงแทนการเดา **เป็นเครื่องมือ debug ชั่วคราว แนะนำให้เอาออกหรือซ่อนไว้หลัง flag ก่อนส่งงานจริง/ปล่อยให้ผู้ใช้ทั่วไปใช้งาน**

**ยืนยันด้วย `flutter analyze` (0 errors) และ `flutter test` (27/27 ผ่าน) หลังแก้ทุกข้อ — ยืนยันเพิ่มเติมด้วยการทดสอบ UTF-8 roundtrip แยกต่างหาก และผู้ใช้ทดสอบเครื่องจริง 2 เครื่องแล้วเห็นหมุดโรงพยาบาลอัปเดต real-time ถูกต้อง**

### 11.6 ความเร็ว "คุณ" บนแผนที่ Driver เป็นค่า hardcode ตายตัว
**ไฟล์:** `lib/features/driver_radar/presentation/driver_home_screen.dart`

`_driverSpeed = 50.0` ตายตัวเสมอ (บั๊กคลาสเดียวกับความเร็วรถพยาบาลที่แก้ไปแล้วในข้อ 9.x — ตอนนั้นแก้แค่ฝั่ง Ambulance พลาดฝั่ง Driver) ค่านี้ยังถูกใช้ป้อนเข้า AI trajectory evaluation จริงด้วย แก้โดยคำนวณจากระยะทาง GPS 2 จุดล่าสุด/เวลาที่ผ่านไป เหมือนฝั่ง Ambulance ทุกประการ

### 11.7 ฝั่ง Ambulance ไม่มีปุ่มจัดกึ่งกลาง GPS เลย
**ไฟล์:** `lib/features/ambulance/presentation/ambulance_home_screen.dart`

แผนที่ฝั่งนี้ไม่เคยมี `MapController` มาก่อนเลย เพิ่มปุ่มวงกลม 🎯 มุมขวา (มิเรอร์ปุ่มเดียวกันที่มีอยู่แล้วฝั่ง Driver) กดแล้วเลื่อนแผนที่กลับมาตำแหน่งรถพยาบาลตัวเองทันที

### 11.8 พิกัด GPS "วาปไปวาปมา" ตอนทดสอบในอาคาร
**ไฟล์:** `lib/core/services/location_service.dart`

`getLiveLocationStream()` เดิมไม่กรองความแม่นยำเลย พิกัดดิบทุกจุด (รวมค่าที่เพี้ยนจากสัญญาณสะท้อนในอาคาร) ถูกส่งตรงไปอัปเดต UI ทันที เพิ่มการกรองทิ้งพิกัดที่ `Position.accuracy` แย่กว่า 50 เมตร ก่อนส่งต่อ

### 11.9 รถพยาบาลไม่หายจากแผนที่ Driver แม้ปิดแอปไปแล้ว
**ไฟล์:** `lib/core/services/emergency_mqtt_service.dart`

ไม่มีกลไกหมดอายุข้อมูลเลย ปิดแอปฝั่ง Ambulance โดยไม่มีการส่งสัญญาณ "ออฟไลน์" ใดๆ พิกัดล่าสุดค้างอยู่ในหน่วยความจำฝั่ง Driver ตลอดไป เพิ่มตัวจับเวลาทุก 5 วินาที ตรวจรถพยาบาลที่ไม่มีอัปเดตเกิน 12 วินาที (นานกว่า heartbeat broadcast ปกติทุก 3 วินาทีหลายเท่า) แล้วลบออกจาก fleet พร้อมยิง event `sirenActive:false` ปลอมผ่าน `emergencyStream` ให้โค้ดเดิมของ Driver เคลียร์หมุดให้เอง

### 11.10 (ไม่ใช่บั๊ก — ชี้แจงพฤติกรรมที่ตั้งใจ) "สวนเลน" ขึ้นทั้งที่เดินเข้าหากันตรงๆ

ระบบตัดสิน "สวนเลน" จากทิศทางเดิน/ขับที่ตรงข้ามกัน (~180°) ซึ่งตรงกับสถานการณ์จริงบนถนน 2 เลน (รถสวนมาคนละเลน ไม่ต้องหลบทาง) แต่การเดินทดสอบในอาคารแบบ "เดินเข้าหากันตรงๆ" ตรงกับนิยามนี้พอดี ทำให้ดูเหมือนเพี้ยน — วิธีทดสอบให้เห็น "ต้องหลบทาง/วิกฤต" ที่ถูกต้องคือให้เดินทิศทางเดียวกัน (คนนึงไล่ตามอีกคนจากด้านหลัง) ไม่ใช่เดินสวนหน้ากัน นอกจากนี้ทิศทางคำนวณจากระยะขยับแค่ 2 เมตร ซึ่งเล็กกว่าความคลาดเคลื่อน GPS ในอาคารมาก แนะนำเดินเป็นเส้นตรงยาวๆ 5-10 เมตรต่อครั้งเพื่อความแม่นยำของทิศทางที่คำนวณได้

**ยืนยันด้วย `flutter analyze` (0 errors) และ `flutter test` (27/27 ผ่าน) หลังแก้ข้อ 11.6-11.9 ทั้งหมด**

---

## 12. เสียงพูดแจ้งเตือนแบบเลือกโทน/เสียงได้ (Voice Alert Tone & Voice Selection)

**ไฟล์:** `lib/core/services/voice_alert_service.dart`, `lib/features/driver_radar/presentation/driver_settings_screen.dart`

ระบบเสียงพูดแจ้งเตือน (`VoiceAlertService`, ใช้ `flutter_tts`) มีอยู่แล้วและทำงานจริง (พูดเตือนตอนเข้าเขตเรดาร์/วิกฤต/รถผ่านไปแล้ว) แต่ใช้ pitch/ความเร็วพูด/เสียงคงที่ตายตัว ไม่มีทางปรับได้เลย

**เพิ่ม:**
1. **โทนเสียง 3 แบบ** (`VoiceTone` enum): ปกติ, นุ่มนวล (pitch/ความเร็วต่ำกว่า), กระชับเร่งด่วน (pitch/ความเร็วสูงกว่า) — ทำงานได้แน่นอนทุกเครื่องเพราะแค่ปรับพารามิเตอร์ ไม่ต้องพึ่งว่าเครื่องมีเสียงให้เลือกกี่แบบ
2. **เลือกเสียง TTS ของระบบได้** ผ่าน `getAvailableVoices()` (กรองเฉพาะเสียงภาษาไทยถ้ามี ถ้าไม่มีเลยจะโชว์ทุกเสียงที่เครื่องมีแทน)
3. ทั้ง 2 อย่างบันทึกถาวรผ่าน `SharedPreferences` และโหลดกลับมาใช้ทันทีตอนเปิดแอปใหม่ พูดตัวอย่างเสียงทันทีตอนเลือกเพื่อให้ผู้ใช้ได้ยินผลก่อนตัดสินใจ
4. เพิ่มการ์ดตั้งค่าใหม่ในหน้า Driver Settings (ระหว่างการ์ดตรวจจับเสียงไซเรนกับการ์ดแจ้งเตือนพื้นหลัง)

**ไม่ได้ทำ (ตามที่ผู้ใช้เลือก):** Live Activity บนหน้าจอล็อก (iOS 16+) — ต้องสร้าง Widget Extension target ใหม่ผ่าน Xcode GUI wizard ก่อน (สร้าง target, เปิด capability "Push Notifications"/"App Groups") ซึ่งเป็นขั้นตอนที่ทำผ่านการแก้ไฟล์โดยตรงไม่ได้อย่างปลอดภัย (เสี่ยงทำให้ไฟล์ .pbxproj ของโปรเจกต์เสียหาย) ต้องให้ผู้ใช้ทำ 2-3 ขั้นตอนในเครื่องเองก่อน ถึงจะเขียนโค้ด Swift/Dart ที่เหลือให้ได้

**ยืนยันด้วย `flutter analyze` (0 errors) และ `flutter test` (27/27 ผ่าน)**

---

## 13. รอบตรวจสอบครั้งที่ 2 หลังแก้ไขเยอะๆ ติดกันในเซสชันเดียว — พบ 2 บั๊กที่เพิ่งแก้ไปเองด้วย

หลังทำหัวข้อ 10-12 เสร็จ (แก้ไขเยอะมากติดกันในไฟล์เดียวกันหลายรอบ) ตรวจสอบซ้ำแบบละเอียดอีกครั้งแยกตาม Driver/Ambulance/Agency/Core services พบว่า **การแก้ไขเองในหัวข้อก่อนหน้า 2 จุดสร้างบั๊กใหม่ขึ้นมาโดยไม่ตั้งใจ** (regression) นอกเหนือจากบั๊กเดิมที่ยังไม่เคยเจอ — บันทึกไว้ทั้งหมดเพื่อเป็นบทเรียน: การย้าย/เพิ่ม UI element แบบเร็วๆ โดยไม่ไล่เช็คทุก state ที่เป็นไปได้ เสี่ยงสร้างปัญหาใหม่แทนที่จะแก้ปัญหาเดิมเท่านั้น

### 13.1 (Regression ของตัวเอง) ย้ายป้าย "ออนไลน์"/"กฎหมายระยะ" ไป top:14 แล้วไปทับ HUD แจ้งเตือน
**ไฟล์:** `lib/features/driver_radar/presentation/driver_home_screen.dart`

ตอนย้ายป้ายทั้งสองขึ้นมาชิดขอบบนตามที่ขอ (หัวข้อก่อนหน้า) ไม่ได้เช็คว่า `_buildDramaticEmergencyHud()` เป็น Container เต็มความกว้างที่วางอยู่ที่ `top:12` เหมือนกัน และแสดงผลจริง (ไม่ใช่ค่าว่าง) ในสถานะที่พบได้บ่อยมาก เช่น สวนเลน, รถผ่านไปแล้ว, กำลังจะเลี้ยวออก, หรืออยู่ในโซนเรดาร์สีฟ้า (ทุกสถานะที่ `shouldAlert: false`) ผลคือป้ายทั้งสองไปทับซ้อนกับ HUD ทุกครั้งที่มีรถพยาบาลอยู่ในสถานะเหล่านี้ — **แก้โดย** ขยายเงื่อนไขการแสดงป้ายทั้งสองจาก `!_isInRedZone && _activeHeadsUp == null` เป็น `!_isInRedZone && _activeHeadsUp == null && _aiPrediction == null` (ซ่อนป้ายเมื่อ HUD กำลังแสดงข้อมูลอยู่ ไม่ว่าจะสถานะไหนก็ตาม)

### 13.2 (Regression ของตัวเอง) ปุ่มจัดกึ่งกลาง GPS ฝั่ง Ambulance ทับแผ่นสถานะที่ลากได้
**ไฟล์:** `lib/features/ambulance/presentation/ambulance_home_screen.dart`

ตอนเพิ่มปุ่มจัดกึ่งกลาง GPS (หัวข้อก่อนหน้า) คำนวณตำแหน่ง `bottom` จากค่าคงที่ 0.12 (ขนาดย่อสุดของแผ่น) ครั้งเดียว แต่แผ่นสถานะจริงเปิดที่ 0.24 เป็นค่าเริ่มต้น (ไม่ใช่ 0.12) และลากขึ้นได้ถึง 0.65 — ปุ่มเลยจมอยู่ใต้/ในแผ่นสถานะตั้งแต่เปิดหน้าจอครั้งแรก ไม่ใช่แค่ตอนลากขึ้นสุด **แก้โดย** เพิ่ม `DraggableScrollableController` ผูกกับแผ่น ฟังการลากแบบ real-time แล้วคำนวณตำแหน่งปุ่มใหม่ทุกครั้งจากขนาดแผ่นจริง ณ ขณะนั้น

### 13.3 Agency ไม่เคยลบรถพยาบาลที่ออฟไลน์ออกจากแผนที่ตัวเอง (บั๊กเดิม ไม่ใช่ regression)
**ไฟล์:** `lib/features/agency/presentation/agency_home_screen.dart`

กลไกลบรถพยาบาลหมดอายุที่เพิ่งทำไว้ในหัวข้อ 11.9 (ให้ Driver ใช้งานอยู่แล้ว) ฝั่ง Agency ไม่เคยได้ใช้เลย เพราะหน้านี้ดักฟัง `emergencyStream` ดิบแล้วสะสมข้อมูลรถพยาบาลเองแยกต่างหาก (ไม่เคยลบออกเมื่อได้รับสัญญาณ `sirenActive:false`) ทำให้รถพยาบาลที่ออฟไลน์ยังค้างอยู่บนแผนที่/สถิติ/แบนเนอร์เตือนของ Agency ตลอดไป ทั้งที่ Driver มองไม่เห็นแล้ว **แก้โดย** เปลี่ยนไปใช้ `EmergencyMqttService().activeFleetStream` (ที่กรองรถออฟไลน์ให้แล้วในตัว) แทนการสะสมเองจาก stream ดิบ

### 13.4 อื่นๆ ที่พบและแก้ในรอบนี้ (สรุปย่อ — ไม่ใช่ regression ของตัวเอง)

- **`location_service.dart`**: `.handleError((_) => defaultLocation)` เป็นโค้ดที่ไม่มีผลจริง (ค่าที่ return จาก `handleError` ถูกทิ้ง ไม่เคยถูกส่งเป็นข้อมูลจริงเข้าสตรีม) แก้เป็น `StreamTransformer.fromHandlers` ที่ยิงค่า fallback เข้าสตรีมจริง — และเพิ่ม timeout 15 วินาทีให้ตัวกรองความแม่นยำ GPS (จากหัวข้อ 11.8) กันไม่ให้สตรีมค้างเงียบตลอดไปถ้าเครื่องไม่เคยรายงานความแม่นยำดีพอสักครั้ง
- **`emergency_mqtt_service.dart`**: กลไกหมดอายุรถพยาบาล (11.9) เดิมเทียบเวลากับนาฬิกาของเครื่องผู้ส่งเอง เสี่ยงพังถ้านาฬิกา 2 เครื่องไม่ตรงกัน แก้เป็นเทียบกับเวลาที่ "เครื่องนี้" ได้รับข้อมูลจริงแทน
- **`voice_alert_service.dart`**: เพิ่มการกันเรียก `initialize()` ซ้อนกันพร้อมกัน (race condition ที่อาจทำให้ค่าที่เพิ่งเลือกไว้ถูกทับกลับเป็นค่าเก่า)
- **Agency**: เพิ่ม timeline step "ใกล้ถึง รพ." ที่หายไปในหน้าเคส, แก้ subscription รั่วในหน้าเคส (ไม่เคย cancel), แก้สวิตช์ ER-availability หน้า home ให้แจ้งเตือนตอน error เหมือนหน้าโปรไฟล์
- **Ambulance**: แก้ `MapController` รั่ว (ไม่เคย dispose), แก้ไอคอนลูกศรทับข้อความที่อยู่ยาวๆ ในรายการเคส, แก้ default ที่ไม่ปลอดภัยของ `_isOwnCase` เมื่อไม่มีข้อมูลเคส
- **Driver**: ปิดแถบ debug MQTT ไว้เป็นค่าเริ่มต้น (`kShowMqttDebugBar = false`) เพราะบั๊กที่ใช้วินิจฉัยแก้หมดแล้ว เปิดกลับมาได้ง่ายๆ ถ้าต้องใช้อีก

**ยืนยันด้วย `flutter analyze` (0 errors) และ `flutter test` (27/27 ผ่าน) หลังรวมการแก้ไขทั้งหมดจากทั้ง 4 กลุ่มเข้าด้วยกัน**

---

## 14. หน้าแนะนำการใช้งาน (Onboarding) แบบ Liquid Swipe ตอนเปิดแอปครั้งแรก

**ไฟล์ใหม่:** `lib/features/onboarding/presentation/onboarding_screen.dart`, `lib/core/services/onboarding_service.dart`
**ไฟล์ที่แก้:** `lib/main.dart`, `driver_settings_screen.dart`, `ambulance_settings_screen.dart`, `agency_settings_screen.dart`

ผู้ใช้ส่งวิดีโอตัวอย่างมา (เป็นคลิปรีวิว Flutter package "liquid swipe" ไม่ใช่คลิปจากแอปตัวเอง) เพื่อขอสไตล์อนิเมชันแบบเดียวกัน — ลากเปลี่ยนหน้าแบบเป็นคลื่นของเหลว (liquid wave) พร้อมปุ่มลากตรงกลางที่ตามนิ้วไปด้วย ผมเปิดวิดีโอ .mov ตรงๆ ไม่ได้ (รองรับแค่รูปภาพ/PDF) เลยติดตั้ง `ffmpeg` ผ่าน Homebrew ดึงเฟรมจากวิดีโอออกมาดูแทน ยืนยันได้ว่าเป็นเอฟเฟกต์จาก package `liquid_swipe` (`iamSahdeep/liquid_swipe_flutter`) จริง

**สิ่งที่ทำ:**
1. เพิ่ม package `liquid_swipe: ^3.1.0`
2. สร้างหน้า Onboarding 3 หน้า อธิบาย 3 role: **Driver** (สีน้ำเงิน — อธิบายว่าจะได้รับแจ้งเตือนเมื่อรถพยาบาลใกล้เข้ามา), **Ambulance** (สีแดง — อธิบายว่าเปิดสัญญาณแล้วจะกระจายตำแหน่งเตือนผู้ใช้ถนน), **Agency** (สีเขียว — อธิบายว่าเห็นรถพยาบาลทุกคันบนแผนที่และมอบหมายเคสได้) พร้อม**ภาพประกอบจริงสไตล์ flat illustration** (ไม่ใช่แค่ไอคอน) ตามที่ขอให้เหมือนวิดีโอต้นฉบับ — ใช้ภาพจากคลังโอเพนซอร์ส **unDraw** (ฟรีทั้งเชิงบุคคล/พาณิชย์ ไม่ต้องขึ้นเครดิต) วางไว้ที่ `assets/illustrations/` (`onboarding_driver.svg`=คนขับรถบนถนน, `onboarding_ambulance.svg`=หมอ+pulse หัวใจ, `onboarding_agency.svg`=คนดูแลแดชบอร์ดสั่งการ) render ด้วย package `flutter_svg` ในการ์ดวงกลมสีขาวลอยอยู่บนพื้นหลังสี ตรงกับ layout ในวิดีโอตัวอย่าง
3. **ปุ่ม "เริ่มต้นใช้งาน" ขึ้นเฉพาะหน้าสุดท้ายเท่านั้น** (fade+scale เข้ามา) ตามที่ขอ กดแล้วบันทึกว่าเคยดูแล้ว (`OnboardingService.markOnboardingSeen()`) แล้วไปหน้าล็อกอิน มีปุ่ม "ข้าม" มุมขวาบนให้ข้ามได้ทุกหน้าก่อนหน้าสุดท้ายด้วย
4. **โชว์แค่ครั้งเดียวจริงๆ**: `lib/main.dart` เพิ่ม `_StartupRouter` เช็ค `OnboardingService.hasSeenOnboarding()` (เก็บใน SharedPreferences) ก่อนตัดสินใจว่าจะพาไปหน้า Onboarding หรือข้ามไปหน้าล็อกอินเลย เช็คเร็วมากไม่กระทบความเร็วเปิดแอป
5. **ย้อนกลับไปดูซ้ำได้จากหน้าตั้งค่า**: เพิ่มเมนู "ดูคำแนะนำการใช้งานอีกครั้ง" ในหน้า Settings ทั้ง 3 role (Driver/Ambulance/Agency) เปิดหน้า Onboarding แบบ `isReplay: true` (ปุ่มท้ายเปลี่ยนเป็น "ปิด" แค่ pop กลับ ไม่ไปหน้าล็อกอินซ้ำ ไม่กระทบ flag ที่บันทึกไว้)

**ยืนยันด้วย `flutter analyze` (0 errors) และ `flutter test` (27/27 ผ่าน) — เพิ่ม package `flutter_svg` และติดตั้ง `ffmpeg`/`librsvg` ผ่าน Homebrew เป็นเครื่องมือช่วยดูวิดีโอ/พรีวิวภาพประกอบก่อนเลือกเท่านั้น (ไม่ใช่ dependency ของแอป) sync CocoaPods แล้ว จำนวน pod ฝั่ง iOS ไม่เปลี่ยน (ทั้ง 2 package ใหม่เป็น pure-Dart)**

---

## 15. Coach Mark — ชี้ตำแหน่งปุ่มจริงบนหน้าจอ แยกตาม role อัตโนมัติ

**ไฟล์ใหม่:** `lib/core/services/coach_mark_service.dart`
**ไฟล์ที่แก้:** `driver_home_screen.dart`, `ambulance_home_screen.dart`, `agency_home_screen.dart`

ต่อยอดจากหน้า Onboarding (หัวข้อ 14) — คุยกับผู้ใช้แล้วสรุปว่าการอธิบาย "ปุ่มไหนทำอะไร" ควรอยู่แยกจากหน้า Onboarding เดิม เพราะ Onboarding โชว์**ก่อน**ล็อกอิน ยังไม่รู้ว่าผู้ใช้จะเข้า role ไหน อธิบายปุ่มทั้ง 3 role พร้อมกันจะยาวเกินไปและคนละบริบทเวลากับตอนใช้งานจริง — เปลี่ยนมาทำ **Coach Mark** (กรอบไฮไลต์ชี้ตำแหน่งปุ่มจริงบนหน้าจอ พร้อมคำอธิบายสั้นๆ) แทน โชว์**หลังล็อกอินแล้ว** ตอนเข้าหน้าหลักของแต่ละ role เป็นครั้งแรกเท่านั้น ข้อดีคือรู้แน่ชัดว่าผู้ใช้อยู่หน้าจอไหน role ไหน ไม่ต้องเดา

**ใช้ package `tutorial_coach_mark`** ปุ่มที่ชี้ในแต่ละ role:
- **Driver**: ปุ่มจัดกึ่งกลาง GPS, ปุ่ม SOS
- **Ambulance**: ปุ่มจัดกึ่งกลาง GPS, สวิตช์ "ส่งสัญญาณเตือน", สวิตช์ "โหมดทดสอบในห้อง" (ขยายแผ่นสถานะที่ลากได้ให้เห็นเต็มก่อนชี้ ไม่งั้นตำแหน่งจะผิดเพราะสวิตช์อยู่นอกมุมมองตอนแผ่นย่ออยู่)
- **Agency**: ปุ่มเปิด/ปิดแผนที่จุดเสี่ยงอุบัติเหตุ (Hotspot), ปุ่มอัปเดตสถานะ ER ว่าง/เต็ม

**บันทึกว่าเคยดูแล้วแยกเป็นรายบทบาท** (`CoachMarkService`, คีย์ `has_seen_coach_mark_driver/ambulance/agency` ใน SharedPreferences) ไม่ปะปนกัน — ถ้าสมัครใหม่/ทดสอบหลาย role ในเครื่องเดียวกัน (เช่น บัญชีทดสอบ admin_1/2/3) แต่ละ role จะได้เห็น Coach Mark ของตัวเองครั้งแรกเสมอ ไม่ขึ้นซ้ำอีกหลังจากนั้น กดข้าม (Skip) ได้ก็ถือว่าดูแล้วเหมือนกัน

**ยืนยันด้วย `flutter analyze` (0 errors) และ `flutter test` (27/27 ผ่าน) — เพิ่ม package `tutorial_coach_mark` (pure-Dart) sync CocoaPods แล้ว จำนวน pod ฝั่ง iOS ไม่เปลี่ยน**

---

## 16. ปรับสถาปัตยกรรมหัวข้อ 14-15 ใหม่ทั้งหมด — รวม Onboarding เข้ากับ Coach Mark ตามที่ผู้ใช้ขอ

หลังคุยกันเพิ่มเติม ผู้ใช้ขอปรับจากที่ทำไว้ในหัวข้อ 14-15 ให้ตรงใจมากขึ้น สรุปเป็นสถาปัตยกรรมสุดท้ายดังนี้ **(ทับของเดิมในหัวข้อ 14-15 บางส่วน อ่านหัวข้อนี้เป็นสถานะล่าสุดที่ถูกต้อง)**:

### สิ่งที่เปลี่ยน
1. **Onboarding (Liquid Swipe) ย้ายจากก่อนล็อกอิน → หลังล็อกอิน แยกตาม role**
   - เดิม: โชว์ก่อนล็อกอินครั้งเดียว รวม 3 role ในหน้าเดียวกัน (role ละ 1 หน้า อธิบายกว้างๆ)
   - ใหม่: โชว์**หลังล็อกอินแล้ว** ตอนเข้าหน้าหลักของแต่ละ role เป็นครั้งแรกเท่านั้น (`XxxMainScreen.initState()` เช็ค `OnboardingService.hasSeenOnboarding(role)` แล้ว `Navigator.push` แบบ `fullscreenDialog: true`) แต่ละ role มี **3 หน้าย่อยของตัวเอง** อธิบายละเอียดขึ้น (ภาพรวม role + ปุ่ม/ฟีเจอร์สำคัญ 2 อย่าง) เพราะรู้ role แน่ชัดแล้วอธิบายเจาะจงได้ ไม่ต้องเดา
   - `OnboardingScreen` เปลี่ยนจาก 1 หน้า/role (ทั้งหมด 3 หน้า) เป็น `required String role` + หน้าย่อยเฉพาะ role นั้น (3 หน้า/role) — ย้ายเนื้อหาปุ่ม (SOS, GPS, สวิตช์ต่างๆ) จาก Coach Mark descriptions มาเขียนเป็นหน้า text/ภาพในนี้ด้วย
   - `OnboardingService` เปลี่ยนจากเก็บ flag เดียว (`hasSeenOnboarding()`) เป็นแยกรายบทบาท (`hasSeenOnboarding(String role)`) เหมือน `CoachMarkService` เดิม
   - `main.dart` ตัด `_StartupRouter`/onboarding-check ออก กลับไปเป็น `home: const FaceLoginScreen()` ตรงๆ

2. **Coach Mark เลิกโชว์อัตโนมัติ → ย้ายเป็นปุ่ม manual ในหน้าตั้งค่า**
   - เดิม: โชว์อัตโนมัติครั้งแรกหลังล็อกอินคู่ขนานกับ Onboarding (ซ้ำซ้อนกันเกินไป ผู้ใช้บอกว่า "เกินไปหน่อย")
   - ใหม่: ตัดการโชว์อัตโนมัติทิ้งทั้งหมด (`CoachMarkService` เลยไม่ได้ใช้แล้ว **ลบไฟล์ทิ้ง**) เปลี่ยนเป็นปุ่ม **"สอนการใช้งานปุ่มต่างๆ"** ใหม่ในหน้า Settings ของทั้ง 3 role กดแล้วจะ: สลับไปแท็บแผนที่ (home tab) อัตโนมัติ → รอเฟรม render เสร็จ → เปิด Coach Mark ชี้ปุ่มจริงให้ทันที
   - เหตุผลทางเทคนิคที่ต้องส่ง callback ข้ามไฟล์: Coach Mark ผูกอยู่กับ GlobalKey ของปุ่มใน `XxxHomeScreen` แต่ปุ่ม "สอนการใช้งาน" อยู่ใน `XxxSettingsScreen` (คนละหน้าใน `IndexedStack` เดียวกัน) — แก้ด้วย pattern ส่งฟังก์ชันขึ้นไปให้ `XxxMainScreen` เก็บไว้ตอน `initState()` ของ Home screen (`onCoachMarkReady: (fn) => _showXxxCoachMark = fn`) แล้ว Settings screen เรียกผ่าน callback อีกทีตอนกดปุ่ม (`onShowCoachMark: _showCoachMarkTour`)

### ลำดับการทำงานจริงหลังปรับ
เปิดแอป → ล็อกอิน/เลือก role → เข้าหน้าหลักของ role นั้น → **(ครั้งแรกเท่านั้น)** ขึ้นหน้า Onboarding 3 หน้าของ role นั้นแบบ Liquid Swipe → กด "เริ่มต้นใช้งาน" ปิดหน้านี้ เข้าใช้แอปจริง — ถ้าอยากดู Onboarding ซ้ำ หรืออยากให้ชี้ปุ่มแบบ Coach Mark อีกครั้ง กดได้เองจากหน้า Settings ตลอดเวลา (คนละปุ่มกัน ไม่บังคับดูพร้อมกัน)

**ยืนยันด้วย `flutter analyze` (0 errors) และ `flutter test` (27/27 ผ่าน) หลังปรับสถาปัตยกรรมทั้งหมดและลบไฟล์ที่ไม่ได้ใช้แล้ว (`coach_mark_service.dart`)**

---

## 17. บั๊กจริง: ต้องล็อกอินใหม่ทุกครั้งที่ปิด-เปิดแอป ทั้งที่ไม่เคยกด logout เลย

**ไฟล์ที่แก้:** `lib/features/auth_face_login/presentation/face_login_screen.dart`, `lib/features/ambulance/presentation/ambulance_profile_screen.dart`

ผู้ใช้ทดสอบแล้วสังเกตว่าปิดแอปแล้วเปิดใหม่ต้องล็อกอินใหม่ทุกครั้ง (ทั้งที่ไม่เคยกด logout เลย) ตรวจสอบโค้ดพบสาเหตุจริง: `FaceLoginScreen.initState()` มีคำสั่ง `FaceAuthRepository.logout();` ที่ทำงาน**ทุกครั้ง**ที่หน้านี้ถูกเปิดขึ้นมา ไม่ว่าจะมาจากการปิด-เปิดแอปใหม่หรือกด logout เองก็ตาม — ทั้งที่ระบบ session (`FaceAuthRepository.getCurrentUser()`/`setCurrentUser()`) เก็บข้อมูลถาวรผ่าน SharedPreferences อยู่แล้วจริงๆ (รอดจากการปิดแอปได้ปกติ) แต่ถูกลบทิ้งเองทุกครั้งโดยไม่จำเป็น

**หลังแก้:**
1. ตัด `FaceAuthRepository.logout();` แบบไม่มีเงื่อนไขออก เปลี่ยนเป็นเช็ค session ที่บันทึกไว้จริงก่อน (`_checkExistingSession()`) — ถ้ามี user ที่ยังไม่เคย logout ค้างอยู่จริง จะพาเข้าหน้าหลักของ role นั้นทันทีโดยไม่ต้องล็อกอินซ้ำ ถ้าไม่มี (หรือเพิ่ง logout ไป) ถึงจะโชว์ฟอร์มล็อกอินตามปกติ ระหว่างเช็ค (เร็วมาก) โชว์ loading indicator กันฟอร์มล็อกอินกะพริบเห็นแวบเดียวก่อนเด้งออก
2. **พบบั๊กแฝงที่ถูกซ่อนไว้โดยพฤติกรรมเดิม**: ปุ่ม "ออกจากระบบ" ในหน้าโปรไฟล์ฝั่ง **Ambulance** ไม่เคยเรียก `FaceAuthRepository.logout()` เลยจริงๆ (แค่ `Navigator.push` ไปหน้าล็อกอินเฉยๆ) ที่ผ่านมาดู "เหมือนทำงานได้" เพราะ `FaceLoginScreen` บังคับ logout ทุกครั้งอยู่แล้วไม่ว่ากรณีใด — พอแก้ข้อ 1 แล้ว ปุ่มนี้จะพังทันที (เปิดแอปใหม่จะเด้งกลับเข้าบัญชีเดิมอัตโนมัติ ทั้งที่กด "ออกจากระบบ" ไปแล้ว) แก้โดยเพิ่ม `await FaceAuthRepository.logout();` เข้าไปให้ตรงกับที่ Driver/Agency ทำอยู่แล้ว

**พฤติกรรมหลังแก้:** ปิดแอปเฉยๆ (ไม่ logout) → เปิดใหม่ → เข้าหน้าหลักของ role เดิมทันที ไม่ต้องล็อกอินซ้ำ — กด "ออกจากระบบ" จริงๆ เท่านั้นถึงจะต้องล็อกอินใหม่ในครั้งถัดไป (ตรวจสอบแล้วว่า Driver/Agency/Ambulance/บัญชีทดสอบ admin_1/2/3 ทำงานสอดคล้องกันหมด)

**ยืนยันด้วย `flutter analyze` (0 errors) และ `flutter test` (27/27 ผ่าน)**

---

## 18. หน้าโหลดแอปแบบกำหนดเอง (Custom Loading Screen) — มือการ์ตูนวาดเอง (นิ้วกาง/งอ) + ทรานสิชันลากเข้าจากขวา

**ไฟล์ใหม่:** `lib/features/auth_face_login/presentation/app_loading_screen.dart`, `lib/core/utils/role_screen_resolver.dart`, `lib/core/utils/slide_from_right_route.dart`
**ไฟล์ที่แก้:** `lib/main.dart`, `lib/features/auth_face_login/presentation/face_login_screen.dart`

ผู้ใช้ส่งคลิปตัวอย่างมา (ไอคอนมือสีน้ำเงินการ์ตูนแทนวงกลมโหลดธรรมดา) ขอให้ทำหน้าโหลดแบบนี้ (เดิมเป็นหน้าขาวเปล่าล้วนตอนเช็ค session ตามหัวข้อ 17) พร้อมทรานสิชันลากเข้าจากขวาแบบหวือหวาตอนโหลดเสร็จ

**สิ่งที่ทำ:**
1. **แยกหน้าที่เช็ค session ออกมาเป็นหน้าใหม่ต่างหาก** — `AppLoadingScreen` เป็นหน้าแรกสุดของแอป (`main.dart`'s `home:`) รับผิดชอบเช็ค `FaceAuthRepository.getCurrentUser()` (ย้ายมาจาก `FaceLoginScreen` ที่เพิ่งเพิ่มไว้ในหัวข้อ 17) แล้วตัดสินใจว่าจะไปหน้าล็อกอินหรือหน้าหลักของ role ที่ resume มา — `FaceLoginScreen` กลับไปเป็นแค่ฟอร์มล็อกอินล้วนๆ ไม่ต้องรู้เรื่อง session-check อีกต่อไป (ถ้ามาถึงหน้านี้ได้แปลว่า `AppLoadingScreen` ยืนยันแล้วว่าไม่มี session ค้าง)
2. **มือการ์ตูนวาดเองด้วย `CustomPainter` แทนวงกลมโหลด** — ผ่านการปรับ 3 รอบตามคลิปตัวอย่างที่ผู้ใช้ส่งมาแก้ทีละจุด:
   - รอบที่ 1: ดูคลิปแรกผิด เข้าใจว่ามือหมุน 3 มิติ ทำเป็น `Transform`+`Matrix4.rotateY()` หมุนต่อเนื่อง — ผู้ใช้แก้ว่ามือไม่ได้หมุน อยู่นิ่งแล้วขยับไปมาเหมือนนับนิ้ว
   - รอบที่ 2: เปลี่ยนเป็นสลับ emoji "✋"/"✊" ผ่าน `AnimationController` บีบแนวตั้ง (`scaleY` ผ่าน `Matrix4.diagonal3Values`) ไปกลับต่อเนื่อง (300ms ต่อขา) — ผู้ใช้ส่งคลิปที่ 2 (เฟรมเรตสูงกว่า) มาให้ดูซ้ำ ชี้ว่ายังผิด: ไม่ต้องการ emoji เลย (ให้วาดมือขึ้นมาเอง) และการเคลื่อนไหวจริงคือ "นิ้วขยับ" ไม่ใช่ "กำแล้วแบ" (emoji ✊ ยุบเป็นก้อนตันหมดรูปนิ้ว ซึ่งไม่ตรงกับคลิป)
   - รอบที่ 3 (ปัจจุบัน): ถอดเฟรมคลิปที่ 2 ออกมาดูละเอียดทีละเฟรมอีกครั้ง พบว่าแม้ในเฟรมที่ "หุบ" ที่สุด นิ้วทั้ง 4 ก็ยังเป็นแท่งแคปซูลแยกชิ้นมองเห็นได้ ซ้อนทับกันแบบพัดหุบ ไม่เคยยุบเป็นก้อนกลมทึบ — เขียน `_HandPainter` (`CustomPainter`) วาดฝ่ามือ+นิ้วโป้ง+นิ้ว 4 นิ้วเป็นรูปแคปซูลโค้งมนเองทั้งหมด (สีน้ำเงิน `#3B5BFB` ขอบกรมท่า `#1B2560` ตามโทนสีคลิป) แล้วอนิเมตนิ้วทั้ง 4 กางออกเป็นพัด (มุม/ระยะห่าง/ความยาวมากสุด) ↔ งอเข้าซ้อนกันแน่น (มุมชิด/ระยะห่างน้อย/สั้นลง) พร้อมกันด้วย `AnimationController` เดิม (320ms ต่อขา, ปิงปองไปกลับ) แต่ใส่ดีเลย์เล็กน้อยต่อนิ้ว (`index * 0.07`) ให้ดูเป็นคลื่นแทนที่จะขยับพร้อมกันเป๊ะๆ ทื่อๆ — นิ้วโป้งอยู่นิ่งเกือบตลอด ขยับเอียงเบาๆ ตามจังหวะเดียวกัน พร้อมข้อความ "LOADING" ด้านล่าง — บังคับแสดงอย่างน้อย 1.1 วินาทีแม้ session จะเช็คเสร็จเร็วกว่านั้นมาก กันอนิเมชันกะพริบผ่านตาเร็วเกินไป
3. **ทรานสิชันลากเข้าจากขวา** (`slideFromRightRoute`): `PageRouteBuilder` แบบกำหนดเอง (`SlideTransition` จากขวาสุดจอ + fade เบาๆ, curve `easeOutCubic`) ใช้แทน `MaterialPageRoute` เริ่มต้นทั้งตอนออกจาก `AppLoadingScreen` ไปหน้าล็อกอิน/หน้าหลักของ role ที่ resume มา **และ**ตอนล็อกอิน/สมัครสำเร็จจริงจาก `FaceLoginScreen` ด้วย (`_navigateToRoleScreen` เดิมใช้ `MaterialPageRoute` ธรรมดา เปลี่ยนให้ใช้ทรานสิชันเดียวกันเพื่อความต่อเนื่องของสไตล์ทั้งแอป)
4. **`role_screen_resolver.dart`**: ดึงตรรกะ "role ไหนไปหน้าไหน" (`ambulance`→`AmbulanceMainScreen`, `agency`→`AgencyMainScreen`, อื่นๆ→`DriverMainScreen`) ออกมาเป็นฟังก์ชันกลาง ใช้ทั้งใน `AppLoadingScreen` และ `FaceLoginScreen` กันโค้ดตรรกะเดียวกันซ้ำกันคนละที่

**หมายเหตุ:** ไม่ได้ใช้ภาพ/asset จากคลิปต้นฉบับโดยตรง (ดึงจากวิดีโอที่บีบอัดมาจะได้คุณภาพต่ำ) แต่วาดรูปทรงมือขึ้นมาเองทั้งหมดด้วยโค้ด (`CustomPainter`) ให้ได้สัดส่วน/ท่าทางตรงกับที่สังเกตจากเฟรมคลิปจริง ไม่มีปัญหาลิขสิทธิ์และไม่ผูกกับไฟล์ภาพภายนอก

**ยืนยันด้วย `flutter analyze` (0 errors ใหม่, เหลือแค่ 6 info เดิมที่ไม่เกี่ยวข้อง) และ `flutter test` (27/27 ผ่าน)**

## 19. มาสคอตหน้าล็อกอิน/สมัครสมาชิก — ลองไฟล์ Rive จริงแล้วสุดท้ายกลับไปใช้เป็ดวาดเอง

**ไฟล์คงเหลือ:** `lib/features/auth_face_login/presentation/widgets/login_duck_mascot.dart`
**ไฟล์ที่แก้:** `lib/features/auth_face_login/presentation/face_login_screen.dart`
**ไฟล์ที่ลองใช้แล้วลบทิ้ง:** `assets/rive/login_teddy.riv`, `lib/features/auth_face_login/presentation/widgets/rive_login_mascot.dart`, dependency `rive` ใน `pubspec.yaml`

ผู้ใช้ส่งคลิปตัวอย่างมา (`login.MP4`) เป็นคลิปสอน Rive+Flutter — หมีการ์ตูนอยู่เหนือฟอร์ม email/password คอยดูตอนพิมพ์อีเมล แล้วยกอุ้งเท้าทั้งสองข้างขึ้นปิดตาสนิทตอนโฟกัสช่องรหัสผ่าน เส้นทางที่ลองมา:

1. **รอบแรก**: ทำเวอร์ชันเป็ดที่วาดเองด้วย `CustomPainter` (เพราะสร้างไฟล์ `.riv` เองไม่ได้ ต้องใช้ Rive Editor ซึ่งเป็นเครื่องมือ GUI)
2. **ผู้ใช้อยากได้ไฟล์ Rive จริงมากกว่า** — ค้นพบว่าหมีในคลิปต้นฉบับ ("RiveBear Login" โดย Ruksar) เป็นของขาย แต่มีไฟล์ฟรีลิขสิทธิ์ CC BY ที่คอนเซปต์ตรงกัน ("Animated Login Character" โดย JcToon บน Rive Community) ผู้ใช้ดาวน์โหลดมาเองแล้วส่งให้ (`2244-7248-animated-login-character.riv`)
3. **ตรวจสอบไฟล์จริงก่อนเขียนโค้ด** — รัน `strings` บนไฟล์ `.riv` (เป็นไบนารี) พบ state machine ชื่อ `"Login Machine"` มี input จริง 5 ตัว: `isChecking`/`numLook`/`isHandsUp`/`trigSuccess`/`trigFail` — และตรวจพบว่า `flutter pub add rive` เวอร์ชันล่าสุด (`0.14.x`) เปลี่ยนสถาปัตยกรรมทั้งหมดเป็นเอนจิน `rive_native` ใหม่ ไม่มี `RiveAnimation`/`StateMachineController`/`SMIBool` แบบเดิมที่ตรงกับไฟล์นี้ (สร้างด้วย Rive Editor รุ่นเก่า) จึง pin เป็น `rive: 0.13.20` แทน สร้าง `RiveLoginMascot` ผูก `isHandsUp` กับสถานะโฟกัสช่อง Password จริง
4. **ปัญหาที่เจอตอนใช้งานจริงบนเครื่อง** — ผู้ใช้รายงาน 2 จุด: (ก) มีกรอบ/พื้นหลังไม่สวยล้อมรอบตัวหมี ทั้งที่อยากได้แค่ตัวละครลอยๆ (ข) กดปุ่มดูรหัสผ่านแล้วมือไม่ขยับเลย ไม่ลืมตามาดูเหมือนในคลิป — ตรวจโค้ด renderer ของ `rive` package แล้วพบว่าไม่ได้วาดพื้นหลังทึบเพิ่มเองเลย (ไม่มี `drawRect`/fill สีในซอร์สส่วนนั้น) แปลว่ากรอบที่เห็นน่าจะเป็นรูปทรงที่ติดมากับไฟล์ `.riv` เอง (ไฟล์ที่ยืมมาจากคนอื่น อาจมีพื้นหลัง/กรอบที่ผู้ออกแบบวาดไว้ตอนพรีวิวบนเว็บ Rive ไม่ได้ลบก่อนแชร์) ซึ่งแก้ไม่ได้ในโค้ด ต้องเปิดไฟล์ด้วย Rive Editor เท่านั้น — ส่วนปัญหามือไม่ขยับแก้ได้จริง (`isHandsUp` เดิมผูกกับแค่ "โฟกัสช่อง" อย่างเดียว ไม่ได้ดูว่ารหัสกำลังซ่อนหรือโชว์อยู่ ทำให้ค้างเป็น "มือขึ้น" ตลอดไม่ว่าจะกดปุ่มตาหรือไม่ แก้เป็นดูทั้งสองเงื่อนไข: โฟกัส+ซ่อนอยู่ → ยกมือ, โฟกัส+โชว์แล้ว → เอามือลง)
5. **ผู้ใช้ตัดสินใจ**: แทนที่จะพยายาม crop/ซ่อนกรอบที่ติดมากับไฟล์คนอื่น (ไม่ชัวร์ว่าจะสวย) เลือกเลิกใช้ไฟล์ Rive นี้ กลับไปใช้เป็ด `CustomPainter` เดิมที่คุมรูปลักษณ์ได้ 100% แทน — ลบ `assets/rive/`, `rive_login_mascot.dart`, dependency `rive` ออกทั้งหมด คืนโค้ด `face_login_screen.dart` ให้ใช้ `LoginDuckMascot` เหมือนก่อนหน้า

**บทเรียนที่ได้**: ไฟล์ Rive ที่ยืมมาจาก community ฟรี แม้ concept จะตรงและ state machine input จะใช้งานได้จริง แต่เนื้อหาภาพ (รวมถึงพื้นหลัง/กรอบที่ผู้ออกแบบต้นฉบับวาดไว้) แก้ไขไม่ได้เลยถ้าไม่มี Rive Editor — ต่างจากวาดเองด้วย `CustomPainter` ที่ควบคุมได้ทุกพิกเซล ไม่มีความเสี่ยงแบบนี้

**ยืนยันด้วย `flutter analyze` (0 errors ใหม่, เหลือแค่ 6 info เดิมที่ไม่เกี่ยวข้อง) และ `flutter test` (27/27 ผ่าน)**

## 20. แก้ 2 จุดหลัง build จริง — คลื่น Onboarding มองไม่เห็น + เป็ดนิ่งเกินไป

**ไฟล์ที่แก้:** `lib/features/onboarding/presentation/onboarding_screen.dart`, `lib/features/auth_face_login/presentation/widgets/login_duck_mascot.dart`

ผู้ใช้ build ลงเครื่องจริงแล้วรายงาน 2 จุด:

1. **Onboarding ไม่เห็นคลื่น liquid swipe ตอนลากเปลี่ยนหน้า** สีเปลี่ยนแบบกลืนกับหน้าเดิมจนไม่รู้ว่ากำลังเปลี่ยนหน้า — ต้นเหตุจริงคือทั้ง 3 หน้าย่อยของแต่ละ role ใช้สีพื้นหลัง**เดียวกัน**มาตั้งแต่ต้น (ตั้งใจให้ illustration/สีเหมือนกันตลอด 3 หน้า ต่างแค่หัวข้อ/คำอธิบาย) — คลื่น liquid reveal ของ `liquid_swipe` ทำงานถูกต้องอยู่แล้ว แต่มองไม่เห็นเพราะไม่มีสีให้ morph ระหว่างหน้าเก่ากับหน้าใหม่เลย (ไม่ใช่เพราะขาด "กรอบ" ตามที่ผู้ใช้เดา) แก้โดยย้าย `color` จากระดับ role (`_RoleOnboardingData`) ลงมาเป็นของแต่ละหน้า (`_PageData`) แล้วให้ทั้ง 3 หน้าในแต่ละ role ไล่โทนสีต่างกันจริง (เช่น driver: น้ำเงิน→ม่วง→ฟ้าอมเขียว) ยังคงอยู่ในกลุ่มโทนเดียวกันของ role นั้นเพื่อความกลมกลืน แต่ต่างพอให้เห็นคลื่นชัดเจนตอนลาก — ตรวจสอบด้วย widget test แคปภาพจริงยืนยันว่าตอนนี้ 2 หน้าที่ต่อกันมีสีต่างกันจริงในโครงสร้าง widget tree (ที่ `liquid_swipe` เรนเดอร์ไว้พร้อมกันสำหรับเอฟเฟกต์คลื่น)
2. **เป็ดนิ่งเกินไปตอนไม่ได้โฟกัสช่องรหัสผ่าน + ท่าทางขยับดูไม่ลื่น** — เพิ่ม `AnimationController` ตัวที่สอง (`_idleController`) ที่หมุนวนตลอดเวลา (`repeat(reverse: true)`, 1.7 วินาทีต่อรอบครึ่ง) ทำให้ตัวเป็ดลอยขึ้นลงเบาๆ (~±3.5px) พร้อมเอียงตัวเล็กน้อย (~±1.4°) ตลอดเวลาแม้ไม่มีการโต้ตอบใดๆ ให้ดูมีชีวิตไม่นิ่งสนิท ส่วนจังหวะยกปีก/ลดปีกตอนโฟกัสช่องรหัสผ่าน เปลี่ยน curve จาก `easeOutBack` (มีจังหวะเด้งเกินตัว) เป็น `easeInOutCubic` (นุ่มนวล ไม่เด้ง) ยืดเวลาขึ้นเล็กน้อย (380ms → 460ms) และให้ปีกซ้าย/ขวาเริ่ม-จบไม่พร้อมกันเป๊ะๆ (หน่วงกันเล็กน้อยผ่าน `_wingProgress()`) ให้ดูเป็นธรรมชาติแทนกลไกขยับพร้อมกันทื่อๆ — ระหว่างตรวจพบเพิ่มว่าลำตัวเป็ดเดิมสูงเกิน canvas ที่ประกาศไว้ (132×132) จริงๆ ประมาณ 7% ทำให้ส่วนล่างของลำตัวโดนตัดขาดหายไป (เห็นได้จากภาพแคปที่ไม่มีลำตัวเลย) แก้โดยขยาย canvas เป็น 132×148 และรวมหน่วยอ้างอิงสัดส่วนทั้งหมดให้ยึดความกว้าง (`w`) เดียวเท่านั้นแทนที่จะปนกับความสูง (`h`) ป้องกันปัญหาสัดส่วนเพี้ยน/ตัดขอบแบบนี้อีกในอนาคต

**ยืนยันด้วย `flutter analyze` (0 errors ใหม่, เหลือแค่ 6 info เดิมที่ไม่เกี่ยวข้อง), `flutter test` (27/27 ผ่าน) และ widget test แคปภาพจริงยืนยันทั้งสีที่ต่างกันจริงและลำตัวเป็ดที่ไม่โดนตัดขอบแล้ว**

## 21. เลิกใช้มาสคอตเป็ด + Onboarding ไม่โชว์ซ้ำหลัง logout + บั๊กเคส SOS รั่วข้ามบัญชี

**ไฟล์ที่แก้:** `lib/features/auth_face_login/presentation/face_login_screen.dart`, `lib/core/services/onboarding_service.dart`, `lib/features/auth_face_login/data/services/face_auth_repository.dart`, `lib/features/driver_radar/presentation/driver_home_screen.dart`, `lib/features/driver_radar/presentation/incident_list_screen.dart`
**ไฟล์ที่ลบ:** `lib/features/auth_face_login/presentation/widgets/login_duck_mascot.dart`

ผู้ใช้แจ้ง 3 เรื่องหลัง build ทดสอบจริง:

1. **เลิกใช้มาสคอตเป็ดในหน้าล็อกอินไปเลย** (เปลี่ยนใจ ไม่อยากได้แล้ว) — ลบ `LoginDuckMascot`/`login_duck_mascot.dart` ออกทั้งหมด รวมถึง scaffolding ที่มีไว้รองรับมันโดยเฉพาะ (FocusNode 3 ตัวของ email/password/re-password, getter `_isPasswordFieldActive`/`_isActivePasswordRevealed`, listener `_onMascotRelevantFocusChanged`, พารามิเตอร์ `focusNode` ใน `_buildTextField()`) คืนหน้าล็อกอินกลับไปเป็นฟอร์มเดิมล้วนๆ ก่อนที่จะเริ่มทำฟีเจอร์นี้
2. **Onboarding ไม่โชว์ซ้ำหลัง logout แล้ว login ใหม่** — ตรงข้ามกับที่ตั้งใจไว้ตอนออกแบบ (ดูหัวข้อ 16: ควร "logout แล้ว login ใหม่ = โชว์ Onboarding อีกครั้ง แต่แค่ปิดแอปเฉยๆ ไม่ logout = ไม่โชว์ซ้ำ") ต้นเหตุคือ `OnboardingService` เก็บสถานะ "เคยดูแล้ว" ถาวรใน SharedPreferences โดยที่ `FaceAuthRepository.logout()` ไม่เคยล้างค่านี้เลย เพิ่ม `OnboardingService.clearOnboardingSeen(roleKey)` แล้วเรียกจาก `logout()` (ดึง role ของผู้ใช้ปัจจุบันมาก่อนลบ current-user key) ตรวจสอบแล้วว่าปุ่ม "ออกจากระบบ" ทั้ง 3 role + `user_type_screen.dart` เรียก `FaceAuthRepository.logout()` ตรงกันหมด ทำให้แก้จุดเดียวครอบคลุมทุกทาง
3. **บั๊กเคส SOS รั่วข้ามบัญชี (ร้ายแรง)**: สลับบัญชี driver บนเครื่องเดียวกัน (เช่น logout จาก `admin_1` แล้ว login เข้าบัญชีที่สร้างเอง) ยังเห็นเคส SOS ของบัญชีก่อนหน้าค้างอยู่ ให้ agent สืบสาเหตุก่อนแก้ พบ 2 จุดที่ไม่กรอง `reporterEmail` เลย:
   - `driver_home_screen.dart` (Active SOS Tracking Banner ป้าย "🚨 เหตุฉุกเฉินที่คุณแจ้ง"): หยิบเคส active (ไม่ resolved/cancelled) ตัวแรกสุดของทั้งระบบมาโชว์ตรงๆ ไม่เช็คว่าเป็นของผู้ใช้ปัจจุบันจริงไหม — เพิ่ม `_currentUserEmail` (โหลดจาก `FaceAuthRepository.getCurrentUser()` ใน `initState`) แล้วกรอง `i.reporterEmail == _currentUserEmail` เพิ่มในเงื่อนไข `where()`
   - `incident_list_screen.dart` แท็บ "รายงานของฉัน (SOS)": โค้ดเดิม `if (_selectedTab == 1) { return true; }` คืนค่า `true` ให้ทุกเคสที่ไม่ถูกยกเลิกจากทุกคน ทั้งที่แท็บถัดไป (พื้นที่ใกล้เคียง) กรองด้วย `_currentUserEmail` อยู่แล้ว — แก้เป็น `return item.reporterEmail == _currentUserEmail;` ให้กรองเหมือนกัน

**ยืนยันด้วย `flutter analyze` (0 errors ใหม่, เหลือแค่ 6 info เดิมที่ไม่เกี่ยวข้อง) และ `flutter test` (27/27 ผ่าน)**

## 22. Onboarding คลื่นดูกระตุก/ไม่ลื่น — เพิ่ม RepaintBoundary กันเงาวาดซ้ำทุกเฟรม

**ไฟล์ที่แก้:** `lib/features/onboarding/presentation/onboarding_screen.dart`

ผู้ใช้รายงานว่าคลื่น liquid swipe ตอนลากเปลี่ยนหน้ารู้สึกกระตุก ไม่ลื่นไหลตามนิ้ว ไม่สมูธ — วงกลมภาพประกอบในแต่ละหน้ามี `BoxShadow` (เบลอ) อยู่ 2 จุด ซึ่งเป็นการวาดที่กินแรงประมวลผลกว่าปกติ ตอนลากคลื่น `liquid_swipe` จะหมุน/บีบ/clip ทั้งหน้ารวมถึงส่วนนี้ทุกเฟรม ถ้าไม่กันไว้ Flutter จะ rasterize เงาใหม่ทุกเฟรมที่ลาก ทำให้เฟรมเรตตกได้ — ห่อวงกลมภาพประกอบทั้งชุดด้วย `RepaintBoundary` ให้ cache เป็นภาพนิ่งไว้ครั้งเดียว แล้วแค่ขยับ/clip ภาพนั้นระหว่างลาก ไม่ต้องวาดเงาใหม่ทุกเฟรม

**สิ่งสำคัญที่ต้องแจ้งผู้ใช้ด้วย**: build ที่ทดสอบทั้งหมดในเซสชันนี้รันผ่านปุ่ม Run ปกติของ Xcode ซึ่งเป็น **Debug build** โดยดีฟอลต์ — Flutter ในโหมด Debug ทำอนิเมชันแบบ custom clip/transform (เช่นคลื่น liquid swipe) ได้ไม่ลื่นเท่า **Release build** เลยโดยธรรมชาติ (ไม่เกี่ยวกับโค้ดของแอปเองเลย) เป็นไปได้สูงที่ความกระตุกส่วนใหญ่ที่เจอมาจากตรงนี้ ไม่ใช่บั๊ก — แนะนำให้ทดสอบด้วย Release build เทียบดูก่อนตัดสินว่ายังกระตุกอยู่ไหม

**ยืนยันด้วย `flutter analyze` (0 errors ใหม่) และ `flutter test` (27/27 ผ่าน)**

## 23. Onboarding คลื่นดูแข็ง/เป็นเส้นตรง ไม่ใช่บั๊กเฟรมตก แต่เป็น WaveType ผิด

**ไฟล์ที่แก้:** `lib/features/onboarding/presentation/onboarding_screen.dart`

ผู้ใช้ยืนยันชัดเจนว่าปัญหาคลื่น "แข็งๆ" **ไม่เกี่ยวกับการกระตุก/เฟรมตกของเครื่องเลย** (แก้ต่างหากจากหัวข้อ 22) แต่เป็นเรื่องรูปทรงคลื่นเองที่ดูไม่ลื่นไหลเหมือนของเหลวจริงๆ — ตรวจสอบโดยจำลองการลากนิ้วจริงผ่าน widget test (`tester.startGesture`+`moveBy`) แล้วแคปภาพระหว่างลากจริง (ไม่ใช่เดา) พบว่า:

1. **อ่านซอร์สโค้ด `liquid_swipe` package โดยตรง** (`WaveLayer.dart`) พบว่า `WaveType.liquidReveal` ที่ใช้อยู่ **ไม่ได้ทำให้คลื่นตามตำแหน่งแนวตั้งของนิ้วที่ลากเลย** — จุดยึดแนวตั้งของคลื่น (`verticalReveal`) มาจากค่าคงที่ `positionSlideIcon` (ดีฟอลต์ 0.8 = ยึดที่ 80% ของความสูงจอเสมอ) ไม่ใช่ตำแหน่งนิ้วสัมผัสจริง แล้ว`waveVertRadius` จะพุ่งไปแตะ 90% ของความสูงจอทันทีที่ลากผ่านแค่ 40% ของระยะทาง ในขณะที่ `waveHorRadius` (แนวนอน) เล็กกว่ามาก ทำให้เกิดวงรีที่ผอมสุดขั้ว (eccentric) จนส่วนโค้งที่มองเห็นในจอแบนราบจนดูเหมือนเส้นตรงทแยงมุม แทนที่จะเป็นคลื่นโค้งมนแบบของเหลว — ยืนยันด้วยภาพแคปจริงที่ตำแหน่งลาก 160px/240px เห็นขอบเป็นเส้นทแยงเกือบตรงชัดเจน
2. **ลอง `WaveType.circularReveal` แทน** (อีกตัวเลือกเดียวที่ package นี้มีให้) — ใช้วงกลมขยายจริงจากไอคอนลากแทนสมการวงรีผอมของ `liquidReveal` — แคปภาพเปรียบเทียบที่ตำแหน่งลากเดียวกันทุกจุด เห็นความต่างชัดเจนมาก: ขอบคลื่นเป็นส่วนโค้งวงกลมจริงๆ นูนเข้าไปในหน้าถัดไปแบบเห็นความโค้งชัดตลอดการลาก ไม่ใช่เส้นตรงเลย — เปลี่ยน `waveType: WaveType.liquidReveal` เป็น `WaveType.circularReveal` ในโค้ด

**ยืนยันด้วย `flutter analyze` (0 errors ใหม่) `flutter test` (27/27 ผ่าน) และ widget test จำลองลากนิ้วจริงเปรียบเทียบภาพก่อน/หลังยืนยันว่าโค้งขึ้นจริง**

## 24. ขัดเกลาคลื่น Onboarding เพิ่มอีก 3 จุดตามที่ผู้ใช้ขอ

**ไฟล์ที่แก้:** `lib/features/onboarding/presentation/onboarding_screen.dart`

ต่อจากหัวข้อ 23 ผู้ใช้ขอให้ปรับเพิ่มอีก 3 จุดที่แนะนำไว้ (ทั้งหมดตรวจด้วย widget test จำลองลากนิ้วจริงแคปภาพเปรียบเทียบก่อน/หลังเหมือนหัวข้อ 23):

1. **`fullTransitionValue`**: ลดจาก `400` เป็น `280` — ต้องลากนิ้วน้อยลงกว่าเดิมถึงจะเปลี่ยนหน้าสำเร็จ รู้สึกไว/เฟี๊ยวขึ้นตามที่ขอ
2. **`positionSlideIcon`**: เพิ่มพารามิเตอร์นี้เข้าไป (เดิมไม่ได้ตั้งเลย ใช้ค่าดีฟอลต์ของ package คือ `0.8` ซึ่งยึดจุดขยายวงกลมไว้ต่ำเกินไปที่ 80% ของความสูงจอ) ปรับเป็น `0.5` ให้จุดขยายอยู่กึ่งกลางจอ บาลานซ์สายตากว่า
3. **`slideIconWidget`**: เดิมเป็นแค่ `Icon` ลูกศรสีเทาเปล่าๆ ไม่มีพื้นหลัง เปลี่ยนเป็นวงกลมพื้นขาว+เงาเบาๆ+ไอคอนลูกศรสีตามธีมของหน้าปัจจุบัน (`pages[_currentPage].color`) ให้ดูตั้งใจออกแบบและเข้ากับสีพื้นหลังทุกหน้าที่ต่างกัน (ตรวจสอบด้วยภาพแคปจริงแล้วว่าสีไอคอนเปลี่ยนตามหน้าปัจจุบันถูกต้อง)

**ยืนยันด้วย `flutter analyze` (0 errors ใหม่, เหลือแค่ 6 info เดิมที่ไม่เกี่ยวข้อง) และ `flutter test` (27/27 ผ่าน)**

## 25. Onboarding: haptic feedback + ปุ่มสุดท้าย fade ตามจังหวะลากจริง (เจอ+แก้บั๊ก setState ระหว่าง build ไปด้วย)

**ไฟล์ที่แก้:** `lib/features/onboarding/presentation/onboarding_screen.dart`

ผู้ใช้ขอเพิ่มอีก 2 จุดจากที่แนะนำไว้ (หัวข้อ 24): haptic feedback ตอนเปลี่ยนหน้า และให้ปุ่ม "เริ่มต้นใช้งาน" fade เข้า/ออกตามจังหวะการลากนิ้วจริงแทนโผล่ตัดทันทีตอนเปลี่ยนหน้าเสร็จ

1. **Haptic feedback**: เพิ่ม `HapticFeedback.lightImpact()` ใน `onPageChangeCallback` ตอนเปลี่ยนหน้าสำเร็จ
2. **ปุ่ม "เริ่มต้นใช้งาน" + จุด pagination ขยับตามจังหวะลากจริง**: `liquid_swipe` มี `slidePercentCallback(horizontal, vertical)` รายงานความคืบหน้าการลากสดๆ (ไม่ใช่แค่ตอนเปลี่ยนหน้าเสร็จแบบ `onPageChangeCallback`) — เพิ่ม state `_lastPageProximity` (0..1) คำนวณจาก callback นี้ (ตอนอยู่หน้าสุดท้ายแล้วลากออก = `1-h`, ตอนอยู่หน้าก่อนสุดท้ายแล้วลากเข้า = `h`, หน้าอื่นๆ = `0`) แล้วเปลี่ยนปุ่มจาก `AnimatedOpacity`/`AnimatedScale` ที่ผูกกับ `isLastPage` (bool, กระโดดตัดทันที) มาใช้ `Opacity`/`Transform.scale` ที่ผูกกับ `_lastPageProximity` ตรงๆ (ค่าที่ไหลลื่นอยู่แล้วจากการลากจริง ไม่ต้องซ้อน animation ทับอีกชั้น) จุด pagination ก็ขยับตำแหน่ง `bottom` ตามค่าเดียวกันให้ไปด้วยกันลื่นๆ ไม่ใช่แค่ปุ่มอย่างเดียว
3. **บั๊กที่เจอระหว่างตรวจด้วย widget test จำลองลากนิ้วจริง (ไม่ใช่แค่ทฤษฎี)**: เรียก `setState()` ตรงๆ ใน `slidePercentCallback`/`onPageChangeCallback` ทำให้แอป **crash จริง** ด้วย assertion "setState() or markNeedsBuild() called during build" เพราะ `liquid_swipe` เรียก callback ทั้งสองจากข้างใน build cycle ของ `Consumer<LiquidProvider>` ของมันเองได้ — แก้ด้วยการเลื่อน `setState` ไปทำหลังเฟรมปัจจุบันจบเสมอผ่าน `WidgetsBinding.instance.addPostFrameCallback` (ห่อเป็นเมธอด `_scheduleSetState()` ใช้ร่วมกันทั้ง 2 callback) ดีเลย์แค่ ~1 เฟรมมองไม่ทันสายตา แต่ปลอดภัยจาก crash แน่นอน

**ยืนยันด้วย `flutter analyze` (0 errors ใหม่, เหลือแค่ 6 info เดิมที่ไม่เกี่ยวข้อง), `flutter test` (27/27 ผ่าน) และ widget test จำลองลากนิ้วจริงข้ามหน้า ยืนยันทั้งว่าไม่ crash แล้วและปุ่ม/จุด fade เข้าแบบต่อเนื่องตามจังหวะลากจริงก่อนเปลี่ยนหน้าเสร็จด้วยซ้ำ**

## 26. วงจรชีวิตเคส + ฝั่ง Agency + ฝั่ง Ambulance — แก้ 7 กลุ่มตามที่ผู้ใช้ทดสอบจริงแล้วแจ้ง

ผู้ใช้ทดสอบแอปจริงแล้วแจ้งปัญหา/ขอฟีเจอร์เพิ่มพร้อมกันหลายจุด ครอบคลุมทั้ง 3 role — ใช้ Explore agent 3 ตัวคู่ขนานสืบสาเหตุแต่ละจุดก่อน (ยืนยันด้วยการอ่านโค้ดจริงเองอีกชั้นในจุดที่ซับซ้อน) แล้ววางแผนเป็น 7 กลุ่มก่อนลงมือแก้ (ผ่าน Plan Mode ให้ผู้ใช้อนุมัติก่อน)

**ไฟล์ที่แก้:** `lib/features/driver_radar/presentation/incident_list_screen.dart`, `lib/features/ambulance/presentation/ambulance_incident_list_screen.dart`, `lib/features/ambulance/presentation/ambulance_home_screen.dart`, `lib/features/ambulance/presentation/ambulance_incident_detail_screen.dart`, `lib/features/agency/presentation/agency_incident_list_screen.dart`, `lib/features/agency/presentation/agency_home_screen.dart`, `lib/features/agency/presentation/agency_incident_detail_screen.dart`, `lib/core/services/incident_service.dart`, `lib/core/models/incident_report.dart`, `test/widget_test.dart`
**ไฟล์ใหม่:** `lib/core/widgets/status_confirm_dialog.dart`

1. **ซ่อนเคส resolved ออกจากหน้าจอ active** (เก็บใน Firestore ตามเดิมสำหรับอนาคต — `delete: if false` บล็อกการลบไว้อยู่แล้วโดยไม่ต้องแก้ rule เพิ่ม): เพิ่มเงื่อนไข `status != 'resolved'` คู่กับ `!= 'cancelled'` ที่มีอยู่แล้วใน 3 จุดที่ยังกรองไม่ครบ — `incident_list_screen.dart` (driver), `ambulance_incident_list_screen.dart`, `agency_incident_list_screen.dart`
2. **บังคับรถพยาบาล 1 คัน = 1 เคส active**: เพิ่ม `IncidentService.getBusyAmbulanceIds()` แล้วเช็คทั้ง 2 เส้นทางที่เคยไม่มี guard เลย — agency auto-dispatch (`agency_incident_detail_screen.dart:_handleDispatchCase`) กรองรถที่ไม่ว่างออกก่อนหาคันใกล้สุด, ambulance self-accept (`ambulance_incident_list_screen.dart`) เช็คก่อนให้กดรับเคสใหม่ถ้ามีเคสค้างอยู่
3. **ลบฟีเจอร์สัญญาณชีพ/tele-report ทั้งหมด**: ต้นเหตุจริงคือ `callSessionActive` ไม่เคยถูกรีเซ็ตเป็น false เลย ทำให้การ์ดค้างจอถาวรฝั่ง agency โดยไม่มีปุ่มปิด — ผู้ใช้เลือกตัดทิ้งทั้งฟีเจอร์แทนการแก้บั๊ก ลบฟิลด์ออกจาก `IncidentReport` (`vitalSigns`/`patientCondition`/`medicalNotes`/`callSessionActive`), ลบ `submitMedicalTeleReport()`, ลบ dialog+ปุ่มฝั่งรถพยาบาล, ลบการ์ดแสดงผลฝั่ง agency ทั้งในหน้าหลักและหน้ารายละเอียด — อัปเดต test ที่อ้างฟิลด์เหล่านี้ใน `test/widget_test.dart` ให้ตรงด้วย
4. **Agency: ปุ่มยืนยันเตียง ER ไม่มี feedback + แบนเนอร์เคสใหม่บังหน้าจอ**: เพิ่ม SnackBar ยืนยันหลังกด (`agency_incident_list_screen.dart`) ให้ตรงสไตล์ปุ่มอื่นที่ทำถูกอยู่แล้ว; แบนเนอร์เคสใหม่ (`agency_home_screen.dart`) เพิ่มปุ่มปิด (X) + เก็บ `_dismissedBannerIds` (ปิดแล้วไม่โผล่ซ้ำ แต่ยังจัดการจากรายการได้ปกติ ไม่ได้ถูกบล็อก) และกัน overflow ข้อความยาวด้วย `maxLines`
5. **Ambulance: ป้องกันกดปุ่มอัปเดตสถานะพลาดบนหน้าหลัก**: ปุ่มด่วนใน `_buildAmbulanceStatusCard` มีอยู่แล้วแต่ไม่มีการยืนยันเลย (ตรงข้ามกับที่คิดไว้ตอนแรก) — สกัด dialog ยืนยัน+คูลดาวน์ 3 วิที่มีอยู่แล้วในหน้ารายละเอียดออกมาเป็น `showStatusConfirmDialog()` ใช้ร่วมกัน ลดโค้ดซ้ำและปิดช่องโหว่พร้อมกัน
6. **Ambulance: ปักเคสของตัวเองไว้บนสุด + ไฮไลต์**: `ambulance_incident_list_screen.dart` แยกเคสที่ `assignedAmbulanceId` ตรงกับหน่วยตัวเองไว้กลุ่มแรกเสมอ (ไม่สนลำดับ `createdAt`) พร้อมขอบสีน้ำเงินเข้ม+ป้าย "เคสของคุณ • กำลังดำเนินการ" แยกจากกรอบเขียว "accepted" ทั่วไปที่อาจเป็นเคสของหน่วยอื่น
7. **Ambulance: แจ้งเตือนชัดเจนตอนได้รับมอบหมายเคสใหม่**: เดิมแค่เปลี่ยนสี badge เงียบๆ เพิ่ม `HapticFeedback.heavyImpact()` + แบนเนอร์เด่นชัด (ไล่เฉดแดง ขอบขาว บอกประเภทเหตุ+ที่อยู่) เลื่อนลงมาจากบนสุดจอ auto-dismiss เอง 6 วิ

**ยืนยันด้วย `flutter analyze` (0 errors ใหม่, เหลือแค่ 6 info เดิมที่ไม่เกี่ยวข้อง) และ `flutter test` (27/27 ผ่าน) หลังแก้ครบทั้ง 7 กลุ่ม — จุดที่ 2 (บังคับ 1 คัน 1 เคส) ต้องทดสอบบนเครื่องจริงกับรถพยาบาลหลายคันออนไลน์พร้อมกันถึงจะเห็นผลชัดเจน**

## 27. Agency: บั๊กเคส resolved ค้างจอ + เพิ่มปุ่มลบเคสออกจากหน้าจอเอง / Onboarding: กลับไปใช้ liquidReveal ตัวจริง

**ไฟล์ที่แก้:** `lib/features/agency/presentation/agency_incident_list_screen.dart`, `lib/core/services/agency_storage_service.dart`, `lib/features/onboarding/presentation/onboarding_screen.dart`

1. **บั๊กจริง: เคสที่ resolved แล้วยังค้างอยู่ในหน้า "เคสที่กำลังมุ่งหน้ามา" ของ agency** — ต้นเหตุคือ `agency_incident_list_screen.dart` กรองแค่ `status != 'cancelled'` จุดเดียว ไม่เคยกรอง `resolved` เลย (ต่างจาก 3 จุดที่แก้ไปแล้วในหัวข้อ 26 ข้อ 1 ซึ่งไม่ครอบคลุมไฟล์นี้ในบรรทัดที่ถูกจุด) ทำให้เคสที่ "ทุกอย่างติ๊กถูกทำจบแล้ว" ยังไม่หายไปจากจอ — เพิ่มกรอง `!= 'resolved'` เข้าไปด้วย
2. **เพิ่มปุ่มลบเคสออกจากหน้าจอเอง (ไม่แตะข้อมูลใน database)**: ผู้ใช้ขอให้มีทางลบเคสออกจากมุมมอง agency ได้เองแม้เคสจะยังไม่ resolved (เผื่อกรณีอยากเคลียร์จอ) โดยข้อมูลต้องเก็บไว้ครบสำหรับ heatmap/เว็บดูย้อนหลังในอนาคต — เพิ่ม `AgencyStorageService.loadDismissedIncidentIds()`/`setDismissedIncidentIds()` (เก็บแค่ id ใน SharedPreferences เครื่องนั้นๆ ไม่ยุ่งกับ Firestore เลย) และปุ่ม "×" จางๆ มุมขวาบนของการ์ดแต่ละใบ กดแล้วซ่อนทันที+โชว์ SnackBar พร้อมปุ่ม "เลิกทำ"
3. **Onboarding: คลื่นยังไม่เหมือนวิดีโออ้างอิงเลย — สาเหตุคือแก้ผิดทางไปตั้งแต่หัวข้อ 23** — ผู้ใช้แท็กวิดีโอเดิมมาเทียบอีกครั้ง ครั้งนี้ตัดเฟรมจากวิดีโอออกมาดูจริง (`ffmpeg` ตัดเฟรมช่วงที่มีการลากเปลี่ยนหน้า) แล้วเทียบกับโค้ด `liquid_swipe` เห็นชัดว่ารูปทรงคลื่นในวิดีโอเป็นเส้นโค้งแบบ S (cubic bezier หลายจุด โป่ง-ยุบสลับกัน) ไม่ใช่วงกลมล้วนแบบที่ `WaveType.circularReveal` วาด — ตอนหัวข้อ 23 สรุปว่า `liquidReveal` "แข็ง/เป็นวงรีเบี้ยว" นั้นวินิจฉัยผิด สาเหตุจริงที่แข็งตอนนั้นคือสีพื้นหลังซ้ำกันทุกหน้า (แก้แยกไปแล้วในหัวข้อ 20) ไม่เกี่ยวกับ wave type เลย — กลับไปใช้ `WaveType.liquidReveal` และคืนค่า `positionSlideIcon` เป็นดีฟอลต์ของ package (0.8 แทน 0.5 ที่เคยลดไว้ตอนใช้ circularReveal) เพราะสูตรเส้นโค้งของ liquidReveal ถูกปรับแต่งมาคู่กับค่านี้ ยืนยันด้วย widget test จำลองลากจริง 2 แบบ (ลากจากค่อนล่างจอ และลากจากใกล้ขอบบนจอ) แคปภาพเทียบกัน พบว่าจุดหักโค้งของคลื่นขยับตามตำแหน่งแนวตั้งที่ลากจริง (ลากใกล้ขอบบนจะเห็นแค่เสี้ยวของเส้นโค้งเพราะช่วงคลื่นทั้งหมดสูงถึง ~90% ของจอ ส่วนลากกลางๆ/ค่อนล่างจะเห็นเส้นโค้ง S เต็มรูปแบบ — เป็นพฤติกรรมที่ถูกต้องตามการออกแบบของ package ไม่ใช่บั๊ก)
4. **Onboarding: เอาไอคอนลูกศรในวงกลมออก** — ผู้ใช้ขอให้เอาปุ่มวงกลม+ลูกศรที่ดูเป็นปุ่มกดออก เปลี่ยนเป็นสัญลักษณ์ ">>>" (ไอคอน chevron 3 ตัวซ้อนกันแบบจางๆ opacity 0.55 ไม่มีพื้นหลัง) บอกใบ้ทิศทางที่ควรลากแทน

**ยืนยันด้วย widget test จำลองลากนิ้วจริงบน `OnboardingScreen` (แคปภาพ `RepaintBoundary` ระหว่างลากหลายจุด ต้องห่อการแคปด้วย `tester.runAsync()` ไม่งั้น `toImage()`/เขียนไฟล์จะค้างจนเทสต์ timeout — จุดนี้พลาดไปรอบแรกแล้วแก้ทัน), `flutter analyze` (0 errors ใหม่) และ `flutter test` (27/27 ผ่าน)**

## 28. Onboarding: เพิ่มระลอกคลื่นน้ำจางๆ ที่ยังเคลื่อนไหวต่อเนื่องแม้นิ้วหยุดนิ่ง (ไม่ใช่แค่คลื่นหลักที่ยึดตำแหน่งนิ้วเฉยๆ)

ผู้ใช้ต้องการให้การลากรู้สึกเหมือนน้ำจริงมากขึ้นไปอีก: "ถ้าหยุดลากมันก็ยังมีคลื่นน้ำจางๆ เคลื่อนที่อยู่ในทิศทางนั้น แต่คลื่นน้ำใหญ่มันจะกดที่นิ้วที่กดนิ่ง" — คือคลื่นหลัก (wave การเปลี่ยนหน้าของ `liquid_swipe`) ให้ยึดตำแหน่งนิ้วตามเดิมทุกประการ แต่ต้องมีคลื่นเล็กๆ ที่ "มีชีวิต" เคลื่อนไหวเองต่อเนื่องด้วยเวลาจริง ไม่ใช่หยุดนิ่งสนิททันทีที่นิ้วหยุดขยับ — สิ่งนี้ `liquid_swipe` ไม่มีให้ในตัว (รูปทรง wave ของมันเป็นฟังก์ชันของ drag percent + ตำแหน่งนิ้วล้วนๆ ไม่มีอะไรขับเคลื่อนด้วยเวลาเลย หยุดขยับนิ้วปุ๊บสูตรก็หยุดนิ่งปุ๊บ) จึงต้องเพิ่มชั้นตกแต่งเองแยกต่างหาก

**ไฟล์ที่แก้:** `lib/features/onboarding/presentation/onboarding_screen.dart`

- เพิ่ม `Listener` (behavior: translucent) ครอบ `LiquidSwipe` ทั้งก้อน ดักจับตำแหน่งนิ้วดิบจริงเอง (`onPointerDown/Move/Up/Cancel`) เก็บใน `ValueNotifier<Offset?>` — ไม่ใช้ `setState` เพราะเรียกถี่มากตอนลาก ใช้ `ValueNotifier` + `AnimatedBuilder` แทนเพื่อ repaint เฉพาะจุดนี้ ไม่รีบิลด์ทั้งจอ (`Listener` ไม่แย่ง gesture arena กับ `GestureDetector` ภายในของ `liquid_swipe` เอง อยู่ร่วมกันได้ปกติ)
- เพิ่ม `AnimationController` วนซ้ำต่อเนื่อง (`repeat()`) เริ่มตอนนิ้วแตะจอ (`onPointerDown`) หยุดตอนนิ้วยก (`onPointerUp`/`onPointerCancel`) — ตราบใดที่นิ้วยังแตะค้างอยู่ (ไม่ว่าจะขยับหรือนิ่ง) ตัวนี้หมุนต่อเนื่องตลอด
- วาดระลอกคลื่น 3 วงซ้อนกัน (`_RippleWavePainter`) ที่ตำแหน่งนิ้วปัจจุบัน แต่ละวงมีเฟสต่างกัน (offset 1/3 รอบ) ขยายรัศมี+จางความทึบไปพร้อมกันตามเวลา ขอบวงใส่ noise แบบ sine (`sin(angle*5 + t*2π)`) แทนวงกลมเรียบเป๊ะ ให้ดูเป็นผิวน้ำมากกว่ารูปทรงเรขาคณิต ห่อด้วย `IgnorePointer` กันไม่ให้ไปบังการลากจริง

**ยืนยันด้วย widget test 2 ชุด**: (1) กดนิ้วค้างที่จุดเดียวไม่ขยับเลย แล้วปล่อยเวลาผ่านไปเรื่อยๆ (300ms ทีละสเต็ป) แคปภาพเทียบ — เห็นชัดว่าวงคลื่นขยาย/จางไปตามเวลาจริงแม้นิ้วไม่ขยับแม้แต่พิกเซลเดียว (ถ้าไม่ผูกกับเวลาจริง ภาพทุกเฟรมจะเหมือนกันเป๊ะ ซึ่งไม่ใช่ผลที่ได้) และปล่อยนิ้วแล้วระลอกหายทันที; (2) ลากขยับนิ้วจริงข้ามหน้า แคปภาพระหว่างทาง — ยืนยันว่าคลื่นหลัก (S-curve เปลี่ยนหน้า) กับระลอกตกแต่งทำงานพร้อมกันได้ไม่ชนกัน และระลอกขยับตามตำแหน่งนิ้วที่เคลื่อนที่จริงด้วย ทั้งหมดยืนยันด้วยภาพที่แคปได้จริง ไม่ใช่แค่อ่านโค้ดแล้วเดา — ปิดท้ายด้วย `flutter analyze` (0 errors ใหม่) และ `flutter test` (27/27 ผ่าน)

## 29. รอบตรวจสุขภาพแอปทั้งหมด (3 agent คู่ขนาน) — พบบั๊กจริงร้ายแรง: Firestore เขียนล้มเหลวแต่แอปบอกว่าสำเร็จเสมอ + API key รั่วลง log

ผู้ใช้ขอให้ตรวจทั้งแอปว่ามีอะไรควรแก้/เพิ่มให้ดีที่สุด ใช้ Explore agent 3 ตัวคู่ขนานตรวจ 3 มุม (error handling/ความปลอดภัย, ความสม่ำเสมอของฟีเจอร์ 3 role + dead code, ความพร้อมของเอกสาร/setup) แล้วตรวจซ้ำเองอีกชั้นในจุดที่ร้ายแรงที่สุดก่อนลงมือแก้

**[แก้แล้ว] บั๊กร้ายแรง: ทุกเมธอดเขียน Firestore ใน `incident_service.dart` (createIncident, setErPrepared, addScenePhoto, dispatchIncidentByHospital, updateIncidentProgressStep) ดัก error แล้วทิ้งเงียบๆ จากนั้นคืนค่า `success: true`/`true` เสมอไม่ว่า Firestore จะเขียนสำเร็จจริงหรือไม่** — ระบบนี้ทั้ง 3 role อยู่คนละเครื่องกัน สื่อสารกันผ่าน Firestore เท่านั้น ถ้าเน็ตหลุดตอนกด SOS/มอบหมายเคส/อัปเดตสถานะ ผู้ใช้จะเห็นข้อความ "สำเร็จแล้ว" ทั้งที่อีกฝั่งไม่มีทางรู้เรื่องเลย ยืนยันโดยอ่านโค้ดจริงตรงจุดที่ agent ระบุก่อนแก้ (ไม่เชื่อ agent เฉยๆ) แก้โดยให้ทุกเมธอดคืนค่าจริงตามผล Firestore แล้วอัปเดต UI ทุกจุดที่เรียกให้แจ้งเตือน/ย้อนสถานะเมื่อไม่สำเร็จแทนนิ่งเงียบ:
- `lib/features/agency/presentation/agency_incident_detail_screen.dart` — ปุ่มมอบหมายเคส (เพิ่ม SnackBar แจ้งล้มเหลว) และปุ่มยืนยันเตียง ER (ย้อน UI + แจ้งเตือนเมื่อล้มเหลว)
- `lib/features/agency/presentation/agency_incident_list_screen.dart` — ปุ่มยืนยันเตียง ER ในรายการ (แจ้งเตือนตามผลจริง)
- `lib/features/ambulance/presentation/ambulance_incident_detail_screen.dart` — ถ่ายรูปหน้างาน (แจ้งเตือนเมื่อส่งไม่สำเร็จ) และปุ่มอัปเดตสถานะในหน้ารายละเอียด (ย้อนสถานะ+แจ้งเตือนเมื่อล้มเหลว)
- `lib/features/ambulance/presentation/ambulance_home_screen.dart` — ปุ่มอัปเดตสถานะด่วนทั้ง 3 ปุ่มบนหน้าหลัก (แจ้งเตือนเมื่อล้มเหลว)
- `lib/features/ambulance/presentation/ambulance_incident_list_screen.dart` — ปุ่มยืนยันรับเคส (แจ้งเตือนตามผลจริงแทนบอกสำเร็จเสมอ)
- `lib/features/driver_radar/presentation/sos_report_screen.dart` — ไม่ต้องแก้ เพราะมี branch แจ้งเตือนความล้มเหลวไว้ถูกต้องอยู่แล้ว (แค่ไม่เคยถูกเรียกใช้จริงเพราะ `createIncident` เดิมคืนค่า `success: true` เสมอ)

**[แก้แล้ว] Gemini API key รั่วลง log เครื่องได้ (รวม release build)**: `ai_vision_triage_service.dart` เดิมแปะ `?key=$apiKey` ไว้ใน URL ตรงๆ ตอน request ล้มเหลว (เน็ตหลุด/timeout) ข้อความ exception ที่ debugPrint ไว้จะมี URL เต็มรวม key อยู่ด้วย ย้ายไปส่งผ่าน header `x-goog-api-key` แทน (Gemini API รองรับทั้ง 2 แบบ) ตัด key ออกจาก URL ไปเลย

**พบแต่ยังไม่แก้ (รอผู้ใช้เลือกว่าจะทำแค่ไหน)**: README.md ล้าสมัยมาก (ยังบอกว่าเป็น UI Only ทั้งที่ setup instructions ตัดจบไม่ครบด้วย), bundle ID ยังเป็นค่า default `com.example.*` ทั้ง Android/iOS, `pubspec.yaml` description/version ไม่เคยอัปเดต, Dark mode มีแค่ฝั่ง Driver ทั้งที่ `ThemeSettingsService` เขียนคอมเมนต์ไว้ว่าเป็น "unified ทุกหน้าจอ", การตั้งค่าเสียง/แจ้งเตือนฝั่ง Agency บันทึกได้แต่ไม่มีอะไรอ่านไปใช้จริงเลย, หน้าตั้งค่าฝั่ง Ambulance ไม่มีการบันทึกค่าเลยสักตัว (ปิดแอปแล้วรีเซ็ตทุกครั้ง), มีไฟล์ orphaned 4 ไฟล์ (`ai_acoustic_siren_service.dart` เป็น placeholder ที่ประกาศไว้ในคอมเมนต์ตัวเองว่ายังไม่ได้ต่อกับหน้าไหนเลย, `user_type_screen.dart`, `face_scan_settings_service.dart`, `app_settings.dart`) และ dependency ที่ไม่ได้ใช้ 3 ตัวใน `pubspec.yaml` (`provider`, `just_audio`, `firebase_auth`)

**ยืนยันด้วย `flutter analyze`** (0 error ใหม่ เหลือแค่ info เดิม + 3 info ใหม่ประเภทเดียวกับที่มีอยู่แล้วในโปรเจกต์ `use_build_context_synchronously` ซึ่งเป็นรูปแบบที่ยอมรับอยู่แล้วทั้งโปรเจกต์) **และ `flutter test` (27/27 ผ่าน)**

## 30. ผู้ใช้ขอ "แก้ทั้งหมดเลย" — จัดการรายการที่เหลือจากรอบตรวจสุขภาพแอป (หัวข้อ 29)

**[แก้แล้ว] Dead code cleanup**: ตรวจซ้ำเองก่อนลบ (ไม่เชื่อผล agent เฉยๆ) พบว่า `face_scan_settings_service.dart` จริงๆ แล้วมี test ใช้งานจริงอยู่ 3 เทสต์ใน `test/widget_test.dart` (agent ตรวจแค่ `lib/` ไม่ได้ตรวจ `test/`) จึง**ไม่ลบไฟล์นี้** — ลบแค่ 3 ไฟล์ที่ยืนยันแล้วว่าไม่มีใครอ้างถึงเลยทั้ง `lib/` และ `test/`: `ai_acoustic_siren_service.dart`, `user_type_screen.dart`, `app_settings.dart` และลบ 3 dependency ที่ไม่มีการ import ใช้เลย (`provider`, `just_audio`, `firebase_auth`) ออกจาก `pubspec.yaml`

**[แก้แล้ว] Ambulance: หน้าตั้งค่าไม่บันทึกอะไรเลยสักตัว**: เพิ่ม `saveSettings()`/`loadSettings()`/`settingsNotifier` ใน `ambulance_storage_service.dart` (รูปแบบเดียวกับ `AgencyStorageService`) แล้วผูกเข้ากับทั้ง 5 การตั้งค่าใน `ambulance_settings_screen.dart` (หน้าจอเปิดตลอด, โหมดทางหลวง, GPS ความละเอียดสูง, แจ้งเตือน ER อัตโนมัติ, ระยะส่งสัญญาณ) — Slider ใช้ `onChangeEnd` บันทึกแทน `onChanged` กันเขียนดิสก์รัวๆ ระหว่างลาก

**[แก้แล้ว] Agency: การตั้งค่าเสียง/หน้าจอกะพริบเป็นแค่ของประดับ**: เพิ่มการตรวจจับ "เคสใหม่ที่เพิ่งโผล่มา" ใน `agency_home_screen.dart` (เทียบ id เคสปัจจุบันกับที่เคยเห็นแล้ว ไม่นับเคสที่มีอยู่แล้วตอนเปิดแอปครั้งแรกเป็นเคสใหม่) เมื่อเจอเคสใหม่จะเรียก `VoiceAlertService().speakNewIncidentAlert()` (เมธอดใหม่) ถ้า `voiceAnnouncement` เปิดอยู่ และเล่นเอฟเฟกต์จอกะพริบแดงจางๆ ผ่าน `AnimationController` ถ้า `screenFlashAlert` เปิดอยู่ — ทั้งสองอ่านค่าจริงจาก `AgencyStorageService.settingsNotifier` ที่มีอยู่แล้ว

**[แก้แล้ว] Dark Mode มีแค่ฝั่ง Driver**: เพิ่มสวิตช์ "โหมดกลางคืน" ในหน้าตั้งค่าของทั้ง Ambulance และ Agency ผูกกับ `ThemeSettingsService.isNightMode` (global ValueNotifier ตัวเดียวกับที่ Driver ใช้อยู่แล้ว ไม่ต้องสร้างใหม่) แล้วปรับสีพื้นหลัง/หัวข้อ/การ์ดในหน้าตั้งค่าของทั้ง 2 role ให้ตอบสนองจริง — **ขอบเขตที่ทำ**: ครอบคลุมเต็มรูปแบบเฉพาะหน้าตั้งค่า (Settings) ของ Ambulance/Agency เท่านั้น ไม่ได้ไล่แก้ทุกสีในหน้า Profile/Home ของทั้ง 2 role ให้ลึกเท่าฝั่ง Driver (ซึ่งมีจุดอ้างอิง `isNightMode` มากถึง 130 จุดกระจายอยู่ 5 ไฟล์) เพราะการทำแค่บางส่วน (เช่น เปลี่ยนแค่ Scaffold/header แต่ตัวเนื้อหายังขาวอยู่) จะทำให้หน้าจอดูเหมือนบั๊กสีไม่ครบมากกว่าดูเป็นฟีเจอร์ที่ตั้งใจทำ — บันทึกไว้ตรงนี้เพื่อให้ชัดเจนว่ายังไม่ใช่ parity ระดับเดียวกับ Driver 100%

**[แก้แล้ว] README.md ล้าสมัย + pubspec description**: เขียนใหม่ทั้งหมดให้ตรงสถานะจริงของแอป (ระบบเชื่อมต่อ Firestore/MQTT/Gemini ครบแล้ว ไม่ใช่ UI Only) พร้อมขั้นตอน setup ที่ครบจริง (`flutter pub get` → คัดลอก `.env.example` → `flutter run`) และหัวข้อ "ข้อจำกัดที่รู้อยู่แล้ว" อธิบายตรงๆ ว่าโปรเจกต์นี้เป็นงานวิทยานิพนธ์มีข้อจำกัดอะไรบ้าง — เพิ่ม `GEMINI_API_KEY` ที่ขาดหายไปใน `.env.example` ด้วย (มีใช้จริงในโค้ดแต่ไม่เคยอยู่ใน template) — แก้ `pubspec.yaml` บรรทัด `description` จาก "A new Flutter project." เป็นคำอธิบายจริงของแอป

**[ตั้งใจไม่แก้] Bundle ID ยังเป็น `com.example.*`**: ไม่เปลี่ยนให้ เพราะความเสี่ยงสูงกว่าประโยชน์ที่ได้ในสถานการณ์นี้ — (1) `google-services.json`/`GoogleService-Info.plist` ผูกกับ bundle ID เดิมไว้ในฝั่ง Firebase console แล้ว เปลี่ยน bundle ID โดยไม่ไปสร้างแอปใหม่ในนั้นก่อนจะทำให้ Firebase เชื่อมต่อไม่ได้เลยทันที (2) เพิ่งเจอปัญหา "application-identifier entitlement mismatch" ตอนติดตั้งแอปไปหมาดๆ ในเซสชันนี้ (ต้องลบแอปออกจากเครื่องแล้วลงใหม่) เปลี่ยน bundle ID จะเจอปัญหาเดียวกันซ้ำอีกทันทีเพราะกลายเป็น "แอปคนละตัว" ในสายตา iOS — ถ้าต้องการแก้จริงต้องทำเองที่ Firebase Console ก่อน (สร้าง app entry ใหม่ด้วย bundle ID ใหม่ แล้วโหลดไฟล์ config ชุดใหม่มาแทน) จึงปล่อยเรื่องนี้ไว้ให้ผู้ใช้ตัดสินใจเอง ไม่ลงมือทำเองแบบเงียบๆ

**ยืนยันด้วย `flutter analyze` (0 error ใหม่ เหลือ 9 info เดิม/รูปแบบเดิม) และ `flutter test` (27/27 ผ่าน) หลังแก้ครบทุกจุดที่ตัดสินใจแก้**

## 31. เว็บแดชบอร์ด Agency/โรงพยาบาล (Flutter Web) — v1 ดูข้อมูลอย่างเดียว

ผู้ใช้ขอเว็บแดชบอร์ดให้โรงพยาบาลเปิดดูภาพรวมเคส+ตำแหน่งรถพยาบาลบนคอมได้ (ข้าม push notification/FCM ไปก่อนเพราะต้องใช้ Firebase Blaze plan) วางแผนผ่าน Plan Mode (Explore agent 2 ตัวคู่ขนานตรวจความเป็นไปได้ก่อน) พบจุดติดขัดสำคัญ: ตำแหน่งรถพยาบาลแบบสดส่งผ่าน MQTT (`EmergencyMqttService` ใช้ TCP socket ตรง) ซึ่งเบราว์เซอร์เชื่อมต่อแบบนี้ไม่ได้เลย (ข้อจำกัดแซนด์บ็อกซ์เบราว์เซอร์) แก้โดยให้ฝั่งมือถือเขียนตำแหน่งสะท้อนลง Firestore เพิ่มด้วย (หน่วง 4 วิ/ครั้ง) แล้วให้เว็บอ่านจาก Firestore แทน

**ไฟล์ใหม่**: `lib/main_web.dart` (entry point แยกจาก `lib/main.dart` เดิม 100% ไม่แตะมือถือเลย), `lib/web_dashboard/presentation/web_dashboard_screen.dart` (แผนที่ + sidebar รายการเคส เลย์เอาต์กว้างสำหรับจอคอม), `lib/core/services/emergency_fleet_web_service.dart` (อ่าน collection `emergency_fleet` จาก Firestore แปลงเป็น `EmergencyVehicleData` เดิม ไม่สร้างโมเดลใหม่)

**ไฟล์ที่แก้**: `firestore.rules` (เปิด `emergency_fleet` จาก `read/write: false` ที่ไม่เคยใช้จริง เป็น `allow read: if true` + เช็คพิกัดเป็นตัวเลขตอนเขียน), `lib/core/services/emergency_mqtt_service.dart` (เพิ่ม `_mirrorToFirestore()` เขียนคู่ขนานกับ MQTT ทุก broadcast แบบ throttle 4 วิ/คัน ปิดสัญญาณลบทิ้งทันทีไม่รอ throttle — ไม่กระทบ path MQTT เดิมเลย เป็นการเพิ่มเท่านั้น)

**ขอบเขต v1 ที่ตั้งใจจำกัดไว้**: ดูข้อมูลอย่างเดียว ไม่มีปุ่มมอบหมายเคส/ยืนยันเตียง ER จากเว็บ (ยังไม่มีระบบล็อกอินเว็บ ทำ action จากเว็บตอนนี้จะไม่รู้ว่าใครกด), ไม่มีระบบล็อกอิน (สอดคล้องกับ security model เดิมทั้งแอปที่ไม่มี Firebase Auth จริงอยู่แล้ว), single-hospital (`HOSP-01` เหมือนทั้งแอป ไม่ใช่ multi-tenant ใหม่)

**ยืนยันด้วย `flutter build web -t lib/main_web.dart` (build จริงผ่าน ไม่ใช่แค่ `flutter analyze`) `flutter analyze` (0 error ใหม่) และ `flutter test` (27/27 ผ่าน — ยืนยันว่าการเพิ่มโค้ดฝั่งเว็บไม่กระทบแอปมือถือเดิมเลย)

## 32. เพิ่มล็อกอินให้เว็บ Agency Dashboard + ฟิลด์ `archived` สำหรับเว็บ "Data" ที่กำลังจะสร้าง

ผู้ใช้ขอย้อนกลับไปเพิ่มระบบล็อกอินให้เว็บ Agency (หัวข้อ 31) โดยใช้บัญชี role "agency" เดียวกับแอปมือถือ ไม่สร้างรหัสผ่านแยกใหม่

**[บั๊กจริงที่เจอระหว่างทำ ยืนยันด้วย `flutter build web` ไม่ใช่แค่เดา]**: ตอนแรกวางแผนจะเรียก `FaceAuthRepository.authenticateWithPassword()` ตรงๆ (มีอยู่แล้ว ดูสมเหตุสมผลที่จะ reuse) แต่ build web จริงแล้วพัง — `FaceAuthRepository` import `face_recognition_service.dart` ซึ่งลาก `tflite_flutter` → `dart:ffi` ตามมาด้วย (เรียก native library ผ่าน FFI) ไลบรารีนี้ไม่มีบนเว็บเลย ทำให้ compile พังทันทีแค่เพราะ import ไฟล์นี้ ต่อให้ไม่เคยเรียกเมธอดเกี่ยวกับใบหน้าจริงๆ เลยก็ตาม (Dart ต้อง resolve ทั้งไฟล์ตอน compile) แก้โดยสร้าง **ไฟล์ใหม่** `lib/web_dashboard/data/web_auth_service.dart` — copy เฉพาะ logic เช็ครหัสผ่าน (Firestore collection `users` + รูปแบบ hash `salt:sha256Hash` เดียวกันเป๊ะ) มาไว้แยกต่างหาก ไม่ import อะไรที่เกี่ยวกับ ML/กล้องเลย

**ไฟล์ใหม่อื่นๆ**: `lib/web_dashboard/presentation/web_login_screen.dart` (ฟอร์มอีเมล/รหัสผ่าน เรียก `WebAuthService.loginAsAgency()` เช็ค role ต้องเป็น agency เท่านั้น)
**ไฟล์ที่แก้**: `lib/main_web.dart` (เปลี่ยนหน้าเริ่มต้นเป็น `WebLoginScreen`)

**เตรียมฟิลด์ `archived` ให้ `IncidentReport` model** (`lib/core/models/incident_report.dart`) — สำหรับเว็บ "Data" (เครื่องมือแอดมินจัดการฐานข้อมูล กำลังจะสร้างต่อ ดูหัวข้อ 33) ใช้เป็น soft-delete/เก็บเข้าคลัง กู้คืนได้ ต่างจากลบถาวรจริง เพิ่ม field ครบทุกจุด (constructor/toMap/fromMap/copyWith) และกรองออกจาก heatmap ของ agency ด้วย (`agency_home_screen.dart:_buildHotspotCircles()`) เหมือน cancelled (resolved ยังนับรวมตามเดิม ไม่แตะ)

**เปิด `firestore.rules` ให้ลบ `incident_reports` ถาวรได้จริง** (`allow delete: if true` เดิม `if false`) — ผู้ใช้ตัดสินใจและรับทราบความเสี่ยงแล้ว (ลบแล้วกู้คืนไม่ได้ + ระบบไม่มี auth จริงแยกแยะ client ได้ เปิดกว้างให้ client ไหนก็ลบได้ในทางเทคนิค ไม่ใช่แค่เว็บ Data) เพื่อรองรับปุ่ม "ลบถาวร" ในเว็บ Data ที่กำลังจะสร้าง

**ยืนยันด้วย `flutter build web -t lib/main_web.dart` (ผ่านหลังแก้ปัญหา dart:ffi), `flutter analyze` (0 error ใหม่) และ `flutter test` (27/27 ผ่าน)

## 33. สร้างเว็บ "Data" — เครื่องมือแอดมินจัดการฐานข้อมูลเคสเต็มรูปแบบ (โปรเจกต์แยกต่างหาก)

**ตำแหน่ง**: `~/Developer/rount alert/route-alert-data-web/` — sibling ของ `route-alert-app/` แยกโปรเจกต์กันเด็ดขาดตามที่ผู้ใช้ขอ ไม่ใช่ Flutter (HTML/CSS/JavaScript ธรรมดา + Firebase JS SDK ผ่าน CDN ไม่มี build step) สไตล์กระดาษใบเสร็จขอบฉีกขาด/ฟอนต์พิมพ์ดีด ตามภาพอ้างอิงที่ผู้ใช้ส่งมา รายละเอียดทั้งหมด (วิธีรัน, คำเตือนความปลอดภัย) อยู่ใน README ของโปรเจกต์นั้นเอง

**ฟีเจอร์**: ดูรายการเคสแบบเรียลไทม์ (`onSnapshot`), ค้นหา/กรองตามสถานะ/ความรุนแรง/จังหวัด, สร้างเคสใหม่, แก้ไขทุก field (ยกเว้น id/createdAt), เก็บเข้าคลัง (soft-delete ผ่าน field `archived` กู้คืนได้) และลบถาวรจริง (ต้องพิมพ์ยืนยันคำว่า "ลบ" ก่อน) — ตัดสินใจเรื่องนี้ร่วมกับผู้ใช้ผ่าน Plan Mode ก่อนลงมือ (ดูหัวข้อ 32 สำหรับฝั่ง Firestore rules ที่ต้องเปิดรองรับ)

**ไม่มีระบบล็อกอิน** ตามที่ผู้ใช้ตัดสินใจไว้ชัดเจน (ต่างจากเว็บ Agency ที่เพิ่งเพิ่ม login ไปในหัวข้อ 32) — บันทึกคำเตือนไว้ใน README ของโปรเจกต์นั้นชัดเจนว่าห้าม deploy ขึ้นสาธารณะแล้วแชร์ URL

**การยืนยันที่ทำได้จริงในสภาพแวดล้อมนี้ (ไม่มี Flutter test suite ให้ช่วยเหมือนฝั่งแอป)**:ตรวจ syntax ของทุกไฟล์ JS (`node --check`), เทียบ DOM id ทุกตัวที่ JS อ้างอิงกับที่ประกาศจริงใน `index.html` (ตรงกันครบ), เทียบ CSS class ทุกตัวที่ใช้ใน JS/HTML กับที่นิยามใน `style.css` (ครบ), ยืนยัน URL ของ Firebase SDK บน CDN ใช้งานได้จริง (HTTP 200), รัน local static server แล้วเปิดผ่าน headless Chrome ยืนยันว่าเชื่อมต่อ Firestore ไปถึง project จริง (`route-alert-ccf91`) สำเร็จ (เห็น session/channel ของ Firestore Listen API ในระดับ network log) — **แต่ไม่สามารถแคปภาพหน้าจอที่โหลดข้อมูลจริงมาแสดงผลได้** เพราะ headless Chrome's virtual-time ไม่รองรับ connection แบบ long-polling ของ Firestore ได้ดีในสภาพแวดล้อมนี้ (ข้อจำกัดของเครื่องมือทดสอบ ไม่ใช่ของแอป) เจอบั๊กจริง 1 จุดระหว่างตรวจโค้ดเอง (จังหวะ animation ตอนกด archive/delete เร็วเกินไปอาจชนกับ animation ตอนเข้าจอ) แก้แล้วก่อนส่งมอบ — **แนะนำให้ผู้ใช้เปิด `index.html` ในเบราว์เซอร์จริงเองอีกครั้งเพื่อยืนยันขั้นสุดท้าย**

## 34. แยกเว็บ Agency Dashboard เป็นโปรเจกต์ต่างหาก (3 โฟลเดอร์แล้ว) + เพิ่มฟีเจอร์ทั้ง 2 เว็บตามที่ขอ

ผู้ใช้ขอ 2 เรื่องพร้อมกัน: (1) แยกเว็บ Agency Dashboard ออกจาก `route-alert-app` เป็นโปรเจกต์ของตัวเอง เพื่อให้ commit ลง git แยกกันชัดเจนเหมือนเว็บ Data (2) แก้ gap ที่เคยแจ้งไว้ทั้ง 2 เว็บ — วางแผนผ่าน Plan Mode โดย**ตรวจความเป็นไปได้จริงก่อนเขียนแผน** (สร้างโปรเจกต์ทดลอง + path dependency กลับไปที่ `route-alert-app` แล้วรัน `flutter build web` จริง ผ่านสำเร็จ ก่อนค่อยลงมือจริง)

**Part A — ย้ายไปโปรเจกต์ใหม่**: `~/Developer/rount alert/route-alert-agency-web/` (sibling ของ `route-alert-app` และ `route-alert-data-web` — ตอนนี้มี 3 โฟลเดอร์แล้วตามที่ขอ) ใช้ path dependency ใน `pubspec.yaml` กลับไปที่ `../route-alert-app` เพื่อ reuse `IncidentReport`/`IncidentService`/`HospitalLocationService`/`EmergencyVehicleData`/`EmergencyMqttService` (แค่ static method คำนวณระยะทาง) โดยไม่ต้อง copy โค้ดซ้ำ — ย้าย `web_login_screen.dart`/`web_dashboard_screen.dart`/`web_auth_service.dart` ไปทั้งหมด ลบ `route-alert-app/lib/main_web.dart` และโฟลเดอร์ `lib/web_dashboard/` ทิ้ง (ย้ายออกไปหมดแล้ว) ลบไฟล์ template test เดิม (`test/widget_test.dart` ของ `flutter create` ที่อ้าง `MyApp` ซึ่งไม่มีอยู่จริงในโปรเจกต์นี้) เพิ่ม README อธิบาย path dependency + วิธีรัน

**Part B — ฟีเจอร์เว็บ Agency**:
- **Session persist ข้าม refresh**: เก็บอีเมลไว้ใน SharedPreferences (localStorage บนเว็บ) ตอนเปิดแอปเช็ค session ค้าง ยืนยัน role agency ซ้ำกับ Firestore ทุกครั้งก่อนเข้า dashboard (กันบัญชีถูกเปลี่ยน role/ลบไปแล้วแต่ session ยังค้างอยู่)
- **Action จริงจากเว็บ**: ปุ่ม "มอบหมายเคส" (หาเรือใกล้ที่สุดจาก fleet ที่แสดงอยู่แล้ว เรียก `IncidentService.dispatchIncidentByHospital`) และ "ยืนยัน/ยกเลิกเตียง ER" (`IncidentService.setErPrepared`) โผล่ในการ์ดที่กดเลือกอยู่ พร้อมปุ่ม logout ที่ header
- **ลดหน่วงตำแหน่งรถพยาบาล**: `emergency_mqtt_service.dart` ลด `_firestoreMirrorInterval` จาก 4 วิ → 2 วิ (ฝั่งมือถือ ส่งผลถึงเว็บ Agency โดยตรง)

**Part C — ฟีเจอร์เว็บ Data**:
- **ดูรูปภาพหน้างาน**: โมดัลแก้ไขเคสแสดง thumbnail ของ `photosBase64`/`scenePhotosBase64` กดดูขยายเต็มจอผ่าน lightbox ใหม่
- **Bulk action**: checkbox ที่แต่ละการ์ด + แถบเครื่องมือลอยด้านล่างเมื่อเลือกไว้ ≥1 รายการ (เก็บเข้าคลัง/กู้คืน/ลบถาวรพร้อมกันหลายเคส ปุ่ม archive สลับข้อความอัตโนมัติตามแท็บที่อยู่ — เจอ+แก้บั๊กเรื่องข้อความปุ่มไม่ตรงกับการกระทำจริงตอนอยู่แท็บคลัง)
- **Pagination**: แสดงทีละ 30 รายการ ปุ่ม "โหลดเพิ่ม" ต่อท้ายลิสต์ รีเซ็ตกลับหน้าแรกเมื่อเปลี่ยนแท็บ/ตัวกรอง

**ไม่ทำในรอบนี้ (แจ้งเหตุผลไว้ในแผนแล้ว)**: Multi-hospital (เลิก hardcode `HOSP-01`) — เป็นการเปลี่ยนสถาปัตยกรรมข้ามทั้งระบบ (มือถือ 3 role ทั้งหมด ไม่ใช่แค่เว็บ) ต้องวางแผนแยกต่างหาก

**ยืนยันด้วย `flutter build web` ผ่านทั้ง `route-alert-agency-web` (โปรเจกต์ใหม่) และ `route-alert-app` (มือถือไม่กระทบ), `flutter analyze`/`flutter test` (27/27) ผ่านฝั่ง `route-alert-app`, และตรวจเว็บ Data ซ้ำแบบเดียวกับรอบก่อน (syntax + DOM id + CSS class ครบ) หลังเพิ่มฟีเจอร์ใหม่ทั้ง 3 อย่าง

## 35. เว็บ "Data" — แก้อาการกระตุกตอนเปิดดูเคส + เพิ่ม stat-chip กดกรองด่วน + ตัวกรองประเภทเหตุ + แผนที่คลัสเตอร์

ผู้ใช้รายงาน 2 เรื่อง แล้วขอฟีเจอร์เพิ่มอีก 3 อย่าง (พร้อมแนบภาพอ้างอิงแดชบอร์ด SCADA เกาหลี):

**แก้อาการกระตุกตอนเปิดโมดัลแก้ไขเคส**: ต้นเหตุคือ `renderPhotoThumbnails()` (decode รูป base64 เป็น `<img>` ผ่าน `innerHTML`) ถูกเรียกแบบ synchronous ก่อน `showModal()` พอดี ทำให้แย่ง main thread กับแอนิเมชัน `modal-in` ตอนเริ่มเล่น — แก้โดยโชว์ placeholder "กำลังโหลดรูปภาพ..." ก่อน เรียก `showModal()` ทันที แล้วค่อย `renderPhotoThumbnails()` ผ่าน `requestAnimationFrame` ซ้อน 2 ชั้น (รอแอนิเมชันเริ่มเล่นให้ main thread ว่างก่อน) พร้อมเพิ่ม `decoding="async"`/`loading="lazy"` ที่ `<img>`

**Stat-chip กดกรองด่วน**: เปลี่ยน 4 กล่องสถิติ (รอยืนยัน/กำลังดำเนินการ/เสร็จสิ้นสะสม/ทั้งหมดในระบบ) จาก `<div>` แสดงผลอย่างเดียวเป็น `<button>` กดได้ — กดแล้วตั้ง `quickFilter` มากรอง list ให้ตรงกับตัวเลขที่โชว์เป๊ะ (กด "รอยืนยัน"/"กำลังดำเนินการ" จะสลับมาแท็บปกติอัตโนมัติถ้าอยู่แท็บคลัง เพราะสองอันนี้หมายถึงเคสที่ยังไม่เก็บเข้าคลังเสมอ, กด "เสร็จสิ้นสะสม" นับรวมทั้งที่เก็บเข้าคลังแล้วด้วยเหมือนตัวเลขที่โชว์) กด chip เดิมซ้ำ = ปิดตัวกรอง (toggle) กด "ทั้งหมดในระบบ" = ล้างตัวกรองทั้งหมด (เก็บช่องค้นหาไว้) ตัวกรอง severity/province/type ยังกรองซ้อนต่อจาก chip ได้ (ใช้เป็นตัวกรองย่อยของ shortlist)

**ตัวกรองประเภทเหตุ**: เพิ่ม dropdown "ประเภทเหตุ" (`filter-type`) ในแถบเครื่องมือ ประชากรค่าจากข้อมูลจริงอัตโนมัติแบบเดียวกับ severity/province ที่มีอยู่แล้ว (ไม่ hardcode)

**แผนที่คลัสเตอร์**: เพิ่มแท็บ "🗺 แผนที่" ที่ 3 ต่อจาก "เคสทั้งหมด"/"คลัง" ใช้ Leaflet.js + Leaflet.markercluster (โหลดผ่าน CDN unpkg) แสดงเคสที่มีพิกัด lat/lng เป็นหมุด ถ้าอยู่ใกล้กันจะรวมเป็นจุดเดียวแสดงตัวเลขจำนวน (cluster) แบบในภาพอ้างอิง กดหมุด/คลัสเตอร์ดูรายละเอียดเคสในป็อปอัพ มีปุ่ม "ดูรายละเอียด" เปิดโมดัลแก้ไขเคสเดิมต่อได้เลย สไตล์ tile แผนที่ปรับด้วย CSS filter (sepia/contrast) ให้กลืนกับธีมกระดาษของเว็บ ไอคอนคลัสเตอร์ทำเป็นวงกลมกระดาษขอบเส้นประให้เข้าธีม แผนที่ยังเคารพตัวกรอง (severity/province/type/search/quickFilter) เหมือน list view ทุกอย่าง

**ไม่ได้ทำ**: ป็อปอัพตัวกรองแยกกล่องขวามือแบบในภาพอ้างอิงเป๊ะๆ — ใช้ dropdown ในแถบเครื่องมือเดิม (เพิ่ม type filter เข้าไปด้วย) แทน เพราะฟังก์ชันเดียวกัน (กรองตามสถานที่/ความรุนแรง/ประเภท) แต่ความเสี่ยงต่ำกว่ามากในวันก่อนส่งงาน

**ยืนยันด้วย `node --check js/app.js` (syntax), ไล่ตรวจ DOM id ทุกตัวที่ `$()` เรียกกับ id ใน `index.html` ครบ (ยกเว้น `btn-load-more` ที่สร้างจาก JS เอง), ไล่ตรวจ CSS class ที่ใช้ครบทุกตัวมีนิยามใน `style.css`, และ `curl` ยืนยัน CDN ของ Leaflet/Leaflet.markercluster ทั้ง 5 ไฟล์ตอบ HTTP 200 จริง — **ยังไม่ได้เปิดเบราว์เซอร์จริงทดสอบแผนที่/คลัสเตอร์แบบ end-to-end** เพราะข้อจำกัดสภาพแวดล้อมเดิม (headless Chrome เชื่อม Firestore ไม่เสถียรตามที่เจอมาก่อนหน้านี้) ควรลองเปิดเองที่เครื่องก่อนส่งงานจริง

## 36. เว็บ "Data" — เจอสาเหตุจริงของอาการกระตุกตอนเปิด modal (ผู้ใช้ยืนยันว่าแก้รอบก่อนไม่หาย)

ผู้ใช้แจ้งว่าเว็บ Data ยังกระตุกเหมือนเดิมหลังแก้ไปแล้วในหัวข้อ 35 (ตอนนั้นแก้แค่การ decode รูปภาพที่แย่ง main thread) — ไล่ดู `css/style.css` ซ้ำอีกรอบ เจอสาเหตุจริงคือ `#modal-overlay` มี `backdrop-filter: blur(2px)` ควบคู่กับแอนิเมชัน `overlay-in` (opacity 0→1) วิ่งพร้อมกัน ซึ่งเป็นสาเหตุคลาสสิกของอาการกระตุกที่รู้จักกันดี: เบราว์เซอร์ต้อง re-blur ทุกอย่างที่อยู่ข้างหลัง overlay ใหม่ทุกเฟรมตลอดที่ opacity กำลังเปลี่ยนค่า เป็นงานหนักบน GPU มาก โดยเฉพาะตอนข้างหลังเป็น list การ์ดยาวๆ ที่มี box-shadow/gradient เยอะ — เกิดขึ้น**ทุกครั้ง**ที่เปิด modal ไม่ว่าจะเป็นสร้างเคสใหม่/แก้ไข/ลบ/bulk-delete ไม่ใช่แค่ตอนมีรูปภาพ จึงอธิบายได้ว่าทำไมการแก้รอบก่อน (ซึ่งแก้แค่ปัญหาการ decode รูป) ไม่ช่วยให้อาการหายไปจริง

**แก้โดย**เอา `backdrop-filter: blur(2px)` ออกจาก `#modal-overlay` ทั้งหมด แล้วเพิ่มความทึบของพื้นหลังสีเข้มจาก `rgba(20,18,14,0.55)` เป็น `rgba(20,18,14,0.68)` แทน เพื่อให้ modal ยังแยกออกจากพื้นหลังได้ชัดโดยไม่ต้องเบลอ (เอฟเฟกต์เบลอเสียไปเล็กน้อยแต่แลกกับความลื่นไหลที่ดีขึ้นมาก)

**ยืนยันด้วยการ grep ยืนยันว่าไม่มี `backdrop-filter` เหลืออยู่ในไฟล์ (เหลือแค่คอมเมนต์อธิบายเหตุผลไว้เป็นหลักฐาน) — ยังไม่ได้เปิดเบราว์เซอร์จริงทดสอบซ้ำเพราะข้อจำกัดสภาพแวดล้อมเดียวกับหัวข้อก่อนหน้า ควรลองเปิดที่เครื่องจริงเพื่อยืนยันว่าอาการกระตุกหายจริง

## 37. เว็บ "Data" — เพิ่ม stat-chip กดกรองด่วน (ทำจริง ไม่ใช่แค่ dropdown) + แผนที่คลัสเตอร์ + แก้ล็อกอิน admin_3 บนเว็บ Agency

ผู้ใช้ส่งคำขอเดิม (stat-chip/แผนที่) ซ้ำอีกครั้งพร้อมภาพอ้างอิงแดชบอร์ด SCADA และย้ำว่า "API maps ก็มีในแอปแล้ว" — ไล่เช็คโค้ดแอปมือถือจริง (`agency_home_screen.dart`, `driver_home_screen.dart` ฯลฯ) ยืนยันว่าทุกจุดใช้ `flutter_map` + tile `tile.openstreetmap.org` เฉยๆ ไม่มี API key แยก ตรงกับที่เว็บ Data ใช้อยู่แล้ว (Leaflet + OSM tile เดียวกัน) จึงไม่ต้องเปลี่ยนอะไรฝั่ง tile source — สอดคล้องกันอยู่แล้ว

**เรื่องล็อกอิน `admin_3` บนเว็บ Agency Dashboard ที่ค้างมาตั้งแต่หัวข้อก่อนๆ — เจอสาเหตุจริงแล้ว**: ผู้ใช้พิมพ์ "admin_3" สั้นๆ (ไม่ใช่อีเมลเต็ม) แต่ `WebAuthService` เดิมเอาข้อความที่พิมพ์ไปหา doc ใน Firestore ตรงๆ (`users/admin_3`) ซึ่งไม่มีจริง เพราะบัญชีสาธิตนี้ฝั่งแอปมือถือ (`face_login_screen.dart`) ผูกกับอีเมลปลอม `admin_3@routealert.test` ต่างหาก (ดู `_kDemoAccounts` ในนั้น) — นอกจากนี้ยังพบว่าฝั่งมือถือเขียนข้อมูลพื้นฐานของบัญชี (email/role) ขึ้น Firestore ผ่าน `registerUser()` -> `_syncUserToCloud()` แบบ **fire-and-forget (ไม่ await ผลเขียน)** มีโอกาสที่ field `role` จะยังไปไม่ถึง Firestore จริงตอนมาล็อกอินเว็บ ทำให้ต่อให้แก้แค่เรื่องอีเมลอย่างเดียวก็อาจยังพังอยู่ดี

**แก้โดย**เพิ่ม whitelist บัญชีสาธิต `admin_3`/`admin_3@routealert.test` + รหัสผ่านคงที่ `12345` ไว้ใน `WebAuthService.loginAsAgency()` และ `tryRestoreSession()` ของ `route-alert-agency-web` ให้ตรวจสอบตรงนี้ทันทีโดยไม่ต้องพึ่งข้อมูลใน Firestore เลย (บัญชีสาธิตใช้เพื่อดูงานเท่านั้น ความเสี่ยงต่ำ ไม่กระทบบัญชีจริง) — ไม่ได้แก้โค้ดฝั่งแอปมือถือ (`face_login_screen.dart`/`face_auth_repository.dart`) เพราะเป็นโค้ด auth การผลิตจริง ความเสี่ยงสูงกว่าจะแก้คืนก่อนส่งงาน

**Stat-chip/แผนที่**: ยืนยันการทำงานจริงของฟีเจอร์ที่ทำไปแล้วในหัวข้อ 35 (chip กดกรองได้จริง ไม่ใช่แค่ static ตัวเลข, แท็บแผนที่คลัสเตอร์ด้วย Leaflet.markercluster) — ยังไม่ได้เพิ่มแผงตัวกรองแยกด้านขวาแบบภาพอ้างอิงเป๊ะๆ ในรอบนี้ (ใช้ dropdown ในแถบเครื่องมือแทนตามที่บันทึกไว้ในหัวข้อ 35)

**ยืนยันด้วย `flutter analyze` ผ่าน (No issues found) หลังแก้ `web_auth_service.dart`, และรีสตาร์ท `flutter run -d chrome` ใหม่ทั้งหมด (kill task เดิม รันใหม่) ให้แน่ใจว่าโค้ดที่แก้ถูก compile เข้าไปจริง ยืนยัน Debug service เชื่อมต่อสำเร็จ — ยังไม่ได้ล็อกอินทดสอบจริงในเบราว์เซอร์ (ข้อจำกัดสภาพแวดล้อมเดิม) ผู้ใช้ควรลองพิมพ์ `admin_3` / `12345` ที่เครื่องจริงเพื่อยืนยัน

## 38. เว็บ "Data" — ทำแผงตัวกรองแยกด้านขวาจริง (facet panel) + อัปเกรดแท็บแผนที่เป็นแดชบอร์ด + เจอ/แก้ 8 บั๊กจากรีวิวอิสระ

ผู้ใช้ย้ำคำขอเดิมอีกครั้งพร้อมภาพอ้างอิง SCADA — คราวนี้ทำของจริงแทนที่จะใช้ dropdown ทดแทนแบบหัวข้อ 37:

**Facet panel**: กดปุ่ม "รอยืนยัน"/"กำลังดำเนินการ"/"เสร็จสิ้นสะสม" แล้วจะมีแผง `#facet-panel` โผล่ด้านขวาของแถบสถิติ (ชั้นล่างถ้าจอแคบ) แสดงตัวเลือกกรอง จังหวัด/ความรุนแรง/ประเภทเหตุ พร้อมจำนวนที่นับจาก shortlist ปัจจุบัน (`getQuickFilterBase()`/`computeFacetCounts()`) กดเลือกเพื่อกรองต่อ กดซ้ำเพื่อเอาออก มีปุ่ม ✕ ปิด shortlist ทั้งหมด

**แท็บแผนที่อัปเกรดเป็นแดชบอร์ด**: เพิ่มแผงข้าง "🚨 เหตุการณ์ล่าสุดบนแผนที่" (20 เคสล่าสุดที่มีพิกัด กดแล้วซูมแผนที่ไปหา+เปิด popup ผ่าน `markerClusterGroup.zoomToShowLayer()`), หมุดสีตามสถานะ (แดง=รอยืนยัน/ส้ม=กำลังดำเนินการ/เขียว=เสร็จสิ้น/เทา=ยกเลิก ใช้ CSS variable ชุดเดียวกับ badge เดิม) พร้อม legend มุมขวาบนของแผนที่

**ตรวจสอบ tile source ของแอปมือถือจริง**: grep `agency_home_screen.dart`/`driver_home_screen.dart` ฯลฯ ยืนยันใช้ `flutter_map` + `tile.openstreetmap.org` เฉยๆ ไม่มี API key แยก ตรงกับเว็บ Data อยู่แล้ว ไม่ต้องแก้อะไร

**แก้ล็อกอิน `admin_3`**: เพิ่ม whitelist บัญชีสาธิตใน `WebAuthService` ของ `route-alert-agency-web` (ดูหัวข้อ 37) — รอบนี้เพิ่ม `kEnableAgencyWebDemoLogin` เป็นสวิตช์ปิด-เปิดตัวเดียว (เหมือน `kEnableDemoQuickLogin` ฝั่งมือถือ) หลังรีวิวอิสระชี้ว่าเดิมไม่มีสวิตช์แบบนี้เลย

**สั่งรีวิวอิสระแบบ adversarial (workflow แยก 4 มิติ: logic/map/theme-css/accessibility ตามด้วยขั้นยืนยันแยกทุกข้อ) เจอบั๊กจริง 8 ข้อ แก้ครบทุกข้อในรอบนี้**:
1. **(High)** กด chip "รอยืนยัน"/"กำลังดำเนินการ" ตอนอยู่แท็บ "แผนที่" จะโดนสลับออกจากแผนที่ไปแท็บลิสต์โดยไม่ตั้งใจ (โค้ดเดิมเช็คแค่ "ถ้าไม่ใช่ pending/ongoing ก็ข้าม" โดยลืมว่าตอนนี้มี 3 แท็บแล้วไม่ใช่ 2) — แก้เป็นเช็คเฉพาะตอนอยู่แท็บ "คลัง" เท่านั้น
2. ตัวเลขนับบนปุ่ม facet ไม่รวมตัวกรองคำค้นหา (`filters.search`) ทำให้กดแล้วอาจได้ 0 ผลลัพธ์ทั้งที่ปุ่มบอกว่ามี — เพิ่มการกรอง search เข้าไปใน `getQuickFilterBase()`
3. ปุ่ม ✕ ปิดแผง facet ไม่ได้ล้างตัวกรอง severity/province/type ที่เลือกไว้ ทำให้ตัวกรองค้างต่อในมุมมองปกติแบบไม่มีอะไรบอก — เพิ่มการล้างให้ครบเหมือน `setQuickFilter()`
4. แผนที่ทุบสร้าง marker ใหม่ทุกครั้งที่ Firestore อัปเดต (แม้เคสอื่นที่ไม่เกี่ยวข้อง) ทำให้ popup ที่เปิดค้างอยู่หายไปเงียบๆ — เพิ่ม `openPopupDocId` ไว้เปิด popup กลับให้อัตโนมัติถ้า marker ยังไม่ถูกยุบเข้าคลัสเตอร์ (ไม่บังคับซูม กันแผนที่กระโดดเองระหว่างผู้ใช้ไม่ได้สั่ง)
5. ตัวกรองพิกัด marker เช็คแค่ `typeof === "number"` ซึ่ง `NaN` ผ่านด้วย ทำให้ `L.marker([NaN,...])` throw กลางลูปจนเคสที่เหลือไม่ขึ้นแผนที่เลย — เปลี่ยนเป็น `Number.isFinite()`
6. การ์ด `#map-main`/`#map-side-panel` ตั้ง `overflow: hidden`/`auto` ตรงๆ บน `.receipt-card` ทำให้ไปตัดขอบฉีก (`::after`) ของธีมทิ้ง ดูแบนผิดจากการ์ดอื่น — ย้าย overflow ไปไว้ที่ wrapper ชั้นในแทน (`#map-canvas-wrap`/`#map-recent-list-wrap`)
7. `.map-recent-id`/`.paper-cluster-icon`/`.map-popup-id` ใช้ font fallback แค่ 2 ชั้น (`"Special Elite", monospace`) ขาด `"Courier Prime"` ตรงกลางที่จุดอื่นในไฟล์ใช้กันหมด — เพิ่มให้ครบ 3 ชั้น
8. `#map-legend` ตั้ง z-index:400 สูงกว่า modal/lightbox ที่มีอยู่โดยไม่จำเป็น (จริงๆ ไม่เคยชนกันเพราะเป็น sibling ของแผนที่ ไม่ใช่ descendant) — ลดเหลือ 10 กันปัญหาถ้าโครงสร้าง DOM เปลี่ยนในอนาคต

**ไม่แก้ (ยอมรับเป็นความเสี่ยงต่ำที่รู้อยู่แล้ว)**: รีวิวยังเจอว่า credential บัญชีสาธิต (`admin_3`/`12345`) จะอยู่เป็น plaintext ใน `main.dart.js` หลัง build จริง — ยอมรับได้เพราะเป็นบัญชีทดสอบสำหรับรันในเครื่องตัวเอง/สาธิตเท่านั้น (README ของ `route-alert-agency-web` เตือนไว้แล้วว่าไม่ควร deploy เว็บนี้ให้คนอื่นเข้าถึงได้แบบสาธารณะ)

> **แก้ไขคำกล่าวอ้างข้างบน (หัวข้อ 39)**: ตอนเขียนหัวข้อ 38 นี้ README ของ `route-alert-agency-web` **ยังไม่มี**คำเตือนแบบนั้นจริงๆ (รีวิวรอบถัดมาตรวจแล้วพบว่าไม่มี) เป็นการอ้างผิดพลาด — เพิ่มคำเตือนจริงเข้าไปแล้วในหัวข้อ 39 ด้านล่าง ตอนนี้ข้อความข้างบนถึงจะเป็นจริง

**ยืนยันด้วย `flutter analyze` ผ่าน (No issues found), `node --check js/app.js` ผ่าน, ไล่ตรวจ DOM id/CSS class ครบอีกรอบหลังแก้, และ `curl` ยืนยันโค้ดต้นทางของ `leaflet.markercluster@1.5.3`/`leaflet@1.9.4` มี `getVisibleParent`/`popupclose` จริง (ไม่ได้เดา API) — ยังไม่ได้เปิดเบราว์เซอร์จริงทดสอบซ้ำเพราะข้อจำกัดสภาพแวดล้อมเดิม

## 39. สีคลัสเตอร์บนแผนที่ตามจำนวนเคส + audit ใหญ่ทั้ง 3 โค้ดเบส (มือถือ/เว็บ Data/เว็บ Agency) เจอ/แก้ 16 ปัญหา

ผู้ใช้ขอ 2 เรื่องเล็กก่อน แล้วถามภาพรวมว่า "มีอะไรที่ต้องแก้อีกไหมเว็บทั้งสองฝั่งเลยอะ":

**สีคลัสเตอร์ตามจำนวนเคส**: วงกลมตัวเลขบนแผนที่ (คลัสเตอร์ของ Leaflet.markercluster) เดิมสีเดียว/ขนาดเดียวเสมอไม่ว่าจะมีกี่เคสรวมกัน ผู้ใช้ขอให้แยกสีให้ดูออกว่าจุดไหนเยอะกว่า — เพิ่ม `getClusterTier()` ใน `app.js` ไล่สี/ขนาด 3 ระดับ (<5 / 5-9 / 10+) จากอ่อนไปเข้ม (ครีม→น้ำตาลทอง→ดำ) ตั้งใจไม่ใช้ชุดสีแดง/ส้ม/เขียวที่ legend สถานะใช้อยู่แล้ว เพราะจะสื่อสารสองความหมาย (สถานะของหมุดเดี่ยว vs จำนวนสะสมของคลัสเตอร์) ด้วยสีชุดเดียวกัน สับสนได้ — เพิ่ม CSS variable `--cluster-mid-bg` ใหม่ใน `:root` สำหรับโทนกลาง

**ตอบคำถามเรื่องจังหวัด/ประเภทเหตุ**: ยืนยันว่า dropdown/facet ดึงค่าจากข้อมูลจริงใน Firestore แบบไดนามิก (`populateDynamicFilterOptions()`) ไม่ได้ hardcode — เคสใหม่จากจังหวัดใหม่จะโผล่เองอัตโนมัติ ไม่ต้องแก้โค้ด

**Audit ใหญ่ทั้ง 3 โค้ดเบส**: สั่ง workflow รีวิวอิสระ 5 มิติ (data-web-core, data-web-security, agency-web-core, agency-web-consistency, cross-app-schema) ตามด้วยขั้นยืนยันแยกทุกข้อ (agent ทั้งหมด 22 ตัว) เจอ 17 ข้อ ยืนยันจริง 16 ข้อ แก้ครบทุกข้อในรอบนี้:

**เว็บ Data (`route-alert-data-web`)**:
1. **(High)** `renderPhotoThumbnails()` แทรก base64 ของรูปเคสเข้า `<img src="...">` โดยไม่ผ่าน `esc()` เหมือนจุดอื่นทุกจุดในไฟล์ — เป็นช่องโหว่ stored XSS จริง (field นี้เป็นแค่ string array ธรรมดาใน Firestore ไม่มีอะไรบังคับว่าต้องเป็น base64 เสมอ) — เพิ่ม `esc()` เข้าไป (ไม่กระทบ base64 ที่ถูกต้องเลย)
2. **(High)** `syncSelectOptions()` reset ค่า dropdown ที่แสดงเป็น "" เมื่อค่าที่เลือกไว้หายไปจากข้อมูล แต่ไม่เคย sync ตัวแปร `filters.*` ที่จำค่าไว้จริง (เพราะตั้ง `.value` ทาง DOM ไม่ยิง event `change`) ทำให้ filter ค้างกรองด้วยค่าที่มองไม่เห็นแล้ว ได้ผลลัพธ์ว่างเปล่าแบบไม่มีสาเหตุ — แก้ให้ sync `filters[key]` ด้วยทุกครั้ง
3. **(High)** `#bulk-bar` (z-index:150) วาดทับ `#modal-overlay` (z-index:100 เดิม) ได้ รวมถึงทับปุ่ม "ลบถาวร/ยกเลิก" ของ modal ยืนยันลบแบบเลือกหลายรายการเอง (ซึ่งเปิดได้ก็ต่อเมื่อ bulk-bar กำลังโชว์อยู่แล้ว) บนจอที่แคบพอ กดปุ่มไม่ได้เลย — ยก `#modal-overlay` เป็น z-index:160 ให้อยู่เหนือ bulk-bar เสมอ (ยังต่ำกว่า lightbox 300)
4. **(Medium)** เปิดโมดัลแก้ไขเคสไว้ค้าง แล้วอีกฝั่ง (เช่นแอมบูแลนซ์) เปลี่ยนสถานะเคสเดียวกันสดๆ — กด "บันทึก" จะส่งทั้งฟอร์ม (รวมสถานะเก่าที่เห็นตอนเปิด) ไปทับค่าล่าสุดจริงโดยไม่ตั้งใจ — เพิ่ม `editingOriginalSnapshot` เก็บค่าตอนเปิด แล้ว diff กับค่าตอนบันทึก ส่งเฉพาะฟิลด์ที่แอดมินแก้จริงเท่านั้น (`updateIncident` เป็น partial `updateDoc` อยู่แล้ว ปลอดภัยที่จะส่งแค่บางฟิลด์)
5. **(Medium)** เช็คบ๊อกซ์เลือกเคสไว้ทำ bulk action แล้วเคสนั้นหลุดจากมุมมองปัจจุบันเพราะข้อมูลอัปเดตสด (ไม่ใช่แอดมินเปลี่ยนตัวกรองเอง) — docId ที่เลือกไว้ยังค้างอยู่ ถ้ากด bulk action จะไปโดนเคสที่มองไม่เห็นอยู่ตรงหน้าแล้ว — เพิ่มการตัด docId ที่หลุดออกจากมุมมองทิ้งทุกครั้งที่มีข้อมูลอัปเดตสด
6. **(Medium, security)** `watchIncidents()` ไม่มี `onError` เลย ถ้า listener แรกสุด error (เน็ตเวิร์กบล็อก/proxy โรงเรียน/error ชั่วคราว) จะค้างที่ loading screen ตลอดไปไม่มีอะไรบอกสาเหตุเลย — เพิ่ม `onError` callback ทั้งใน `incidents.js`/`app.js` โชว์ข้อความ error ชัดเจนแทน
7. **(Medium, security)** README เขียนว่าความปลอดภัยของข้อมูลทั้งหมดขึ้นอยู่กับ URL ของเว็บนี้ไม่หลุด — เข้าใจผิด เพราะ Firebase config ที่ใช้เป็นชุดเดียวกับที่ฝังใน build เว็บของแอปมือถือเองอยู่แล้ว (ไม่ต้องพึ่งเว็บนี้เลยก็เรียก Firestore API ตรงได้) ตัวกำหนดความปลอดภัยจริงๆ คือ `firestore.rules` — แก้คำอธิบายให้ตรงกับความเป็นจริง พร้อมแก้ path ที่อ้างเว็บ Agency ผิด (`route-alert-app/lib/main_web.dart` ที่ย้ายไปแล้วตั้งแต่หัวข้อ 34 → `route-alert-agency-web`)
8. **(Medium, cross-app-schema)** Dropdown สถานะ (`f-status`/`filter-status`) ไม่มีตัวเลือก `in_progress` ทั้งที่เป็นสถานะจริงที่ `incident_report.dart`/`incident_service.dart` ฝั่งแอปมือถือใช้อยู่ — เปิดเคสแบบนี้แล้วกด "บันทึก" โดยไม่ได้ตั้งใจแก้สถานะ จะเผลอเขียนทับเป็น `""` (เพราะ `<select>` หา option ที่ตรงไม่เจอ `.value` เลยว่าง) — เพิ่ม option/label/สี badge ให้ครบ (แก้ปัญหานี้ซ้ำสองชั้นเพราะข้อ 4 ด้านบนก็ช่วยกันเคสนี้ไม่ให้เขียนทับถ้าแอดมินไม่ได้แตะช่องสถานะเลยด้วย)

**เว็บ Agency (`route-alert-agency-web`)**:
9. **(High)** `EmergencyFleetWebService` เช็ค staleness ของรถพยาบาลเฉพาะตอนมี snapshot ใหม่เข้ามาเท่านั้น (ต่างจาก `EmergencyMqttService` ฝั่งมือถือที่มี `Timer.periodic` คอยเช็คเองอยู่แล้ว) — รถที่แอปพังไปเฉยๆ ไม่ทันส่ง `sirenActive:false` จะค้างเป็น "ออนไลน์" ตลอดไปจนกว่าจะมีรถคันอื่นบังเอิญอัปเดตอะไรสักอย่าง เสี่ยงมากเพราะเว็บนี้ใช้ fleet เลือกรถไปมอบหมายเคสจริง — เพิ่ม `Timer.periodic` เช็คซ้ำทุก 5 วิ ไม่ต้องรอ snapshot ใหม่ (ในไฟล์เดียวกันนี้ยังแก้เพิ่ม: `updatedAt` ที่หายไป/parse ไม่ขึ้น เดิมถือว่า "ออนไลน์อยู่" โดย default ซึ่งเสี่ยงเกินไป เปลี่ยนเป็นตัดออกแทน — ปลอดภัยกว่าเวลาใช้เลือกรถจริง)
10. **(High)** `_tryRestoreSession()` ในหน้า login ไม่มี try/catch เลย ถ้า Firestore อ่าน session ค้างไว้แล้ว error (ออฟไลน์/เน็ตเวิร์กชั่วคราว) จะค้างที่ `CircularProgressIndicator` ตลอดไป ล็อกอินใหม่ด้วยมือไม่ได้เลยแม้แต่จะลอง — เพิ่ม try/catch ให้ fallback กลับมาที่ฟอร์ม login เสมอ
11. **(High)** `dispatchIncidentByHospital()`/`setErPrepared()` ใน `incident_service.dart` (ฝั่งแอปมือถือ ใช้ร่วมกับเว็บ Agency ผ่าน path dependency) อัปเดต local cache/stream แบบ optimistic ก่อนเขียน Firestore จริง — ถ้าเขียน Firestore fail (ออฟไลน์) ไม่เคย revert คืนเลย ทำให้เคสดูเหมือน "มอบหมายสำเร็จ/ยืนยันเตียง ER แล้ว" ค้างอยู่ในสายตาแอดมินทั้งที่เซิร์ฟเวอร์จริงไม่ได้เปลี่ยนอะไรเลย (ปุ่มมอบหมายก็หายไปด้วยเพราะเช็ค `status=='pending'` เท่านั้น กดมอบหมายซ้ำไม่ได้อีก) — เพิ่ม revert local cache/stream กลับเป็นค่าเดิมเมื่อ Firestore เขียนไม่สำเร็จ ทั้งสองฟังก์ชัน
12. **(Low)** `_dispatchNearestAmbulance()` เทียบระยะทางรถพยาบาลโดยไม่เช็คว่าพิกัดเป็นตัวเลขจริง (`NaN`/`infinite`) ก่อน ถ้ารถทุกคันในฟลีตพิกัดเพี้ยนหมด `nearest` จะเป็น `null` ค้างไว้ตลอดลูป แล้ว force-unwrap (`nearest!.id`) จะ throw กลางฟังก์ชัน ทำให้ `_isDispatching` ไม่ถูก reset กลับเป็น `false` เลย ปุ่มมอบหมายเคสค้าง spinner ไปตลอด session — เพิ่มการข้ามรถที่พิกัดเพี้ยนในลูป และเช็ค `nearest == null` ก่อนเรียกใช้ พร้อม reset state ให้ถูกต้อง
13. **(High, doc)** README ไม่เคยพูดถึงบัญชีสาธิต `admin_3`/`12345` ที่ข้ามการเช็ค Firestore ทั้งหมดเลย (เพิ่มไว้ในหัวข้อ 37/38) — ใครอ่าน README เพื่อเข้าใจระบบ auth จะไม่รู้เลยว่ามี backdoor นี้อยู่ — เพิ่มหัวข้อ "⚠️ บัญชีทดสอบสาธิต" อธิบายครบ พร้อมย้ำว่าต้องปิด `kEnableAgencyWebDemoLogin` ก่อน deploy สาธารณะ
14. **(Medium, doc)** `pubspec.yaml` เขียนคอมเมนต์ว่า path dependency reuse `WebAuthService` ด้วย ทั้งที่จริงคลาสนี้ประกาศแยกอยู่ในโปรเจกต์นี้เอง ไม่ได้ reuse จากแอปมือถือเลย (เหตุผลเดียวกับที่ทำเว็บ dashboard แยกไฟล์แต่แรก — `FaceAuthRepository` ตัวจริงลาก `tflite_flutter` มาด้วยซึ่งพังบนเว็บ) — แก้คอมเมนต์ให้ตรง กันคนแก้ auth logic ฝั่งมือถือแล้วงงว่าทำไมเว็บไม่เปลี่ยนตาม

**ยืนยันด้วย `flutter analyze` ผ่านทั้ง `route-alert-app`/`route-alert-agency-web` (No issues found), `flutter test` ผ่านครบ 27/27 ที่ `route-alert-app` (ยืนยันว่าแก้ `incident_service.dart`/`emergency_fleet_web_service.dart` ไม่กระทบของเดิม), `flutter build web` ผ่านที่ `route-alert-agency-web` (build จริง ไม่ใช่แค่ analyze), `node --check` ผ่านทุกไฟล์ JS ที่แก้, และไล่ตรวจ DOM id/CSS class ของเว็บ Data ครบอีกรอบ — ยังไม่ได้เปิดเบราว์เซอร์จริงทดสอบ end-to-end เพราะข้อจำกัดสภาพแวดล้อมเดิม

**ตามมาแก้ทันที**: `addScenePhoto()` ใน `incident_service.dart` มีรูปแบบ optimistic-update ไม่ revert แบบเดียวกับข้อ 11 ทุกประการ (ไม่ได้อยู่ในผลรีวิวรอบนี้ตอนแรกเพราะไม่ได้ถูกตรวจ) ผู้ใช้สั่งให้แก้ด้วย — เพิ่ม revert local cache/stream กลับเป็นค่าเดิมเมื่อเขียน Firestore ไม่สำเร็จ เหมือนกับอีกสองฟังก์ชัน ยืนยันด้วย `flutter analyze`/`flutter test` ผ่านครบอีกรอบ

## 40. เว็บ Data — แท็บสถิติย้อนหลัง (Chart.js + แผนที่ประวัติ) + เว็บ Agency — แก้ไขตำแหน่ง/ข้อมูลโรงพยาบาลได้แล้ว (พาริตี้กับแอปมือถือ)

ผู้ใช้ขอ 2 เรื่อง: (1) เลือกไอเดีย "แดชบอร์ดแนวโน้มเคสรายสัปดาห์" จากรอบ brainstorm หัวข้อก่อนหน้ามาทำจริง พร้อมขอเพิ่มแผนที่ย้อนหลังของพิกัด/จำนวนเคสด้วย (2) ถามว่าทำไมเว็บ Agency ไม่เหมือนแอปมือถือเลย มีแค่เคส+แผนที่ ไม่มีฟีเจอร์ย้ายพิกัดโรงพยาบาลหรืออย่างอื่น

**ตรวจสอบก่อนตอบ**: ใช้ Explore agent ไล่เทียบ `agency_home_screen.dart`/`agency_profile_screen.dart`/`agency_incident_detail_screen.dart`/`agency_settings_screen.dart` (มือถือ) กับ `web_dashboard_screen.dart` (เว็บ) แบบละเอียด พบว่าเว็บขาดฟีเจอร์จริงถึง ~19 อย่าง (ย้ายหมุด รพ., แก้ชื่อ/ที่อยู่/เบอร์ ER, สลับสถานะ ER ทั้ง รพ., heatmap toggle, banner แจ้งเตือนเคสใหม่/รถใกล้ถึง, เสียง+จอกะพริบ, coach mark, onboarding, dark mode, การตั้งค่าเสียง/ระยะแจ้งเตือน, แดชบอร์ดสถิติ+กราฟแนวโน้ม 6 เดือน, จัดการรหัสผ่าน/ลบบัญชี, ปุ่มซ่อนการ์ดเคสรายตัว, timeline สถานะ 6 ขั้น, และหน้ารายละเอียดเคสเต็ม+รูปหน้างาน) — เว็บ Agency เป็นแค่มุมมองปฏิบัติการแบบย่อ ไม่ใช่แอปฉบับเต็มบนเว็บ

**ทำจริงรอบนี้ (เลือกจุดที่ผู้ใช้ระบุชัดเจน)**:
- **เว็บ Agency**: เพิ่มปุ่ม "แก้ไขตำแหน่ง/ข้อมูลโรงพยาบาล" ที่ header เปิด dialog ใหม่ (`hospital_pin_edit_dialog.dart`) มีแผนที่เล็กแตะเพื่อย้ายหมุด + ช่องแก้ชื่อ/ที่อยู่/เบอร์ ER เรียก `HospitalLocationService().updatePinnedLocation()` ตัวเดียวกับที่แอปมือถือใช้เป๊ะ (ไม่ได้เขียน logic ใหม่ ใช้ path dependency ที่มีอยู่แล้ว) ข้อมูล sync ผ่าน Firestore ถึงทั้งสองฝั่งทันที
- **เว็บ Data**: เพิ่มแท็บ "📊 สถิติย้อนหลัง" ตัวที่ 4 มี 3 ส่วน: (1) กราฟเส้นแนวโน้มเคสรายสัปดาห์ 12 สัปดาห์ล่าสุด แยกสีตามความรุนแรง ด้วย Chart.js (CDN, ไม่มี build step) (2) กราฟแท่งแจกแจงชั่วโมงที่มีเคสสูงสุด (0-23 น.) (3) แผนที่ประวัติ (Leaflet + markercluster ชุดเดียวกับแท็บแผนที่สด นำ `getClusterTier()`/`createStatusMarkerIcon()` มาใช้ซ้ำ) แสดงทุกเคสในหน้าต่าง 12 สัปดาห์ **รวมสถานะ resolved/cancelled/archived ด้วย** (ต่างจากแผนที่สดที่กรองตามแท็บ) เพราะจุดประสงค์คือดูภาพรวมการกระจายตัวย้อนหลัง ไม่ใช่จัดการเคสรายตัว จึงไม่มีปุ่ม "ดูรายละเอียด" ใน popup ของแผนที่นี้ (ตั้งใจ) ข้อมูลทั้งหมดคำนวณจาก `allIncidents` ที่มีอยู่แล้วฝั่ง client ล้วนๆ ไม่ต้อง query Firestore ใหม่/ไม่ต้องมี backend เพิ่ม
- แก้ `setQuickFilter()` ให้ตรรกะ force-switch แท็บ (จากหัวข้อ 39 ข้อ 2) ครอบคลุมแท็บใหม่นี้ด้วย (กด stat-chip ตอนอยู่แท็บสถิติย้อนหลังจะสลับไปแท็บปกติเหมือนตอนอยู่แท็บคลัง เพราะแท็บนี้ก็ไม่รองรับการแสดงผล quickFilter เหมือนกัน)

**ยืนยันด้วย** `flutter analyze`/`flutter build web` ผ่านที่ `route-alert-agency-web` (build จริง), `node --check js/app.js` ผ่าน, ไล่ตรวจ DOM id/CSS class ครบ, `curl` ยืนยัน CDN ของ Chart.js 4.4.0 ตอบ 200 จริงและ export global ชื่อ `Chart` ตรงกับที่โค้ดเรียกใช้ (ไม่ได้เดา) — ยังไม่ได้เปิดเบราว์เซอร์จริงทดสอบ end-to-end ทั้งสองฟีเจอร์เพราะข้อจำกัดสภาพแวดล้อมเดิม ควรลองเปิดที่เครื่องจริงก่อนส่งงาน

ผู้ใช้เปิดจริงที่เครื่องแล้วส่งภาพหน้าจอมายืนยันว่าใช้งานได้จริง (กราฟ/แผนที่ขึ้นถูกต้อง)

## 41. เลือกช่วงเวลาได้เองในแท็บสถิติย้อนหลัง + แก้บั๊ก 12 ข้อจากรีวิวรอบสุดท้ายก่อนส่งงาน (เจอ session limit ระหว่างขั้นยืนยัน)

ผู้ใช้บอก "พอแล้ว ไม่เพิ่มฟีเจอร์ใหม่ ให้ตรวจว่ามีจุดไหนต้องปรับให้ทั้งสองเว็บสมบูรณ์" — สั่ง workflow รีวิวรอบสุดท้าย 5 มิติ (stats-history-correctness, hospital-pin-dialog-correctness, data-web-completeness, agency-web-completeness, docs-freshness) ได้ raw finding 21 ข้อ แต่**ขั้นยืนยัน (verify) ทั้ง 21 เอเจนต์ล้มเหลวหมดเพราะชน session usage limit ของบัญชี** (reset 14:10 เวลาไทย) — `confirmed: []` ที่ได้กลับมาจึงไม่ได้แปลว่า "ไม่เจอปัญหา" แต่หมายความว่ายังไม่ได้ยืนยันเลยสักข้อ (สำคัญ: ต้องอ่าน journal.jsonl ก่อนสรุปผลเสมอเมื่อเจอ pattern นี้ ไม่ใช่เชื่อ confirmed:[] ตรงๆ)

**เนื่องจากยิง agent เพิ่มไม่ได้ชั่วคราว จึงอ่าน raw finding จาก journal.jsonl แล้วไล่ตรวจสอบเองด้วยการอ่านโค้ดจริงแทน** (ไม่ใช่ adversarial multi-agent verification แบบรอบก่อนๆ) พบว่าส่วนใหญ่เป็นปัญหาจริง แก้ไปทั้งหมด 12 ข้อ:

**เว็บ Data**:
1. **แก้ให้เลือกช่วงเวลาได้เอง** (คำขอผู้ใช้โดยตรง แทนที่ "12 สัปดาห์" ตายตัวเดิม) — เพิ่มปุ่มเลือกช่วง 7 วัน/4 สัปดาห์/3 เดือน/6 เดือน/1 ปี/ทั้งหมด ("ทั้งหมด" หาเคสเก่าสุดจากข้อมูลจริงเป็นจุดเริ่ม ไม่ตัดทิ้ง) ปรับความละเอียดแกนเวลาอัตโนมัติตามความยาวช่วง (≤31 วัน = รายวัน, ≤~1 ปี = รายสัปดาห์, ยาวกว่านั้น = รายเดือน) กันกราฟมีจุดเป็นร้อยจุดถ้าเลือก "ทั้งหมด" กับข้อมูลหลายปี
2. **(High, แก้พร้อมข้อ 1)** กราฟชั่วโมงพีคเดิมใช้ข้อมูล all-time เสมอ ไม่ตรงกับกราฟแนวโน้ม/แผนที่ข้างๆ ที่ตอนนั้นล็อกไว้ 12 สัปดาห์ ตัวเลขเทียบกันไม่ได้ — ตอนนี้ทั้ง 3 การ์ดใช้ช่วงเวลาเดียวกันจากตัวเลือกด้านบนแล้ว
3. **(High)** กราฟแนวโน้มแยกเส้นตาม `severity` ซึ่งเป็นข้อความอิสระจาก AI vision triage ไม่ใช่ enum — ข้อมูลจริงอาจมีค่าไม่ซ้ำกันเป็นสิบจนกราฟ/legend อ่านไม่ออกและสีเริ่มวนซ้ำ — จำกัดเหลือ 5 เส้นหลัก (ตามจำนวนเคสมากสุด) รวมที่เหลือเป็นเส้น "อื่นๆ"
4. เพิ่มข้อความ "— ไม่มีข้อมูล... —" ให้ทั้ง 3 การ์ดเมื่อไม่มีข้อมูลในช่วงที่เลือก (เดิมไม่มีเลยสักการ์ด ต่างจากมุมมองอื่นในแอปที่มี empty-state ครบ)
5. **(High)** กด stat-chip "เสร็จสิ้นสะสม" ตอนอยู่แท็บสถิติย้อนหลัง — เดิมเช็คแค่ pending/ongoing ทำให้ chip ติด active เปิดแผง facet ให้กดได้ แต่กราฟ/แผนที่ไม่ขยับตามเลยสักนิด (ควบคุมได้แต่ไม่มีผลจริง) — ตอนนี้ quickFilter ค่าไหนก็ตามจะสลับออกจากแท็บนี้เสมอ เพราะทุกค่าเป็นหมันบนแท็บนี้เท่ากันหมด
6. **(High)** แท็บบาร์ 4 แท็บไม่มี layout รองรับจอแคบเลย (ตกหล่นจาก media query ที่จุดอื่นมีครบ) — เพิ่ม `flex-wrap` ให้ขึ้นบรรทัดใหม่แทนล้นจอ/ต้องเลื่อนแนวนอน
7. เพิ่ม Escape ปิด modal/lightbox ได้ (เดิมปิดได้แค่คลิกฉากหลังเท่านั้น)
8. เพิ่ม `required` ให้ช่องประเภทเหตุ/ความรุนแรง/ที่อยู่ในฟอร์มสร้าง-แก้ไขเคส (เดิมกด "บันทึก" ทั้งที่ฟอร์มว่างเปล่าหมดก็ผ่านเงียบๆ)
9. `hideModal()` ไม่มีพารามิเตอร์จริงแต่ทุกจุดเรียกพร้อมส่ง argument (เพราะมี overlay เดียวใช้ร่วมกันโดยตั้งใจ ไม่ใช่บั๊ก แต่หลอกคนอ่านโค้ดว่าเจาะจงเลือก modal ได้) — เอา argument ที่ไม่มีผลออกจากทุกจุดเรียกให้ตรงกับพฤติกรรมจริง

**เว็บ Agency**:
10. **(High)** `EmergencyFleetWebService().dispose()` ถูกเรียกตอน logout แล้วปิด StreamController ของ singleton ถาวร แต่ `initialize()` ถูกออกแบบให้เรียกซ้ำได้ (guard ด้วย `_sub ??=`) — ล็อกเอาต์แล้วล็อกอินใหม่ในแท็บเดียวกัน ตำแหน่งรถพยาบาลจะหยุดอัปเดตถาวรเพราะเขียนลง StreamController ที่ปิดไปแล้ว (ต่างจาก `HospitalLocationService`/`IncidentService` อีกสอง singleton ที่ไม่ถูก dispose แบบนี้) — เอาการเรียก `.dispose()` singleton นี้ออก ให้สอดคล้องกับอีกสอง service
11. **(Medium)** ปุ่มล็อกอินบัญชีจริง (ไม่ใช่ demo) ค้าง spinner ตลอดไปถ้า Firestore error ระหว่างเช็ครหัสผ่าน (จุดเดียวในไฟล์นี้ที่ไม่มี try/catch ทั้งที่ `_tryRestoreSession()` ห่อไว้แล้วพร้อมคอมเมนต์อธิบาย bug class นี้ชัดเจน) — เพิ่ม try/catch ให้ครบ
12. **(Medium)** แดชบอร์ดแยกไม่ออกระหว่าง "ยังโหลดไม่เสร็จ" กับ "โหลดเสร็จแล้วแต่ไม่มีเคสจริงๆ" (ข้อความเดียวกันทั้งคู่) — เพิ่ม `_isLoading` flag แสดง spinner ระหว่างโหลดครั้งแรกแทน
13. เพิ่ม `_disposed` guard กัน subscription ที่สร้างหลัง widget ถูก dispose ไปแล้ว (ระหว่างที่ `_init()` ยังค้างรอ await) รั่วไม่มีวันถูกยกเลิก
14. Dialog แก้ไขตำแหน่ง/ข้อมูลโรงพยาบาล (หัวข้อ 40): เพิ่มตรวจชื่อ/ที่อยู่/เบอร์ ER ว่างก่อนบันทึก (เดิมบันทึกค่าว่างเป็นค่าจริงได้เงียบๆ) และปิด drag/pan ของแผนที่เล็กในนั้น (เหลือแค่ซูม) กันชนกับการ scroll ของ dialog เอง
15. อัปเดตทั้งสอง README ให้พูดถึงฟีเจอร์ใหม่ล่าสุด (สถิติย้อนหลังของเว็บ Data, แก้ไขตำแหน่งโรงพยาบาลของเว็บ Agency) ที่ตกหล่นไปตอนเพิ่มฟีเจอร์เมื่อหัวข้อ 40

**ยังไม่แก้ (ตั้งใจ/ยอมรับความเสี่ยง)**: ระบบล็อกอิน demo (`admin_3`/`12345`) ที่รีวิวชี้ว่า "shipped enabled" เป็นความเสี่ยงถ้า deploy สาธารณะ — **ไม่ปิด** เพราะเป็นฟีเจอร์ที่ผู้ใช้ขอเองโดยตรงให้ใช้งานได้ ไม่ใช่บั๊ก มีสวิตช์ `kEnableAgencyWebDemoLogin` + คำเตือนใน README ไว้แล้วสำหรับวันที่จะ deploy จริง (หัวข้อ 39-40); dialog ยังไม่ sync ข้อมูลสดถ้ามีคนแก้โปรไฟล์เดียวกันจากเครื่องอื่นระหว่างที่ dialog เปิดค้างอยู่ (multi-admin race เล็กน้อย ไม่ likely สำหรับเดโมวิทยานิพนธ์คนเดียว); busy state ของปุ่ม dispatch/ER-toggle เป็น global ไม่ใช่ per-incident (ผลกระทบแคบ กด 2 เคสพร้อมกันจังหวะเดียวกันเป๊ะเท่านั้น)

**ยืนยันด้วย** `flutter analyze` ผ่านทั้ง `route-alert-agency-web` (No issues found), `flutter build web` ผ่านจริง, `node --check js/app.js` ผ่าน, ไล่ตรวจ DOM id/CSS class ของเว็บ Data ครบอีกรอบ, ยืนยัน API `InteractionOptions`/`InteractiveFlag.pinchZoom`/`InteractiveFlag.doubleTapZoom` มีจริงในซอร์ส `flutter_map-6.2.1` ที่ติดตั้งอยู่ (ไม่ได้เดา) — **ไม่ได้รัน adversarial verification ผ่าน agent รอบนี้เพราะชน session limit** ตรวจสอบเองด้วยการอ่านโค้ดโดยตรงแทน ควรพิจารณาทดสอบซ้ำเมื่อ session limit reset ถ้ามีเวลา

## 42. เพิ่มเลือกวันเริ่มต้น-สิ้นสุดแบบกำหนดเองในแท็บสถิติย้อนหลัง

ผู้ใช้ขอเพิ่มจากปุ่มช่วงเวลาสำเร็จรูป (7 วัน/4 สัปดาห์/ฯลฯ) ในหัวข้อ 41 ให้เลือกวันเริ่มต้น-สิ้นสุดเองได้ด้วย — เพิ่ม `<input type="date">` 2 ช่อง ("วันเริ่มต้น"/"วันสิ้นสุด") ต่อจากปุ่มช่วงสำเร็จรูปใน `.history-range-selector` เลือกวันไหนก็ได้จะเข้าโหมด `statsHistoryRange = "custom"` ทันที (ปุ่มสำเร็จรูปทั้งหมดจะเลิก active) และกดปุ่มสำเร็จรูปกลับไปจะเคลียร์ช่องวันที่ทิ้งให้เห็นชัดว่าตัวควบคุมไหนกำลังกำหนดช่วงเวลาที่แสดงอยู่จริง

**พฤติกรรมเมื่อกรอกไม่ครบ**: เลือกแค่วันเริ่มต้น → วันสิ้นสุดใช้ "วันนี้" อัตโนมัติ, เลือกแค่วันสิ้นสุด → วันเริ่มต้นใช้เคสที่เก่าสุดในข้อมูลจริงอัตโนมัติ (เหมือนโหมด "ทั้งหมด"), เลือกวันสิ้นสุดมาก่อนวันเริ่มต้น → สลับให้เองอัตโนมัติ (ไม่ error/ไม่โชว์กราฟว่างเปล่าแบบงงๆ) ช่องวันสิ้นสุดใส่ `max` เป็นวันนี้กันเลือกวันในอนาคตที่ไม่มีความหมาย

รีแฟกเตอร์ `getHistoryWindowStart()`/`getHistoryWindowEnd()` (หัวข้อ 41) รวมเป็นฟังก์ชันเดียว `getHistoryWindow()` คืนค่า `{start, end}` พร้อมกัน เพราะโหมดกำหนดเองต้อง normalize (สลับค่าถ้าเลือกกลับด้าน) ทั้งคู่พร้อมกัน แยกเป็น 2 ฟังก์ชันจะคำนวณซ้ำซ้อน/normalize ไม่ตรงกันได้

**ยืนยันด้วย** `node --check js/app.js` ผ่าน, ไล่ตรวจ DOM id/CSS class ครบ (ไม่มีจุดไหนอ้างถึง `getHistoryWindowStart`/`getHistoryWindowEnd` เดิมหลงเหลืออยู่) — ยังไม่ได้เปิดเบราว์เซอร์จริงทดสอบเพราะข้อจำกัดสภาพแวดล้อมเดิม

## 43. ปรับปรุง Colab notebook เทรน Accident Classifier ให้แม่นขึ้นจริง (นำเสนอวิทยานิพนธ์เสร็จแล้ว รับ feedback มา 3 เรื่อง)

ผู้ใช้แจ้งว่านำเสนอวิทยานิพนธ์เสร็จแล้ว ได้รับ feedback 3 เรื่องที่ต้องแก้เพิ่ม: (1) Multi-hospital ทั้งเว็บและแอป (2) push notification เบื้องหลังทุกฝั่ง (ผู้ใช้/รถพยาบาล/โรงพยาบาล) (3) ปรับปรุงโค้ดเทรนโมเดล AI เช็คอุบัติเหตุให้แม่นขึ้นจริง เอาไปเทรนใน Colab — ทำเฉพาะข้อ 3 ในรอบนี้ก่อน เพราะมีสเปกชัดเจนจากโค้ดที่มีอยู่แล้ว ส่วนข้อ 1-2 เป็นงานสถาปัตยกรรมใหญ่ข้ามหลายโค้ดเบส ถามผู้ใช้ก่อนว่าจะให้เริ่มจากจุดไหน

**พบว่ามี notebook เทรนอยู่แล้ว** ที่ `scripts/train_accident_classifier_colab.ipynb` (ไม่เคยเห็นมาก่อนในเซสชันนี้ น่าจะทำไว้ตั้งแต่รอบก่อนๆ) พร้อม `lib/core/ml/accident_image_classifier_service.dart` ที่รอโหลด `assets/models/accident_classifier.tflite` + `accident_labels.txt` อยู่แล้ว (fallback เป็น heuristic เดิมถ้ายังไม่มีไฟล์โมเดล) — สเปกที่โค้ด Dart กำหนดไว้ตายตัว: input 224×224×3 normalize เป็นช่วง [-1,1] แบบ MobileNetV2, output softmax 2 คลาส, label file เรียงตามตัวอักษร (`accident` มาก่อน `non_accident`)

**ปรับปรุง notebook เดิม (Transfer Learning จาก MobileNetV2 แต่มีแค่ freeze-only ไม่มี fine-tuning จริง) ให้เป็นเวอร์ชันแม่นขึ้นจริงตามที่ขอ**:
1. **เพิ่ม Phase 2 fine-tuning จริง** — ของเดิมมีแค่คอมเมนต์แนะนำไว้เฉยๆ ไม่มีโค้ด เพิ่มการปลดล็อกชั้นบนสุด ~40% ของ MobileNetV2 เทรนต่อด้วย learning rate ต่ำมาก (1e-5) โดย freeze BatchNormalization ไว้เสมอตามคำแนะนำมาตรฐานของ TensorFlow (กันค่าสถิติจาก ImageNet พังจากข้อมูลเราเองที่มีน้อยกว่ามาก) — เป็นขั้นที่ช่วยดัน accuracy ได้มากที่สุดของงานประเภทนี้
2. **เปลี่ยนจาก epoch ตายตัว (15 รอบ) เป็น callback-driven** — EarlyStopping (คืน best weight อัตโนมัติ) + ReduceLROnPlateau ทั้ง 2 phase ตั้ง epoch สูงไว้พอ (30) แล้วปล่อยให้หยุดเองเมื่อไม่ดีขึ้นแล้วจริงๆ ตรงกับที่ผู้ใช้บอกว่า "เทรนกี่นาทีก็ได้" ไม่ต้องเดาจำนวน epoch เอง
3. **เพิ่ม class weight อัตโนมัติ** จากจำนวนรูปจริงต่อคลาส (ของเดิมไม่มีเลย) — สำคัญเพราะ false negative ของ "accident" คือพลาดเคสฉุกเฉินจริง อันตรายกว่าทายผิดฝั่งตรงข้ามมาก
4. **เพิ่มขั้นตอนกรองไฟล์ภาพเสีย/เปิดไม่ได้ทิ้งก่อนเทรน** (ใช้ PIL `.verify()`) — ปัญหาที่พบบ่อยเวลารวบรวมรูปจำนวนมากจากหลายแหล่ง ("หลายๆรูป" ตามที่ผู้ใช้ขอ) เดิมไม่มีเลย จะพังกลางทางตอนกำลังเทรนพอดี
5. **ขยาย data augmentation** เพิ่ม RandomContrast/RandomTranslation นอกจาก flip/rotation/zoom เดิม ช่วยให้ทนต่อสภาพแสง/มุมกล้องของภาพอุบัติเหตุจริงที่ถ่ายจากมือถือกลางถนน
6. **เพิ่มการประเมินผลแบบเต็ม** — classification report (precision/recall/F1 ต่อคลาสจาก scikit-learn), confusion matrix แบบกราฟ, ตัวอย่างภาพที่ทำนายผิดให้ดู — ของเดิมมีแค่ accuracy ตัวเดียวซึ่งหลอกตาได้ง่ายถ้าข้อมูล 2 คลาสไม่เท่ากัน ตรงตามที่ขอ "แม่นจริงๆ" ต้องพิสูจน์ได้ด้วยตัวเลขที่ละเอียดกว่านั้น
7. **เพิ่มขั้นตอนตรวจสอบไฟล์ TFLite ที่ export ออกมา** — โหลดกลับมารันเทียบกับโมเดล Keras ต้นฉบับบนภาพชุดเดียวกัน ถ้าผลตรงกันหมดแปลว่า export ถูกต้อง ของเดิม export แล้วดาวน์โหลดไปใช้เลยโดยไม่เคยตรวจสอบว่า conversion พังเงียบๆ หรือเปล่า
8. **คง dynamic-range weight quantization (ไม่ใช่ full integer quantization)** อย่างตั้งใจ — ต้อง float32 input/output เท่านั้น เพราะโค้ด Dart ฝั่งแอปส่ง/อ่านค่าเป็น float ตรงๆ ไม่ได้ทำ dequantize เอง ถ้า quantize input/output ด้วยแอปจะพังทันทีตอนรันบนมือถือ

**ไม่ได้แตะ**: ส่วน "เช็คภาพว่า AI สร้างขึนมาก่อนไหม" ที่ผู้ใช้พูดถึง — ผู้ใช้บอกเองว่าส่วนนี้ "ใช้โมเดลอื่นได้" (ไม่ต้องเทรนเอง) ต่างจากส่วน accident/non-accident ที่ระบุชัดว่า "ส่วนนี้คือส่วนที่ให้เทรนเอไอ" จึงโฟกัส notebook นี้เฉพาะส่วนเทรนที่ขอจริงๆ

**ยืนยันด้วย** parse notebook JSON ผ่าน (`nbformat` ถูกต้อง), รัน `ast.parse()` ตรวจ syntax Python ของทุก code cell ผ่านหมด (ไม่มี error), ตรวจสอบ metadata/accelerator (GPU) ของ Colab คงไว้ตามเดิม — **ยังไม่ได้รันจริงใน Colab เพราะต้องใช้ dataset จริงของผู้ใช้และเวลาเทรนหลายนาที** ผู้ใช้ควรลองรันเองก่อนนำไปใช้งานจริง

## 44. แก้บั๊ก 3 จุดระหว่าง notebook เทรน AI กับแอป (ก่อนเทรนจริง)

- **แอปจัด non_accident เป็นอุบัติเหตุเสมอ** (`accident_image_classifier_service.dart`) — เช็ค `label.contains('accident')` ซึ่ง "non_accident" ก็มีคำนี้อยู่ จึงเพิ่มเงื่อนไขกันคำขึ้นต้นด้วย `non`
- **Normalize ภาพซ้ำ 2 รอบ** — โมเดลจาก notebook มี `preprocess_input` อยู่ในตัวแล้ว แต่แอปแปลงพิกเซลเป็น [-1, 1] ก่อนส่งอีกรอบ ทำให้ผลทำนายเพี้ยน เปลี่ยนให้แอปส่งค่าพิกเซลดิบ 0-255 ตรงกับที่ notebook ใช้ตรวจความถูกต้องของไฟล์ TFLite
- **แตก zip ผิดโครงสร้าง** (cell 2 ของ notebook) — ถ้า zip มีโฟลเดอร์ครอบ `dataset/` หรือมี `__MACOSX` จาก Mac จะได้คลาสผิด เปลี่ยนเป็นค้นหาโฟลเดอร์ `accident/` + `non_accident/` เองอัตโนมัติ
- ตัวอ่าน label รองรับรูปแบบ `0 accident` ด้วย (ตัดเลขนำหน้าทิ้ง)

## 45. Multi-hospital — หลายโรงพยาบาลใช้ระบบร่วมกัน (แอป + เว็บทั้งสอง)

ของเดิมมี nearest-hospital (Haversine) ที่ถูกต้องอยู่แล้วตอนสร้างเคส แต่ปลายทางทุกจุดผูกตายตัวกับ `HOSP-01`

**แอปมือถือ**
- `HospitalLocationService` — `loadAllHospitals()` ดึงรายชื่อโรงพยาบาลทั้งหมดจาก `hospital_profiles` แบบ realtime (เก็บ 4 โรงพยาบาลเดิมไว้เป็น seed กรณี Firestore ว่าง), `initialize({hospitalId})` ไม่มีค่า default แล้ว, `createHospital()` ใหม่, cache ใน SharedPreferences แยกตามโรงพยาบาล
- `UserFaceProfile` เพิ่ม `hospitalId` (เฉพาะ agency) — `FaceAuthRepository.updateHospitalId()`
- **แก้บั๊ก:** `dispatchIncidentByHospital()` เคยเขียนทับโรงพยาบาลเป้าหมายของเคสด้วยโรงพยาบาลของ agency ที่กดมอบหมาย — ตัดออก เหลือแค่เตือนใน log ถ้าไม่ตรง
- หน้าใหม่ `HospitalSetupScreen` — สมัคร agency ใหม่ต้องปักหมุด/กรอกข้อมูลโรงพยาบาลก่อนใช้งาน (ย้อนกลับไม่ได้)
- หน้า agency (home / รายการเคส / โปรไฟล์) กรองเคสเฉพาะ `targetHospitalId` ของตัวเอง — แก้ race condition ตอน init ให้โหลดบัญชีก่อนแล้วค่อยกรอง
- ฝั่งผู้ใช้/รถพยาบาลแสดงโรงพยาบาลที่ใกล้ที่สุดจริงตาม GPS (รถพยาบาลที่มีเคสใช้โรงพยาบาลเป้าหมายของเคสนั้น)

**เว็บ Agency** — `WebAuthResult.hospitalId` ส่งต่อเข้า dashboard, กรองเคสตามโรงพยาบาล, ตัด parameter เขียนทับโรงพยาบาลตอน dispatch

**เว็บ Data** — `js/hospitals.js` ใหม่ (CRUD `hospital_profiles`), แท็บ "🏥 จัดการโรงพยาบาล", ตัวกรอง/facet "โรงพยาบาล"

## 46. แจ้งเตือนเบื้องหลัง (Push Notification) ทุก role — แม้ปัดแอปปิดไปแล้ว

**ฝั่งแอป**
- เพิ่ม `firebase_messaging`, ลงทะเบียน background handler ใน `main.dart`
- `PushNotificationService` — ขอสิทธิ์, บันทึก token ลง `users/{email}.fcmToken`, แสดง local notification ตอนเปิดแอปอยู่ เรียกจากทุกเส้นทางล็อกอิน (cold-start, login, สมัคร agency ใหม่) ถ้าสลับบัญชีบนเครื่องเดิมจะย้าย token ไปบัญชีใหม่ และ retry ได้ถ้า Firebase ยังไม่พร้อมตอนเปิดแอป
- logout ลบ token ออกจากบัญชี (เฉพาะถ้ายังเป็น token ของเครื่องนี้) — กันบัญชีเก่ายังได้แจ้งเตือนเข้าเครื่องที่คนอื่นใช้อยู่
- รหัสหน่วยรถพยาบาล (`AMB-xxxx`) เดิมอยู่ในเครื่องเท่านั้น — บันทึกลง `users/{email}.ambulanceUnitId` ด้วย (ตอนล็อกอินและตอนแก้โปรไฟล์) เซิร์ฟเวอร์จะได้หาเครื่องของรถที่ได้รับมอบหมายเจอ
- `dispatchIncidentByHospital()` เขียน `assignedBy: 'hospital' | 'ambulance'` เพิ่ม

**ฝั่งเซิร์ฟเวอร์** — `functions/index.js` (Node 22, Cloud Functions v2, region asia-southeast1) + `.firebaserc` + block `functions` ใน `firebase.json`
- `notifyNewIncident` — เคสใหม่ → agency ของโรงพยาบาลเป้าหมาย (และ agency ที่ยังไม่ผูกโรงพยาบาล) + รถพยาบาลทุกคัน
- `notifyIncidentUpdate` — มอบหมายรถ → รถคันนั้น (ยกเว้นรถกดรับเอง) + ผู้แจ้งเหตุ; เคสจบ (`resolved`) → ผู้แจ้งเหตุ
- ใช้ Android channel เดียวกับแอป (heads-up), กันส่งซ้ำเครื่องเดียวกัน, ลบ token ที่ใช้ไม่ได้แล้วออกอัตโนมัติ
- ทดสอบ logic การเลือกผู้รับ 6 กรณีด้วย stub ผ่านหมด, `firebase deploy --dry-run` ผ่านจนถึงขั้นต้องเปิด Blaze plan

**สิ่งที่ต้องทำเองก่อนใช้งานจริง:** เปิด Blaze plan → `firebase deploy --only functions`; iOS ต้องเปิด Push Notifications capability ใน Xcode และอัปโหลด APNs Key ใน Firebase Console

## 47. ตัวสั่งส่งแจ้งเตือนบน Cloudflare Workers (ไม่ต้องเปิด Blaze plan)

ผู้ใช้ไม่อยากผูกบัตรเพื่อเปิด Blaze — FCM เองฟรีบน Spark อยู่แล้ว ที่ติดคือ Cloud Functions จึงย้ายตัวสั่งส่งไป Cloudflare Workers (ฟรี ไม่ต้องใช้บัตร) โดยเก็บ `functions/` ไว้เป็นทางเลือก (ใช้ได้ทีละอย่าง)

- `push-worker/src/index.js` — รับ `{incidentId}` → ขอ access token จาก service account (เซ็น JWT ด้วย WebCrypto) → อ่านเคสผ่าน Firestore REST → ตัดสินใจเอง (`planNotifications`) → ส่ง FCM HTTP v1 ไม่มี dependency ภายนอก
- กันส่งซ้ำ/กันคนนอกสแปม: จด `pushLog` ในเคสก่อนส่ง แบบมีเงื่อนไข `updateTime` (สองคำขอพร้อมกันจะส่งแค่ชุดเดียว), เคสเก่าที่มีอยู่ก่อนเปิดระบบจะไม่ส่งย้อนหลัง, ตรวจรูปแบบ `incidentId`
- ลบ token ที่ใช้ไม่ได้แล้วออกอัตโนมัติ, จำกัด 40 เครื่องต่อครั้ง (ลิมิต subrequest แพลนฟรี)
- แอป: `lib/core/services/push_trigger.dart` (`kPushWorkerUrl` ว่าง = ปิด) เรียกจาก `IncidentService` หลังสร้างเคส/มอบหมายรถ/ปิดเคสสำเร็จ — เว็บ Agency ได้ไปด้วยเพราะใช้ `IncidentService` ร่วมกัน
- เว็บ Data: `notifyPush()` ใน `js/incidents.js` หลังสร้างเคสและตอนแก้สถานะเป็น resolved/มอบหมายรถ (`PUSH_WORKER_URL` ใน `firebase-config.js`)
- ทดสอบ: จำลอง Google OAuth (ตรวจลายเซ็น JWT จริง) + Firestore REST + FCM ครบ 15 กรณีผ่านหมด, `wrangler deploy --dry-run` bundle ได้ 13.6 KB, `flutter analyze`/`flutter test` 27/27, `flutter build web` (Agency) ผ่าน
- วิธี deploy: `push-worker/README.md`

## 48. แจ้งเตือนแบบแอปดัง: กดแล้วเปิดหน้าเคส, 1 เคส = 1 แจ้งเตือน, ปุ่มบนแจ้งเตือน, แจ้งรถใกล้ถึง

**เจอระหว่างทำ:** บัญชี Apple บนเครื่องที่ใช้ build เป็นบัญชีฟรี (provisioning profile หมดอายุ 7 วัน ไม่มี `aps-environment`) → iPhone รับ remote push ไม่ได้ไม่ว่าจะใช้ตัวส่งแบบไหน จึงเพิ่ม "ตัวแจ้งเตือนสำรองในเครื่อง" ให้ iPhone ได้แจ้งเตือนแบบเดียวกันตลอดที่แอปยังไม่ถูกปัดทิ้ง (แอปมีโหมด location เบื้องหลังอยู่แล้ว) ส่วน Android ได้ครบแม้ปัดแอปทิ้ง

**รูปแบบข้อความใหม่ (Worker + Cloud Functions)**
- Android ได้แบบ data-only (`incidentId, kind, audience, title, body`) ให้แอปวาดแจ้งเตือนเอง — จึงใส่ปุ่มและทับอันเดิมได้ / iOS ได้แบบ alert ที่มี `apns-collapse-id` และ `thread-id` = รหัสเคส
- เหตุการณ์ใหม่ `ambulance_near` (รถใกล้จุดเกิดเหตุ < 500 ม. → ผู้แจ้ง) และ `case_taken` (มีรถรับเคสแล้ว → สั่งลบ "มีเคสใหม่รอรับ" ที่ค้างในเครื่องรถคันอื่น รวมถึงคันที่กดรับเอง)
- Cloud Functions เปลี่ยนเป็น trigger เดียว `onDocumentWritten` + จอง pushLog ใน transaction ให้ตรรกะเดียวกับ Worker ทุกอย่าง
- ทดสอบ: สถานการณ์เดียวกัน 12 ขั้นรันผ่านทั้ง Worker และ Functions ได้ผลตรงกันทุกข้อความ + ตรวจรูปแบบข้อความ/JWT/คำขอพร้อมกัน/validation

**แอป**
- `notification_intent.dart` — ค่ากลางของโปรโตคอล, id แจ้งเตือนคงที่ต่อเคส (สถานะใหม่ทับอันเก่า), ตัวกลางส่งต่อการกดแจ้งเตือน
- `CriticalNotificationService` — ช่องใหม่ "อัปเดตสถานะเคส", ปุ่มบนแจ้งเตือน (iOS category), รับการกด/เปิดแอปจากแจ้งเตือน, ไม่ขอสิทธิ์ตอนเปิดแอป (กัน Firebase ค้างรอกล่องขอสิทธิ์) — แจ้งเตือนเรดาร์เดิมไม่เปลี่ยน
- `IncidentNotificationPresenter` — แปลงข้อมูลเป็นแจ้งเตือน ใช้ได้ทั้งตอนแอปเปิดและใน isolate เบื้องหลังของ FCM
- `LocalIncidentNotifier` — ตัวแจ้งเตือนสำรอง (ตรรกะเดียวกับ Worker กรองเฉพาะผู้ใช้เครื่องนี้) เปิดเมื่อเครื่องรับ push ไม่ได้ หรือยังไม่ได้ตั้งค่าตัวส่ง
- `NotificationRouter` — กดแจ้งเตือน → หน้าเคสของ role นั้น (agency/รถพยาบาล/ผู้แจ้ง), กดตอนแอปปิดสนิทก็รอจนผ่านหน้าโหลด/ล็อกอินแล้วค่อยเปิด, เช็คว่าแจ้งเตือนเป็นของบัญชีที่ล็อกอินอยู่
- ปุ่ม **รับเคส** (`AmbulanceCaseActions`, ใช้ร่วมกับปุ่มในรายการเคส) เช็คสถานะล่าสุดก่อน + รับเคสแบบ transaction ให้คันแรกที่กดได้เคส (เดิมกดพร้อมกันจะเขียนทับกัน) / ปุ่ม **ส่งรถพยาบาล** เปิดหน้าเคสแล้วมอบหมายรถใกล้สุดให้เอง (รอรายชื่อรถจาก MQTT ได้ถึง 8 วิ)
- รถพยาบาลบันทึก `ambulanceNearSceneAt` ครั้งเดียวต่อเคสเมื่อระยะตามถนนเหลือไม่ถึง 500 ม.
- แก้ race: ตอนเปิดแอป push registration อาจรันก่อน Firebase พร้อม → รอ Firebase ก่อน (ไม่งั้น Android จะเปิดตัวสำรองซ้อนกับ push จริง)
- Native: Android เพิ่ม `ActionBroadcastReceiver`, iOS ตั้ง `UNUserNotificationCenter` delegate ใน `AppDelegate.swift`
- เทสต์ใหม่ 17 ข้อ (โปรโตคอล, ตรรกะตัวสำรองทุก role, presenter, สิทธิ์ของ router) รวมเป็น 44 ผ่านทั้งหมด

**แก้จากรีวิวอิสระ (8 ข้อ ก่อนผู้ใช้ทดสอบ)**
- 🔴 Worker ปฏิเสธรหัสเคสจากแอป (`Case #AVCB…` มีช่องว่าง/#) → รับทุก document id ที่ไม่มี `/` และ encode ใน URL — ถ้าไม่แก้ Android จะไม่ได้แจ้งเตือนเคสที่แจ้งจากแอปเลยสักเคส
- 🔴 `createdAt` จากแอปเป็นเวลาไทยไม่มี timezone เซิร์ฟเวอร์ (UTC) อ่านเป็นอนาคต 7 ชม. → "เคสใหม่" ไม่ถูกส่ง — เปลี่ยนไปวัดความใหม่จาก `createTime` ของ Firestore เอง (ทั้ง Worker และ Functions)
- รับเคส/ส่งรถ: ใช้ transaction ทั้งสองทาง (agency กด "ส่งรถพยาบาล" ไม่ทับรถที่กดรับเคสไปแล้ว), กดซ้ำ = สำเร็จ, ล้มเหลวแล้วอ่านสถานะจริงจากเซิร์ฟเวอร์มาแก้เฉพาะเคสนั้น (เดิมเขียนทั้งรายการเก่ากลับไปทับ), timeout แต่ commit แล้วถือว่าสำเร็จ, กันกดซ้ำระหว่างรอผล, agency เห็นข้อความ "มีรถรับไปแล้ว" แทน "เช็คอินเทอร์เน็ต"
- Worker: ถ้ามีฟิลด์อื่นเปลี่ยนระหว่างอ่าน-เขียน pushLog อ่านใหม่แล้วลองอีก (สูงสุด 3 รอบ) แทนการทิ้งแจ้งเตือน; `apns-collapse-id` ตัดตามไบต์
- ตัวแจ้งเตือนสำรอง: ไม่ตัด log ของเคสที่ยังอยู่ (เดิมเกิน 300 เคสจะแจ้งเตือนซ้ำ)
- token: ลงทะเบียนแล้วลบ token เดียวกันออกจากบัญชีอื่น (กันเครื่องได้แจ้งเตือนของบัญชีเก่า)
- ข้อจำกัดที่ยังเหลือ (iOS): แอปใช้ UIScene lifecycle ซึ่ง firebase_messaging 15.x ตั้งค่าตัวเองไม่ทัน → iOS remote push ใช้ไม่ได้แม้มีบัญชี Apple แบบเสียเงิน ต้องอัปเกรดชุด Firebase (core 4 / firestore 6 / messaging 16) ภายหลัง — ไม่กระทบตอนนี้เพราะ iPhone ใช้ตัวแจ้งเตือนสำรองอยู่แล้ว
- ทดสอบ: push test 14 ขั้น (เพิ่มรหัสเคสแบบแอป + เวลาไม่มี timezone + ฟิลด์เปลี่ยนระหว่างทาง), flutter test 44/44, `flutter build ios --no-codesign` ผ่าน, Agency web build ผ่าน (APK build ไม่ได้เพราะเครื่องนี้ไม่มี Android SDK — ตรวจ manifest ด้วย XML parser แทน)

## 49. GPS เบื้องหลังของรถพยาบาล + ETA รถพยาบาลบนหน้าล็อก / Dynamic Island (ใช้บัญชี Apple ฟรีได้)

ผู้ใช้ต้องการแบบฟรี (ไม่มี push บน iPhone) จึงออกแบบให้ทุกอย่างอัปเดตจากแอปเองทั้งหมด

**รถพยาบาล** (`ambulance_home_screen.dart`)
- เข้าเวร = GPS ทำงานต่อแม้พับแอป/ล็อกจอ (Android เป็น foreground service ข้อความ "กำลังส่งตำแหน่งรถพยาบาลให้ศูนย์สั่งการ", iOS แสดงไอคอนตำแหน่งสีฟ้า) พักเวร = เฉพาะตอนเปิดแอป สลับทันทีเมื่อเปลี่ยนสถานะเวร
- ส่ง ETA/ระยะตามถนน (`ambulanceEtaMinutes`, `ambulanceDistanceMeters`, `ambulanceEtaTarget` scene|hospital, `ambulanceEtaUpdatedAt`) ขึ้น Firestore เมื่อค่าเปลี่ยน (ห่างกัน ≥ 10 วิ) + heartbeat ทุก 60 วิแม้รถจอดนิ่ง — เขียนเฉพาะ Firestore ไม่แตะ stream ในเครื่อง (กันวนไม่จบ)
- จำกัดการขอเส้นทาง OSRM ไม่เกินทุก 4 วิ (เดิมขอทุกครั้งที่ GPS ขยับ 3 ม. ≈ หลายครั้งต่อวินาที) และทิ้งผลที่ตอบกลับช้าหลังเปลี่ยนช่วงเดินทาง
- OSRM ล่ม: เดิม ETA ตายตัว 2 นาทีไม่ว่าไกลแค่ไหน → ประมาณจากระยะ (เส้นตรง × 1.4 ที่ 45 กม./ชม.) และไม่เอาค่าประมาณไปทับค่าจริงที่ส่งไปแล้ว

**ผู้แจ้งเหตุ** (`live_tracking_service.dart`)
- เลือกเคสล่าสุดที่ตัวเองแจ้งและยังไม่จบ → แสดงสถานะสด: รอยืนยัน → รถกำลังมา (ETA/ระยะ/แถบความคืบหน้า) → ใกล้ถึง → ถึงแล้ว → กำลังนำส่ง รพ. (ETA ถึง รพ.) → จบ (ค้างสถานะสุดท้าย 4 นาที)
- iOS: Live Activity (หน้าล็อก + Dynamic Island บน iPhone 14 Pro ขึ้นไป) / Android: แจ้งเตือนค้างพร้อมแถบความคืบหน้าบนช่องเงียบ
- ระหว่างมีเคสที่รออยู่ หน้าผู้ขับขี่เปิด GPS เบื้องหลังให้เอง (`keepAlive`) แอปจะได้ไม่ถูก iOS หยุดและ ETA ขยับต่อได้ตอนพับแอป
- ETA ที่ไม่อัปเดตเกิน 3 นาทีจะถูกซ่อน + หน้าล็อกขึ้น "กำลังรอตำแหน่งล่าสุดของรถ", กันนาฬิกาต่างเครื่อง, เคส pending ที่ไม่มีใครรับเกิน 2 ชม. ไม่ติดตาม
- ล้าง Live Activity/แจ้งเตือนติดตามที่ค้างจากรอบก่อนตอนเปิดแอป/สลับเคส/logout, ผู้ใช้ปัด Live Activity ทิ้งเองจะไม่สร้างกลับมา, เรียก native ทีละคำสั่งกันซ้ำ

**iOS native**
- ส่วนเสริมใหม่ `ios/RouteAlertLiveActivity/` (Widget Extension, iOS 16.2+) — หน้าล็อกและ Dynamic Island ออกแบบเอง: ตัวเลข ETA ใหญ่, สีตามสถานะ, แถบเส้นทางที่รถขยับเข้าหาหมุด
- `ios/Runner/LiveActivityBridge.swift` (MethodChannel `com.routealert/live_activity` → ActivityKit), `NSSupportsLiveActivities` ใน Info.plist
- เพิ่ม target ด้วยสคริปต์ (xcodeproj gem) ไม่ต้องคลิกใน Xcode — ฝังก่อน "Thin Binary" กัน build cycle, bundle id `com.example.routeAlert.LiveActivity`
- ใช้ ActivityKit ตรงๆ ไม่ผ่าน plugin เพราะ plugin ส่วนใหญ่ต้องใช้ App Groups

**ตรวจสอบ**: flutter test 54/54, `flutter build ios --no-codesign` ผ่าน (มี `RouteAlertLiveActivity.appex` ในแอป), เว็บ Agency build ผ่าน, รีวิวอิสระ 1 รอบ แก้ครบ 9 ข้อ (ข้อหลัก: ETA ปลอมตอน OSRM ล่ม, แจ้งเตือนติดตามค้างบน Android) — ยังต้องยืนยันบนเครื่องจริง: Live Activity เริ่มได้, แอปรันเบื้องหลังต่อด้วย GPS, การวางตัวอักษรไทยบน Dynamic Island

## 50. ใช้โมเดลที่เทรนเองเป็นหลัก + แก้ช้า + notebook v2 (แก้ "หน้าคน = อุบัติเหตุ")

**โมเดลที่ผู้ใช้เทรนมา** (EfficientNetV2-L 384px, 470 MB) ใส่ใน `assets/models/` แล้ว — มี rescaling ในตัว รับภาพดิบ 0-255 ตรงกับแอป
- ลำดับใหม่ใน `AiVisionTriageService`: โมเดลที่เทรนเองตัดสิน "อุบัติเหตุหรือไม่" ก่อนเสมอ (เดิมเรียก Gemini ก่อนถ้ามี key โมเดลที่เทรนเองไม่เคยถูกใช้) — Gemini เป็นปุ่ม "ประเมินละเอียดด้วย Gemini (ไม่บังคับ)" แสดงผลสองโมเดลคู่กันว่าเห็นตรงกันไหม
- เลิกเดาความรุนแรงจากสูตรความคมชัดของภาพ (เดิมรูปหน้าคนชัดๆ กลายเป็น "วิกฤต") — ให้ผู้แจ้งเลือกเองหรือกด Gemini
- ยืนยันก่อนส่ง SOS (สรุปประเภท/ความรุนแรง/ผล AI, เตือนชัดถ้า AI ไม่พบอุบัติเหตุ แต่ยังส่งได้)
- แก้ช้า: วิเคราะห์ภาพใน isolate แยก (เดิมรันบน UI thread หน้าจอค้าง), ส่งพิกเซลเป็นก้อน byte เดียว (เดิม List ซ้อนกันถูกแปลงทีละค่า ~440,000 ค่าต่อรูป), โหลดโมเดลล่วงหน้าตอนเปิดหน้าแจ้งเหตุ, ใช้ 4 threads

**ตรวจโมเดลบน Mac กับ dataset จริง**: รูปใน dataset ถูก 50/50 แต่รูปคนที่ไม่เคยเห็นได้ P(อุบัติเหตุ) 0.60-0.90 — สาเหตุคือ `non_accident` มีแต่รถยนต์สภาพดีทั้งหมด (dataset bias ไม่ใช่บั๊กของแอป)

**`scripts/train_accident_classifier_v2_colab.ipynb`** (notebook เดิมของผู้ใช้ไม่แตะ)
- เพิ่มรูป non_accident อัตโนมัติจาก TensorFlow Datasets: หน้าคน (LFW) + สิ่งของ/ยานพาหนะสภาพปกติ (Caltech-101) และแยกหน้าคนชุดหนึ่งไว้ทดสอบว่าแก้ปัญหาเดิมได้จริง
- EfficientNetV2-B0 224px (`include_preprocessing=True` รับภาพดิบ 0-255), 2-phase fine-tune, class weight, dynamic-range quantization → ~6-7 MB float32 I/O
- ไม่ติดตั้ง tensorflow ทับของ Colab (กัน GPU พัง)
- ทดสอบรันจริงทุกเซลล์บน Mac (TF 2.21, dataset ย่อ): เจอและแก้ 2 บั๊ก (LFW label เป็นชื่อคนไม่ใช่ตัวเลข, เช็ค TFLite ด้วย argmax ให้ผลหลอกตอนโมเดลยังไม่แน่นอน → เทียบความน่าจะเป็นแทน)

**Live Activity**: เริ่มตัวติดตามก่อนขั้นตอน FCM (บน iPhone บัญชีฟรีอาจค้าง), ใส่ timeout ให้ requestPermission, แสดงเหตุผลบนจอถ้าเปิดไม่ได้ (เดิมกลืน error เงียบ) — ปุ่มทดสอบแจ้งเตือนเบื้องหลังรอ 8 วิให้พับแอปก่อน + แก้บั๊กไม่เคยขอสิทธิ์แจ้งเตือน
- เปลี่ยน bundle id iOS เป็น `com.yuttapat.routealert` (ชื่อเดิม `com.example.routeAlert` ถูกทีมอื่นจองไปแล้ว)

## 51. ตรวจภาพ 2 ด่านตาม feedback อาจารย์: ภาพ AI หรือไม่ → อุบัติเหตุจริงหรือไม่

- **ด่าน 1 (Gemini):** ถามว่าแต่ละภาพสร้าง/แก้ด้วย AI หรือไม่ (ดูตัวอักษร/ป้ายทะเบียนบิดเบี้ยว มือ-หน้า-รถผิดรูป แสงเงาไม่สอดคล้อง ผิวเนียนแบบพลาสติก ลายน้ำเครื่องมือ AI) ตอบ JSON พร้อมความมั่นใจและเหตุผลภาษาไทย — มั่นใจ ≥ 70% ว่าเป็นภาพ AI = หยุดตรงนี้ ขึ้นการ์ด "ภาพนี้อาจสร้างด้วย AI" (ส่ง SOS ได้อยู่ แต่เคสจะติดป้าย `[⚠️ ภาพอาจสร้างด้วย AI]` ให้โรงพยาบาลเห็น) — ไม่มี key/ออฟไลน์ = ข้ามด่าน 1 พร้อมบอกบนการ์ด ไม่ขวางการแจ้งเหตุ
- **ด่าน 2 (โมเดลที่เทรนเอง):** ตรวจว่าเป็นอุบัติเหตุจริงเฉพาะภาพที่ผ่านด่าน 1
- เก็บผลด่าน 1 ต่อชุดภาพ กด "ประเมินละเอียดด้วย Gemini" ซ้ำไม่เรียกซ้ำ
- ทดสอบกับ Gemini จริง: ภาพอุบัติเหตุจริงจาก dataset → "ภาพถ่ายจริง" (85%), กราฟิก/infographic ที่สร้างด้วยเครื่องมือ → "สร้างด้วย AI" (90-95%) + เทสต์ตรรกะด่าน 1 (flutter test 59/59)

## 52. แก้บั๊กจากการทดสอบบนเครื่องจริง (รถพยาบาลแอปเด้ง, บัญชีเดียวหลายเครื่อง, ติดตามเคส) + ปิดเคส/ปักหมุด

- **รถพยาบาลรับเคสแล้วแอปเด้งออกทันทีและเปิดไม่ได้อีก** (ดึง crash log จากเครื่องจริงด้วย `devicectl`): `emergency_mqtt_service.dart` เขียนตำแหน่งรถลง Firestore พร้อม `routePoints` เป็น array ซ้อน array `[[lat,lng],…]` ซึ่ง Firestore ไม่รองรับ → SDK iOS โยน exception ปิดแอป (และพังซ้ำทุกครั้งที่เปิดเพราะยังมีเคสค้าง) → เก็บเป็น `{lat, lng}` ไม่เกิน 200 จุด, ฝั่งอ่านรองรับทั้ง 2 แบบ + เทสต์กันถอยหลัง / ที่ "เปิดไม่ได้อีก" เพราะแอป Debug ของ Flutter เปิดจากหน้าโฮมไม่ได้ถ้าไม่ต่อ Xcode → ติดตั้งแบบ Release
- **บัญชีรถพยาบาลเดียวกันใช้คนละเครื่องแล้วเห็นเคสตัวเองเป็น "ของหน่วยอื่น"**: รหัสหน่วย (AMB-xxxx) เดิมสุ่มแยกต่อเครื่อง → ผูกกับบัญชีแทน (`AmbulanceStorageService.syncWithAccount`: บัญชีมีหน่วยแล้วใช้ของบัญชี ยังไม่มีใช้ของเครื่อง, ข้อมูลเก่าที่เครื่องนี้ถือเคสค้างอยู่ภายใต้รหัสเดิมให้รหัสเครื่องนี้ชนะ เคสไม่หาย) ซิงก์ทันทีหลังล็อกอิน และทุกหน้าของรถพยาบาลอัปเดตรหัสหน่วยสดเมื่อเปลี่ยน
- **ติดตามสถานะย้อนหลังไม่ได้**: หน้าติดตามเคสของผู้แจ้งอัปเดตสดจาก Firestore (เดิมแสดงข้อมูล ณ ตอนเปิด), แท็บ "รายงานของฉัน" แสดงประวัติทั้งหมดรวมเคสที่จบ/ยกเลิก (เคสที่ยังไม่จบขึ้นก่อน), เทียบอีเมลไม่สนตัวพิมพ์เล็ก-ใหญ่
- **โรงพยาบาลกด X ที่เคส**: มีกล่องยืนยัน — "ปิดเคส (ทุกฝั่ง)" ตั้ง `cancelled` + `cancelledBy: hospital` ทุกฝั่งไม่เห็นอีก (เตือนถ้ามีรถกำลังไป) หรือ "ซ่อนเฉพาะเครื่องนี้" แบบเดิม
- **ปักหมุดโรงพยาบาล**: ปุ่ม 📍 ไปตำแหน่งปัจจุบันทั้งหน้าแก้หมุดและหน้าตั้งค่าตอนสมัคร (หน้าตั้งค่าเปิดมาที่ตำแหน่งปัจจุบันเลย) ใช้ `getCurrentLocationOrNull` ที่ไม่คืนพิกัดปลอมตอนหาไม่เจอ
- เปลี่ยน bundle id iOS เป็น `com.yuttapat.routealert` (ของเดิมถูกทีมอื่นจองไว้)

## 53. ทดสอบหลายผู้ใช้พร้อมกัน (ตามที่อาจารย์ขอ)

**`tools/multi_user_sim/`** — ตัวจำลองผู้ใช้หลายคนพร้อมกัน (Node + Firebase JS SDK + MQTT) ผู้ใช้จำลองแต่ละคนใช้ Firebase app แยกกันเหมือนมือถือคนละเครื่อง ทำตามตรรกะเดียวกับโค้ดแอปทุกขั้น (สูตรระยะทาง `latlong2` Vincenty ปัด กม. เต็ม + ลำดับ ER ว่างก่อน, transaction รับเคส, busy set แบบ optimistic cache, ETA/ใกล้ถึง/ขั้นสถานะ, MQTT 3.1 QoS 1 + ล้างรถที่เงียบเกิน 12 วิ)
- 5 สถานการณ์: `burst` (แจ้งพร้อมกัน 20 คน), `race` (รถ 5 คันแย่งรับเคสเดียว 10 รอบ — ยืนยันว่าแย่งกันจริงใน transaction), `isolation` (3 โรงพยาบาลเห็นเฉพาะเคสตัวเอง), `lifecycle` (10 เคสครบวงจรพร้อมกัน กองรถผ่าน MQTT), `risks` (สาธิตจุดเสี่ยง) + `cleanup`
- ผลบน Firestore emulator (รัน `all` 2 รอบติดกัน): ผ่าน 18 ข้อ · ไม่ผ่าน 0 · วัดค่า 3 ข้อ (+ ตรวจรูปแบบข้อมูลจำลอง 5 ข้อ ไม่นับเป็นผลทดสอบ), ล้างข้อมูลจำลองเหลือ 0, ใช้ ~520 เขียน / ~7,300 อ่าน — รายงานภาษาไทยใน `results/report-*.md`
- ปรับตามผู้ตรวจอิสระ: `risks` วัดเป็น "ช่วงเวลาเสี่ยง" (ห่างกัน 0–1600 ms) แทนอัตราการเกิด, ล้างข้อมูลใน `finally` + Ctrl-C, ข้อตรวจรูปแบบข้อมูลแยกจากข้อผ่าน, วัดเวลาที่เครื่องผู้แจ้งเจ้าของเคสเห็นจริง, เจ้าหน้าที่ใช้เวลาตัดสินใจแบบสุ่ม 0.75–2.25 วิ, ETA ตามกฎค่าประมาณของแอป (`--route-mode`), ผู้แจ้ง 1 เคสต่อเครื่อง (cooldown), ปิด listener ทุกเครื่องเมื่อจบแต่ละสถานการณ์, แยกเวลา transaction ออกจากเวลาอ่านซ้ำ
- ปลอดภัย: ค่าเริ่มต้นคือ emulator, รันระบบจริงต้องใส่ flag ยืนยัน, เขียน/ลบได้เฉพาะเอกสาร `SIM-` ที่มี `simulation: true`, MQTT ระบบจริงใช้ topic แยก (topic จริงต้องยืนยันสองชั้น)
- unit test 7 ข้อ (เทียบสูตรกับค่าจริงจาก Dart), README มีวิธีรัน ค่าใช้จ่ายโดยประมาณ และตารางทดสอบด้วยมือถือจริงหลายเครื่อง

**`test/multi_user_concurrency_test.dart`** — 12 เทสต์ที่รัน `IncidentService` จริงด้วยผู้ใช้หลายคนพร้อมกัน (dev dependency `fake_cloud_firestore` + จุดฉีด `firestoreOverride` สำหรับเทสต์เท่านั้น) — ใช้ Firestore จำลองที่เลียนแบบ optimistic transaction เพราะ fake ของ package ไม่มี isolation จริง และทำ mutation test ยืนยันว่าเทสต์จับข้อผิดได้จริง (flutter test 71/71)

**สิ่งที่พบ (ความเสี่ยงในโค้ดแอป — ข้อ 1–2 แก้แล้วในหัวข้อ 54):**
1. รถคันเดียวถูกโรงพยาบาลสองแห่งสั่งไปคนละเคสพร้อมกันได้ ถ้าสั่งก่อนเครื่องที่สองรับข้อมูลทัน (transaction ล็อกแค่เอกสารเคส; เว็บ Agency ไม่เช็ครถว่าง) — ช่วงเสี่ยงบน emulator ~0–50 ms, ใน `lifecycle` ยังเกิดทุกรอบ
2. เคสที่โรงพยาบาลปิดแล้วถูกเปิดกลับได้ ถ้ารถกดเลื่อนสถานะก่อนรู้ว่าเคสถูกปิด (`updateIncidentProgressStep` เขียนโดยไม่เช็คสถานะ) — ช่วงเสี่ยงบน emulator ~50 ms, บนเครือข่ายจริงคาดว่ากว้างกว่า
3. อื่นๆ: เคสจบใช้ `statusStep` 5 (หน้าหลักรถ) กับ 4 (หน้ารายละเอียด), MQTT broker ตายตัวไม่อ่าน `.env` และไม่มียืนยันตัวตน

## 54. เคสเดียวรับได้หลายคัน (นับตามทะเบียน) + แก้บั๊กรถรับสองเคส / เคสที่ปิดแล้วถูกเปิดกลับ

**รูปแบบข้อมูล** (`incident_report.dart`): เพิ่ม `AssignedUnit` และฟิลด์ `assignedUnits` (หน่วยละ 1 แถว: unitId, ทะเบียน, ชื่อเรียกขาน, vehicleKey, ใครสั่ง, เวลาเข้า)
พร้อม `assignedUnitIds` / `assignedVehicleKeys` / `assignedVehicleCount` — **นับรถตามทะเบียน** (`vehicleKeyFor` ตัดช่องว่าง/ขีด/จุด; ยังไม่ตั้งทะเบียนใช้รหัสหน่วยแทน)
หลายบัญชีบนรถคันเดียวกัน = 1 คัน, คันแรกยังเขียนลง `assignedAmbulance*` เดิม (เคสเก่า/ตัวส่ง push เดิมใช้ต่อได้)
getter ใหม่: `units`, `vehicles`, `vehicleCount`, `vehiclesLabel`, `hasUnit(unitId, plate:)`, `isJoinable` (รอรับ/กำลังไป/ถึงจุดเกิดเหตุ), `reporterUnitLabel`, `shouldPublishEta`

**`IncidentService`**
- `assignAmbulance(...)` → `DispatchResult` (assigned / joined / alreadyMine / alreadyHasVehicles / caseClosed / notJoinable / vehicleBusy / notFound / failed) — transaction อ่านเอกสารเคส + `ambulance_locks/{vehicleKey}` (+ เคสที่ล็อกชี้อยู่) ถ้ารถยังอยู่ในเคสอื่นที่ยังไม่จบ = `vehicleBusy`; ล็อกที่ชี้เคสที่จบ/ปิดแล้วถือว่าว่าง (ไม่ต้องปลดล็อก)
  `onlyIfUnassigned` สำหรับปุ่ม "ส่งรถพยาบาล" คันแรกของ รพ.; rules ยังไม่ deploy (permission-denied) → ทำงานต่อแบบไม่มีล็อก + log เตือน
- `advanceIncidentStatus(...)` → `ProgressOutcome` — transaction เดินหน้าอย่างเดียว, ไม่แตะเคสที่ปิด/จบ, ขั้นคำนวณจากสถานะ (resolved = 5 เสมอ แก้ 4/5 ไม่ตรงกัน); `updateIncidentProgressStep` เรียกตัวนี้
- `getBusyAmbulanceIds` นับทุกหน่วย, `getBusyVehicleKeys` ใหม่, `unitHasOpenCase` ค้นทั้ง `assignedUnitIds` และฟิลด์เดิม
- ETA หลายคัน: บันทึก `ambulanceEtaUnitId/CallSign` แล้วส่งทับเฉพาะคันที่ถึงเร็วกว่า (หรือคันเดิมหยุดส่งเกิน 90 วิ) — ผู้แจ้งเห็นคันที่ใกล้สุด; `ambulanceNearCallSign`

**หน้าจอ**
- รถพยาบาล: การ์ดเคสแสดง "กำลังดำเนินเคส N คัน : ทะเบียน…", ปุ่ม "ร่วมรับเคส (+1 คัน)" (ถามยืนยัน) จนกว่าจะเริ่มนำส่ง, เคสของเรานับรวมบัญชีอื่นที่ทะเบียนเดียวกัน, ข้อความผลการรับเคส/เลื่อนสถานะแยกตามสาเหตุ ("เคสนี้ถูกปิดแล้ว", "รถของคุณมีเคสอื่น")
- โรงพยาบาล (มือถือ + เว็บ Agency): แสดงจำนวนรถ/ทะเบียน, ปุ่ม "ส่งรถเพิ่มอีก 1 คัน" (คันว่างที่ใกล้ที่สุด), เว็บกรองรถที่มีเคสค้างแล้ว (เดิมไม่เช็ค), กล่องปิดเคสบอกจำนวนรถ
- ผู้แจ้ง: รายการ/รายละเอียดแสดง N คัน, หน้าติดตาม/Dynamic Island แสดงชื่อคันที่ใกล้สุด "(+N คัน)", แจ้งเตือน "มีรถพยาบาลมาเพิ่ม"
- เว็บ Data แสดงจำนวนรถต่อเคส

**แจ้งเตือน** (`push-worker`, `functions`, `local_incident_notifier`): แจ้ง "ได้รับมอบหมาย" ทุกคันที่ รพ. สั่งเพิ่ม, แจ้งผู้แจ้งเมื่อจำนวนรถเพิ่ม (ส่งเป็นชนิด `ambulance_on_the_way` ให้แอปรุ่นเดิมเปิดได้), pushLog เก็บ `assignedUnits`/`vehicleCount` (อ่าน log เดิมได้), worker `encodeValue` รองรับ array

**`firestore.rules`**: เพิ่ม `ambulance_locks/{vehicleKey}` — ⚠️ ต้อง deploy (`firebase deploy --only firestore:rules`, ใช้ได้บนแพลนฟรี) และ deploy worker ใหม่ (`npm run deploy` ใน `push-worker`)

**ทดสอบ**
- `flutter test` 76/76 — เทสต์แย่งรับเคสเปลี่ยนเป็น "ไม่มีการเขียนทับ + นับคันถูก" แทน "ผู้ชนะคนเดียว", เทสต์ข้อจำกัดเดิม 2 ข้อกลายเป็นเทสต์ยืนยันว่าแก้แล้ว, เพิ่มเทสต์หลายบัญชีทะเบียนเดียวกัน/ล็อกค้าง/สถานะเดินหน้า/ETA หลายคัน/แจ้งเตือนรถเพิ่ม; mutation test (ปิดล็อก, ปิดเช็คเคสปิด, ปิดเดินหน้าอย่างเดียว) — เทสต์จับได้ทุกกรณี
- ตัวจำลอง: ตรรกะเดียวกับแอป + `--app-logic=legacy` ไว้เทียบก่อน/หลัง, ล็อกจำลองชื่อ `SIM-LOCK-…` (ล้างใน cleanup), `run-emulator.sh` (ใช้เมื่อ Firebase CLI ค้าง)

| (emulator, `all`) | ก่อนแก้ (`legacy`) | หลังแก้ |
|---|---|---|
| สอง รพ. ส่งรถคันเดียวกันไปคนละเคส (`risks`) | เกิดเมื่อห่างกัน ≤ 0–400 ms (ขึ้นกับภาระเครื่อง) | ไม่เกิดเลยทุกช่วง 0–1600 ms (0/24) |
| เคสที่ปิดแล้วถูกเปิดกลับ (`risks`) | เกิดเมื่อห่างกัน ≤ 50–400 ms | ไม่เกิดเลย (0/24) |
| รถถือเคสค้างพร้อมกันสูงสุด (`lifecycle`) | 2 เคส/คัน | 1 เคส/คัน (เจอรถไม่ว่าง 3 ครั้ง เลือกคันถัดไปแทน) |
| รถ 5 คันกดรับเคสเดียวกัน (`race`) | ได้ 1 คัน อีก 4 คัน "มีรถรับแล้ว" | ได้ครบ 5 คัน ไม่มีคันไหนถูกเขียนทับ |
| สรุป | ผ่าน 18 · วัดค่า 4 | ผ่าน 21 · ไม่ผ่าน 0 · วัดค่า 1 · ล้างข้อมูลเหลือ 0 |


## 55. ทดสอบอัตโนมัติตามสถานการณ์ 20 ข้อ (S01–S20) + แก้บั๊กที่พบเพิ่ม 3 ข้อ

**รายการสถานการณ์** `docs/TEST_SCENARIOS.md` (สร้างจาก `tools/multi_user_sim/src/catalog.mjs`) — 5 กลุ่ม: การแจ้งเหตุ (S01–S05), โรงพยาบาลหลายแห่ง (S06–S08),
การรับเคส (S09–S14), ระหว่างปฏิบัติงาน (S15–S18), แจ้งเตือนและผู้ใช้ถนน (S19–S20) แต่ละข้อมี โอกาสเกิดจริง / ผู้ใช้ที่เกี่ยวข้อง / ผลที่ต้องได้ / ทดสอบด้วยอะไร

**รันคำสั่งเดียว** `tools/run_all_scenarios.sh` (`--quick` = Dart + Worker, `--legacy` = ตัวจำลองใช้ตรรกะก่อนแก้) → `tools/multi_user_sim/results/scenarios-*.md`
ข้อทดสอบทุกชุดติดรหัส `[Sxx]` แล้วรวมผลรายสถานการณ์ (`src/scenario_report.mjs`): ผ่านเมื่อทุกข้อที่ติดรหัสผ่านและมีผลครบทุกชุดที่ระบุ

**ชุดทดสอบใหม่**
- ตัวจำลอง: สถานการณ์ `edge` (S03, S05, S07, S08, S11, S12, S13 ผ่าน MQTT, S14, S16, S18) + ติด sid ให้ check เดิม, `cancelByReporter` (fixed/legacy)
- Dart: S04 (Firestore ปฏิเสธการเขียน), S08, S18, `test/scenario_agency_list_test.dart` (S05), `test/scenario_road_users_test.dart` (S20 ผู้ขับขี่ 20 คน 6 กลุ่ม) — flutter test 80/80
- Worker: `push-worker/test/notify.test.mjs` (S19 — 8 คำขอพร้อมกันต่อเหตุการณ์ ส่งครั้งเดียวต่อคน, `npm test`) + แยก `handleIncidentWith` ให้ฉีด client จำลองได้

**บั๊กที่พบจากการคิดสถานการณ์ (แก้แล้ว, mutation test ยืนยันว่าเทสต์จับได้)**
- S04: ส่งเคสไม่ถึงศูนย์แต่ cooldown 2 นาทีเริ่มนับ ผู้แจ้งส่งใหม่ไม่ได้ → ล้าง cooldown เมื่อส่งไม่สำเร็จ
- S05: รายการเคสของโรงพยาบาลซ่อนเคสที่ไกลเกิน 5 กม. แม้เป็นเคสที่ส่งมาที่โรงพยาบาลนั้น (ER ใกล้สุดเต็ม/เกิดเหตุนอกเมือง) → ไม่มีใครเห็นเคส → `agency_case_filter.dart`
- S18: ผู้แจ้งยกเลิกเช็คจาก cache แล้วเขียนทับ เคสถูกยกเลิกทั้งที่รถรับแล้ว และเน็ตหลุดก็ตอบว่าสำเร็จ → `cancelIncident` เป็น transaction (ยกเลิกได้เฉพาะ pending ที่ยังไม่มีรถ, บันทึก `cancelledBy: reporter`)

**ผล** (emulator, เครื่องไม่มีภาระอื่น): ผ่าน **20/20** สถานการณ์ — Dart 80/80, Worker 2/2, ตัวจำลอง 39/39 ข้อ, ~2.5 นาที
`--legacy`: ผ่าน 15/20 — ไม่ผ่าน S11, S12, S14, S16, S18 (สถานะถอยหลัง 3→2, ยกเลิกทับรถ 2/8 ครั้ง ฯลฯ) แสดงว่าชุดทดสอบจับบั๊กเดิมได้

## 56. สถานการณ์ GPS และตำแหน่ง 20 ข้อ (G01–G20) แทน S20 เดิม + แก้บั๊ก "พิกัดปลอม"

รายการสถานการณ์เป็น **39 ข้อ**: S01–S19 (หลายผู้ใช้) + G01–G20 (GPS) — `docs/TEST_SCENARIOS.md`, รันทั้งหมด `tools/run_all_scenarios.sh`
- ตำแหน่งผู้แจ้ง: G01 GPS ปกติ, G02 ไม่อนุญาต/ปิด GPS, G03 GPS ช้า (ใช้ตำแหน่งล่าสุด ≤ 5 นาที), G04 เลื่อนหมุดเอง
- คุณภาพสัญญาณ: G05 ในอาคาร > 50 ม., G06 GPS กระโดด, G07 GPS ขัดข้องกลางทาง
- เรดาร์ผู้ขับขี่: G08 ระดับเตือนตาม พ.ร.บ.จราจร ม.76 (ค่าขอบ), G09 ตามหลัง ≤ 500 ม., G10 0.5–2.5 กม., G11 ถนนขนาน, G12 ผ่านไปแล้ว, G13 เลี้ยวออก/เลี้ยวเข้า, G14 ไม่มีเส้นทาง (ทิศ+ระยะ, สวนเลน), G15 เกิน 3 กม.
- ตำแหน่งรถพยาบาล: G16 ใกล้จุดเกิดเหตุ < 500 ม. ครั้งเดียว, G17 ใกล้ รพ. ≤ 1.5 กม. อัตโนมัติ, G18 ETA หน้าติดตาม/Dynamic Island, G19 รถหยุดส่งตำแหน่ง (หายใน ~15 วิ), G20 พักเวร/ปิดไซเรนหายทันที + เส้นทางใน Firestore ไม่ซ้อน array

**บั๊กที่พบ (แก้แล้ว, mutation test ยืนยัน)** — ต้นเหตุเดียวกัน: "หาตำแหน่งไม่ได้ = ใช้พิกัดตายตัว"
- G02/G03: `getCurrentLocation()` คืนพิกัดประตูท่าแพเมื่อไม่มีสิทธิ์/ปิด GPS/เกิน 3 วิ → **เคสถูกปักไว้ที่ท่าแพโดยไม่เตือน**
  → `LocationService.resolveFix()` (GPS 8 วิ → ตำแหน่งล่าสุด ≤ 5 นาที → หาไม่ได้), ไม่คืนพิกัดปลอมอีก, ทิ้ง (0,0)/NaN
  → หน้าแจ้งเหตุ (`sos_location_policy.dart`): แถบเตือนเมื่อ GPS อ่อน/หาไม่ได้ และ**ส่งไม่ได้จนกว่าผู้แจ้งเลื่อน/ยืนยันหมุดเอง**, หมุดที่ผู้แจ้งเลื่อนไม่ถูก GPS ทับ
- G07: สตรีม GPS error → ส่งพิกัดท่าแพเข้าไป รถพยาบาลกระโดดไปท่าแพแล้วประกาศให้ทุกเครื่อง → `positionsToLocations` กลืน error (ค้างที่จุดจริงล่าสุด)
  → รถพยาบาลไม่ประกาศตำแหน่งจนกว่าจะได้ตำแหน่งจริงครั้งแรก (เดิมประกาศพิกัดตั้งต้นในอำเภอฝาง), เรดาร์ผู้ขับขี่ไม่ประเมินการเตือนจากพิกัดตั้งต้น (ยกเว้นโหมดสาธิต)

**ทดสอบ**: `test/scenario_gps_test.dart` (G01–G15 เรียกโค้ดจริง: LocationService, กติกาหมุด, HospitalLocationService, EmergencyProximityTier, AiTrajectoryService),
ตัวจำลองเพิ่ม G17 (สถานะใกล้ถึง รพ. จากตำแหน่ง) และ G20 (ปิดไซเรนหายใน < 3 วิ), ติด G16/G18/G19/G20 ให้เทสต์เดิม
ผล: **ผ่าน 39/39 สถานการณ์** — flutter test 94/94, Worker 2/2, ตัวจำลองผ่านทุกข้อ, analyze เหลือ info เดิม 9 ข้อ

## 57. เอกสารผลการทดลอง (docs/TEST_RESULTS.md) จากการรันจริง

- `tools/run_all_scenarios.sh --results`: Dart + Worker + ตัวจำลอง 3 รอบ + ตรรกะก่อนแก้ 1 รอบ → `results/batch-*/` แล้วสร้าง `docs/TEST_RESULTS.md` (`src/results_doc.mjs`) — ตัวเลขทั้งหมดมาจากการรันนั้น ไม่ได้แก้ด้วยมือ
- เนื้อหา: สภาพแวดล้อม (เครื่อง/ซอฟต์แวร์/พารามิเตอร์/ปริมาณอ่าน-เขียน), สรุปผลรายกลุ่ม, ผลการวัดเวลา (มัธยฐาน ± SD ระหว่างรอบ, p95, ต่ำสุด, สูงสุด),
  เปรียบเทียบก่อน/หลังแก้ (ตารางช่วงเวลาเสี่ยง, รถต่อเคส, ประวัติสถานะ ฯลฯ), ผลรายสถานการณ์ (เงื่อนไข / ผลที่คาด / ผลที่ได้จริง / ผ่าน-ไม่ผ่านกี่รอบ), ข้อจำกัดของการทดลอง
- เทสต์บันทึกค่าที่วัดได้จริงด้วย `@@RESULT` (`test/support/scenario_result.dart`, `record()` เดิม, worker) — เช่น G09–G15 บันทึกระยะ/หมวดที่ระบบตัดสิน/เตือนหรือไม่ ทีละผู้ขับขี่
- แก้การวัด "สั่งจ่าย → อีกโรงพยาบาลเห็น" และ "ปิดเคส → รถเห็น" ใน `risks` ให้ใช้เวลาที่ listener เห็นจริง (เดิมรวมช่วงหน่วงที่ตั้งไว้)
- ผลล่าสุด (Apple M2 8 GB, 3 รอบ): ผ่าน 39/39 สถานการณ์ทุกรอบ, Dart 94/94, Worker 2/2, ตัวจำลอง 41/41 ข้อต่อรอบ
