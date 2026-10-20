#!/usr/bin/env bash
# Exercise the published command against an isolated Discord installation.
set -Eeuo pipefail
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
export HOME="$fixture/home" XDG_CONFIG_HOME="$fixture/config" XDG_DATA_HOME="$fixture/data"
core="$XDG_CONFIG_HOME/discord/app-1.0.1/modules/discord_desktop_core-1/discord_desktop_core"
mkdir -p -- "$core" "$HOME"
printf 'fixture' >"$core/core.asar"
printf "module.exports = require('./core.asar');\n// independent modification\n" >"$core/index.js"
cp -- "$core/index.js" "$fixture/original"
command="curl -fsSL https://raw.githubusercontent.com/sulistta/dc-auto-quest-downloads/main/install.sh | bash"
bash -o pipefail -c "$command"
grep -q 'BEGIN DC AUTO QUEST INTEGRATION' "$core/index.js"
grep -q 'independent modification' "$core/index.js"
cp -- "$core/index.js" "$fixture/installed"
bash -o pipefail -c "$command"
cmp -- "$fixture/installed" "$core/index.js"
"$HOME/.local/bin/dc-auto-quest" --status
"$HOME/.local/bin/dc-auto-quest" --remove
cmp -- "$fixture/original" "$core/index.js"
test ! -e "$XDG_DATA_HOME/dev.dcautoquest.desktop/integration.json"
printf 'Published Linux installation, repeat and removal passed.\n'
