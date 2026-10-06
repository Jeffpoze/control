#!/bin/zsh
# Double-click to install Control on your plugged-in iPhone.
cd "$(dirname "$0")"
export PATH="$HOME/flutter/bin:$PATH"

echo "== Preparing the project (flutter pub get)…"
flutter pub get || { echo "pub get failed"; read -k1 "?Press any key to close"; exit 1; }

echo "== Looking for your iPhone (plug it in, unlock it, tap Trust)…"
DEVICE=""
for i in {1..20}; do
  DEVICE=$(flutter devices --machine 2>/dev/null | python3 -c '
import json,sys
for d in json.load(sys.stdin):
    if d.get("targetPlatform","").startswith("ios") and not d.get("emulator"):
        print(d["id"]); break')
  [ -n "$DEVICE" ] && break
  sleep 3
done
if [ -z "$DEVICE" ]; then
  echo "No iPhone found. Plug it in with a cable, unlock it, tap Trust, then run this again."
  read -k1 "?Press any key to close"; exit 1
fi
echo "== Found iPhone: $DEVICE"

echo "== Building and installing (first build takes a few minutes)…"
if ! flutter run --release -d "$DEVICE"; then
  echo ""
  echo "Install failed. If the error mentions signing or a development team:"
  echo "  Xcode is opening now -> click Runner -> Signing & Capabilities ->"
  echo "  tick 'Automatically manage signing' -> pick your Apple ID as Team."
  echo "  Then double-click iphone.command again."
  open ios/Runner.xcworkspace
fi
read -k1 "?Press any key to close"
