#!/usr/bin/env bash
set -e

# ==========================================
#  MPRIS Lyrics on GNOME — One-Click Install
#  Repository: mpris-lyrics-on-gnome
#  Local MPRIS edition (no account-based service)
# ==========================================

PREFIX="${PREFIX:-$HOME/.local}"
BIN_DIR="$PREFIX/bin"
DATA_DIR="$PREFIX/share/mpris-lyrics"
SCHEMA_DIR="$PREFIX/share/glib-2.0/schemas"
AUTOSTART_DIR="$HOME/.config/autostart"
PIPE_PATH="${PIPE_PATH:-/tmp/mpris-lyrics}"
# Optional: pin a specific MPRIS player, e.g. MPRIS_PLAYER=spotify
MPRIS_PLAYER="${MPRIS_PLAYER:-}"

PIPE_NAME="mpris-lyrics-pipe"
SERVICE_NAME="mpris-lyrics.service"
EXT_UUID="mpris-lyrics@gnome-shell-extension"
SCHEMA_ID="org.gnome.shell.extensions.mpris-lyrics"
SCHEMA_FILE="$SCHEMA_DIR/$SCHEMA_ID.gschema.xml"
CONF_DIR="$HOME/.config/mpris-lyrics"
CONF="$CONF_DIR/config.yaml"

# Legacy names from the previous sptlrx-based installation.
LEGACY_SCRIPT="$BIN_DIR/sptlrx-pipe"
LEGACY_SERVICE="sptlrx-pipe.service"
LEGACY_EXT_UUID="sptlrx-lyrics@gnome-shell-extension"
LEGACY_EXT_DIR="$HOME/.local/share/gnome-shell/extensions/$LEGACY_EXT_UUID"
LEGACY_SCHEMA="$SCHEMA_DIR/org.gnome.shell.extensions.sptlrx-lyrics.gschema.xml"
LEGACY_CONF_DIR="$HOME/.config/sptlrx"
LEGACY_CONF="$LEGACY_CONF_DIR/config.yaml"
LEGACY_DATA_DIR="$HOME/.local/share/sptlrx"
LEGACY_OUTPUT="/tmp/sptlrx-lyrics"

if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: python3 is required by $PIPE_NAME." >&2
    exit 1
fi

echo "==> Installing MPRIS lyrics for GNOME..."
echo "    Binary dir:  $BIN_DIR"
echo "    Pipe output: $PIPE_PATH"

mkdir -p "$BIN_DIR" "$DATA_DIR" "$SCHEMA_DIR" "$AUTOSTART_DIR" "$CONF_DIR"

# 1. Stop the legacy service and migrate old settings/files.
if command -v systemctl >/dev/null 2>&1 && \
   systemctl --user show-environment >/dev/null 2>&1; then
    systemctl --user disable --now "$LEGACY_SERVICE" >/dev/null 2>&1 || true
    rm -f "$HOME/.config/systemd/user/$LEGACY_SERVICE"
    systemctl --user daemon-reload >/dev/null 2>&1 || true
fi

if [ -f "$LEGACY_OUTPUT.pid" ]; then
    OLD_PID="$(cat "$LEGACY_OUTPUT.pid" 2>/dev/null || true)"
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        if tr '\0' ' ' < "/proc/$OLD_PID/cmdline" 2>/dev/null | grep -q "sptlrx-pipe"; then
            kill "$OLD_PID" 2>/dev/null || true
        fi
    fi
    rm -f "$LEGACY_OUTPUT.pid"
fi

rm -f "$AUTOSTART_DIR/sptlrx-pipe.desktop"
rm -f "$BIN_DIR/sptlrx" "$LEGACY_SCRIPT"

if [ -f "$LEGACY_CONF" ] && [ ! -f "$CONF" ]; then
    cp "$LEGACY_CONF" "$CONF"
    echo "    [✓] migrated config → $CONF"
fi

if [ -f "$LEGACY_DATA_DIR/TSCharacters.txt" ] && \
   [ ! -f "$DATA_DIR/TSCharacters.txt" ]; then
    cp "$LEGACY_DATA_DIR/TSCharacters.txt" "$DATA_DIR/TSCharacters.txt"
fi

if command -v dconf >/dev/null 2>&1; then
    OLD_SETTINGS="$(dconf dump /org/gnome/shell/extensions/sptlrx-lyrics/ 2>/dev/null || true)"
    NEW_SETTINGS="$(dconf dump /org/gnome/shell/extensions/mpris-lyrics/ 2>/dev/null || true)"
    if [ -n "$OLD_SETTINGS" ] && [ -z "$NEW_SETTINGS" ]; then
        printf '%s\n' "$OLD_SETTINGS" | \
            dconf load /org/gnome/shell/extensions/mpris-lyrics/ 2>/dev/null || true
        echo "    [✓] migrated extension settings"
    fi
fi

if command -v gnome-extensions >/dev/null 2>&1; then
    gnome-extensions disable "$LEGACY_EXT_UUID" >/dev/null 2>&1 || true
fi
rm -rf "$LEGACY_EXT_DIR"
rm -f "$LEGACY_SCHEMA"
rm -f "$HOME/.config/systemd/user/$LEGACY_SERVICE"

rm -rf "$LEGACY_CONF_DIR" "$LEGACY_DATA_DIR"
rm -f "$LEGACY_OUTPUT" "$LEGACY_OUTPUT.log" "$LEGACY_OUTPUT.pid"

# 2. Install pipe script (atomic replace).
cp "$(dirname "$0")/$PIPE_NAME" "$BIN_DIR/.$PIPE_NAME.new"
chmod +x "$BIN_DIR/.$PIPE_NAME.new"
mv -f "$BIN_DIR/.$PIPE_NAME.new" "$BIN_DIR/$PIPE_NAME"
echo "    [✓] $PIPE_NAME → $BIN_DIR/$PIPE_NAME"

# 3. Traditional -> simplified data.
cp "$(dirname "$0")/data/TSCharacters.txt" "$DATA_DIR/TSCharacters.txt"
echo "    [✓] Chinese conversion data → $DATA_DIR/TSCharacters.txt"

# 4. Install the bundled GNOME Shell top-bar extension.
EXT_DIR="$HOME/.local/share/gnome-shell/extensions/$EXT_UUID"
mkdir -p "$EXT_DIR"
cp "$(dirname "$0")/gnome-extension/metadata.json" "$EXT_DIR/metadata.json"
cp "$(dirname "$0")/gnome-extension/stylesheet.css" "$EXT_DIR/stylesheet.css"
cp "$(dirname "$0")/gnome-extension/prefs.js" "$EXT_DIR/prefs.js"
sed "s|/tmp/mpris-lyrics|$PIPE_PATH|g" \
    "$(dirname "$0")/gnome-extension/extension.js" > "$EXT_DIR/extension.js"

cp "$(dirname "$0")/gnome-extension/$SCHEMA_ID.gschema.xml" "$SCHEMA_FILE"
if command -v glib-compile-schemas >/dev/null 2>&1; then
    glib-compile-schemas "$SCHEMA_DIR"
    echo "    [✓] GNOME 扩展设置 schema → $SCHEMA_DIR"
else
    echo "    [!] glib-compile-schemas not found; extension preferences may not open"
fi
echo "    [✓] GNOME 顶栏扩展 → $EXT_DIR"

# 5. Check local MPRIS support (gdbus comes with GLib/GNOME).
if command -v gdbus >/dev/null 2>&1; then
    echo "    [✓] gdbus found"
else
    echo "    [!] gdbus not found — install glib2 (Debian/Ubuntu: libglib2.0-bin)"
fi

# 6. Point the pipe at the local MPRIS interface and optionally pin a player.
mkdir -p "$CONF_DIR"
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

# Force the local MPRIS player (no account-based login).
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

# 7. Enable the new extension and remove legacy/stale UUIDs.
if command -v gsettings >/dev/null 2>&1; then
    python3 - "$EXT_UUID" <<'PY' || true
import ast
import subprocess
import sys

uuid = sys.argv[1]
old_uuids = {
    "sptlrx-lyrics@gnome-shell-extension",
    "spotify-lyrics@gnome-shell-extension",
}

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

enabled = [item for item in enabled if item not in old_uuids]
if uuid not in enabled:
    enabled.append(uuid)

subprocess.run(
    ["gsettings", "set", "org.gnome.shell", "enabled-extensions", repr(enabled)],
    check=False,
)
PY
    echo "    [✓] GNOME 扩展已启用"
fi

# 8. Remove any legacy instance still using the old output file.
PID_FILE="${PIPE_PATH}.pid"
KILLED=0
if [ -f "$PID_FILE" ]; then
    OLD_PID="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        if tr '\0' ' ' < "/proc/$OLD_PID/cmdline" 2>/dev/null | grep -q "$PIPE_NAME"; then
            kill "$OLD_PID" 2>/dev/null || true
            KILLED=1
        fi
    fi
    rm -f "$PID_FILE"
fi
if [ "$KILLED" -eq 0 ]; then
    pkill -f "$BIN_DIR/[$PIPE_NAME]" 2>/dev/null || true
fi

# 9. Start the new pipe. Prefer a systemd user service so snap-packaged
#    players are readable from an unconfined process.
USE_SYSTEMD=0
if command -v systemctl >/dev/null 2>&1 && \
   systemctl --user show-environment >/dev/null 2>&1; then
    USE_SYSTEMD=1
fi

if [ "$USE_SYSTEMD" -eq 1 ]; then
    UNIT_DIR="$HOME/.config/systemd/user"
    UNIT_FILE="$UNIT_DIR/$SERVICE_NAME"
    mkdir -p "$UNIT_DIR"
    cat > "$UNIT_FILE" <<EOF
[Unit]
Description=MPRIS lyrics pipe (local MPRIS)
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=$BIN_DIR/$PIPE_NAME $PIPE_PATH
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
EOF
    systemctl --user daemon-reload
    UNIT_ENABLED=0
    if systemctl --user enable "$SERVICE_NAME" >/dev/null 2>&1; then
        UNIT_ENABLED=1
    fi
    if systemctl --user restart "$SERVICE_NAME" >/dev/null 2>&1; then
        if [ "$UNIT_ENABLED" -eq 1 ]; then
            rm -f "$AUTOSTART_DIR/mpris-lyrics.desktop"
        fi
        echo ""
        echo "    🎵 Lyrics pipe started as a systemd user service"
        echo "    📁 Output file: $PIPE_PATH"
        echo "    📊 Monitor:  watch -n0.5 cat $PIPE_PATH"
        echo "    📜 Status:   systemctl --user status $SERVICE_NAME"
    else
        echo "    [!] systemd service failed to start, falling back to autostart"
        USE_SYSTEMD=0
    fi
fi

if [ "$USE_SYSTEMD" -eq 0 ]; then
    sed -e "s|/home/haku/.local|$PREFIX|g" \
        -e "s|/tmp/mpris-lyrics|$PIPE_PATH|g" \
        "$(dirname "$0")/mpris-lyrics.desktop" > "$AUTOSTART_DIR/mpris-lyrics.desktop"
    echo "    [✓] autostart → $AUTOSTART_DIR/mpris-lyrics.desktop"
    nohup "$BIN_DIR/$PIPE_NAME" "$PIPE_PATH" &>/dev/null &
    echo ""
    echo "    🎵 Lyrics pipe started (PID $!)"
    echo "    📁 Output file: $PIPE_PATH"
    echo "    📊 Monitor:  watch -n0.5 cat $PIPE_PATH"
fi

echo ""
echo "    ✅ Done! The top-bar extension is installed."
echo ""
echo "    ⚠  第一次安装/改名后需要重启 GNOME Shell 才会加载扩展："
echo "       X11:    按 Alt+F2，输入 r，回车"
echo "       Wayland: 注销并重新登录"
echo ""
echo "    All valid MPRIS players are auto-detected; the one that is"
echo "    currently playing is used."
echo "    To pin a single player: MPRIS_PLAYER=spotify ./install.sh"
