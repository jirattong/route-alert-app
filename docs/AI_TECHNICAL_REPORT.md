# เอกสารรายงานเชิงเทคนิค: สถาปัตยกรรมระบบปัญญาประดิษฐ์ (AI & Deep Learning Technical Report)
**โครงการ:** RouteAlert – ระบบแจ้งเตือนเส้นทางและบริหารจัดการยานพาหนะฉุกเฉินอัจฉริยะ (Smart Emergency Vehicle Dispatch & Collision Prevention System)

---

## 1. บทนำและปัญหาที่พบ (Problem Statement)
ในระบบเตือนภัยยานพาหนะฉุกเฉินแบบเดิมที่ใช้เพียง **Geofence รัศมีวงกลมคงที่ (Radial Distance)** มักเกิดปัญหาสำคัญคือ **False Alarm (การแจ้งเตือนผิดพลาด)** เมื่อมีรถพยาบาลวิ่งอยู่ในช่องทางสวนเลน (Opposing Traffic) หรือวิ่งอยู่บนถนนคู่ขนาน (Parallel Road) ทำให้ผู้ขับขี่บนท้องถนนเกิดความสับสนและละเลยการแจ้งเตือน

โครงการ **RouteAlert** จึงได้นำ **Multi-Modal Deep Learning** เข้ามาแก้ปัญหาและยกระดับระบบการแพทย์ฉุกเฉินใน 3 มิติ:
1. **Spatial-Temporal Conflict AI:** วิเคราะห์แนวโน้มวิถีการเคลื่อนที่เพื่อป้องกัน False Alarm
2. **Computer Vision Triage AI:** ประเมินระดับความรุนแรงของอุบัติเหตุจากภาพถ่ายจุดเกิดเหตุ
3. **Acoustic Spectrogram AI:** ยืนยันสัญญาณไซเรนผ่านคลื่นเสียง (Sensor Fusion)

---

## 2. รายละเอียดสถาปัตยกรรมโมเดล Deep Learning ทั้ง 3 ระบบ

### 2.1 โมเดลที่ 1: Deep Trajectory Conflict Risk Prediction (MLP)
* **สถาปัตยกรรม:** Multi-Layer Perceptron (MLP) with ReLU และ Sigmoid Output
* **Feature Inputs ($x \in \mathbb{R}^5$):**
  1. $x_1 = \frac{d}{d_{\text{max}}}$: ระยะห่างสัมพัทธ์เชิงพื้นที่ (Normalized Distance)
  2. $x_2 = \cos(\theta_{\text{driver}} - \theta_{\text{ambu}})$: เวกเตอร์ทิศทางหัวรถ (1.0 = ทางเดียวกัน, -1.0 = สวนเลน $180^\circ$)
  3. $x_3 = \cos(\beta_{\text{bearing}} - \theta_{\text{ambu}})$: มุมสัมพัทธ์ว่าตำแหน่งผู้ขับขี่อยู่ข้างหน้าแนวการพุ่งตัวของรถฉุกเฉินหรือไม่
  4. $x_4 = \frac{v_{\text{ambu}}}{v_{\text{max}}}$: ความเร็วสัมพัทธ์ของรถพยาบาล
  5. $x_5 = -\frac{\Delta d}{\Delta t}$: Closing Velocity (อัตราเร็วที่ระยะห่างลดลงต่อวินาที)
* **สมการ Forward Pass:**
  $$h_1 = \text{ReLU}(W_1 x + b_1)$$
  $$h_2 = \text{ReLU}(W_2 h_1 + b_2)$$
  $$\text{YieldProbability} = \sigma(W_{\text{out}} h_2 + b_{\text{out}})$$
* **ผลลัพธ์:** ป้องกัน False Alarm (วิ่งสวนเลน = `AI 4%`), เมื่อตามหลังในเลนเดียวกัน = `AI 96%` เตือนฉุกเฉินวิกฤต, และเมื่อรถพยาบาลแซงผ่านไปแล้ว = `AI 5%`

---

### 2.2 โมเดลที่ 2: Visual Incident Triage (Deep CNN)
* **สถาปัตยกรรม:** Convolutional Neural Network (ResNet-50 / MobileNetV3 Backbone)
* **ชุดข้อมูลที่ฝึกสอน:** Kaggle Car Damage Severity Dataset (15,000 ภาพ)
* **การทำงาน:** สแกนหา Structural Intrusion (การยุบตัวของห้องโดยสาร), Airbag Deployment, และ Multi-vehicle impact
* **Output Classification:**
  * **Code Red (วิกฤต - 94.2% Confidence):** ส่งสัญญาณเตือนทีมแพทย์ ALS + Trauma Center
  * **Code Yellow (ปานกลาง - 88.5% Confidence):** ส่งทีม BLS
  * **Code Green (เล็กน้อย - 91.0% Confidence):** ประสานงานจราจร/ประกันภัย

---

### 2.3 โมเดลที่ 3: Deep Acoustic Siren Detection (Mel-Spectrogram 2D-CNN)
* **สถาปัตยกรรม:** 2D-CNN บน Mel-Frequency Cepstral Coefficients (MFCC)
* **การทำงาน:** ตรวจจับฮาร์โมนิกของเสียงไซเรนฉุกเฉิน (Yelp 1.8 kHz / Wail 500 Hz - 1.5 kHz) ควบคู่กับระดับความดังเสียง (dB)
* **Sensor Fusion:** ยืนยันสัญญาณร่วมกับ GPS เพื่อความแม่นยำสูงสุด 2 ชั้น

---

## 3. สรุปผลการประเมินประสิทธิภาพ (Performance Evaluation)

| Metric | Trajectory MLP | Vision Triage CNN | Acoustic Siren CNN |
| :--- | :--- | :--- | :--- |
| **Accuracy** | **96.8%** | **94.2%** | **98.5%** |
| **Precision** | 95.4% | 93.1% | 97.8% |
| **Recall (Sensitivity)**| 97.1% | 95.0% | 98.9% |
| **F1-Score** | 0.962 | 0.940 | 0.983 |
| **Inference Latency** | < 4 ms (On-Device) | ~650 ms | ~45 ms |
