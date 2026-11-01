#!/bin/bash
# dsh-power-monitor 特权助手：采集 SMC（风扇/温度）+ powermetrics（功耗），写入快照供插件读取
SMC=/usr/local/libexec/dsh-power-monitor-smc
OUT=/tmp/dsh-power-monitor.json
PM=/usr/bin/powermetrics

while true; do
  smc_json=$("$SMC" 2>/dev/null)
  [ -z "$smc_json" ] && smc_json='{"fan":null,"cpuTemp":null,"gpuTemp":null}'

  pm_out=$("$PM" -n 1 -i 250 --samplers cpu_power,gpu_power 2>/dev/null)
  cpu_w=$(printf '%s' "$pm_out" | awk '/^CPU Power:/{print $3; exit}')
  gpu_w=$(printf '%s' "$pm_out" | awk '/^GPU Power:/{print $3; exit}')
  comb_w=$(printf '%s' "$pm_out" | awk '/^Combined Power/{print $(NF-1); exit}')

  /usr/bin/python3 - "$smc_json" "${cpu_w:-0}" "${gpu_w:-0}" "${comb_w:-0}" > "$OUT.tmp" <<'PY'
import json, sys, time
smc = json.loads(sys.argv[1])
cpu = float(sys.argv[2]) / 1000.0 if sys.argv[2] else None
gpu = float(sys.argv[3]) / 1000.0 if sys.argv[3] else None
comb = float(sys.argv[4]) / 1000.0 if sys.argv[4] else None
out = {
    "ts": int(time.time() * 1000),
    "cpu": smc.get("cpu"),
    "fan": smc.get("fan"),
    "temp": smc.get("cpuTemp"),
    "gpuTemp": smc.get("gpuTemp"),
    "cpuPower": cpu,
    "gpuPower": gpu,
    "power": comb,
}
print(json.dumps(out))
PY
  chmod 644 "$OUT.tmp" 2>/dev/null
  mv "$OUT.tmp" "$OUT"
  sleep 2
done
