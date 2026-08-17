# herdr-atuin-plugin

A [herdr](https://herdr.dev) plugin that opens [Atuin](https://atuin.sh)'s
interactive shell history search in a herdr popup, then copies your pick to
the clipboard and pastes it back into the active pane — the same
"press a key, fuzzy-search history, hit enter" flow tmux users get from the
Atuin tmux integration, but for herdr.

## Requirements

- macOS (the paste-back step uses `osascript`/AppleScript; see [Platform
  support](#platform-support) below)
- [herdr](https://herdr.dev) >= 0.7.0
- [atuin](https://atuin.sh) installed and initialized (`atuin init zsh` in
  your `.zshrc`, with history already imported)

## Install

```sh
herdr plugin install smanickam01/herdr-atuin-plugin
```

### Local development

To iterate on the plugin from a working checkout instead of a managed
install:

```sh
git clone https://github.com/smanickam01/herdr-atuin-plugin.git
herdr plugin link ./herdr-atuin-plugin
```

`herdr plugin link` registers the plugin from that directory in place,
skipping the `[[build]]` step — convenient while editing the script.

## Usage

Press `prefix+a` in any herdr pane. A popup opens with Atuin's interactive
search; pick a command (or press Esc to cancel) and it's copied to your
clipboard and pasted back into the pane you came from, ready to run.

You can also invoke it as a plugin action (e.g. from a command palette or
`herdr plugin action invoke atuin.history-popup shell-history`) without the
keybinding.

## How it works

- `herdr-plugin.toml` declares:
  - a `shell-history` **action** that runs `herdr-atuin.sh`
  - a `prefix+a` **popup keybinding** (80% width/height) that runs the same
    script in a modal popup pane
- `herdr-atuin.sh`:
  1. runs `atuin search -i` and captures the selected command
  2. sets the macOS clipboard to that command via `osascript`
  3. briefly waits for the popup to close, then simulates `Cmd+V` + `Enter`
     via System Events so the command lands in your terminal buffer

Herdr runs plugin commands non-interactively with the plugin directory as
the working directory, so the script doesn't source `.zshrc` — it fails
fast with a clear error if `atuin` isn't resolvable on `PATH` instead of
silently doing nothing.

## Platform support

Currently macOS-only (`platforms = ["macos"]` in the manifest), because the
clipboard/paste-back step is implemented with AppleScript. Linux/Windows
support would mean swapping steps 2–3 in `herdr-atuin.sh` for an
equivalent clipboard + keystroke mechanism on those platforms (e.g. `xdotool`
or `wl-copy` on Linux) — contributions welcome.

## License

MIT, see [LICENSE](LICENSE).
