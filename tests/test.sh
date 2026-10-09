#!/bin/bash
# Sandboxed tests: fake Claude Profiles wrappers, fake Chrome data dir, stub `open`.
# Nothing outside a temp dir is read or written, and no app is launched.
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CLI="$ROOT/claude-chrome"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

export CLAUDE_CHROME_INSTANCES_DIR="$T/instances"
export CLAUDE_CHROME_APPS_DIR="$T/Applications"
export CLAUDE_CHROME_DATA="$T/Chrome"
export CLAUDE_CHROME_OPEN="$T/open-stub"
export CLAUDE_CHROME_LAUNCHCTL="$T/launchctl-stub"
export CLAUDE_CHROME_AGENTS_DIR="$T/LaunchAgents"
export CLAUDE_CHROME_APP="$T/Google Chrome.app"
LAUNCHCTL_LOG="$T/launchctl.log"
OPEN_LOG="$T/open.log"

pass=0 fail=0
check() {  # $1 description, rest: command that must succeed
    local d="$1"; shift
    if "$@"; then pass=$((pass + 1)); printf 'ok   %s\n' "$d"
    else fail=$((fail + 1)); printf 'FAIL %s\n' "$d"; fi
}

printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$OPEN_LOG" > "$CLAUDE_CHROME_OPEN"
chmod +x "$CLAUDE_CHROME_OPEN"
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$LAUNCHCTL_LOG" > "$CLAUDE_CHROME_LAUNCHCTL"
chmod +x "$CLAUDE_CHROME_LAUNCHCTL"
mkdir -p "$CLAUDE_CHROME_APP"
mkdir -p "$CLAUDE_CHROME_DATA"

make_wrapper() {  # $1 slug, $2 display name — mirrors the Claude Profiles launcher layout
    local app="$CLAUDE_CHROME_APPS_DIR/$2.app"
    mkdir -p "$app/Contents/MacOS"
    cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
	<key>CFBundleDisplayName</key><string>$2</string>
	<key>CFBundleIdentifier</key><string>local.claude-profiles.$1</string>
</dict>
</plist>
PLIST
    cat > "$app/Contents/MacOS/launcher" <<'LAUNCHER'
#!/bin/bash
DATA_DIR="$HOME/.claude-instances/SLUG"
CLAUDE_APP="/Applications/Claude.app"
exec /usr/bin/open -n -a "$CLAUDE_APP" --args --user-data-dir="$DATA_DIR"
LAUNCHER
    sed -i.bak "s/SLUG/$1/" "$app/Contents/MacOS/launcher" && rm -f "$app/Contents/MacOS/launcher.bak"
    chmod +x "$app/Contents/MacOS/launcher"
}

# one-command setup: no profiles yet -> friendly message, nothing installed
check "setup with no profiles explains what to do" sh -c "'$CLI' | grep -q 'No Claude Profiles apps found'"
check "setup with no profiles installs no agent" test ! -f "$CLAUDE_CHROME_AGENTS_DIR/io.github.lcbasu.claude-chrome.plist"
rm -f "$CLAUDE_CHROME_INSTANCES_DIR/chrome-map.tsv"
make_wrapper alice "Claude Alice"
make_wrapper work01 "Claude Work 01"
mkdir -p "$CLAUDE_CHROME_APPS_DIR/Unrelated.app/Contents/MacOS"   # must be ignored

MAP="$CLAUDE_CHROME_INSTANCES_DIR/chrome-map.tsv"
L_ALICE="$CLAUDE_CHROME_APPS_DIR/Claude Alice.app/Contents/MacOS/launcher"

# init
"$CLI" init >/dev/null
check "init maps every Claude Profiles app" test "$(grep -vc '^#' "$MAP")" -eq 2
check "init writes slug, profile dir and name" grep -q "$(printf 'alice\tClaude alice\tClaude Alice')" "$MAP"
"$CLI" init >/dev/null
check "init is idempotent" test "$(grep -vc '^#' "$MAP")" -eq 2

# list
check "list shows uncreated profiles" sh -c "'$CLI' list | grep -q 'alice.*not created'"

# open: seeds a named profile and passes the right args to open
"$CLI" open alice
check "open creates the Chrome profile dir" test -d "$CLAUDE_CHROME_DATA/Claude alice"
check "open names the new profile" grep -q '"name":"Claude Alice"' "$CLAUDE_CHROME_DATA/Claude alice/Preferences"
check "open targets the mapped profile" grep -q -- '-n -a .*Google Chrome.app --args --profile-directory=Claude alice$' "$OPEN_LOG"
echo '{"keep":true}' > "$CLAUDE_CHROME_DATA/Claude alice/Preferences"
"$CLI" open alice
check "open never touches an existing profile" grep -q keep "$CLAUDE_CHROME_DATA/Claude alice/Preferences"
check "open rejects unknown slugs" sh -c "! '$CLI' open nobody 2>/dev/null"

# setup / list status
"$CLI" setup work01
check "setup opens the extension store page" grep -q 'profile-directory=Claude work01 https://chromewebstore.google.com/detail/claude/fcoeoabgfenejglbffodgkkbkcdhcgfn' "$OPEN_LOG"
mkdir -p "$CLAUDE_CHROME_DATA/Claude alice/Extensions/fcoeoabgfenejglbffodgkkbkcdhcgfn"
check "list detects an installed extension" sh -c "'$CLI' list | grep -q 'alice.*installed'"
check "list detects a missing extension" sh -c "'$CLI' list | grep -q 'work01.*missing'"

# paired column: no config, paired to its own profile, paired elsewhere
check "list shows unpaired instances" sh -c "'$CLI' list | grep -q 'work01 .*missing *no$'"
EXT_STORE="$CLAUDE_CHROME_DATA/Claude alice/Local Extension Settings/fcoeoabgfenejglbffodgkkbkcdhcgfn"
mkdir -p "$CLAUDE_CHROME_INSTANCES_DIR/alice" "$CLAUDE_CHROME_INSTANCES_DIR/work01" "$EXT_STORE"
printf 'x"deviceId":"dev-alice-1"x' > "$EXT_STORE/000003.log"
printf '{\n  "preferences": {\n    "chromeExtension": {\n      "pairedDeviceId": "dev-alice-1"\n    }\n  }\n}\n' \
    > "$CLAUDE_CHROME_INSTANCES_DIR/alice/claude_desktop_config.json"
printf '{"preferences":{"chromeExtension":{"pairedDeviceId":"dev-someone-else"}}}' \
    > "$CLAUDE_CHROME_INSTANCES_DIR/work01/claude_desktop_config.json"
check "list shows a pairing to its own profile" sh -c "'$CLI' list | grep -q 'alice .*installed *yes$'"
check "list flags a pairing to another browser" sh -c "'$CLI' list | grep -q 'work01 .*other browser$'"

# install / uninstall
"$CLI" install >/dev/null
check "install hooks every launcher" test "$(grep -l 'claude-chrome hook' "$CLAUDE_CHROME_APPS_DIR"/*/Contents/MacOS/launcher | wc -l)" -eq 2
check "hook runs before Claude launches" sh -c "grep -n . '$L_ALICE' | grep -A1 'claude-chrome hook' | grep -q 'exec /usr/bin/open'"
check "hooked launcher is valid bash" bash -n "$L_ALICE"
check "hooked launcher stays executable" test -x "$L_ALICE"
check "install is idempotent" sh -c "'$CLI' install | grep -q 'hooked 0'"
: > "$OPEN_LOG"
HOME="$T/home" bash -c "$(sed 's/^exec .*/exit 0/' "$L_ALICE")"
check "hook opens the slug's Chrome profile" grep -q 'profile-directory=Claude alice' "$OPEN_LOG"
"$CLI" uninstall >/dev/null
check "uninstall removes every hook" sh -c "! grep -q 'claude-chrome hook' '$CLAUDE_CHROME_APPS_DIR'/*/Contents/MacOS/launcher"
check "uninstall restores a valid launcher" bash -n "$L_ALICE"

# one-command setup on a fresh machine
"$CLI" uninstall >/dev/null
rm -rf "$CLAUDE_CHROME_INSTANCES_DIR" "$CLAUDE_CHROME_DATA" && mkdir -p "$CLAUDE_CHROME_DATA"
: > "$OPEN_LOG"
UP_OUT=$("$CLI")
AGENT="$CLAUDE_CHROME_AGENTS_DIR/io.github.lcbasu.claude-chrome.plist"
check "setup maps every profile" test "$(grep -vc '^#' "$CLAUDE_CHROME_INSTANCES_DIR/chrome-map.tsv")" -eq 2
check "setup hooks every launcher" test "$(grep -l 'claude-chrome hook' "$CLAUDE_CHROME_APPS_DIR"/*/Contents/MacOS/launcher | wc -l)" -eq 2
check "setup writes the auto-sync agent" grep -q '<string>sync</string>' "$AGENT"
check "agent watches the apps folder" grep -q "<string>$CLAUDE_CHROME_APPS_DIR</string>" "$AGENT"
check "setup loads the agent" grep -q "^bootstrap gui/$(id -u) $AGENT" "$LAUNCHCTL_LOG"
check "setup opens Chrome for each profile missing the extension" test "$(grep -c chromewebstore "$OPEN_LOG")" -eq 2
check "setup tells the user what to click" sh -c "printf '%s' \"\$1\" | grep -q 'Add to Chrome'" _ "$UP_OUT"
mkdir -p "$CLAUDE_CHROME_DATA/Claude alice/Extensions/fcoeoabgfenejglbffodgkkbkcdhcgfn" \
         "$CLAUDE_CHROME_DATA/Claude work01/Extensions/fcoeoabgfenejglbffodgkkbkcdhcgfn"
: > "$OPEN_LOG"
check "re-running setup when done reports all set" sh -c "'$CLI' | grep -q 'All set'"
check "re-running setup opens nothing" test ! -s "$OPEN_LOG"

# sync: a profile added later is mapped and hooked silently
make_wrapper research "Claude Research"
check "sync is silent" test -z "$("$CLI" sync)"
check "sync maps the new profile" grep -q '^research' "$CLAUDE_CHROME_INSTANCES_DIR/chrome-map.tsv"
check "sync hooks the new launcher" grep -q 'claude-chrome hook' "$CLAUDE_CHROME_APPS_DIR/Claude Research.app/Contents/MacOS/launcher"

# uninstall removes the agent too
"$CLI" uninstall >/dev/null
check "uninstall removes the agent" test ! -f "$AGENT"
check "uninstall unloads the agent" grep -q "^bootout gui/$(id -u)/io.github.lcbasu.claude-chrome" "$LAUNCHCTL_LOG"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
