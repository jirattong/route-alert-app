// สคริปต์ชั่วคราวสร้างไอคอนแอปแบบง่าย (teal + กากบาทการแพทย์สีขาว)
// รันด้วย: dart run scripts/generate_app_icon.dart
// ไม่ใช่ส่วนหนึ่งของแอป แค่ใช้ generate ไฟล์ assets/icon/app_icon.png ครั้งเดียว
import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  const int size = 1024;
  final image = img.Image(width: size, height: size, numChannels: 4);

  // พื้นหลัง Teal ตามสีแบรนด์ของแอป (#00A896)
  img.fill(image, color: img.ColorRgb8(0x00, 0xA8, 0x96));

  // วาดกากบาทการแพทย์สีขาวตรงกลาง (สัญลักษณ์สากลของการแพทย์ฉุกเฉิน)
  final white = img.ColorRgb8(0xFF, 0xFF, 0xFF);
  const double armThickness = size * 0.24;
  const double armLength = size * 0.64;
  final double cx = size / 2;
  final double cy = size / 2;

  // แขนตั้ง
  img.fillRect(
    image,
    x1: (cx - armThickness / 2).round(),
    y1: (cy - armLength / 2).round(),
    x2: (cx + armThickness / 2).round(),
    y2: (cy + armLength / 2).round(),
    color: white,
    radius: 24,
  );
  // แขนนอน
  img.fillRect(
    image,
    x1: (cx - armLength / 2).round(),
    y1: (cy - armThickness / 2).round(),
    x2: (cx + armLength / 2).round(),
    y2: (cy + armThickness / 2).round(),
    color: white,
    radius: 24,
  );

  final pngBytes = img.encodePng(image);
  final outFile = File('assets/icon/app_icon.png');
  outFile.createSync(recursive: true);
  outFile.writeAsBytesSync(pngBytes);
  print('เขียนไอคอนไปที่ ${outFile.path} เรียบร้อยแล้ว (${size}x$size)');
}
