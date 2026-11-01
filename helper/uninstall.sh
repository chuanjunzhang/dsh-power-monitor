#!/bin/bash
# 彻底移除特权助手
set -euo pipefail
osascript <<'APPLESCRIPT'
do shell script "
launchctl bootout system/com.local.dsh-sysmon 2>/dev/null || true
rm -f /Library/LaunchDaemons/com.local.dsh-sysmon.plist
rm -f /usr/local/libexec/dsh-sysmon-helper.sh /usr/local/libexec/dsh-sysmon-smc
rm -f /tmp/dsh-sysmon.json
echo done
" with administrator privileges
APPLESCRIPT
echo "✅ 助手已移除（插件本身仍在，会降级为仅显示 CPU/内存）"
