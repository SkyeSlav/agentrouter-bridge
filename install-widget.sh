#!/data/data/com.termux/files/usr/bin/bash
# install-widget.sh — install the Termux:Widget shortcut
HOME_DIR="${HOME:-/data/data/com.termux/files/home}"
APPDIR="$HOME_DIR/agentrouter-bridge"
SRC="$APPDIR/toggle-bridge.sh"
TASKS="$HOME_DIR/.shortcuts/tasks"
TERMS="$HOME_DIR/.shortcuts"

[ -f "$SRC" ] || { echo "missing $SRC"; exit 1; }
chmod +x "$SRC" "$HOME_DIR/start-bridge.sh" 2>/dev/null

mkdir -p "$TASKS" "$TERMS"

# Background version (no terminal window opens)
ln -sf "$SRC" "$TASKS/bridge on-off"
chmod +x "$TASKS/bridge on-off"

# Terminal version (opens a window so you can watch it)
cat > "$TERMS/bridge (watch)" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
exec "$SRC"
EOF
chmod +x "$TERMS/bridge (watch)"

echo "Installed:"
echo "  $TASKS/bridge on-off        (silent, background)"
echo "  $TERMS/bridge (watch)       (opens a terminal)"
echo
echo "Next:"
echo "  1. Install Termux:Widget from F-Droid (same source as Termux)"
echo "  2. Long-press home screen -> Widgets -> Termux:Widget"
echo "  3. Pick 'bridge on-off'"
