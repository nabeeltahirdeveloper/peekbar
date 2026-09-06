#!/bin/bash
# Launches dist/PeekBar.app with the debug bridge and exercises collapse, popup, arrange mode.
# Pre-seeds status item positions so the items land in the visible part of the bar.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swiftc -O Scripts/pbctl.swift -o dist/pbctl 2>/dev/null
pkill -x PeekBar 2>/dev/null || true
sleep 0.5
defaults write com.peekbar.app onboardingCompleted -bool true
defaults write com.peekbar.app "NSStatusItem Preferred Position peekbar_toggle" -float 230
defaults write com.peekbar.app "NSStatusItem Preferred Position peekbar_separator" -float 262
(dist/PeekBar.app/Contents/MacOS/PeekBar --debug-bridge >dist/peekbar.log 2>&1 &)
sleep 4
fail=0
check() { echo "$2" | grep -q "$3" && echo "PASS $1" || { echo "FAIL $1: $2"; fail=1; }; }
check ping "$(dist/pbctl ping)" pong
check collapsed "$(dist/pbctl status)" "collapsed=true"
dist/pbctl dump dist/smoke-collapsed.json >/dev/null
check hidden-offscreen "$(python3 -c "import json;r=json.load(open('dist/smoke-collapsed.json'));print('ok' if all(x['x']<0 for x in r if x['hidden']) and any(x['hidden'] for x in r) else 'bad')")" ok
check popup-open "$(dist/pbctl openPopup)" open
check popup-frame "$(dist/pbctl popupFrame)" "("
dist/pbctl closePopup >/dev/null
check arrange "$(dist/pbctl arrange; sleep 1; dist/pbctl status)" "collapsed=false"
check arrange-done "$(dist/pbctl arrangeDone; sleep 1; dist/pbctl status)" "collapsed=true"
# Monitoring
check idle-demand "$(dist/pbctl engineTasks)" "demand=\[\]"
check dashboard-open "$(dist/pbctl openDashboard; sleep 3; dist/pbctl popupFrame)" "400.0"
dist/pbctl metrics dist/smoke-metrics.json >/dev/null
check metrics-cpu "$(python3 -c "import json;print('cpu' in json.load(open('dist/smoke-metrics.json'))['readings'])")" True
check detail-esc "$(dist/pbctl openDetail cpu >/dev/null; dist/pbctl popupKey 53)" "page=home"
dist/pbctl closePopup >/dev/null; sleep 1
check demand-released "$(dist/pbctl engineTasks)" "demand=\[\]"
check widget-on "$(dist/pbctl widgetOn cpu:lineChart >/dev/null; sleep 3; dist/pbctl widgetFrames)" "drawn=true"
check widget-not-extra "$(dist/pbctl status)" "collapsed=true"
check widget-off "$(dist/pbctl widgetOff cpu >/dev/null; sleep 1; dist/pbctl widgetFrames)" "none"
check alert-fires "$(dist/pbctl alertsClear >/dev/null; dist/pbctl alertRule 'cpu.total above 0.001 2' >/dev/null; sleep 6; dist/pbctl alertStatus)" "active=1"
dist/pbctl alertsClear >/dev/null
dist/pbctl quit >/dev/null
sleep 1
defaults delete com.peekbar.app >/dev/null 2>&1 || true
rm -rf ~/Library/Application\ Support/PeekBar
exit $fail
