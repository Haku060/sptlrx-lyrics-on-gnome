#!/usr/bin/env bash
set -e

# ==========================================
#  sptlrx Lyrics Package — One-Click Install
#  Local MPRIS edition (no Spotify account)
# ==========================================

PREFIX="${PREFIX:-$HOME/.local}"
BIN_DIR="$PREFIX/bin"
DATA_DIR="$PREFIX/share/sptlrx"
AUTOSTART_DIR="$HOME/.config/autostart"
PIPE_PATH="${PIPE_PATH:-/tmp/sptlrx-lyrics}"
# Optional: pin a specific MPRIS player, e.g. MPRIS_PLAYER=spotify
MPRIS_PLAYER="${MPRIS_PLAYER:-}"

if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: python3 is required by sptlrx-pipe." >&2
    exit 1
fi

echo "==> Installing sptlrx lyrics package..."
echo "    Binary dir:  $BIN_DIR"
echo "    Pipe output: $PIPE_PATH"

mkdir -p "$BIN_DIR" "$DATA_DIR" "$AUTOSTART_DIR"

# 1. Install sptlrx binary (atomic replace: it may be running right now)
cp "$(dirname "$0")/sptlrx" "$BIN_DIR/.sptlrx.new"
chmod +x "$BIN_DIR/.sptlrx.new"
mv -f "$BIN_DIR/.sptlrx.new" "$BIN_DIR/sptlrx"
echo "    [✓] sptlrx → $BIN_DIR/sptlrx"

# 2. Install pipe script (atomic replace as well)
cp "$(dirname "$0")/sptlrx-pipe" "$BIN_DIR/.sptlrx-pipe.new"
chmod +x "$BIN_DIR/.sptlrx-pipe.new"
mv -f "$BIN_DIR/.sptlrx-pipe.new" "$BIN_DIR/sptlrx-pipe"
echo "    [✓] sptlrx-pipe → $BIN_DIR/sptlrx-pipe"

# 2b. Traditional -> simplified data for better NetEase matching
cp "$(dirname "$0")/data/TSCharacters.txt" "$DATA_DIR/TSCharacters.txt"
echo "    [✓] Chinese conversion data → $DATA_DIR/TSCharacters.txt"

# 3. Install the bundled GNOME Shell top-bar extension
EXT_UUID="sptlrx-lyrics@gnome-shell-extension"
EXT_DIR="$HOME/.local/share/gnome-shell/extensions/$EXT_UUID"
mkdir -p "$EXT_DIR"
cp "$(dirname "$0")/gnome-extension/metadata.json" "$EXT_DIR/metadata.json"
cp "$(dirname "$0")/gnome-extension/stylesheet.css" "$EXT_DIR/stylesheet.css"
sed "s|/tmp/sptlrx-lyrics|$PIPE_PATH|g" \
    "$(dirname "$0")/gnome-extension/extension.js" > "$EXT_DIR/extension.js"
echo "    [✓] GNOME 顶栏扩展 → $EXT_DIR"

# 5. Check local MPRIS support (gdbus comes with GLib/GNOME)
if command -v gdbus >/dev/null 2>&1; then
    echo "    [✓] gdbus found"
else
    echo "    [!] gdbus not found — install glib2 (Debian/Ubuntu: libglib2.0-bin)"
fi

# 6. Point sptlrx at the local MPRIS interface and optionally pin a player
CONF="$HOME/.config/sptlrx/config.yaml"
mkdir -p "$(dirname "$CONF")"
python3 - "$CONF" "$MPRIS_PLAYER" <<'PY'
import os
import re
import sys

path, player = sys.argv[1], sys.argv[2]

if os.path.exists(path):
    with open(path) as f:
        lines = f.read().splitlines()
else:
    lines = []

# Force the local MPRIS player (no Spotify login).
for i, line in enumerate(lines):
    if re.match(r"^player\s*:", line):
        lines[i] = "player: mpris"
        break
else:
    lines.insert(0, "player: mpris")

# Pin one MPRIS player if requested; otherwise clear the pin so every
# MPRIS player is considered and the currently playing one is followed.
players_value = f"[{player}]" if player else "[]"
mpris_idx = None
for i, line in enumerate(lines):
    if re.match(r"^mpris\s*:", line):
        mpris_idx = i
        break

if mpris_idx is None:
    lines += ["mpris:", f"  players: {players_value}"]
else:
    # Look for an existing "players:" key inside the mpris block.
    block_end = len(lines)
    for j in range(mpris_idx + 1, len(lines)):
        raw = lines[j]
        if raw.strip() and not raw[0].isspace():
            block_end = j
            break
    for j in range(mpris_idx + 1, block_end):
        m = re.match(r"^(\s+)players\s*:", lines[j])
        if m:
            indent = m.group(1)
            lines[j] = f"{indent}players: {players_value}"
            # Remove an existing YAML block list under "players:".
            k = j + 1
            while k < len(lines):
                raw = lines[k]
                if not raw.strip() or raw.lstrip().startswith("#"):
                    k += 1
                    continue
                raw_indent = len(raw) - len(raw.lstrip())
                if raw.lstrip().startswith("- ") and raw_indent >= len(indent):
                    del lines[k]
                    continue
                break
            break
    else:
        lines.insert(mpris_idx + 1, f"  players: {players_value}")

with open(path, "w") as f:
    f.write("\n".join(lines).rstrip("\n") + "\n")
PY
echo "    [✓] config → $CONF (player: mpris)"
if [ -n "$MPRIS_PLAYER" ]; then
    echo "    [✓] MPRIS player pinned: $MPRIS_PLAYER"
else
    echo "    [✓] MPRIS auto-detect enabled (all players)"
fi

# 7. Enable the extension and remove the old stale UUID
if command -v gsettings >/dev/null 2>&1; then
    python3 - "$EXT_UUID" <<'PY' || true
import ast
import subprocess
import sys

uuid = sys.argv[1]
old_uuid = "spotify-lyrics@gnome-shell-extension"

try:
    raw = subprocess.check_output(
        ["gsettings", "get", "org.gnome.shell", "enabled-extensions"],
        text=True,
    ).strip()
    if raw.startswith("@as "):
        raw = raw[5:]
    enabled = ast.literal_eval(raw)
except Exception:
    enabled = []

enabled = [item for item in enabled if item != old_uuid]
if uuid not in enabled:
    enabled.append(uuid)

subprocess.run(
    ["gsettings", "set", "org.gnome.shell", "enabled-extensions", repr(enabled)],
    check=False,
)
PY
    echo "    [✓] GNOME 扩展已启用"
fi

# 8. Stop any old instance (PID file written by sptlrx-pipe)
PID_FILE="${PIPE_PATH}.pid"
KILLED=0
if [ -f "$PID_FILE" ]; then
    OLD_PID="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        if tr '\0' ' ' < "/proc/$OLD_PID/cmdline" 2>/dev/null | grep -q "sptlrx-pipe"; then
            kill "$OLD_PID" 2>/dev/null || true
            KILLED=1
        fi
    fi
    rm -f "$PID_FILE"
fi
# Fallback for installs upgraded from the old version (no PID file).
if [ "$KILLED" -eq 0 ]; then
    pkill -f "$BIN_DIR/[s]ptlrx-pipe" 2>/dev/null || true
fi

# 9. Start it. A systemd user service is preferred because it runs outside
#    the shell that launched this script; this matters for snap-packaged
#    players such as snap Spotify, whose AppArmor profile only allows
#    MPRIS access from unconfined peers.
USE_SYSTEMD=0
if command -v systemctl >/dev/null 2>&1 && \
   systemctl --user show-environment >/dev/null 2>&1; then
    USE_SYSTEMD=1
fi

if [ "$USE_SYSTEMD" -eq 1 ]; then
    UNIT_DIR="$HOME/.config/systemd/user"
    UNIT_FILE="$UNIT_DIR/sptlrx-pipe.service"
    mkdir -p "$UNIT_DIR"
    cat > "$UNIT_FILE" <<EOF
[Unit]
Description=sptlrx lyrics pipe (local MPRIS)
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=$BIN_DIR/sptlrx-pipe $PIPE_PATH
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
EOF
    systemctl --user daemon-reload
    UNIT_ENABLED=0
    if systemctl --user enable sptlrx-pipe.service >/dev/null 2>&1; then
        UNIT_ENABLED=1
    fi
    if systemctl --user restart sptlrx-pipe.service >/dev/null 2>&1; then
        # Avoid a second copy starting from autostart at the next login.
        if [ "$UNIT_ENABLED" -eq 1 ]; then
            rm -f "$AUTOSTART_DIR/sptlrx-pipe.desktop"
        fi
        echo ""
        echo "    🎵 Lyrics pipe started as a systemd user service"
        echo "    📁 Output file: $PIPE_PATH"
        echo "    📊 Monitor:  watch -n0.5 cat $PIPE_PATH"
        echo "    📜 Status:   systemctl --user status sptlrx-pipe.service"
    else
        echo "    [!] systemd service failed to start, falling back to autostart"
        USE_SYSTEMD=0
    fi
fi

if [ "$USE_SYSTEMD" -eq 0 ]; then
    sed -e "s|/home/haku/.local|$PREFIX|g" \
        -e "s|/tmp/sptlrx-lyrics|$PIPE_PATH|g" \
        "$(dirname "$0")/sptlrx-pipe.desktop" > "$AUTOSTART_DIR/sptlrx-pipe.desktop"
    echo "    [✓] autostart → $AUTOSTART_DIR/sptlrx-pipe.desktop"
    nohup "$BIN_DIR/sptlrx-pipe" "$PIPE_PATH" &>/dev/null &
    echo ""
    echo "    🎵 Lyrics pipe started (PID $!)"
    echo "    📁 Output file: $PIPE_PATH"
    echo "    📊 Monitor:  watch -n0.5 cat $PIPE_PATH"
fi

echo ""
echo "    ✅ Done! The top-bar extension is installed."
echo ""
echo "    ⚠  第一次安装需要重启 GNOME Shell 才会加载扩展："
echo "       X11:    按 Alt+F2，输入 r，回车"
echo "       Wayland: 注销并重新登录"
echo ""
echo "    All valid MPRIS players are auto-detected; the one that is"
echo "    currently playing is used."
echo "    To pin a single player: MPRIS_PLAYER=spotify ./install.sh"
