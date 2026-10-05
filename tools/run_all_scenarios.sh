#!/bin/zsh
# รันการทดสอบอัตโนมัติทุกสถานการณ์ (S01–S20 หลายผู้ใช้ + G01–G20 GPS) แล้วรวมผลเป็นรายงานเดียว
#   tools/run_all_scenarios.sh            ทุกชุด: Dart + Worker + ตัวจำลองหลายเครื่องบน emulator
#   tools/run_all_scenarios.sh --quick    เฉพาะ Dart + Worker (ไม่ต้องมี Java)
#   tools/run_all_scenarios.sh --legacy   ตัวจำลองใช้ตรรกะก่อนแก้ (แสดงว่าชุดทดสอบจับบั๊กเดิมได้)
#   tools/run_all_scenarios.sh --results  เก็บผลการทดลองสำหรับเล่ม: ตัวจำลอง 3 รอบ + ตรรกะก่อนแก้ 1 รอบ
#                                         → docs/TEST_RESULTS.md (--repeat=5 เปลี่ยนจำนวนรอบ)
# รายการสถานการณ์: docs/TEST_SCENARIOS.md · รายงาน: tools/multi_user_sim/results/scenarios-*.md
ROOT=${0:A:h:h}
SIM=$ROOT/tools/multi_user_sim
OUT=$SIM/results
mkdir -p $OUT
TS=$(date +%Y%m%d-%H%M%S)
QUICK=0; LOGIC=fixed; RESULTS=0; REPEAT=3
for a in "$@"; do
  case $a in
    --quick) QUICK=1 ;;
    --legacy) LOGIC=legacy ;;
    --results) RESULTS=1 ;;
    --repeat=*) REPEAT=${a#--repeat=} ;;
  esac
done

newest_report() { ls -t $OUT/report-*.json 2>/dev/null | head -1; }

if [ $RESULTS = 1 ]; then
  BATCH=$OUT/batch-$TS
  mkdir -p $BATCH
  echo "▶ เก็บผลการทดลอง → $BATCH"
  node -e '
    const os = require("os"); const { execSync } = require("child_process");
    const sh = (c) => { try { return execSync(c, { encoding: "utf8" }).trim(); } catch { return "-"; } };
    const jar = (sh("ls ~/.cache/firebase/emulators/ | grep cloud-firestore-emulator | tail -1").match(/v[0-9]+(\.[0-9]+)*/) || ["-"])[0];
    const when = new Date(Date.now() + 7 * 3600e3).toISOString().slice(0, 16).replace("T", " ");
    console.log(JSON.stringify({ when, cpu: os.cpus()[0].model + " (" + os.cpus().length + " cores)", ramGb: Math.round(os.totalmem() / 2 ** 30),
      os: "macOS " + sh("sw_vers -productVersion"), node: process.version, emulator: jar,
      flutter: sh("flutter --version 2>/dev/null | head -1").replace(/ •.*/, "") }, null, 2));' > $BATCH/env.json
  echo "▶ Dart"; (cd $ROOT && flutter test --reporter json > $BATCH/flutter.jsonl); echo "   exit $?"
  echo "▶ Worker"; (cd $ROOT/push-worker && node --test --test-reporter=tap test/notify.test.mjs > $BATCH/worker.tap); echo "   exit $?"
  (cd $SIM && [ -d node_modules ] || npm install --silent)
  for i in $(seq 1 $REPEAT); do
    echo "▶ ตัวจำลอง รอบ $i/$REPEAT"
    (cd $SIM && PORT=$((8100 + i)) ./run-emulator.sh all --target=emulator | grep -E "❌|รายงาน:")
    cp "$(newest_report)" $BATCH/sim-fixed-$i.json
  done
  echo "▶ ตัวจำลอง ตรรกะก่อนแก้ (เปรียบเทียบ)"
  (cd $SIM && PORT=8199 ./run-emulator.sh all --target=emulator --app-logic=legacy | grep -E "รายงาน:")
  cp "$(newest_report)" $BATCH/sim-legacy.json
  cd $SIM && node src/results_doc.mjs --batch=$BATCH --out=$ROOT/docs/TEST_RESULTS.md
  exit $?
fi

echo "▶ 1/4 Dart (flutter test)"
(cd $ROOT && flutter test --reporter json > $OUT/flutter-$TS.jsonl)
echo "   exit $?"

echo "▶ 2/4 ตัวส่งแจ้งเตือน (node --test)"
(cd $ROOT/push-worker && node --test --test-reporter=tap test/notify.test.mjs > $OUT/worker-$TS.tap)
echo "   exit $?"

SIMARG=()
if [ $QUICK = 0 ]; then
  echo "▶ 3/4 ตัวจำลองหลายเครื่อง (Firestore emulator, --app-logic=$LOGIC)"
  (cd $SIM && [ -d node_modules ] || npm install --silent)
  (cd $SIM && ./run-emulator.sh all --target=emulator --app-logic=$LOGIC | grep -E "^▶|❌|รายงาน:")
  SIMARG=(--sim=latest)
else
  echo "▶ 3/4 ข้ามตัวจำลอง (--quick)"
fi

echo "▶ 4/4 รวมผลตามสถานการณ์"
cd $SIM && node src/scenario_report.mjs --flutter=$OUT/flutter-$TS.jsonl --worker=$OUT/worker-$TS.tap $SIMARG
