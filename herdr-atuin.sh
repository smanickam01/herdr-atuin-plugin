#!/bin/zsh
# 0. Herdr launches plugin commands non-interactively (no .zshrc sourced), so
#    fail loudly instead of silently if atuin isn't resolvable on this PATH.
if ! command -v atuin >/dev/null 2>&1; then
    echo "herdr-atuin: 'atuin' not found on PATH ($PATH)" >&2
    exit 1
fi

# 1. Force Atuin to open its interactive menu and capture the output
SELECTED_CMD=$(atuin search -i)

# 2. Check if a command was actually selected (not cancelled via Esc)
if [ -n "$SELECTED_CMD" ]; then
    # 3. Securely set the macOS clipboard using native AppleScript
    osascript -e "set the clipboard to \"$SELECTED_CMD\""

    # 4. Pause briefly (0.1s) to allow Herdr's popup window to finish closing 
    #    so the paste focus returns to your active terminal pane buffer
    sleep 0.1
    
    # 5. Tell macOS System Events to simulate pressing Cmd+V followed by Enter
    /usr/bin/osascript -e '
        tell application "System Events"
            keystroke "v" using {command down}
            delay 0.05
            key code 36
        end tell
    '
fi
