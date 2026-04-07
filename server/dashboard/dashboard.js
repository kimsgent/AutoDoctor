// dashboard.js

// ----------------------------------------------------
// API CONFIGURATION
// ----------------------------------------------------
// NOTE:
// Previously the API host/port were hardcoded:
//
// const API_HOST = "127.0.0.1";
// const API_PORT = "8000";
//
// This breaks when:
// - API runs on another port
// - API is behind reverse proxy
// - dashboard is opened remotely
// - docker deployment
//
// The new approach derives the API base URL from the
// browser location automatically.
//
// Example:
// http://192.168.1.10:8000/dashboard
// → API requests will target the same host/port.
//
// This makes the dashboard portable and deployment-safe.
// ----------------------------------------------------

const DEFAULT_API_PORT = "8000";
let API_BASE = null;

const REFRESH_INTERVAL_MS = 5000; // refresh every 5 seconds
const HEALTH_Y_MAX = 105;

function trimTrailingSlash(value) {
  return value ? value.replace(/\/+$/, "") : value;
}

async function canReachApi(base) {
  try {
    const response = await fetch(`${base}/health`, { cache: "no-store" });
    return response.ok;
  } catch {
    return false;
  }
}

async function resolveApiBase() {
  if (API_BASE) return API_BASE;

  const queryBase = new URLSearchParams(window.location.search).get("api_base");
  const configuredBase =
    queryBase || window.AUTO_DOCTOR_API_BASE || localStorage.getItem("AUTO_DOCTOR_API_BASE");

  const candidates = [];

  if (configuredBase) {
    candidates.push(trimTrailingSlash(configuredBase));
  }

  if (window.location.protocol.startsWith("http")) {
    candidates.push(trimTrailingSlash(`${window.location.protocol}//${window.location.host}`));
  }

  candidates.push(`http://127.0.0.1:${DEFAULT_API_PORT}`);
  candidates.push(`http://localhost:${DEFAULT_API_PORT}`);

  const uniqueCandidates = [...new Set(candidates.filter(Boolean))];

  for (const candidate of uniqueCandidates) {
    if (await canReachApi(candidate)) {
      API_BASE = candidate;
      return API_BASE;
    }
  }

  // Last-resort fallback preserves existing behavior if health checks are blocked.
  API_BASE = uniqueCandidates[0] || `http://127.0.0.1:${DEFAULT_API_PORT}`;
  return API_BASE;
}

function formatTimeLabel(value) {
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    return value || "";
  }

  return parsed.toLocaleTimeString([], {
    hour: "2-digit",
    minute: "2-digit",
  });
}

function formatTimeTooltip(value) {
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    return value || "";
  }

  return parsed.toLocaleString([], {
    year: "numeric",
    month: "short",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  });
}

const healthThresholdPlugin = {
  id: "healthThresholdPlugin",
  afterDraw(chart, args, pluginOptions) {
    const lines = pluginOptions && Array.isArray(pluginOptions.lines) ? pluginOptions.lines : [];
    if (!lines.length) return;

    const { ctx, chartArea, scales } = chart;
    const yScale = scales.y;
    if (!chartArea || !yScale) return;

    ctx.save();

    for (const line of lines) {
      const y = yScale.getPixelForValue(line.value);
      if (Number.isNaN(y) || y < chartArea.top || y > chartArea.bottom) continue;

      ctx.strokeStyle = line.color || "rgba(255, 255, 255, 0.35)";
      ctx.lineWidth = line.width || 1;
      ctx.setLineDash(Array.isArray(line.dash) ? line.dash : [6, 4]);

      ctx.beginPath();
      ctx.moveTo(chartArea.left, y);
      ctx.lineTo(chartArea.right, y);
      ctx.stroke();

      if (line.label) {
        ctx.setLineDash([]);
        ctx.fillStyle = line.color || "rgba(255, 255, 255, 0.8)";
        ctx.font = "11px Segoe UI";
        ctx.textAlign = "right";
        ctx.textBaseline = "bottom";
        ctx.fillText(line.label, chartArea.right - 8, y - 2);
      }
    }

    ctx.restore();
  },
};

Chart.register(healthThresholdPlugin);

// ----------------------------------------------------
// Fetch JSON from API
// ----------------------------------------------------
// NOTE:
// All API requests now use API_BASE instead of hardcoded
// host/port values.
async function fetchJSON(endpoint) {
  try {
    const base = await resolveApiBase();
    const r = await fetch(`${base}${endpoint}`);

    if (!r.ok) {
      throw new Error(`HTTP error ${r.status}`);
    }

    return await r.json();
  } catch (e) {
    console.error(`Failed to fetch ${endpoint}:`, e);

    // Returning empty structure prevents dashboard crash
    return [];
  }
}

// ----------------------------
// Load metadata
// ----------------------------
async function loadDashboardMeta() {
    const meta = await fetchJSON("/api/dashboard/meta");
    document.getElementById("run-id").innerText = meta.run_id || "--";
    document.getElementById("host-name").innerText = meta.host_name || "--";
    document.getElementById("generated-time").innerText = meta.generated_time || "--";
}

// ----------------------------
// Create or update line chart
// ----------------------------
function createLineChart(id, labels, data, label, options = {}, datasetOverrides = {}) {
  const ctx = document.getElementById(id).getContext("2d");
  if (ctx.chart) ctx.chart.destroy();
  ctx.chart = new Chart(ctx, {
    type: "line",
    data: {
      labels: labels || [],
      datasets: [
        {
          label: label,
          data: data || [],
          borderColor: "rgba(75, 192, 192, 1)",
          backgroundColor: "rgba(75, 192, 192, 0.2)",
          fill: true,
          tension: 0.25,
          pointRadius: 3,
          pointHoverRadius: 6,
          borderWidth: 2,
          spanGaps: true,
          ...datasetOverrides,
        },
      ],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      scales: {
        x: { ticks: { color: "white" }, grid: { color: "#333" } },
        y: {
          ticks: { color: "white" },
          grid: { color: "#333" },
          beginAtZero: true,
        },
      },
      plugins: {
        legend: { labels: { color: "white" } },
        tooltip: { mode: "index", intersect: false },
      },
      interaction: {
        mode: "nearest",
        axis: "x",
        intersect: false,
      },
      ...options,
    },
  });
}

// ----------------------------
// Create or update bar chart
// ----------------------------
function createBarChart(id, labels, data, label, options = {}) {
  const ctx = document.getElementById(id).getContext("2d");
  if (ctx.chart) ctx.chart.destroy();
  ctx.chart = new Chart(ctx, {
    type: "bar",
    data: {
      labels: labels || [],
      datasets: [
        {
          label: label,
          data: data || [],
          backgroundColor: labels.map(() => "rgba(255, 99, 132, 0.7)"),
        },
      ],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      scales: {
        x: { ticks: { color: "white" }, grid: { color: "#333" } },
        y: {
          ticks: { color: "white" },
          grid: { color: "#333" },
          beginAtZero: true,
        },
      },
      plugins: {
        legend: { labels: { color: "white" } },
        tooltip: { mode: "index", intersect: false },
      },
      ...options,
    },
  });
}

// ----------------------------
// Load all charts
// ----------------------------
async function loadCharts() {
  // ----------------------------
  // System History
  // ----------------------------
  const history = await fetchJSON("/api/system/history");
  const labels = history.map((x) => x.timestamp);

  createLineChart(
    "cpuChart",
    labels,
    history.map((x) => x.cpu_load),
    "CPU Load %",
  );
  createLineChart(
    "memoryChart",
    labels,
    history.map((x) => x.memory_free_gb),
    "Memory Free GB",
  );
  createLineChart(
    "diskChart",
    labels,
    history.map((x) => x.disk_free_gb),
    "Disk Free GB",
  );
  createLineChart(
    "networkChart",
    labels,
    history.map((x) => x.network_latency_ms),
    "Network Latency ms",
  );

  // ----------------------------
  // Health
  // ----------------------------
  const health = await fetchJSON("/api/health");
  const healthPoints = (health || [])
    .map((x) => ({
      timestamp: x.timestamp,
      score: Number(x.health_score),
    }))
    .filter((x) => Number.isFinite(x.score));

  createLineChart(
    "healthChart",
    healthPoints.map((x) => x.timestamp),
    healthPoints.map((x) => x.score),
    "Health Score",
    {
      scales: {
        x: {
          ticks: {
            color: "white",
            maxTicksLimit: 6,
            callback: function (value) {
              const rawLabel = this.getLabelForValue(value);
              return formatTimeLabel(rawLabel);
            },
          },
          grid: { color: "#333" },
        },
        y: {
          min: 0,
          max: HEALTH_Y_MAX,
          beginAtZero: true,
          ticks: {
            color: "white",
            stepSize: 10,
          },
          grid: { color: "#333" },
        },
      },
      plugins: {
        legend: { labels: { color: "white" } },
        tooltip: {
          mode: "index",
          intersect: false,
          callbacks: {
            title: (items) => {
              const rawLabel = items && items[0] && items[0].label ? items[0].label : "";
              return formatTimeTooltip(rawLabel);
            },
          },
        },
        healthThresholdPlugin: {
          lines: [
            { value: 80, label: "Good (80)", color: "rgba(34, 197, 94, 0.8)", dash: [4, 4] },
            { value: 60, label: "Warning (60)", color: "rgba(245, 158, 11, 0.9)", dash: [4, 4] },
          ],
        },
      },
    },
    {
      borderColor: "rgba(78, 161, 255, 1)",
      backgroundColor: (context) => {
        const chart = context.chart;
        const chartArea = chart.chartArea;
        if (!chartArea) {
          return "rgba(78, 161, 255, 0.2)";
        }

        const gradient = chart.ctx.createLinearGradient(0, chartArea.top, 0, chartArea.bottom);
        gradient.addColorStop(0, "rgba(34, 197, 94, 0.35)");
        gradient.addColorStop(0.55, "rgba(245, 158, 11, 0.22)");
        gradient.addColorStop(1, "rgba(239, 68, 68, 0.12)");
        return gradient;
      },
      fill: true,
      borderWidth: 3,
      tension: 0.35,
      pointRadius: 2,
      pointHoverRadius: 5,
      pointBackgroundColor: (context) => {
        const score = Number(context.raw);
        if (score >= 80) return "rgba(34, 197, 94, 1)";
        if (score >= 60) return "rgba(245, 158, 11, 1)";
        return "rgba(239, 68, 68, 1)";
      },
      pointBorderColor: "rgba(255, 255, 255, 0.95)",
      pointBorderWidth: 1,
      spanGaps: true,
    },
  );

  // ----------------------------
  // Alerts
  // ----------------------------
  const alerts = await fetchJSON("/api/alerts");
  createBarChart(
    "alertsChart",
    alerts.map((a) => a.severity),
    alerts.map((a) => a.count),
    "Alerts",
  );
}

// ----------------------------
// Single onload for everything
// ----------------------------
window.onload = async () => {
  await loadDashboardMeta(); // metadata first
  await loadCharts(); // then charts
  setInterval(async () => {
    await loadDashboardMeta();
    await loadCharts();
  }, REFRESH_INTERVAL_MS);
};
