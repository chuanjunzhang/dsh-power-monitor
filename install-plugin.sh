#!/bin/bash
# 把插件链接进 DSH 默认 profile 并登记到 bundles
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PROFILE="${DSH_PROFILE:-$HOME/.dsh/profiles/desktop}"
PKG="dsh-power-monitor"

[ -d "$PROFILE" ] || { echo "找不到 profile: $PROFILE"; exit 1; }
mkdir -p "$PROFILE/node_modules"
ln -sfn "$HERE" "$PROFILE/node_modules/$PKG"
/usr/bin/python3 - "$PROFILE/package.json" "$PKG" <<'PY'
import json, sys
path, pkg = sys.argv[1], sys.argv[2]
d = json.load(open(path))
bundles = d.setdefault('dsh', {}).setdefault('profile', {}).setdefault('bundles', [])
if pkg not in bundles:
    bundles.append(pkg)
json.dump(d, open(path, 'w'), indent=2, ensure_ascii=False)
print('bundles =', bundles)
PY
echo "✅ 插件已注册。重启 DeepSeek Harness 生效。"
