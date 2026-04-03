import { useState, useRef, useEffect, useCallback } from "react";

// ---------------------------------------------------------------------------
// Types — must match the Swift side exactly
// ---------------------------------------------------------------------------

type GlucosePoint = { time: number; value: number };

type GlucoseStats = {
  timeInRangePercent: number; // 0–100
  average: number;            // mmol/L
  periodLow: number;          // mmol/L
  rangeLabel: string;         // e.g. "24H" — shown in the average pill label
};

type GlucoseThresholds = {
  low: number;  // mmol/L — lower bound of target range
  high: number; // mmol/L — upper bound of target range
};

const DEFAULT_THRESHOLDS: GlucoseThresholds = { low: 4.5, high: 10.0 };

type InitialData = {
  readings: GlucosePoint[];
  stats: Record<string, GlucoseStats>; // keyed by range label: "3h" | "6h" | "12h" | "24h"
  thresholds: GlucoseThresholds;
  currentReading: { value: number; trend: string; timestamp: number };
};

type LiveUpdate = {
  value: number;
  trend: string;
  timestamp: number;
  stats: Record<string, GlucoseStats>; // keyed by range label: "3h" | "6h" | "12h" | "24h"
  thresholds?: GlucoseThresholds; // optional — only sent when thresholds change
};

// ---------------------------------------------------------------------------
// Trend map
// ---------------------------------------------------------------------------

const DEXCOM_TREND_MAP: Record<string, { arrow: string; color: string }> = {
  DoubleUp:       { arrow: "↑↑", color: "#ef4444" },
  SingleUp:       { arrow: "↑",  color: "#fb923c" },
  FortyFiveUp:    { arrow: "↗",  color: "#fbbf24" },
  Flat:           { arrow: "→",  color: "#34d399" },
  FortyFiveDown:  { arrow: "↘",  color: "#fbbf24" },
  SingleDown:     { arrow: "↓",  color: "#818cf8" },
  DoubleDown:     { arrow: "↓↓", color: "#ef4444" },
  NotComputable:  { arrow: "?",  color: "rgba(255,255,255,0.3)" },
  RateOutOfRange: { arrow: "-",  color: "rgba(255,255,255,0.3)" },
  None:           { arrow: "",   color: "transparent" },
};

// ---------------------------------------------------------------------------
// Chart
// ---------------------------------------------------------------------------

const RANGES = [
  { label: "3h",  hours: 3  },
  { label: "6h",  hours: 6  },
  { label: "12h", hours: 12 },
  { label: "24h", hours: 24 },
];

function GlucoseChart({ data, thresholds = DEFAULT_THRESHOLDS, yMin = 2, yMax = 16 }: {
  data: GlucosePoint[];
  thresholds?: GlucoseThresholds;
  yMin?: number; yMax?: number;
}) {
  const svgRef = useRef<SVGSVGElement>(null);
  const [dims, setDims] = useState({ w: 800, h: 320 });
  const [hovered, setHovered] = useState<{ x: number; y: number; value: number; time: number } | null>(null);

  useEffect(() => {
    const el = svgRef.current?.parentElement;
    if (!el) return;
    const ro = new ResizeObserver(([e]) => setDims({ w: e.contentRect.width, h: e.contentRect.height }));
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  const { low: LOW, high: HIGH } = thresholds;
  const pad = { top: 20, right: 42, bottom: 44, left: 16 };
  const W = dims.w - pad.left - pad.right;
  const H = dims.h - pad.top - pad.bottom;
  const toX = (t: number) => pad.left + ((t - data[0].time) / (data[data.length - 1].time - data[0].time)) * W;
  const toY = (v: number) => pad.top + (1 - (v - yMin) / (yMax - yMin)) * H;
  const pts = data.map(d => ({ x: toX(d.time), y: toY(d.value), ...d }));

  const pathD = pts.map((p, i) => {
    if (i === 0) return `M ${p.x} ${p.y}`;
    const prev = pts[i - 1];
    const cpx = (prev.x + p.x) / 2;
    return `C ${cpx} ${prev.y}, ${cpx} ${p.y}, ${p.x} ${p.y}`;
  }).join(" ");

  const areaD = pathD + ` L ${pts[pts.length-1].x} ${toY(yMin)} L ${pts[0].x} ${toY(yMin)} Z`;

  const tMin = data[0].time, tMax = data[data.length - 1].time;
  const dH = (tMax - tMin) / 3600000;
  const iH = dH <= 3 ? 0.5 : dH <= 6 ? 1 : dH <= 12 ? 2 : 4;
  const timeLabels: { x: number; label: string }[] = [];
  const sH = Math.ceil(tMin / (iH * 3600000)) * iH;
  for (let t = sH * 3600000; t <= tMax; t += iH * 3600000) {
    const x = pad.left + ((t - tMin) / (tMax - tMin)) * W;
    const d = new Date(t);
    timeLabels.push({ x, label: `${d.getHours().toString().padStart(2,"0")}:${d.getMinutes().toString().padStart(2,"0")}` });
  }

  const ySteps = [4, 6, 8, 10, 12, 14];
  const getColor = (v: number) => v < LOW ? "#f87171" : v > HIGH ? "#fb923c" : "#34d399";
  const cur = data[data.length - 1].value;
  const lowY = toY(LOW), highY = toY(HIGH);

  const handleMouseMove = useCallback((e: React.MouseEvent<SVGSVGElement>) => {
    const rect = svgRef.current!.getBoundingClientRect();
    const mx = e.clientX - rect.left;
    let closest = pts[0], minD = Infinity;
    for (const p of pts) { const d = Math.abs(p.x - mx); if (d < minD) { minD = d; closest = p; } }
    if (minD < 40) setHovered({ x: closest.x, y: closest.y, value: closest.value, time: closest.time });
    else setHovered(null);
  }, [pts]);

  return (
    <div style={{ position:"relative", width:"100%", height:"100%" }}>
      <svg ref={svgRef} width="100%" height="100%" onMouseMove={handleMouseMove} onMouseLeave={() => setHovered(null)} style={{ cursor:"crosshair" }}>
        <defs>
          <linearGradient id="lg" x1="0" y1="0" x2="1" y2="0">
            <stop offset="0%" stopColor="#818cf8" />
            <stop offset="45%" stopColor="#34d399" />
            <stop offset="100%" stopColor="#34d399" />
          </linearGradient>
          <linearGradient id="ag" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="#34d399" stopOpacity="0.14" />
            <stop offset="100%" stopColor="#34d399" stopOpacity="0" />
          </linearGradient>
          <filter id="glow">
            <feGaussianBlur stdDeviation="3" result="b" />
            <feMerge><feMergeNode in="b" /><feMergeNode in="SourceGraphic" /></feMerge>
          </filter>
          <clipPath id="cc"><rect x={pad.left} y={pad.top} width={W} height={H} /></clipPath>
        </defs>
        {ySteps.map(v => <line key={v} x1={pad.left} x2={pad.left+W} y1={toY(v)} y2={toY(v)} stroke="rgba(255,255,255,0.06)" strokeWidth="1" />)}
        {timeLabels.map(tl => <line key={tl.x} x1={tl.x} x2={tl.x} y1={pad.top} y2={pad.top+H} stroke="rgba(255,255,255,0.06)" strokeWidth="1" />)}
        <rect x={pad.left} y={highY} width={W} height={lowY - highY} fill="rgba(52,211,153,0.05)" clipPath="url(#cc)" />
        <line x1={pad.left} x2={pad.left+W} y1={lowY} y2={lowY} stroke="#f87171" strokeWidth="1" strokeDasharray="4 4" opacity="0.4" />
        <line x1={pad.left} x2={pad.left+W} y1={highY} y2={highY} stroke="#fb923c" strokeWidth="1" strokeDasharray="4 4" opacity="0.4" />
        <path d={areaD} fill="url(#ag)" clipPath="url(#cc)" />
        <path d={pathD} fill="none" stroke="url(#lg)" strokeWidth="2.5" strokeLinecap="round" clipPath="url(#cc)" filter="url(#glow)" />
        {ySteps.map(v => <text key={v} x={pad.left+W+8} y={toY(v)+4} fill="rgba(255,255,255,0.25)" fontSize="11" fontFamily="'SF Mono',ui-monospace,Menlo,monospace">{v}</text>)}
        {timeLabels.map(tl => <text key={tl.x} x={tl.x} y={pad.top+H+24} fill="rgba(255,255,255,0.25)" fontSize="11" fontFamily="'SF Mono',ui-monospace,Menlo,monospace" textAnchor="middle">{tl.label}</text>)}
        <circle cx={pts[pts.length-1].x} cy={pts[pts.length-1].y} r="8" fill={getColor(cur)} clipPath="url(#cc)" opacity="0.3" />
        <circle cx={pts[pts.length-1].x} cy={pts[pts.length-1].y} r="4" fill={getColor(cur)} clipPath="url(#cc)" filter="url(#glow)" />
        <circle cx={pts[pts.length-1].x} cy={pts[pts.length-1].y} r="2" fill="white" clipPath="url(#cc)" />
        {hovered && (<>
          <line x1={hovered.x} x2={hovered.x} y1={pad.top} y2={pad.top+H} stroke="rgba(255,255,255,0.1)" strokeWidth="1" />
          <circle cx={hovered.x} cy={hovered.y} r="5" fill={getColor(hovered.value)} opacity="0.9" />
          <circle cx={hovered.x} cy={hovered.y} r="2.5" fill="white" />
          <g transform={`translate(${Math.min(hovered.x+12, pad.left+W-84)},${Math.max(hovered.y-44, pad.top)})`}>
            <rect x="0" y="0" width="80" height="40" rx="7" fill="rgba(10,10,20,0.95)" stroke="rgba(255,255,255,0.1)" strokeWidth="1" />
            <text x="10" y="17" fill={getColor(hovered.value)} fontSize="15" fontWeight="700" fontFamily="'SF Mono',ui-monospace,Menlo,monospace">{hovered.value.toFixed(1)}</text>
            <text x="10" y="31" fill="rgba(255,255,255,0.35)" fontSize="10" fontFamily="'SF Mono',ui-monospace,Menlo,monospace">{new Date(hovered.time).toLocaleTimeString([],{hour:"2-digit",minute:"2-digit"})}</text>
          </g>
        </>)}
      </svg>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Stat pill
// ---------------------------------------------------------------------------

function Stat({ label, value, unit, color }: { label: string; value: string; unit?: string; color?: string }) {
  return (
    <div style={{ display:"flex", flexDirection:"column", gap:3, padding:"12px 16px", borderRadius:14, background:"rgba(255,255,255,0.03)", border:"1px solid rgba(255,255,255,0.07)" }}>
      <span style={{ fontSize:10, letterSpacing:"0.12em", textTransform:"uppercase", color:"rgba(255,255,255,0.3)", fontWeight:600 }}>{label}</span>
      <span style={{ fontSize:18, fontWeight:700, fontFamily:"'SF Mono',ui-monospace,Menlo,monospace", color: color || "rgba(255,255,255,0.9)" }}>
        {value}{unit && <span style={{ fontSize:12, fontWeight:400, color:"rgba(255,255,255,0.3)", marginLeft:4 }}>{unit}</span>}
      </span>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

function EmptyState() {
  return (
    <div style={{ minHeight:"100vh", background:"#09090f", display:"flex", alignItems:"center", justifyContent:"center" }}>
      <div style={{ textAlign:"center" }}>
        <div style={{ width:8, height:8, borderRadius:"50%", background:"rgba(255,255,255,0.2)", margin:"0 auto 16px", animation:"pulse 2s infinite" }} />
        <p style={{ color:"rgba(255,255,255,0.2)", fontSize:13, fontFamily:"-apple-system,sans-serif", letterSpacing:"0.04em" }}>
          Waiting for data
        </p>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// App
// ---------------------------------------------------------------------------

export default function App() {
  const [activeRange, setActiveRange] = useState(1);

  const [readings, setReadings] = useState<GlucosePoint[]>(() => {
    const d = (window as any).__INITIAL_DATA__ as InitialData | undefined;
    return d?.readings ?? [];
  });

  const [stats, setStats] = useState<Record<string, GlucoseStats> | null>(() => {
    const d = (window as any).__INITIAL_DATA__ as InitialData | undefined;
    return d?.stats ?? null;
  });

  const [thresholds, setThresholds] = useState<GlucoseThresholds>(() => {
    const d = (window as any).__INITIAL_DATA__ as InitialData | undefined;
    return d?.thresholds ?? DEFAULT_THRESHOLDS;
  });

  const [liveTrend, setLiveTrend] = useState<string | null>(() => {
    const d = (window as any).__INITIAL_DATA__ as InitialData | undefined;
    return d?.currentReading?.trend ?? null;
  });

  useEffect(() => {
    (window as any).updateReading = (update: LiveUpdate) => {
      setReadings(prev => [...prev, { time: update.timestamp, value: update.value }]);
      setLiveTrend(update.trend ?? null);
      setStats(update.stats);
      if (update.thresholds) setThresholds(update.thresholds);
    };
    return () => { delete (window as any).updateReading; };
  }, []);

  // No data yet — show empty state rather than crashing
  if (readings.length === 0 || stats === null) return <EmptyState />;

  const activeStats = stats[RANGES[activeRange].label] ?? null;

  const cutoff = Date.now() - RANGES[activeRange].hours * 3600 * 1000;
  // Chart shows the selected time window; fall back to full history if window is empty
  const chartData = readings.filter(d => d.time >= cutoff);
  const visibleData = chartData.length >= 2 ? chartData : readings;

  // Current value always from the latest reading regardless of selected range
  const cur = readings[readings.length - 1].value;
  const { arrow, color: arrowColor } = DEXCOM_TREND_MAP[liveTrend ?? "Flat"] ?? DEXCOM_TREND_MAP["Flat"];
  const curColor = cur < thresholds.low ? "#f87171" : cur > thresholds.high ? "#fb923c" : "#34d399";
  const statusLabel = cur < thresholds.low ? "LOW" : cur > thresholds.high ? "HIGH" : "IN RANGE";
  const statusBg = cur < thresholds.low ? "rgba(248,113,113,0.1)" : cur > thresholds.high ? "rgba(251,146,60,0.1)" : "rgba(52,211,153,0.1)";
  const statusBorder = cur < thresholds.low ? "rgba(248,113,113,0.25)" : cur > thresholds.high ? "rgba(251,146,60,0.25)" : "rgba(52,211,153,0.25)";

  return (
    <div style={{ minHeight:"100vh", background:"#09090f", color:"white", display:"flex", alignItems:"center", justifyContent:"center", padding:"1rem 1.25rem", fontFamily:"-apple-system,BlinkMacSystemFont,'SF Pro Display',sans-serif" }}>
      <div style={{ position:"fixed", inset:0, pointerEvents:"none", overflow:"hidden" }}>
        <div style={{ position:"absolute", top:"50%", left:"50%", transform:"translate(-50%,-50%)", width:700, height:700, borderRadius:"50%", background:"radial-gradient(circle, rgba(52,211,153,0.07) 0%, transparent 70%)" }} />
        <div style={{ position:"absolute", top:"15%", left:"15%", width:350, height:350, borderRadius:"50%", background:"radial-gradient(circle, rgba(129,140,248,0.06) 0%, transparent 70%)" }} />
      </div>

      <div style={{ position:"relative", width:"100%", maxWidth:640 }}>
        {/* Header */}
        <div style={{ display:"flex", alignItems:"flex-start", justifyContent:"space-between", marginBottom:24 }}>
          <div>
            <div style={{ display:"flex", alignItems:"baseline", gap:10, marginBottom:8 }}>
              <span style={{ fontSize:68, fontWeight:800, letterSpacing:"-3px", fontFamily:"'SF Mono',ui-monospace,Menlo,monospace", color:curColor, lineHeight:1 }}>{cur.toFixed(1)}</span>
              <span style={{ fontSize:34, fontWeight:700, color:arrowColor }}>{arrow}</span>
            </div>
            <div style={{ display:"flex", alignItems:"center", gap:10 }}>
              <span style={{ color:"rgba(255,255,255,0.3)", fontSize:13, letterSpacing:"0.05em" }}>mmol/L</span>
              <span style={{ fontSize:10, fontWeight:700, letterSpacing:"0.14em", padding:"4px 10px", borderRadius:999, background:statusBg, border:`1px solid ${statusBorder}`, color:curColor }}>{statusLabel}</span>
            </div>
          </div>
          <div style={{ display:"flex", flexDirection:"column", alignItems:"flex-end", gap:6 }}>
            <div style={{ display:"flex", alignItems:"center", gap:7 }}>
              <span style={{ width:6, height:6, borderRadius:"50%", background:"#34d399", display:"inline-block", boxShadow:"0 0 10px #34d399" }} />
              <span style={{ color:"rgba(255,255,255,0.28)", fontSize:12, letterSpacing:"0.03em" }}>Dexcom G7</span>
            </div>
            <span style={{ color:"rgba(255,255,255,0.15)", fontSize:11 }}>{new Date().toLocaleTimeString([],{hour:"2-digit",minute:"2-digit"})}</span>
          </div>
        </div>

        {/* Chart */}
        <div style={{ borderRadius:22, border:"1px solid rgba(255,255,255,0.07)", background:"rgba(255,255,255,0.022)", backdropFilter:"blur(16px)", overflow:"hidden", marginBottom:12, boxShadow:"0 0 0 1px rgba(255,255,255,0.03), 0 28px 64px rgba(0,0,0,0.55)" }}>
          <div style={{ display:"flex", alignItems:"center", justifyContent:"space-between", padding:"18px 22px 8px" }}>
            <span style={{ color:"rgba(255,255,255,0.22)", fontSize:11, letterSpacing:"0.13em", textTransform:"uppercase", fontWeight:600 }}>Glucose History</span>
            <div style={{ display:"flex", gap:2, background:"rgba(255,255,255,0.05)", borderRadius:10, padding:3 }}>
              {RANGES.map((r, i) => (
                <button key={r.label} onClick={() => setActiveRange(i)} style={{ padding:"5px 14px", borderRadius:7, border:"none", fontSize:12, fontWeight:600, letterSpacing:"0.04em", cursor:"pointer", transition:"all 0.2s", background: activeRange===i ? "rgba(255,255,255,0.1)" : "transparent", color: activeRange===i ? "white" : "rgba(255,255,255,0.28)", fontFamily:"-apple-system,sans-serif" }}>{r.label}</button>
              ))}
            </div>
          </div>
          <div style={{ padding:"0 10px 4px", height:260 }}>
            <GlucoseChart data={visibleData} thresholds={thresholds} />
          </div>
          <div style={{ padding:"6px 22px 16px", display:"flex", gap:20, alignItems:"center" }}>
            {[
              { label:`High >${thresholds.high}`, dash:true, color:"#fb923c" },
              { label:`Target ${thresholds.low}–${thresholds.high}`, fill:true, color:"#34d399" },
              { label:`Low <${thresholds.low}`, dash:true, color:"#f87171" },
            ].map(item => (
              <div key={item.label} style={{ display:"flex", alignItems:"center", gap:6 }}>
                {item.fill
                  ? <div style={{ width:18, height:9, borderRadius:3, background:"rgba(52,211,153,0.14)", border:"1px solid rgba(52,211,153,0.22)" }} />
                  : <div style={{ width:18, height:1, borderTop:`1px dashed ${item.color}`, opacity:0.5 }} />
                }
                <span style={{ fontSize:10, color:"rgba(255,255,255,0.22)", letterSpacing:"0.02em" }}>{item.label}</span>
              </div>
            ))}
          </div>
        </div>

        {/* Stats — all values from Swift, keyed to selected range */}
        <div style={{ display:"grid", gridTemplateColumns:"1fr 1fr 1fr", gap:10, marginBottom:20 }}>
          {activeStats ? (<>
            <Stat
              label="Time in Range"
              value={`${activeStats.timeInRangePercent}%`}
              color={activeStats.timeInRangePercent >= 70 ? "#34d399" : activeStats.timeInRangePercent >= 50 ? "#fbbf24" : "#f87171"}
            />
            <Stat
              label={`${activeStats.rangeLabel} Average`}
              value={activeStats.average.toFixed(1)}
              unit="mmol/L"
            />
            <Stat
              label="Period Low"
              value={activeStats.periodLow.toFixed(1)}
              unit="mmol/L"
              color={activeStats.periodLow < thresholds.low ? "#f87171" : undefined}
            />
          </>) : (
            <div style={{ gridColumn:"1/-1", textAlign:"center", color:"rgba(255,255,255,0.2)", fontSize:12 }}>
              No data for this range
            </div>
          )}
        </div>

        <div style={{ textAlign:"center", color:"rgba(255,255,255,0.1)", fontSize:11, letterSpacing:"0.06em" }}>
          Omnipod 5 · Auto Mode · Readings every 5 min
        </div>
      </div>
    </div>
  );
}
