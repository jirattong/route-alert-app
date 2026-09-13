"""
=============================================================================
RouteAlert: AI Model Architecture Notes & Design-Validation Prototype
=============================================================================
⚠️ อ่านก่อนใช้: ไฟล์นี้ไม่ใช่ production training pipeline ที่ export โมเดล
ไปใช้ในแอปจริง มันคือ prototype สำหรับ "ทดลอง/ยืนยันแนวคิด" ตอนออกแบบเท่านั้น

สถานะจริงของแต่ละส่วน:

1. TrajectoryConflictMLP — เทรนจริงในไฟล์นี้ แต่ใช้ "ข้อมูลสังเคราะห์" ที่สร้างจาก
   กฎ if-else ที่เขียนเอง (generate_trajectory_dataset) ไม่ใช่ข้อมูลจริง และ
   ไม่มีโค้ด export ไป TFLite/ไม่ถูกใช้ในแอป Flutter เลย — โมเดลที่ใช้งานจริงใน
   แอปคือสูตรคณิตศาสตร์ถ่วงน้ำหนักคงที่ (hand-tuned weighted formula) ใน
   lib/core/services/ai_trajectory_service.dart ซึ่งใช้ feature set เดียวกัน
   ไฟล์นี้จึงมีประโยชน์แค่เป็น "หลักฐานว่า feature set ที่เลือกใช้สมเหตุสมผล"
   ไม่ใช่หลักฐานว่ามีการเทรน-deploy โมเดลจริง

2. VisionIncidentTriageCNN — นิยามสถาปัตยกรรมไว้เฉยๆ **ไม่เคยถูกเทรน**
   การเทรนจริงสำหรับ vision triage ทำที่ scripts/train_accident_classifier_colab.ipynb
   แทน (เทรนด้วยรูปจริงผ่าน Google Colab + MobileNetV2 transfer learning
   แล้ว export TFLite ไปใช้ใน lib/core/ml/accident_image_classifier_service.dart จริง)

3. AcousticSirenCNN — นิยามสถาปัตยกรรมไว้เฉยๆ **ไม่เคยถูกเทรน** และฟีเจอร์ตรวจจับ
   เสียงไซเรนในแอป (ai_acoustic_siren_service.dart) ปัจจุบันเป็นแค่ placeholder
   จำลองด้วย Random() ไม่ได้เชื่อมกับโมเดลนี้หรือไมโครโฟนจริงแต่อย่างใด — ถ้าจะทำ
   ให้ใช้งานได้จริงต้องเก็บชุดข้อมูลเสียงจริงแล้วเทรนใหม่ (ยังไม่ได้ทำ)
=============================================================================
"""

import random
import torch
import torch.nn as nn
import torch.optim as optim


# =============================================================================
# 1. Trajectory Conflict Risk — Design-Validation Prototype (Synthetic Data)
# =============================================================================
class TrajectoryConflictMLP(nn.Module):
    """
    Multi-Layer Perceptron (MLP) ใช้ยืนยันแนวคิดตอนออกแบบ ai_trajectory_service.dart
    Input Features (dim=5):
      - x[0]: Normalized Distance (d / d_max)
      - x[1]: cos(Delta Heading) (1.0 = same direction, -1.0 = opposing lane)
      - x[2]: cos(Delta Bearing) (1.0 = driver is in front of ambulance)
      - x[3]: Normalized Ambulance Speed (v / v_max)
      - x[4]: Closing Velocity (rate of distance reduction)

    หมายเหตุ: นี่คือ prototype เท่านั้น ไม่ใช่โมเดลที่ใช้งานจริงในแอป
    """
    def __init__(self):
        super(TrajectoryConflictMLP, self).__init__()
        self.layer1 = nn.Linear(5, 8)
        self.relu = nn.ReLU()
        self.layer2 = nn.Linear(8, 4)
        self.out = nn.Linear(4, 1)
        self.sigmoid = nn.Sigmoid()

    def forward(self, x):
        x = self.relu(self.layer1(x))
        x = self.relu(self.layer2(x))
        x = self.sigmoid(self.out(x))
        return x


def generate_trajectory_dataset(num_samples=10000):
    """สร้างข้อมูลสังเคราะห์จากกฎที่เขียนเอง (ไม่ใช่ข้อมูลสถานการณ์จริง)"""
    X = []
    y = []
    for _ in range(num_samples):
        dist = random.uniform(0.05, 1.2)
        cos_h = random.uniform(-1.0, 1.0)
        cos_b = random.uniform(-1.0, 1.0)
        speed = random.uniform(0.3, 1.2)
        closing = random.uniform(-0.5, 1.2)

        is_conflict = (dist < 0.5 and cos_h > 0.3 and cos_b > 0.2 and closing > 0.0)
        label = 1.0 if is_conflict else 0.0

        X.append([dist, cos_h, cos_b, speed, closing])
        y.append([label])

    return torch.tensor(X, dtype=torch.float32), torch.tensor(y, dtype=torch.float32)


# =============================================================================
# 2. Vision Incident Triage — Architecture reference only, NEVER TRAINED here
#    ดู scripts/train_accident_classifier_colab.ipynb สำหรับ pipeline ที่ใช้งานจริง
# =============================================================================
class VisionIncidentTriageCNN(nn.Module):
    """
    สถาปัตยกรรมอ้างอิงเท่านั้น — ไม่เคยถูกเทรนในไฟล์นี้ และไม่ได้ใช้งานจริงในแอป
    """
    def __init__(self):
        super(VisionIncidentTriageCNN, self).__init__()
        self.features = nn.Sequential(
            nn.Conv2d(3, 32, kernel_size=3, padding=1),
            nn.BatchNorm2d(32),
            nn.ReLU(),
            nn.MaxPool2d(2, 2),

            nn.Conv2d(32, 64, kernel_size=3, padding=1),
            nn.BatchNorm2d(64),
            nn.ReLU(),
            nn.MaxPool2d(2, 2),

            nn.Conv2d(64, 128, kernel_size=3, padding=1),
            nn.BatchNorm2d(128),
            nn.ReLU(),
            nn.AdaptiveAvgPool2d((4, 4)),
        )
        self.classifier = nn.Sequential(
            nn.Linear(128 * 4 * 4, 64),
            nn.ReLU(),
            nn.Dropout(0.3),
            nn.Linear(64, 3),
        )

    def forward(self, x):
        x = self.features(x)
        x = torch.flatten(x, 1)
        x = self.classifier(x)
        return x


# =============================================================================
# 3. Acoustic Siren Detection — Architecture reference only, NEVER TRAINED here
#    ai_acoustic_siren_service.dart ในแอปยังเป็น Random() placeholder ไม่ต่อกับโมเดลนี้
# =============================================================================
class AcousticSirenCNN(nn.Module):
    """
    สถาปัตยกรรมอ้างอิงเท่านั้น — ไม่เคยถูกเทรนในไฟล์นี้ และไม่ได้ใช้งานจริงในแอป
    """
    def __init__(self):
        super(AcousticSirenCNN, self).__init__()
        self.conv = nn.Sequential(
            nn.Conv2d(1, 16, kernel_size=3, stride=1, padding=1),
            nn.ReLU(),
            nn.MaxPool2d(2, 2),

            nn.Conv2d(16, 32, kernel_size=3, stride=1, padding=1),
            nn.ReLU(),
            nn.MaxPool2d(2, 2),
        )
        self.fc = nn.Sequential(
            nn.Linear(32 * 16 * 32, 32),
            nn.ReLU(),
            nn.Linear(32, 1),
            nn.Sigmoid(),
        )

    def forward(self, x):
        x = self.conv(x)
        x = torch.flatten(x, 1)
        x = self.fc(x)
        return x


# =============================================================================
# TRAINING EXECUTION (Design-Validation Prototype Only)
# =============================================================================
def train_trajectory_model():
    print("Training TrajectoryConflictMLP on SYNTHETIC rule-based data...")
    print("(design-validation prototype only — not exported, not used by the app)")
    X, y = generate_trajectory_dataset(num_samples=5000)
    model = TrajectoryConflictMLP()
    criterion = nn.BCELoss()
    optimizer = optim.Adam(model.parameters(), lr=0.01)

    for epoch in range(15):
        optimizer.zero_grad()
        outputs = model(X)
        loss = criterion(outputs, y)
        loss.backward()
        optimizer.step()
        if (epoch + 1) % 5 == 0:
            preds = (outputs > 0.5).float()
            acc = (preds == y).float().mean() * 100.0
            print(f"  Epoch [{epoch+1}/15] - Loss: {loss.item():.4f} - Accuracy: {acc.item():.2f}%")

    print("  -> Prototype training complete. No file exported, no app integration.\n")
    return model


if __name__ == '__main__':
    print("==========================================================")
    print(" RouteAlert AI Design-Validation Prototype (NOT production) ")
    print("==========================================================")
    train_trajectory_model()
    print("Only TrajectoryConflictMLP was actually trained here, on synthetic")
    print("data, and it is NOT connected to the Flutter app. For the real,")
    print("data-trained model that IS used by the app, see:")
    print("  scripts/train_accident_classifier_colab.ipynb")
    print("  scripts/train_anti_spoofing_colab.ipynb")
