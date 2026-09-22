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
