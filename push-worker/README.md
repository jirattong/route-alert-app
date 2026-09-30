# RouteAlert Push Worker (Cloudflare Workers)

ตัวสั่งส่งแจ้งเตือนเบื้องหลัง ใช้แทน `functions/` ได้โดยไม่ต้องเปิด Firebase Blaze plan
**ใช้อย่างใดอย่างหนึ่งเท่านั้น** ถ้าเปิดทั้งคู่จะได้แจ้งเตือนซ้ำ

## Deploy (ครั้งแรก)

1. Firebase Console → ⚙️ Project settings → **Service accounts** → **Generate new private key**
   ได้ไฟล์ `.json` มา — ห้ามส่งให้ใคร ห้ามใส่ในแอป
2. ในโฟลเดอร์นี้:
   ```
   npm install
   npx wrangler login
   npx wrangler secret put FIREBASE_SERVICE_ACCOUNT < /path/to/ไฟล์ที่ดาวน์โหลด.json
   npx wrangler deploy
   ```
   (ถ้า `secret put` ถามให้สร้าง Worker ก่อน ตอบ yes)
3. คัดลอก URL ที่ได้ (`https://route-alert-push.<ชื่อ>.workers.dev`) ไปใส่ 2 ที่:
   - `route-alert-app/lib/core/services/push_trigger.dart` → `kPushWorkerUrl`
   - `route-alert-data-web/js/firebase-config.js` → `PUSH_WORKER_URL`
4. build แอป/เว็บใหม่ แล้วลบไฟล์ service account ที่ดาวน์โหลดมาทิ้งได้

## ดู log

```
npx wrangler tail
```

## ทำงานยังไง

แอป/เว็บ Data ส่ง `{ "incidentId": "..." }` มาหลังบันทึกเคส Worker อ่านเคสจริงจาก
Firestore แล้วตัดสินใจเอง และจด `pushLog` ในเคสกันส่งซ้ำ:

| เหตุการณ์ | ผู้รับ |
|---|---|
| เคสใหม่ | agency ของโรงพยาบาลเป้าหมาย (ปุ่ม ดูเคส/ส่งรถพยาบาล) + รถพยาบาลทุกคัน (ปุ่ม ดูเคส/รับเคส) |
| มอบหมายรถ | รถคันนั้น + ผู้แจ้งเหตุ และสั่งลบ "มีเคสใหม่รอรับ" ที่ค้างในเครื่องรถคันอื่น |
| รถใกล้ถึงจุดเกิดเหตุ (< 500 ม.) | ผู้แจ้งเหตุ |
| เคสจบ | ผู้แจ้งเหตุ |

Android ได้ข้อความแบบ data-only ให้แอปวาดแจ้งเตือนเอง (มีปุ่ม, 1 เคส = 1 แจ้งเตือน
อัปเดตทับอันเดิม) ส่วน iOS ได้แบบ alert (`apns-collapse-id` = รหัสเคส จึงทับอันเดิมเช่นกัน)
ถ้าแก้ตรรกะ/ข้อความที่นี่ ต้องแก้ให้ตรงกันที่ `functions/index.js` และ
`lib/core/services/local_incident_notifier.dart` ด้วย
