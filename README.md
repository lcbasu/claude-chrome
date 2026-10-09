# claude-chrome

**Use Claude in Chrome with several Claude Desktop accounts on one Mac, each account with its own Chrome profile.**

I run a few Claude Desktop accounts side by side with [Claude Profiles](https://github.com/jyito/Claude-Profiles). Every time one of them needed the browser, the Claude extension attached to whichever Chrome happened to be signed in, often the wrong one. I kept signing the extension out and back in to switch accounts. This small script is what I wrote to stop doing that. Sharing it in case you hit the same thing.

It gives each Claude account its own Chrome profile and opens that profile when you launch its Claude. After a one-time setup, each account finds its own browser.

![Before and after](docs/how-it-works.svg)

## You might be here because

- Claude in Chrome connects to the wrong Chrome profile, or to the wrong account.
- You have to sign the Claude extension out and back in to switch between Claude accounts.
- A Claude Desktop profile can't find your browser, even though Chrome is open with the extension installed.
- Claude keeps asking which browser to use.
- Your Claude Desktop log shows `local pairing disabled for this launch: userData relocated`.

## Why it happens

This is what I found by reading Claude Desktop's logs and app code, then confirming it on my own machine. It isn't documented by Anthropic, so it may change.

| What I observed | What it means |
|---|---|
| A Claude Desktop instance started with `--user-data-dir` (how multi-account launchers such as Claude Profiles work) logs `local pairing disabled for this launch: userData relocated`. It then reaches Chrome only through Anthropic's hosted bridge. | That instance only sees Chrome extensions signed into **the same Claude account**. |
| A Chrome profile has one Claude extension, signed into one account at a time. | One Chrome profile can serve one Claude account. |
| Claude uses its saved (paired) browser first. If none is saved and exactly one browser is connected, it uses that one. Otherwise it asks. | Sharing one Chrome profile between accounts means re-signing it every time you switch. |

So the fix is one Chrome profile per Claude account. `claude-chrome` sets that up and opens the right profile for you.

## Requirements

- macOS
- Google Chrome
- [Claude Profiles](https://github.com/jyito/Claude-Profiles) for running several Claude Desktop accounts. The launch hook is written for its launchers.

Tested with:

| Software | Version |
|---|---|
| macOS | 26.6.2 |
| Claude Desktop | 2.26454.2 |
| Claude Profiles | 0.7.3 |
| Google Chrome | 154.0.8037.98 |
| Claude extension | 1.0.100 |

If it doesn't work for you on another version, an issue with your versions and the output of `claude-chrome list` would help.

## Install

```bash
brew install lcbasu/tap/claude-chrome && claude-chrome
```

That's the whole setup. `claude-chrome` maps each Claude profile to a new Chrome profile and makes launching Claude open it. It also sets up anything you add later on its own. Then it opens a Chrome window for every account that still needs the Claude extension.

In each window that opens, two clicks are left to you. Chrome and Anthropic require you to do these yourself:

1. Click **Add to Chrome**.
2. Sign the extension into the Claude account named on the window.

That's all. Run `claude-chrome` again any time to check status.

![claude-chrome output](docs/terminal.svg)

<details>
<summary>Without Homebrew</summary>

```bash
git clone https://github.com/lcbasu/claude-chrome.git
cd claude-chrome && ./install.sh && claude-chrome
```

</details>

### If Claude still asks which browser to use

That happens only when two Chrome profiles are signed into the same Claude account. Sign the extra one out, or pair once: in that Claude profile, say **"switch browser"** and click **Connect** in its own Chrome window. `claude-chrome list` shows `PAIRED: yes` afterwards.

### Uninstall

```bash
claude-chrome uninstall && brew uninstall claude-chrome
```

## Commands

| Command | What it does |
|---|---|
| *(none)* | Full setup, safe to re-run: `init`, `install`, the auto-sync agent, and `setup` for accounts missing the extension. |
| `init` | Adds a row to the map for every Claude Profiles app. Safe to re-run. |
| `list` | Shows each profile, whether its Claude extension is installed, and whether its Claude instance is paired to it. |
| `open <slug>` | Opens that account's Chrome profile. |
| `setup <slug>` | Opens it on the Claude extension's store page. |
| `setup-all` | `setup` for every mapped profile. |
| `install` | Adds a one-line hook to each Claude Profiles launcher. Safe to re-run. |
| `sync` | `init` + `install`, silently. The auto-sync agent runs this. |
| `uninstall` | Removes the hooks and the auto-sync agent. |

The map is `~/.claude-instances/chrome-map.tsv`: one tab-separated line per account of `slug`, Chrome profile folder and Chrome profile name. Edit it to point an account at a different Chrome profile.

## What it changes on your Mac

- **Writes** the map file above.
- **Creates new Chrome profiles** by launching Chrome with `--profile-directory=<folder>`. It names a profile before its first launch so the window shows which account it belongs to. It never modifies existing Chrome profiles.
- **Adds one line** to each Claude Profiles launcher, right before the line that starts Claude. `claude-chrome uninstall` removes it.
- **Adds a LaunchAgent** (`~/Library/LaunchAgents/io.github.lcbasu.claude-chrome.plist`) that runs `claude-chrome sync` when `~/Applications` changes, so profiles you create later are set up too. `uninstall` removes it.
- Reads each Claude instance's `claude_desktop_config.json`, only to show the PAIRED column.

It makes no network requests, and it doesn't modify Claude Desktop, the Claude extension or Chrome itself.

## FAQ

### Can I use Claude in Chrome with more than one Claude account at the same time?

Yes, with one Chrome profile per account. Each profile's Claude extension stays signed into its own account, and each Claude Desktop instance connects to the profile signed into its account.

### Why does Claude in Chrome connect to the wrong Chrome profile?

A Claude instance can see every Chrome profile whose extension is signed into its account. If more than one is signed in and none is paired, or a different one was paired earlier, it can pick one you didn't intend. Pairing once with **switch browser → Connect** fixes the choice.

### What does "local pairing disabled for this launch: userData relocated" mean?

Claude Desktop writes this when it runs with a custom `--user-data-dir`, as multi-account launchers do. In that mode it doesn't use the local connection to Chrome; it uses the hosted bridge, which matches by Claude account.

### Why does Claude keep asking which browser to use?

More than one browser signed into the same Claude account is connected, and none is saved as paired. Pair once, or sign the extra one out.

### Do I need to do anything when I add another Claude profile?

Only the two clicks in its new Chrome window. The auto-sync agent maps and hooks the new profile as soon as Claude Profiles creates it. Run `claude-chrome` to open its Chrome window on the extension page.

### Why can't it install the Claude extension and sign in for me?

Chrome only installs Web Store extensions after you click "Add to Chrome", unless your organisation manages Chrome by policy. Signing in needs your Claude credentials, which a script shouldn't handle. Those two clicks per account are the only manual steps.

### Can two Chrome profiles use the same Google account?

You can sign in to websites with the same Google account in several Chrome profiles. Chrome Sync only allows one profile per Google account, so sign in to sites normally rather than turning on Sync.

### Does it work without Claude Profiles?

The pairing advice above applies to any setup. The `init` and `install` commands are written for Claude Profiles' launchers; `open` and `setup` work with any map you write by hand.

### Does it work on Windows or Linux?

No. It's written for macOS. The tests also run on Linux, but only to check the script itself.

### Is this an official Anthropic tool?

No. It's an independent script and isn't affiliated with Anthropic or Google.

## Development

```bash
tests/test.sh             # sandboxed: fake apps, fake Chrome, nothing launched
shellcheck claude-chrome tests/test.sh install.sh
```

Issues and pull requests are welcome.

## Thanks

To [jyito](https://github.com/jyito) for [Claude Profiles](https://github.com/jyito/Claude-Profiles), which this builds on.

## License

MIT. "Claude" is a trademark of Anthropic. "Chrome" is a trademark of Google.
