#!/bin/zsh
# Installs this plugin's prefix+a binding into the user's herdr config.toml.
#
# Runs from [[build]], i.e. during `herdr plugin install`. Build commands get no
# runtime/socket environment, so the config path is derived from XDG rather than
# read from HERDR_* vars.
#
# A [[build]] failure aborts the whole install, so this script always exits 0 --
# it reports problems rather than blocking the plugin from being installed.
set -u

MARKER_START="# >>> herdr-atuin-plugin (managed) >>>"
MARKER_END="# <<< herdr-atuin-plugin (managed) <<<"

# Every install writes a timestamped backup; keep only this many newest.
BACKUP_KEEP=3

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/herdr"
CONFIG="$CONFIG_DIR/config.toml"

mkdir -p "$CONFIG_DIR" 2>/dev/null || {
    print -u2 "herdr-atuin: cannot create $CONFIG_DIR; add the keybinding manually (see README)"
    exit 0
}
[ -f "$CONFIG" ] || : >"$CONFIG" 2>/dev/null

if [ ! -w "$CONFIG" ]; then
    print -u2 "herdr-atuin: $CONFIG is not writable; add the keybinding manually (see README)"
    exit 0
fi

# Report a pre-existing prefix+a binding that is not ours, so the overwrite is
# at least visible in the install output.
CONFLICT=$(awk '
    /^[ \t]*# >>> herdr-atuin-plugin/ { managed = 1 }
    /^[ \t]*# <<< herdr-atuin-plugin/ { managed = 0; next }
    managed { next }
    /^[ \t]*\[\[keys\.command\]\][ \t]*$/ { inblk = 1; next }
    /^[ \t]*\[/ { inblk = 0 }
    inblk && /^[ \t]*key[ \t]*=[ \t]*"prefix\+a"/ { found = 1 }
    END { if (found) print "yes" }
' "$CONFIG" 2>/dev/null)

BACKUP="$CONFIG.bak-$(date +%Y%m%d%H%M%S)"
cp "$CONFIG" "$BACKUP" 2>/dev/null || BACKUP=""

TMP="$CONFIG.herdr-atuin.tmp.$$"

# Pass 1 drops any previously managed block (keeps reinstalls idempotent).
# Pass 2 comments out any remaining active prefix+a binding, so ours wins.
awk -v ms="$MARKER_START" -v me="$MARKER_END" '
    { line[++n] = $0 }
    END {
        m = 0
        for (i = 1; i <= n; i++) {
            if (index(line[i], ms) == 1) {
                while (i <= n && index(line[i], me) != 1) i++
                continue
            }
            keep[++m] = line[i]
        }

        i = 1
        while (i <= m) {
            if (keep[i] ~ /^[ \t]*\[\[keys\.command\]\][ \t]*$/) {
                j = i + 1
                while (j <= m && keep[j] !~ /^[ \t]*\[/) j++
                hit = 0
                for (k = i; k < j; k++)
                    if (keep[k] ~ /^[ \t]*key[ \t]*=[ \t]*"prefix\+a"/) hit = 1
                for (k = i; k < j; k++) {
                    if (hit && keep[k] !~ /^[ \t]*$/ && keep[k] !~ /^[ \t]*#/)
                        print "# " keep[k]
                    else
                        print keep[k]
                }
                i = j
            } else {
                print keep[i]
                i++
            }
        }
    }
' "$CONFIG" >"$TMP" 2>/dev/null || {
    rm -f "$TMP"
    print -u2 "herdr-atuin: could not rewrite $CONFIG; add the keybinding manually (see README)"
    exit 0
}

{
    print -r -- ""
    print -r -- "$MARKER_START"
    print -r -- "# Added by herdr-atuin-plugin. Herdr ignores [[keys.command]] declared"
    print -r -- "# in a plugin manifest, so the binding has to live here. Edit the key"
    print -r -- "# below if you like; reinstalling the plugin rewrites this block."
    print -r -- "[[keys.command]]"
    print -r -- 'key = "prefix+a"'
    print -r -- 'type = "plugin_action"'
    print -r -- 'command = "atuin.history-popup.shell-history"'
    print -r -- 'description = "Open Atuin history search"'
    print -r -- "$MARKER_END"
} >>"$TMP"

mv "$TMP" "$CONFIG" 2>/dev/null || {
    rm -f "$TMP"
    print -u2 "herdr-atuin: could not write $CONFIG; add the keybinding manually (see README)"
    exit 0
}

print -r -- "herdr-atuin: bound prefix+a in $CONFIG"
[ -n "$CONFLICT" ] && print -r -- "herdr-atuin: an existing prefix+a binding was commented out"
[ -n "$BACKUP" ] && print -r -- "herdr-atuin: backup saved to $BACKUP"

# Drop all but the newest BACKUP_KEEP backups. The (Nom) glob qualifiers mean
# "no error if nothing matches, ordered by mtime, newest first".
typeset -a stale
stale=( "$CONFIG".bak-*(Nom) )
if (( ${#stale} > BACKUP_KEEP )); then
    rm -f -- "${stale[@]:$BACKUP_KEEP}" 2>/dev/null \
        && print -r -- "herdr-atuin: pruned $(( ${#stale} - BACKUP_KEEP )) old backup(s), kept newest $BACKUP_KEEP"
fi

# Best effort -- the server may not be running during install, and build
# commands do not get HERDR_BIN_PATH.
if command -v herdr >/dev/null 2>&1; then
    herdr server reload-config >/dev/null 2>&1 \
        && print -r -- "herdr-atuin: reloaded herdr config" \
        || print -r -- "herdr-atuin: run 'herdr server reload-config' to apply"
else
    print -r -- "herdr-atuin: run 'herdr server reload-config' to apply"
fi

exit 0
