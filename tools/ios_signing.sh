#!/bin/zsh
# เลือก Apple ID (ทีม) ที่จะใช้ build ลง iPhone — ใช้ได้หลาย Apple ID บน Mac เครื่องเดียว
#   tools/ios_signing.sh                 แสดงรายชื่อทีมที่มีในเครื่อง
#   tools/ios_signing.sh 2               ใช้ทีมลำดับที่ 2 (bundle id ตั้งให้อัตโนมัติ ไม่ซ้ำกันต่อทีม)
#   tools/ios_signing.sh VV37M7LD96 com.yuttapat.routealert   ระบุทีมและ bundle id เอง
# เขียน ios/Flutter/Signing.xcconfig (ไม่ขึ้น git) — ตัวแอปและ Live Activity ใช้ทีมเดียวกันเสมอ
# ห้ามเปลี่ยน Team ในหน้า Signing ของ Xcode (จะไปแก้ไฟล์โปรเจกต์ที่ทุกคนใช้ร่วมกัน)
ROOT=${0:A:h:h}
OUT=$ROOT/ios/Flutter/Signing.xcconfig

teams=()
while IFS= read -r line; do teams+=("$line"); done < <(
  security find-certificate -a -c "Apple Development" -p 2>/dev/null |
  awk '/BEGIN CERT/{n++} {f="/tmp/ra-cert-" n ".pem"; print > f}' && for f in /tmp/ra-cert-*.pem(N); do
    openssl x509 -in "$f" -noout -subject 2>/dev/null |
      sed -nE 's/.*CN ?= ?Apple Development: ([^(,]*) \(.*OU ?= ?([A-Z0-9]{10}).*/\2 \1/p'
    rm -f "$f"
  done | sort -u)

if [ ${#teams} -eq 0 ]; then
  echo "ไม่พบใบรับรอง Apple Development — เปิด Xcode → Settings → Accounts เพิ่ม Apple ID แล้วกด Manage Certificates → + Apple Development"
  exit 1
fi

if [ -z "$1" ]; then
  echo "ทีม (Apple ID) ที่มีในเครื่องนี้:"
  i=1; for t in $teams; do echo "  $i) $t"; i=$((i+1)); done
  [ -f $OUT ] && echo "\nตอนนี้ใช้: $(grep -E '^(DEVELOPMENT_TEAM|APP_BUNDLE_ID)' $OUT | tr '\n' ' ')"
  echo "\nเลือกด้วย: tools/ios_signing.sh <ลำดับ>"
  exit 0
fi

if [[ $1 == <-> ]]; then
  pick=${teams[$1]}
  [ -z "$pick" ] && { echo "ไม่มีลำดับที่ $1"; exit 1; }
  TEAM=${pick%% *}; WHO=${pick#* }
else
  TEAM=$1; WHO=$(printf '%s\n' $teams | grep "^$TEAM " | cut -d' ' -f2-)
fi
# bundle id ต้องไม่ซ้ำกับทีมอื่น — ใช้รหัสทีมต่อท้าย (เปลี่ยนเองได้ด้วยอาร์กิวเมนต์ที่ 2)
BUNDLE=${2:-com.routealert.app.${TEAM:l}}

cat > $OUT <<CONF
// สร้างโดย tools/ios_signing.sh — ไฟล์นี้ของเครื่องนี้เท่านั้น (ไม่ขึ้น git)
DEVELOPMENT_TEAM = $TEAM
APP_BUNDLE_ID = $BUNDLE
CONF
echo "ใช้ทีม $TEAM (${WHO:-ไม่ทราบชื่อ}) · bundle id $BUNDLE"
echo "Live Activity: $BUNDLE.LiveActivity"
echo "ต่อไป: เสียบ iPhone ของเจ้าของ Apple ID นี้ แล้วกด Run ใน Xcode (หรือ flutter run --release)"
