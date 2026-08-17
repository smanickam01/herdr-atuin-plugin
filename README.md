# herdr-atuin-plugin

A [herdr](https://herdr.dev) plugin that opens [Atuin](https://atuin.sh)'s
interactive shell history search in a herdr popup, then inserts the command you
pick back into the pane you launched from and runs it — the same "press a key,
fuzzy-search history, hit enter" flow tmux users get from the Atuin tmux
integration, but for herdr.

## Requirements

- [herdr](https://herdr.dev) >= 0.7.0 (developed against 0.8.0)
- [atuin](https://atuin.sh) installed and initialized (`atuin init zsh` in your
  `.zshrc`, with history imported)
- macOS for the clipboard convenience copy (`pbcopy`); see [Platform
  support](#platform-support)

## Install

```sh
herdr plugin install smanickam01/herdr-atuin-plugin
```

Then add the keybinding to `~/.config/herdr/config.toml` — **this step is
required**, see [why](#why-the-keybinding-lives-in-configtoml):

```toml
[[keys.command]]
key = "prefix+a"
type = "plugin_action"
command = "atuin.history-popup.shell-history"
description = "Open Atuin history search"
```

Apply it without restarting:

```sh
herdr server reload-config
```

### Local development

```sh
git clone https://github.com/smanickam01/herdr-atuin-plugin.git
herdr plugin link ./herdr-atuin-plugin
```

`herdr plugin link` registers the plugin from that directory in place, skipping
the `[[build]]` step — convenient while editing. Re-run it after manifest
changes.

## Usage

Press `prefix+a` in any pane. A popup opens with Atuin's interactive search;
pick a command (or press Esc to cancel) and it is typed into the pane you came
from and executed. The command is also copied to your clipboard.

You can also trigger it without the keybinding:

```sh
herdr plugin action invoke atuin.history-popup shell-history
```

## How it works

```
prefix+a  →  [[actions]] shell-history  →  herdr plugin pane open
                                              ↓
                                      [[panes]] history (popup)
                                              ↓
                                        herdr-atuin.sh
                                              ↓
                                  herdr pane send-text → origin pane
```

- **`[[panes]] history`** declares the popup itself (`placement = "popup"`,
  80%×80%). Because placement and size live here, callers can open it with just
  `herdr plugin pane open --plugin atuin.history-popup --entrypoint history` and
  inherit the presentation — `placement` is optional in the API and falls back
  to the manifest.
- **`[[actions]] shell-history`** is the bindable bridge. Herdr keybindings can
  invoke a plugin action by qualified id but cannot target a pane directly, so
  this action opens the pane. It forwards the launching pane via
  `--env HERDR_ORIGIN_PANE_ID="$HERDR_PANE_ID"`, because a herdr popup is a
  session-modal singleton with **no pane id of its own** — the script otherwise
  has no way to know where it was launched from. The script falls back to the
  snapshot's `focused_pane_id`, which keeps pointing at the underlying pane
  while a popup is up.
- **`herdr-atuin.sh`** runs `atuin search -i`, then hands the result back with
  `herdr pane send-text` + `herdr pane send-keys <pane> enter`.

### Why not synthetic keystrokes?

An earlier version copied to the clipboard and simulated `Cmd+V` + Return via
AppleScript `System Events`. That approach is fragile here for two reasons:

1. **Permissions.** Keystroke injection requires Accessibility permission for
   the process that spawns it. Plugin panes are spawned by the headless herdr
   *server*, not by your terminal app, so the grant your terminal has does not
   apply.
2. **Focus race.** A popup closes only when its command exits, so the paste
   fired while the popup still had focus.

`herdr pane send-text` is an API call addressed to a specific pane id, so it
needs no permissions and does not depend on what is focused.

The clipboard copy uses `printf '%s' "$cmd" | pbcopy` rather than
`osascript -e "set the clipboard to \"$cmd\""` — piping passes the command as
data, so quotes and backslashes survive and history content can never be
interpreted as AppleScript.

### Why the keybinding lives in config.toml

herdr 0.8.0 parses `[[actions]]` and `[[panes]]` from a plugin manifest but
**silently ignores `[[keys.command]]` declared there** — no error, and
`herdr plugin install` still reports success. You can confirm what herdr
actually ingested:

```sh
python3 -m json.tool ~/.config/herdr/plugins.json   # actions + panes present, keys absent
```

So the binding has to live in the user's `config.toml`. Only the key itself
does — placement and sizing stay in the plugin's `[[panes]]` entry, so this
line does not need to change when the plugin does.

## Troubleshooting

The script logs to `$HERDR_PLUGIN_STATE_DIR/herdr-atuin.log`, typically:

```sh
tail ~/.local/state/herdr/plugins/atuin.history-popup/herdr-atuin.log
```

A successful run logs `OK sent to <pane_id>: <command>`.

| Symptom | Check |
|---|---|
| `prefix+a` does nothing | Is the `config.toml` block above present? Run `herdr config check`, then `herdr server reload-config`. |
| Popup opens, then closes instantly | `herdr-atuin: 'atuin' not found on PATH` — herdr runs plugin commands non-interactively, so `.zshrc` is not sourced. Ensure atuin is on the default PATH. |
| Command copied but not inserted | Log shows `no target pane` or a `send-text` failure; check `herdr pane list`. |
| Nothing in `herdr plugin log list` | The action never fired — the keybinding is not registered. See above. |

## Platform support

The core flow (popup + `send-text`) is cross-platform, since it uses herdr's own
API. The only macOS-specific piece is the `pbcopy` clipboard convenience, which
fails soft (logged as a warning) — replace it with `wl-copy` or `xclip` for
Linux. The manifest currently declares `platforms = ["macos"]`; widen it once
that swap is made.

## License

MIT, see [LICENSE](LICENSE).
