#!/bin/sh
# Relaunches Dia with this build in test mode and prints what the patches' self-checks found. Saved settings stay as they are.
set -eu
cd "$(dirname "$0")"
support="${DIAPATCH_HOME:-$HOME/Library/Application Support/DiaPatches}"
dia="${DIAPATCH_APP:-/Applications/Dia.app}/Contents/MacOS/Dia"
report="$PWD/build/test-report.json"

pid=$(pgrep -f "$dia\$" || true)
[ -z "$pid" ] || kill -TERM $pid
while [ -n "$pid" ] && kill -0 $pid 2>/dev/null; do sleep 0.5; done
# Dia skips its quit notification on SIGTERM, so safe mode would count this as a crash at launch.
plutil -replace launching -bool NO "$support/safe-mode.plist" 2>/dev/null || true
# Dia only loads the dylib it was signed with, and the dylib only runs the diapatch built with it, so both go in and Dia
# is signed again. macOS asks about "Dia Safe Storage" once for each new build.
cp -f build/diapatch "$support/bin/diapatch"
cp -f build/DiaPatches.dylib "$support/DiaPatches.dylib"
"$support/bin/diapatch" build >/dev/null
"$support/bin/diapatch" apply >/dev/null
rm -f "$report"
DIAPATCH_TEST="$report" nohup "$dia" >/dev/null 2>&1 &
for _ in $(seq 240); do [ -f "$report" ] && break; sleep 0.5; done
[ -f "$report" ] || { echo "Dia wrote no report in 2 minutes. Is it patched (./install.sh)?" >&2; exit 1; }

exec python3 - "$report" <<'EOF'
import json, sys
report = json.load(open(sys.argv[1]))
tabs = "in the sidebar" if report["layout"] == "sidebar" else "at the top"
print(f"Dia {report['dia']}, tabs {tabs}. The test can't move them: switch in Dia and run it again for the other layout.")
problems = 0
for key in report["unavailable"]:
    print(f"FAIL {key} is unavailable on this Dia version")
    problems += 1
if report["safeMode"]:
    print("FAIL Dia is in safe mode, so no patches loaded")
    problems += 1
for scenario in report["scenarios"]:
    print(("FAIL " if scenario["failures"] else "ok   ") + scenario["name"])
    for key, problem in sorted(scenario["failures"].items()):
        print(f"     {key}: {problem}")
    problems += len(scenario["failures"])
print(f"{len(report['scenarios'])} scenarios, {problems} problems")
sys.exit(1 if problems else 0)
EOF
