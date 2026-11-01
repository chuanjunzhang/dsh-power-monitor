/**
 * dsh-power-monitor — 客户端（v2）
 *
 * 侧栏底部系统状态卡片：数值按阈值染色，状态点取最严重的一项。
 * 不新增任何采集项，只在渲染层做颜色与排版处理。
 */
window.__ModuleLoader__.load({
  id: 'dsh-power-monitor',
  factory(require) {
    const React = require('react')
    const h = React.createElement

    const POLL_MS = 2000

    // ---- 阈值配色：绿 → 琥珀 → 橙 → 红 ----
    const C = {
      ok: '#34c759',
      warm: '#ffb020',
      hot: '#ff8a00',
      danger: '#ff3b30',
      idle: '#8e8e93',
      muted: 'rgba(127,127,127,0.55)',
    }
    const RANK = { ok: 0, warm: 1, hot: 2, danger: 3 }

    const pick = (v, [a, b, c]) => {
      if (!Number.isFinite(v)) return 'idle'
      if (v < a) return 'ok'
      if (v < b) return 'warm'
      if (v < c) return 'hot'
      return 'danger'
    }

    const level = {
      cpu: (v) => pick(v, [30, 60, 85]),
      temp: (v) => pick(v, [55, 70, 82]),
      mem: (v) => pick(v, [60, 80, 90]),
      power: (v) => pick(v, [4, 12, 25]),
      fan: (v) => {
        if (!Number.isFinite(v)) return 'idle'
        if (v > 4200) return 'hot'
        if (v > 2600) return 'warm'
        return 'ok'
      },
    }

    const worst = (levels) => levels.reduce((acc, l) => (RANK[l] > RANK[acc] ? l : acc), 'ok')

    const fmtMem = (bytes) => {
      if (!Number.isFinite(bytes)) return '—'
      const gb = bytes / 1024 ** 3
      return gb >= 1 ? gb.toFixed(1) : `${Math.round(bytes / 1024 ** 2)}M`
    }
    const fmtFan = (v) => (Number.isFinite(v) ? `${Math.round(v)}` : '—')
    const fmtPower = (w) => {
      if (!Number.isFinite(w)) return '—'
      return w >= 10 ? `${Math.round(w)}` : w.toFixed(1)
    }

    function Value({ text, unit, levelName }) {
      const color = C[levelName] ?? C.idle
      return h('span', {
        style: {
          display: 'inline-flex',
          alignItems: 'baseline',
          gap: 1.5,
          color,
          fontVariantNumeric: 'tabular-nums',
          transition: 'color 400ms ease',
        },
      }, [
        h('span', { key: 'v', style: { fontSize: 12.5, fontWeight: 620, letterSpacing: '-0.01em' } }, text),
        unit
          ? h('span', { key: 'u', style: { fontSize: 9, fontWeight: 500, opacity: 0.7 } }, unit)
          : null,
      ])
    }

    function Cell({ label, text, unit, levelName, title }) {
      return h('div', {
        title,
        style: {
          display: 'flex',
          alignItems: 'baseline',
          justifyContent: 'space-between',
          gap: 6,
          minWidth: 0,
        },
      }, [
        h('span', {
          key: 'l',
          style: {
            fontSize: 9.5,
            fontWeight: 500,
            letterSpacing: '0.05em',
            color: 'inherit',
            opacity: 0.92,
            flex: '0 0 auto',
          },
        }, label),
        h(Value, { key: 'v', text, unit, levelName }),
      ])
    }

    function SysMonCard() {
      const [m, setM] = React.useState(null)
      const [alive, setAlive] = React.useState(true)
      const powerHistory = React.useRef([])

      React.useEffect(() => {
        let timer = null
        let stopped = false
        const tick = async () => {
          try {
            const res = await fetch('/power-monitor/metrics', { cache: 'no-store' })
            const data = await res.json()
            if (stopped) return
            // 功耗抖动大：取最近 3 次中位数平滑（仅渲染层，不增加采集）
            if (Number.isFinite(data.power)) {
              const hist = powerHistory.current
              hist.push(data.power)
              if (hist.length > 3) hist.shift()
              const sorted = [...hist].sort((x, y) => x - y)
              data.power = sorted[Math.floor(sorted.length / 2)]
            }
            setM(data)
            setAlive(true)
          } catch {
            if (!stopped) setAlive(false)
          }
        }
        tick()
        timer = setInterval(tick, POLL_MS)
        return () => {
          stopped = true
          if (timer) clearInterval(timer)
        }
      }, [])

      const memPct = m && Number.isFinite(m.memUsed) && Number.isFinite(m.memTotal)
        ? (m.memUsed / m.memTotal) * 100
        : NaN

      const lv = {
        cpu: level.cpu(m && m.cpu),
        mem: level.mem(memPct),
        temp: level.temp(m && m.temp),
        fan: level.fan(m && m.fan),
        power: level.power(m && m.power),
      }
      const overall = worst([lv.cpu, lv.temp, lv.power])
      const hasHelper = Boolean(m && m.source === 'helper')
      const dot = alive ? (hasHelper ? C[overall] : C.warm) : C.idle

      const tip = m
        ? [
            hasHelper ? '温度/风扇：特权助手' : '未检测到特权助手',
            Number.isFinite(m.cpu) ? `CPU ${m.cpu.toFixed(0)}%` : null,
            Number.isFinite(m.temp) ? `CPU ${m.temp.toFixed(1)}°C` : null,
            Number.isFinite(m.gpuTemp) ? `GPU ${m.gpuTemp.toFixed(1)}°C` : null,
            Number.isFinite(m.fan) ? (m.fan > 0 ? `风扇 ${Math.round(m.fan)} RPM` : '风扇已停转（低于启动温度）') : null,
            Number.isFinite(m.power) ? `合计 ${m.power.toFixed(2)} W` : null,
            Number.isFinite(m.cpuPower)
              ? `CPU ${m.cpuPower.toFixed(2)} W / GPU ${(m.gpuPower ?? 0).toFixed(2)} W`
              : null,
            Number.isFinite(memPct) ? `内存 ${memPct.toFixed(0)}%` : null,
          ].filter(Boolean).join('  ·  ')
        : '正在读取…'

      return h('div', {
        title: tip,
        style: {
          margin: '2px 10px 8px',
          padding: '8px 10px 7px',
          borderRadius: 12,
          border: '1px solid rgba(127,127,127,0.16)',
          background: 'linear-gradient(180deg, rgba(127,127,127,0.07), rgba(127,127,127,0.035))',
          color: 'inherit',
          fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif',
          userSelect: 'none',
        },
      }, [
        h('div', {
          key: 'grid',
          style: {
            display: 'grid',
            gridTemplateColumns: '1fr 1fr',
            columnGap: 12,
            rowGap: 5,
          },
        }, [
          h(Cell, {
            key: 'cpu', label: 'CPU',
            text: m && Number.isFinite(m.cpu) ? `${Math.round(m.cpu)}` : '—',
            unit: '%', levelName: lv.cpu, title: 'CPU 占用',
          }),
          h(Cell, {
            key: 'mem', label: 'MEM',
            text: m ? fmtMem(m.memUsed) : '—',
            unit: m ? 'G' : '', levelName: lv.mem,
            title: Number.isFinite(memPct) ? `内存占用 ${memPct.toFixed(0)}%（active+wired+压缩）` : '',
          }),
          h(Cell, {
            key: 'temp', label: 'TEMP',
            text: m && Number.isFinite(m.temp) ? `${m.temp.toFixed(0)}` : '—',
            unit: '°', levelName: lv.temp, title: 'CPU 传感器最高温',
          }),
          h(Cell, {
            key: 'fan', label: 'FAN',
            text: m ? fmtFan(m.fan) : '—',
            unit: 'rpm', levelName: lv.fan, title: '风扇转速',
          }),
        ]),
        h('div', {
          key: 'footer',
          style: {
            display: 'flex',
            alignItems: 'center',
            gap: 7,
            marginTop: 7,
            paddingTop: 6,
            borderTop: '1px solid rgba(127,127,127,0.12)',
          },
        }, [
          h('span', {
            key: 'dot',
            style: {
              width: 5, height: 5, borderRadius: 3, flex: '0 0 auto',
              background: dot,
              boxShadow: alive && hasHelper ? `0 0 7px ${dot}77` : 'none',
              transition: 'background 400ms ease',
            },
          }),
          h('span', {
            key: 'l',
            style: { fontSize: 9.5, fontWeight: 600, letterSpacing: '0.05em', color: 'inherit', opacity: 0.92 },
          }, 'PWR'),
          h('span', { key: 'gap', style: { flex: 1 } }),
          h(Value, { key: 'v', text: m ? fmtPower(m.power) : '—', unit: 'W', levelName: lv.power }),
        ]),
      ])
    }

    return {
      inject: ['slots'],
      apply(ctx) {
        ctx.slots.inject('sidebar.footer.action', () => ctx.slots.register({
          name: 'sidebar.footer.action',
          id: 'sysmon-card',
          order: 5,
        }, SysMonCard))
      },
    }
  },
})
