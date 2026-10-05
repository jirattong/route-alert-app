#!/bin/zsh
# จำลองตำแหน่ง GPS บน iOS Simulator สำหรับสาธิต (เชียงใหม่ ถ.ห้วยแก้ว)
#   ผู้ขับขี่ = iPhone 17 · รถพยาบาล = iPhone 18 Pro · โรงพยาบาล = iPad mini (A17 Pro)
#   เปลี่ยนเครื่องได้ด้วย DRIVER= AMB= HOSP= (ชื่อ simulator)
#
#   tools/sim_demo.sh setup        วางทุกเครื่องที่จุดเริ่ม (ผู้ขับขี่จอดบน ถ.ห้วยแก้ว, รถพยาบาลอยู่ห่าง 2.5 กม.)
#   tools/sim_demo.sh pass         รถพยาบาลวิ่งผ่านผู้ขับขี่บนถนนเดียวกัน → ผู้ขับขี่ได้เตือนหลบทาง แล้วเลิกเตือนเมื่อผ่านไป
#   tools/sim_demo.sh toscene      รถพยาบาลวิ่งไปจุดเกิดเหตุ (ตำแหน่งผู้แจ้ง) → "รถใกล้ถึง" (< 500 ม.) แล้วถึงจุดเกิดเหตุ
#   tools/sim_demo.sh tohospital   รถพยาบาลนำส่งจากจุดเกิดเหตุไปโรงพยาบาล → "ใกล้ถึง รพ." (≤ 1.5 กม.)
#   tools/sim_demo.sh parallel     ผู้ขับขี่อยู่ถนนขนาน (ไม่ใช่เส้นทางรถพยาบาล) → ไม่ควรได้เตือน
#   tools/sim_demo.sh drivermove   ผู้ขับขี่ขับไปตาม ถ.ห้วยแก้ว (ดูหมุดผู้ขับขี่เคลื่อนที่บนแผนที่ของคนอื่น)
#   tools/sim_demo.sh clear        ล้างตำแหน่งจำลองทุกเครื่อง
DRIVER=${DRIVER:-"iPhone 17"}
AMB=${AMB:-"iPhone 18 Pro"}
HOSP=${HOSP:-"iPad mini (A17 Pro)"}

udid() { xcrun simctl list devices booted | grep -F "    $1 (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/'; }
need() { local u=$(udid "$1"); [ -z "$u" ] && { echo "ไม่พบ simulator \"$1\" ที่เปิดอยู่ (เปิดใน Device Hub ก่อน)"; exit 1; }; echo $u; }

# จุดต่างๆ (ประมาณตามแนวถนนจริง)
HOSPITAL=18.7894,98.9737          # รพ.มหาราชนครเชียงใหม่ (สวนดอก)
SCENE=18.7990,98.9690             # จุดเกิดเหตุ / ผู้ขับขี่จอด ถ.ห้วยแก้ว
AMB_START=18.7955,98.9800         # รถพยาบาลเริ่ม (แยกช้างเผือก-ห้วยแก้ว) ห่างราว 1.2 กม.
AMB_FAR=18.7905,98.9930           # ไกลขึ้นสำหรับวิ่งผ่าน (~2.5 กม.)
HUAYKAEW_1=18.7972,98.9748
HUAYKAEW_2=18.7983,98.9715
BEYOND=18.8030,98.9550            # เลยผู้ขับขี่ไปทาง มช.
PARALLEL=18.8020,98.9700          # ถนนขนานห่างราว 350 ม.

case $1 in
  setup)
    xcrun simctl location $(need "$HOSP") set $HOSPITAL
    xcrun simctl location $(need "$DRIVER") set $SCENE
    xcrun simctl location $(need "$AMB") set $AMB_FAR
    echo "วางแล้ว: โรงพยาบาล $HOSPITAL · ผู้ขับขี่ $SCENE · รถพยาบาล $AMB_FAR" ;;
  pass)
    xcrun simctl location $(need "$DRIVER") set $SCENE
    xcrun simctl location $(need "$AMB") start --speed=15 $AMB_FAR $AMB_START $HUAYKAEW_1 $HUAYKAEW_2 $SCENE $BEYOND
    echo "รถพยาบาลวิ่ง 54 กม./ชม. ผ่านผู้ขับขี่ (ใช้เวลาราว 4 นาที)" ;;
  toscene)
    xcrun simctl location $(need "$AMB") start --speed=12 $AMB_START $HUAYKAEW_1 $HUAYKAEW_2 $SCENE
    echo "รถพยาบาลมุ่งหน้าจุดเกิดเหตุ (~1.2 กม. ราว 2 นาที) — กดรับเคสก่อนถึงจะเห็น ETA/ใกล้ถึง" ;;
  tohospital)
    xcrun simctl location $(need "$AMB") start --speed=12 $SCENE $HUAYKAEW_2 $HUAYKAEW_1 18.7930,98.9745 $HOSPITAL
    echo "รถพยาบาลนำส่งไปโรงพยาบาล (~1.5 กม.) — กด \"รับผู้ป่วยแล้ว\" ก่อนเริ่ม" ;;
  parallel)
    xcrun simctl location $(need "$DRIVER") set $PARALLEL
    xcrun simctl location $(need "$AMB") start --speed=15 $AMB_START $HUAYKAEW_1 $HUAYKAEW_2 $SCENE $BEYOND
    echo "ผู้ขับขี่อยู่ถนนขนาน · รถพยาบาลวิ่งบน ถ.ห้วยแก้ว — ผู้ขับขี่ไม่ควรได้เตือน" ;;
  drivermove)
    xcrun simctl location $(need "$DRIVER") start --speed=10 $AMB_START $HUAYKAEW_1 $HUAYKAEW_2 $SCENE $BEYOND
    echo "ผู้ขับขี่ขับไปตาม ถ.ห้วยแก้ว 36 กม./ชม." ;;
  clear)
    for d in "$DRIVER" "$AMB" "$HOSP"; do u=$(udid "$d"); [ -n "$u" ] && xcrun simctl location $u clear; done
    echo "ล้างตำแหน่งจำลองแล้ว" ;;
  *) sed -n '2,15p' $0 | sed 's/^# \{0,1\}//' ;;
esac
