#!/bin/sh
# Build "Claude Usage.app" from this package and the monitor next to it.
#   ./build-app.sh            build into macos/build/
#   ./build-app.sh --install  also replace ~/Applications/Claude Usage.app and open it
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(dirname "$HERE")"
APP="$HERE/build/Claude Usage.app"

cd "$HERE"
swift build -c release --product ClaudeUsage
BIN="$(swift build -c release --show-bin-path)/ClaudeUsage"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/monitor/static"
cp "$BIN" "$APP/Contents/MacOS/ClaudeUsage"
cp "$HERE/Info.plist" "$APP/Contents/Info.plist"
cp -R "$HERE/Resources/." "$APP/Contents/Resources/"
cp "$REPO/monitor.py" "$APP/Contents/Resources/monitor/monitor.py"
cp "$REPO/static/index.html" "$APP/Contents/Resources/monitor/static/index.html"
codesign --force --sign - --timestamp=none "$APP"
echo "built $APP"

if [ "${1:-}" = "--install" ]; then
    DEST="$HOME/Applications/Claude Usage.app"
    SUPPORT="$HOME/Library/Application Support/Claude Usage"
    mkdir -p "$HOME/Applications" "$SUPPORT"
    # Keep the usage already collected, which outlives deleted transcripts.
    if [ ! -f "$SUPPORT/state.db" ] && [ -f "$REPO/state.db" ]; then
        cp "$REPO/state.db" "$SUPPORT/state.db"
        echo "copied state.db into $SUPPORT"
    fi
    osascript -e 'tell application id "com.ryangan.claude-usage" to quit' 2>/dev/null || true
    # A monitor left behind by an earlier copy would be reused and keep running the old monitor.py.
    pkill -f "$DEST/Contents/Resources/monitor/monitor.py" 2>/dev/null || true
    sleep 1
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    open "$DEST"
    echo "installed $DEST"
fi
