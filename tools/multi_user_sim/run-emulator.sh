#!/bin/zsh
# รัน Firestore emulator จากไฟล์ jar ตรงๆ แล้วรันตัวจำลอง — ใช้แทน `npm run emu` เมื่อ Firebase CLI ค้างตอนเริ่ม
# ต้องเคยรัน `firebase emulators:start --only firestore` สักครั้งให้ CLI ดาวน์โหลด jar ไว้ก่อน และมี Java (JAVA_HOME หรือ java ใน PATH)
# ตัวอย่าง: ./run-emulator.sh all --target=emulator
#          ./run-emulator.sh risks --target=emulator --app-logic=legacy
JAR=$(ls ~/.cache/firebase/emulators/cloud-firestore-emulator-*.jar 2>/dev/null | tail -1)
[ -z "$JAR" ] && { echo "ไม่พบ cloud-firestore-emulator-*.jar ใน ~/.cache/firebase/emulators"; exit 1; }
JAVA=${JAVA_HOME:+$JAVA_HOME/bin/}java
PORT=${PORT:-8086}
"$JAVA" -jar "$JAR" --host 127.0.0.1 --port $PORT > firestore-debug.log 2>&1 &
EMU=$!
trap 'kill $EMU 2>/dev/null' EXIT INT TERM
for i in {1..60}; do curl -s -o /dev/null http://127.0.0.1:$PORT && break; sleep 0.5; done
FIRESTORE_EMULATOR_HOST=127.0.0.1:$PORT node src/cli.mjs "$@"
