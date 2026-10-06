#!/bin/zsh
# Double-click to run Control in the iOS Simulator.
cd "$(dirname "$0")"
export PATH="$HOME/flutter/bin:$PATH"
echo "== Flutter: $(flutter --version 2>/dev/null | head -1)"
open -a Simulator
# wait for a booted simulator
for i in {1..30}; do xcrun simctl list devices booted | grep -q Booted && break; sleep 2; done
flutter pub get
flutter analyze
flutter test
flutter run -d "$(xcrun simctl list devices booted | grep -m1 Booted | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')"
