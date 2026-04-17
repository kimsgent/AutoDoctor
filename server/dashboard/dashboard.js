const DEFAULT_API_PORT = "8000";
let API_BASE = null;

const REFRESH_INTERVAL_MS = 5000;
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

  API_BASE = uniqueCandidates[0] || `http://127.0.0.1:${DEFAULT_API_PORT}`;
  return API_BASE;
}

async function fetchJSON(endpoint) {
  try {
    const base = await resolveApiBase();
    const response = await fetch(`${base}${endpoint}`, { cache: "no-store" });

    if (!response.ok) {
      throw new Error(`HTTP error ${response.status}`);
    }

    return await response.json();
  } catch (error) {
    console.error(`Failed to fetch ${endpoint}:`, error);
    return [];
  }
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

function formatMetricValue(metric, value) {
  if (value === null || value === undefined || value === "") return "n/a";

  const number = Number(value);
  if (!Number.isFinite(number)) return String(value);

  const units = {
    CPU: "%",
    Memory: "%",
    Disk: "%",
    Network: " ms",
  };

  return `${number.toFixed(1)}${units[metric] || ""}`;
}

function formatDelta(metric, value) {
  if (value === null || value === undefined || value === "") return "n/a";

  const number = Number(value);
  if (!Number.isFinite(number)) return String(value);

  const sign = number > 0 ? "+" : "";
  return `${sign}${formatMetricValue(metric, number)}`;
}

function getStateClass(state) {
  switch ((state || "").toLowerCase()) {
    case "sustained":
      return "state-critical";
    case "baseline deviation":
      return "state-baseline";
    case "transient":
    case "increasing":
      return "state-warning";
    case "decreasing":
    case "recovering":
      return "state-improving";
    default:
      return "state-stable";
  }
}

function getDirectionIndicator(icon, direction) {
  switch ((icon || "").toLowerCase()) {
    case "up":
      return "&uarr;";
    case "down":
      return "&darr;";
    case "flat":
      return "&rarr;";
    default:
      switch ((direction || "").toLowerCase()) {
        case "increasing":
          return "&uarr;";
        case "decreasing":
          return "&darr;";
        default:
          return "&rarr;";
      }
  }
}

function createSparkline(values) {
  const numericValues = (values || []).map((value) => Number(value)).filter((value) => Number.isFinite(value));
  if (!numericValues.length) {
    return "<svg viewBox='0 0 100 24'><path d='' /></svg>";
  }

  const min = Math.min(...numericValues);
  const max = Math.max(...numericValues);
  const range = max - min || 1;

  const points = numericValues.map((value, index) => {
    const x = (index / Math.max(numericValues.length - 1, 1)) * 100;
    const y = 24 - ((value - min) / range) * 20 - 2;
    return `${x},${y}`;
  });

  return `
    <svg viewBox="0 0 100 24" preserveAspectRatio="none">
      <polyline
        fill="none"
        stroke="#66b3ff"
        stroke-width="2"
        points="${points.join(" ")}"
      />
    </svg>
  `;
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

function createLineChart(id, labels, data, label, options = {}, datasetOverrides = {}) {
  const ctx = document.getElementById(id).getContext("2d");
  if (ctx.chart) ctx.chart.destroy();
  ctx.chart = new Chart(ctx, {
    type: "line",
    data: {
      labels: labels || [],
      datasets: [
        {
          label,
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
        x: { ticks: { color: "#334155" }, grid: { color: "#d7deea" } },
        y: {
          ticks: { color: "#334155" },
          grid: { color: "#d7deea" },
          beginAtZero: true,
        },
      },
      plugins: {
        legend: { labels: { color: "#334155" } },
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

function createBarChart(id, labels, data, label, options = {}) {
  const ctx = document.getElementById(id).getContext("2d");
  if (ctx.chart) ctx.chart.destroy();
  ctx.chart = new Chart(ctx, {
    type: "bar",
    data: {
      labels: labels || [],
      datasets: [
        {
          label,
          data: data || [],
          backgroundColor: (labels || []).map(() => "rgba(255, 99, 132, 0.7)"),
        },
      ],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      scales: {
        x: { ticks: { color: "#334155" }, grid: { color: "#d7deea" } },
        y: {
          ticks: { color: "#334155" },
          grid: { color: "#d7deea" },
          beginAtZero: true,
        },
      },
      plugins: {
        legend: { labels: { color: "#334155" } },
        tooltip: { mode: "index", intersect: false },
      },
      ...options,
    },
  });
}

function renderDashboardMeta(meta) {
  document.getElementById("run-id").innerText = meta.run_id || "--";
  document.getElementById("host-name").innerText = meta.host_name || "--";
  document.getElementById("generated-time").innerText = meta.generated_time || "--";
}

function renderSummary(summary) {
  const health = summary.health || {};
  const why = summary.why_health_changed || {};
  const metricStates = summary.metric_states || [];

  document.getElementById("heroScore").innerText = health.display || "--";
  document.getElementById("heroMainConcern").innerText = health.main_concern || "System state unavailable";
  document.getElementById("heroSummary").innerText = health.summary || "No summary available";
  document.getElementById("heroWindow").innerText = summary.window && summary.window.label
    ? `${summary.window.label}${summary.window.used_fallback ? " | fallback mode" : ""}`
    : "--";

  document.getElementById("whyPrimaryDriver").innerHTML =
    `<b>Primary driver:</b> ${why.primary_driver ? `${why.primary_driver.Category} (penalty ${why.primary_driver.TotalPenalty})` : "n/a"}`;

  const whySupportingFactors = document.getElementById("whySupportingFactors");
  whySupportingFactors.innerHTML = (why.supporting_factors || [])
    .map((item) => `<li>${item}</li>`)
    .join("") || "<li>No supporting factors recorded</li>";

  document.getElementById("whyStableComponents").innerHTML =
    `<b>Stable components:</b> ${(why.stable_components || []).map((item) => `${item.metric}: ${item.state}`).join(" | ") || "No stable components identified"}`;

  document.getElementById("stateStrip").innerHTML = metricStates
    .map(
      (item) => `
        <div class="state-tile">
          <span class="state-label">${item.Metric}</span>
          <span class="state-badge ${getStateClass(item.State)}">${item.State}</span>
        </div>
      `,
    )
    .join("");

  document.getElementById("metricCards").innerHTML = metricStates
    .map(
      (item) => `
        <div class="card metric-card">
          <div class="metric-header">
            <div>
              <div class="metric-name">${item.Metric}</div>
              <div class="metric-value">${formatMetricValue(item.Metric, item.Current)}</div>
            </div>
            <span class="state-badge ${getStateClass(item.State)}">${item.State}</span>
          </div>
          <div class="metric-row">
            <span>Baseline</span>
            <span>${formatMetricValue(item.Metric, item.Baseline)}</span>
          </div>
          <div class="metric-row">
            <span>Threshold</span>
            <span>${formatMetricValue(item.Metric, item.Threshold)}</span>
          </div>
          <div class="metric-row">
            <span>Delta vs baseline</span>
            <span>${formatDelta(item.Metric, item.DeltaFromBaseline)}</span>
          </div>
          <div class="metric-row">
            <span>Context</span>
            <span>${item.WindowLabel || "--"} | ${item.SampleCount || 0} samples</span>
          </div>
          <div class="direction">
            <span>${getDirectionIndicator(item.DirectionIcon, item.Direction)}</span>
            <span>${item.Direction || "Stable"}</span>
          </div>
          <div class="metric-sparkline">${createSparkline(item.Sparkline || [])}</div>
        </div>
      `,
    )
    .join("");

  document.getElementById("latestFindings").innerHTML = (summary.latest_findings || [])
    .map((item) => `<li>${item.Message || item.message || ""}</li>`)
    .join("") || "<li>No findings available</li>";

  document.getElementById("groupedInsights").innerHTML = (summary.findings_by_domain || [])
    .map(
      (group) => `
        <div style="margin-bottom: 16px;">
          <h4 style="margin: 0 0 8px 0;">${group.domain}</h4>
          <ul class="insight-list">
            ${(group.findings || []).map((item) => `<li>${item.Message || item.message || ""}</li>`).join("")}
          </ul>
        </div>
      `,
    )
    .join("") || "<p>No grouped insights available</p>";
}

async function loadCharts() {
  const history = await fetchJSON("/api/system/history");
  const labels = history.map((item) => item.timestamp);

  createLineChart("cpuChart", labels, history.map((item) => item.cpu_load), "CPU Load %");
  createLineChart("memoryChart", labels, history.map((item) => item.memory_free_gb), "Memory Free GB");
  createLineChart("diskChart", labels, history.map((item) => item.disk_free_gb), "Disk Free GB");
  createLineChart("networkChart", labels, history.map((item) => item.network_latency_ms), "Network Latency ms");

  const health = await fetchJSON("/api/health");
  const healthPoints = (health || [])
    .map((item) => ({
      timestamp: item.timestamp,
      score: Number(item.health_score),
    }))
    .filter((item) => Number.isFinite(item.score));

  createLineChart(
    "healthChart",
    healthPoints.map((item) => item.timestamp),
    healthPoints.map((item) => item.score),
    "Health Score",
    {
      scales: {
        x: {
          ticks: {
            color: "#334155",
            maxTicksLimit: 6,
            callback: function (value) {
              const rawLabel = this.getLabelForValue(value);
              return formatTimeLabel(rawLabel);
            },
          },
          grid: { color: "#d7deea" },
        },
        y: {
          min: 0,
          max: HEALTH_Y_MAX,
          beginAtZero: true,
          ticks: { color: "#334155", stepSize: 10 },
          grid: { color: "#d7deea" },
        },
      },
      plugins: {
        legend: { labels: { color: "#334155" } },
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
      borderColor: "rgba(102, 179, 255, 1)",
      backgroundColor: "rgba(102, 179, 255, 0.18)",
      fill: true,
      borderWidth: 3,
      tension: 0.35,
      pointRadius: 2,
      pointHoverRadius: 5,
      pointBackgroundColor: "rgba(255, 255, 255, 0.95)",
      pointBorderWidth: 1,
      spanGaps: true,
    },
  );

  const alerts = await fetchJSON("/api/alerts");
  createBarChart(
    "alertsChart",
    alerts.map((item) => item.severity),
    alerts.map((item) => item.count),
    "Alerts",
  );
}

async function refreshDashboard() {
  const [meta, summary] = await Promise.all([
    fetchJSON("/api/dashboard/meta"),
    fetchJSON("/api/dashboard/summary"),
  ]);

  renderDashboardMeta(meta || {});
  renderSummary(summary || {});
  await loadCharts();
}

window.onload = async () => {
  await refreshDashboard();
  setInterval(async () => {
    await refreshDashboard();
  }, REFRESH_INTERVAL_MS);
};
