#!/bin/zsh
# Runs inside a herdr popup pane (see [[panes]] in herdr-plugin.toml).
# Picks a command from Atuin's interactive search and injects it back into the
# pane you launched from, using herdr's own pane API rather than synthetic
# keystrokes -- no Accessibility permissions and no focus race with the popup.
set -u

LOG="${HERDR_PLUGIN_STATE_DIR:-${TMPDIR:-/tmp}}/herdr-atuin.log"
log() { print -r -- "$(date '+%Y-%m-%d %H:%M:%S') $*" >>| "$LOG" 2>/dev/null || true; }

HERDR="${HERDR_BIN_PATH:-herdr}"

# Herdr launches plugin commands non-interactively (no .zshrc sourced), so fail
# loudly instead of silently if atuin isn't resolvable on this PATH.
if ! command -v atuin >/dev/null 2>&1; then
    print -u2 "herdr-atuin: 'atuin' not found on PATH ($PATH)"
    log "ERROR atuin not on PATH: $PATH"
    sleep 2
    exit 1
fi

# The popup itself has no pane id, so the launching action passes the origin
# pane through --env. Fall back to whatever is focused, which stays pointed at
# the underlying pane while a popup is up.
TARGET_PANE="${HERDR_ORIGIN_PANE_ID:-}"
if [ -z "$TARGET_PANE" ]; then
    TARGET_PANE=$("$HERDR" api snapshot 2>/dev/null \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["result"]["snapshot"].get("focused_pane_id") or "")' 2>/dev/null)
    log "HERDR_ORIGIN_PANE_ID unset; fell back to focused pane '$TARGET_PANE'"
fi

# ATUIN_SHELL=zsh puts atuin in shell-integration mode, where `enter_accept`
# makes it prefix the result with __atuin_accept__: when the selection was
# accepted with Enter. Tab returns the bare command. That prefix is the only
# signal distinguishing "run it" from "just put it on my prompt".
SELECTED_RAW=$(ATUIN_SHELL=zsh atuin search -i) || exit 0
[ -n "$SELECTED_RAW" ] || exit 0   # cancelled with Esc

if [[ "$SELECTED_RAW" == __atuin_accept__:* ]]; then
    SELECTED_CMD="${SELECTED_RAW#__atuin_accept__:}"
    RUN_IT=1
else
    SELECTED_CMD="$SELECTED_RAW"
    RUN_IT=0
fi

# Copy to the clipboard as a convenience. Piping to pbcopy keeps quotes and
# backslashes intact; interpolating into `osascript -e` would not.
printf '%s' "$SELECTED_CMD" | pbcopy 2>/dev/null || log "WARN pbcopy failed"

if [ -z "$TARGET_PANE" ]; then
    print -u2 "herdr-atuin: could not resolve a target pane; command is on your clipboard"
    log "ERROR no target pane for: $SELECTED_CMD"
    sleep 2
    exit 1
fi

"$HERDR" pane send-text "$TARGET_PANE" "$SELECTED_CMD" >/dev/null 2>&1 \
    || { log "ERROR send-text to $TARGET_PANE failed"; exit 1; }

if (( RUN_IT )); then
    "$HERDR" pane send-keys "$TARGET_PANE" enter >/dev/null 2>&1 \
        || log "WARN send-keys enter to $TARGET_PANE failed"
    log "OK ran on $TARGET_PANE: $SELECTED_CMD"
else
    log "OK inserted on $TARGET_PANE (tab, not run): $SELECTED_CMD"
fi
