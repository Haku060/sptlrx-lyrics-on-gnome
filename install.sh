#!/usr/bin/env bash
set -e

# ==========================================
#  sptlrx Lyrics Package — One-Click Install
# ==========================================

PREFIX="${PREFIX:-$HOME/.local}"
BIN_DIR="$PREFIX/bin"
AUTOSTART_DIR="$HOME/.config/autostart"
PIPE_PATH="${PIPE_PATH:-/tmp/sptlrx-lyrics}"

echo "==> Installing sptlrx lyrics package..."
echo "    Binary dir:  $BIN_DIR"
echo "    Pipe output: $PIPE_PATH"

mkdir -p "$BIN_DIR" "$AUTOSTART_DIR"

# 1. Install sptlrx binary
cp "$(dirname "$0")/sptlrx" "$BIN_DIR/sptlrx"
chmod +x "$BIN_DIR/sptlrx"
echo "    [✓] sptlrx → $BIN_DIR/sptlrx"

# 2. Install pipe script
cp "$(dirname "$0")/sptlrx-pipe" "$BIN_DIR/sptlrx-pipe"
chmod +x "$BIN_DIR/sptlrx-pipe"
echo "    [✓] sptlrx-pipe → $BIN_DIR/sptlrx-pipe"

# 3. Install autostart entry (with correct paths)
sed -e "s|/home/haku/.local|$PREFIX|g" \
    -e "s|/tmp/sptlrx-lyrics|$PIPE_PATH|g" \
    "$(dirname "$0")/sptlrx-pipe.desktop" > "$AUTOSTART_DIR/sptlrx-pipe.desktop"
echo "    [✓] autostart → $AUTOSTART_DIR/sptlrx-pipe.desktop"

# 4. Kill old process if running
pkill -f "sptlrx-pipe" 2>/dev/null || true

# 5. Start now (optional — with Spotify login check)
if [ -f "$HOME/.local/state/sptlrx/spotify-auth.json" ]; then
    nohup "$BIN_DIR/sptlrx-pipe" "$PIPE_PATH" &>/dev/null &
    echo ""
    echo "    🎵 Lyrics pipe started (PID $!)"
    echo "    📁 Output file: $PIPE_PATH"
    echo "    📊 Monitor:  watch -n0.5 cat $PIPE_PATH"
else
    echo ""
    echo "    ⚠ Spotify not logged in yet. Run: sptlrx login"
fi

echo ""
echo "    ✅ Done! Configure GNOME Executor extension:"
echo "       Command: cat $PIPE_PATH"
echo "       Interval: 1s"
