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
OPEN_LOG="$T/open.log"

pass=0 fail=0
check() {  # $1 description, rest: command that must succeed
    local d="$1"; shift
    if "$@"; then pass=$((pass + 1)); printf 'ok   %s\n' "$d"
    else fail=$((fail + 1)); printf 'FAIL %s\n' "$d"; fi
}

printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$OPEN_LOG" > "$CLAUDE_CHROME_OPEN"
chmod +x "$CLAUDE_CHROME_OPEN"
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

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
