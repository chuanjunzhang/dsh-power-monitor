#!/bin/bash
# 彻底移除特权助手
set -euo pipefail
osascript <<'APPLESCRIPT'
do shell script "
launchctl bootout system/com.local.dsh-power-monitor 2>/dev/null || true
rm -f /Library/LaunchDaemons/com.local.dsh-power-monitor.plist
rm -f /usr/local/libexec/dsh-power-monitor-helper.sh /usr/local/libexec/dsh-power-monitor-smc
rm -f /tmp/dsh-power-monitor.json
echo done
" with administrator privileges
APPLESCRIPT
echo "✅ 助手已移除（插件本身仍在，会降级为仅显示 CPU/内存）"
