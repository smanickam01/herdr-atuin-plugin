# herdr-atuin-plugin

A [herdr](https://herdr.dev) plugin that opens [Atuin](https://atuin.sh)'s
interactive shell history search in a herdr popup, then inserts the command you
pick back into the pane you launched from — the same "press a key,
fuzzy-search history, hit enter" flow tmux users get from the Atuin tmux
integration, but for herdr.

| In the popup | Result |
|---|---|
| **Enter** | Command is inserted into your pane **and run** |
| **Tab** | Command is inserted into your pane, **left at the prompt** to edit or run yourself |
| **Esc** | Nothing happens |

## Requirements

- [herdr](https://herdr.dev) >= 0.7.0 (developed against 0.8.0)
- [atuin](https://atuin.sh) installed and initialized (`atuin init zsh` in your
  `.zshrc`, with history imported). Developed against atuin 18.19.0.
- `enter_accept = true` in `~/.config/atuin/config.toml` — required for the
  Enter/Tab split described below. Without it, Tab and Enter behave identically
  and everything is inserted without running.
- macOS for the clipboard convenience copy (`pbcopy`); see [Platform
  support](#platform-support)

## Install

```sh
herdr plugin install smanickam01/herdr-atuin-plugin
```

That's it — `prefix+a` works immediately. The install step writes the keybinding
into `~/.config/herdr/config.toml` for you and reloads herdr, because herdr
[ignores keybindings declared in a plugin manifest](#why-the-keybinding-lives-in-configtoml).

**What it writes to your config**, in a marked block appended at the end:

```toml
# >>> herdr-atuin-plugin (managed) >>>
[[keys.command]]
key = "prefix+a"
type = "plugin_action"
command = "atuin.history-popup.shell-history"
description = "Open Atuin history search"
# <<< herdr-atuin-plugin (managed) <<<
```

Details of that edit:

- Your `config.toml` is backed up to `config.toml.bak-<timestamp>` first. Only
  the 3 most recent backups are kept, so reinstalls don't pile them up.
- **An existing `prefix+a` binding is commented out** so this one takes effect.
  The install output says so when it happens; recover it from the backup or by
  uncommenting.
- Reinstalling rewrites the same marked block rather than adding a second one.
- To use a different key, edit the block — but note a reinstall restores
  `prefix+a`. To opt out permanently, delete the block and bind
  `atuin.history-popup.shell-history` wherever you like.
- Uninstalling the plugin does **not** remove the block; delete it by hand.

Nothing else in your config is touched, and a failure here (unwritable config,
etc.) reports and moves on rather than failing the install.

### Local development

```sh
git clone https://github.com/smanickam01/herdr-atuin-plugin.git
herdr plugin link ./herdr-atuin-plugin
```

`herdr plugin link` registers the plugin from that directory in place, skipping
the `[[build]]` step — convenient while editing. Re-run it after manifest
changes.

Because `link` skips builds, the keybinding is not installed automatically. Run
it yourself once:

```sh
zsh ./setup-keybinding.sh
```

## Usage

Press `prefix+a` in any pane. A popup opens with Atuin's interactive search.
Select a command and accept it with **Enter** to insert and run it, or **Tab**
to insert it without running so you can edit it first. Esc cancels. Either way
the command is also copied to your clipboard.

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
  `herdr pane send-text`, followed by `herdr pane send-keys <pane> enter` only
  when the selection should run.

### Telling Enter apart from Tab

The script invokes atuin as `ATUIN_SHELL=zsh atuin search -i`. That env var puts
atuin in shell-integration mode, where (with `enter_accept = true` in your atuin
config) it prefixes the result with `__atuin_accept__:` if you accepted with
Enter, and returns the bare command for Tab. Stripping that prefix is what
decides whether the Enter keypress is sent:

| Accept key | `ATUIN_SHELL` set | atuin stdout |
|---|---|---|
| Enter | yes | `__atuin_accept__:<command>` |
| Enter | no | `<command>` |
| Tab | either | `<command>` |

Without `ATUIN_SHELL`, Enter and Tab are indistinguishable — atuin returns the
same bare string for both, which is why the env var is set explicitly rather
than relying on the ambient shell.

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

`setup-keybinding.sh` writes it there from `[[build]]` during install, which is
why installing is a single step. If herdr ever starts honoring manifest
keybindings, that block becomes redundant rather than wrong.

## Troubleshooting

The script logs to `$HERDR_PLUGIN_STATE_DIR/herdr-atuin.log`, typically:

```sh
tail ~/.local/state/herdr/plugins/atuin.history-popup/herdr-atuin.log
```

A successful run logs `OK ran on <pane_id>: <command>` (Enter) or
`OK inserted on <pane_id> (tab, not run): <command>` (Tab).

| Symptom | Check |
|---|---|
| `prefix+a` does nothing | Is the managed block present in `~/.config/herdr/config.toml`? If you installed with `plugin link`, run `zsh ./setup-keybinding.sh`. Then `herdr config check` and `herdr server reload-config`. |
| Popup opens, then closes instantly | `herdr-atuin: 'atuin' not found on PATH` — herdr runs plugin commands non-interactively, so `.zshrc` is not sourced. Ensure atuin is on the default PATH. |
| Command copied but not inserted | Log shows `no target pane` or a `send-text` failure; check `herdr pane list`. |
| Enter inserts but does not run | `enter_accept = true` missing from `~/.config/atuin/config.toml`, so atuin never emits the `__atuin_accept__:` prefix. |
| Nothing in `herdr plugin log list` | The action never fired — the keybinding is not registered. See above. |

## Platform support

The core flow (popup + `send-text`) is cross-platform, since it uses herdr's own
API. The only macOS-specific piece is the `pbcopy` clipboard convenience, which
fails soft (logged as a warning) — replace it with `wl-copy` or `xclip` for
Linux. The manifest currently declares `platforms = ["macos"]`; widen it once
that swap is made.

## License

MIT, see [LICENSE](LICENSE).
