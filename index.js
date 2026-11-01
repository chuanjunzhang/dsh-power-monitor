/**
 * dsh-power-monitor — 宿主侧
 *
 * 提供 GET /power-monitor/metrics：
 *  - 优先读取特权助手写入的快照 /tmp/dsh-power-monitor.json（含温度、风扇、功耗）
 *  - 助手未安装时退化为免密的 CPU/内存数据
 */
import { readFile } from 'node:fs/promises'
import { execFile } from 'node:child_process'
import { promisify } from 'node:util'
import os from 'node:os'

const execFileAsync = promisify(execFile)

export const inject = ['webServer']

const SNAPSHOT = '/tmp/dsh-power-monitor.json'
const MAX_AGE_MS = 8000

async function readSnapshot() {
  try {
    const raw = await readFile(SNAPSHOT, 'utf8')
    const data = JSON.parse(raw)
    if (typeof data.ts !== 'number') return null
    if (Date.now() - data.ts > MAX_AGE_MS) return null
    return data
  } catch {
    return null
  }
}

async function readMemory() {
  // os.freemem() 在 macOS 上只算 free page，偏低得离谱；改用 vm_stat 口径
  try {
    const { stdout } = await execFileAsync('vm_stat', [], { timeout: 1500 })
    const pageSize = Number(/page size of (\d+) bytes/.exec(stdout)?.[1] ?? 4096)
    const pages = (label) => {
      const m = new RegExp('^' + label + ':[^0-9]*(\\d+)', 'm').exec(stdout)
      return m ? Number(m[1]) : 0
    }
    const total = os.totalmem()
    const used = (pages('Pages active') + pages('Pages wired down') + pages('Pages occupied by compressor')) * pageSize
    return { memUsed: used, memTotal: total }
  } catch {
    return { memUsed: os.totalmem() - os.freemem(), memTotal: os.totalmem() }
  }
}

async function fallbackMetrics() {
  const load = os.loadavg()[0]
  const cores = os.cpus().length || 1
  const mem = await readMemory()
  return {
    ts: Date.now(),
    source: 'fallback',
    cpu: Math.max(0, Math.min(100, (load / cores) * 100)),
    memUsed: mem.memUsed,
    memTotal: mem.memTotal,
    temp: null,
    fan: null,
    power: null,
  }
}

export function apply(ctx) {
  ctx.effect(() => ctx.webServer.register({
    kind: 'exact',
    path: '/power-monitor/metrics',
    handler: async (req, res) => {
      const base = await fallbackMetrics()
      const snap = await readSnapshot()
      const payload = snap
        ? { ...snap, cpu: base.cpu, memUsed: base.memUsed, memTotal: base.memTotal, source: 'helper' }
        : base
      const body = JSON.stringify(payload)
      res.writeHead(200, {
        'Content-Type': 'application/json; charset=utf-8',
        'Cache-Control': 'no-store',
      })
      res.end(body)
    },
  }), 'sysmon metrics route')
}
