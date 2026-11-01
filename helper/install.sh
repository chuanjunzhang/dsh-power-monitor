#!/bin/bash
# 安装特权助手：复制二进制与脚本，注册 LaunchDaemon（需要管理员密码）
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
BIN="$ROOT/bin/dsh-sysmon-smc"

[ -f "$BIN" ] || { echo "缺少 $BIN"; exit 1; }

echo "即将安装："
echo "  /usr/local/libexec/dsh-sysmon-smc"
echo "  /usr/local/libexec/dsh-sysmon-helper.sh"
echo "  /Library/LaunchDaemons/com.local.dsh-sysmon.plist"
echo
osascript <<APPLESCRIPT
do shell script "
mkdir -p /usr/local/libexec
cp '$BIN' /usr/local/libexec/dsh-sysmon-smc
cp '$HERE/dsh-sysmon-helper.sh' /usr/local/libexec/dsh-sysmon-helper.sh
cp '$HERE/com.local.dsh-sysmon.plist' /Library/LaunchDaemons/com.local.dsh-sysmon.plist
chown root:wheel /usr/local/libexec/dsh-sysmon-smc /usr/local/libexec/dsh-sysmon-helper.sh /Library/LaunchDaemons/com.local.dsh-sysmon.plist
chmod 755 /usr/local/libexec/dsh-sysmon-smc /usr/local/libexec/dsh-sysmon-helper.sh
chmod 644 /Library/LaunchDaemons/com.local.dsh-sysmon.plist
launchctl bootout system/com.local.dsh-sysmon 2>/dev/null || true
launchctl bootstrap system /Library/LaunchDaemons/com.local.dsh-sysmon.plist
echo done
" with administrator privileges
APPLESCRIPT

sleep 3
if [ -f /tmp/dsh-sysmon.json ]; then
  echo "✅ 已启动，当前快照："
  cat /tmp/dsh-sysmon.json
else
  echo "⚠️  守护进程已加载，但快照尚未生成。查看日志：/var/log/dsh-sysmon.err.log"
fi
