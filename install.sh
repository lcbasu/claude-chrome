#!/bin/bash
# Install claude-chrome into $PREFIX (default ~/.local/bin).
set -eu

PREFIX="${PREFIX:-$HOME/.local/bin}"
SRC="$(cd "$(dirname "$0")" && pwd)/claude-chrome"

mkdir -p "$PREFIX"
install -m 0755 "$SRC" "$PREFIX/claude-chrome"
printf 'installed %s\n' "$PREFIX/claude-chrome"

case ":$PATH:" in
    *":$PREFIX:"*) ;;
    *) printf 'note: %s is not on your PATH; add it to your shell profile\n' "$PREFIX" ;;
esac

printf '\nnext:\n  claude-chrome init\n  claude-chrome install\n  claude-chrome setup-all\n'
