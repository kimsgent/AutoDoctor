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
function createLineChart(id, labels, data, label, options = {}) {
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
  createLineChart(
    "healthChart",
    health.map((x) => x.timestamp),
    health.map((x) => x.health_score),
    "Health Score",
    { scales: { y: { min: 0, max: 100 } } },
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
