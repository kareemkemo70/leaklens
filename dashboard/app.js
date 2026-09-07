// ═══════════════════════════════════════════════════════════════
// WaterGuard AI — Dashboard Application Logic
// ═══════════════════════════════════════════════════════════════

const NUM_SENSORS = 119;
const WINDOW_SIZE = 48;

let errorChart = null;
let timeseriesChart = null;
let requestCount = 0;

// ── Zone State (client-side, no extra API calls) ─────────────────
// Tracks the current health of each zone based on prediction results.
// Status: 'green' | 'yellow' | 'red'
const ZONES = ['Zone 1', 'Zone 2', 'Zone 3', 'Zone 4', 'Zone 5'];

const zoneState = {};
ZONES.forEach(z => {
  zoneState[z] = {
    status:     'green',
    confidence: null,
    mse:        null,
    lastUpdated: null,
    decayTimer:  null,   // setTimeout handle for auto-decay back to green
  };
});

// Pipe IDs that should reflect the upstream zone's health
// (each pipe ID maps to the zone it carries flow FROM)
const PIPE_ZONE_MAP = {
  'pipe-z1-z2': 'Zone 1',
  'pipe-z1-z3': 'Zone 1',
  'pipe-z2-z4': 'Zone 2',
  'pipe-z3-z4': 'Zone 3',
  'pipe-z4-z5': 'Zone 4',
};

// ── Auto-Simulation State ────────────────────────────────────────
let autoSimInterval  = null;
let autoSimCountdown = 0;
let countdownTimer   = null;
const AUTO_SIM_INTERVAL_S = 5;   // seconds between auto predictions

// ── Startup ─────────────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
  initCharts();
  loadTimeseries();
  updateApiStatus();
  initGeoMap();
});

function getApiBase() {
  return document.getElementById('apiUrl').value.trim().replace(/\/$/, '');
}

// ─────────────────────────────────────────────────────────────────
// Real Data Simulator — calls backend /api/v1/simulate
// All data comes from the REAL SCADA dataset (no fake values)
// ─────────────────────────────────────────────────────────────────

/**
 * Fetch a real (48×119) sensor window from the backend.
 * The backend reads actual SCADA dataset statistics and returns
 * windows that are grounded in the real training distribution.
 *
 * @param {string} type - 'leak' | 'normal' | 'random'
 * @returns {Promise<number[][]>} - shape (48, 119)
 */
async function fetchRealWindow(type) {
  const apiBase = getApiBase();
  const resp = await fetch(`${apiBase}/api/v1/simulate?type=${type}`);
  if (!resp.ok) {
    const err = await resp.json().catch(() => ({ detail: resp.statusText }));
    throw new Error(`Simulator error: ${err.detail || resp.status}`);
  }
  const json = await resp.json();
  return json.data;   // (48, 119) array from real SCADA stats
}

// ─────────────────────────────────────────────────────────────────
// API Call
// ─────────────────────────────────────────────────────────────────

async function sendData(type) {
  const buttons = ['btnLeak', 'btnNormal', 'btnRandom', 'btnSynthNorm', 'btnSynthLeak'];
  buttons.forEach(id => {
    const btn = document.getElementById(id);
    if (btn) btn.disabled = true;
  });

  let activeBtnId = 'btnRandom';
  if (type === 'leak') activeBtnId = 'btnLeak';
  else if (type === 'normal') activeBtnId = 'btnNormal';
  else if (type === 'synthetic') activeBtnId = 'btnSynthNorm';
  else if (type === 'synthetic_leak') activeBtnId = 'btnSynthLeak';

  const activeBtn = document.getElementById(activeBtnId);
  if (activeBtn) activeBtn.classList.add('loading');

  const t0 = performance.now();
  const apiBase = getApiBase();

  try {
    // Step 1: Get a sensor window via backend simulator
    const data = await fetchRealWindow(type);

    // Get the selected zone from the broadcast dropdown
    const forcedZone = document.getElementById('broadcastZone').value;

    // Step 2: Send it to the Autoencoder for prediction
    const predictUrl = `${apiBase}/api/v1/predict`;
    const resp = await fetch(predictUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ data, forced_zone: forcedZone }),
    });

    if (!resp.ok) {
      const err = await resp.json().catch(() => ({ detail: resp.statusText }));
      throw new Error(err.detail || `HTTP ${resp.status}`);
    }

    const result = await resp.json();
    const elapsed = Math.round(performance.now() - t0);

    displayResult(result, type, elapsed);
    addLog(type, result, elapsed);
    updateChart(result.sensor_errors, result.top_sensors, result.threshold);
    updateZoneState(result);   // ← update live network map
    requestCount++;
    document.getElementById('reqCount').textContent = requestCount;

  } catch (err) {
    showError(err.message, type);
    addLog(type, null, 0, err.message);
  } finally {
    buttons.forEach(id => {
      const btn = document.getElementById(id);
      if (btn) btn.disabled = false;
    });
    if (activeBtn) activeBtn.classList.remove('loading');
  }
}


// ─────────────────────────────────────────────────────────────────
// Result Display
// ─────────────────────────────────────────────────────────────────

function displayResult(r, type, elapsed) {
  const isAnomaly = r.is_anomaly === 1;
  const confidence = (r.confidence * 100).toFixed(1);

  // ── Status card ────────────────────────────────────────────────
  const card = document.getElementById('statusCard');
  card.className = 'status-card ' + (isAnomaly ? 'anomaly' : 'normal-status');

  document.getElementById('statusEmoji').textContent = isAnomaly ? '🚨' : '✅';
  document.getElementById('statusTitle').textContent = isAnomaly ? 'LEAK DETECTED' : 'SYSTEM NORMAL';
  document.getElementById('statusTitle').className = isAnomaly ? 'status-anomaly' : 'status-normal';
  document.getElementById('statusSub').textContent = r.message;

  // ── Confidence ──────────────────────────────────────────────────
  document.getElementById('confidenceValue').textContent = `${confidence}%`;
  document.getElementById('confidenceValue').style.color = isAnomaly ? '#ff4756' : '#00e676';
  document.getElementById('confidenceFill').style.width = `${confidence}%`;
  document.getElementById('confidenceFill').style.background = isAnomaly
    ? 'linear-gradient(90deg, #c41230, #ff4756)'
    : 'linear-gradient(90deg, #00875a, #00e676)';

  // ── MSE boxes ──────────────────────────────────────────────────
  document.getElementById('mseValue').innerHTML = `
    <div class="mse-row">
      <div class="mse-box">
        <div class="mse-dot" style="background:#00d4ff"></div>
        MSE <strong>${r.mse.toFixed(5)}</strong>
      </div>
      <div class="mse-box">
        <div class="mse-dot" style="background:#ff4756"></div>
        THR <strong>${r.threshold.toFixed(5)}</strong>
      </div>
    </div>
    <div class="latency-pill">⚡ ${elapsed}ms round-trip · ${r.sensor_errors.length} sensors</div>
  `;

  // ── Top sensors ─────────────────────────────────────────────────
  const tagsHtml = r.top_sensors
    .map(s => `<span class="sensor-tag">${s}</span>`)
    .join('');
  document.getElementById('sensorTags').innerHTML = tagsHtml;

  // ── Zone ────────────────────────────────────────────────────────
  document.getElementById('zoneBadge').textContent = `📍 ${r.zone}`;
  document.getElementById('zoneSub').textContent = getZoneDescription(r.zone);
}

function showError(msg, type) {
  const card = document.getElementById('statusCard');
  card.className = 'status-card';
  document.getElementById('statusEmoji').textContent = '⚠️';
  document.getElementById('statusTitle').textContent = 'REQUEST FAILED';
  document.getElementById('statusTitle').className = '';
  document.getElementById('statusTitle').style.color = '#ff9100';
  document.getElementById('statusSub').textContent = msg;
}

function getZoneDescription(zone) {
  const map = {
    'Zone 1': 'Early Network — Intake / Primary Pipes',
    'Zone 2': 'Middle Distribution Network',
    'Zone 3': 'Main Distribution Grid',
    'Zone 4': 'End Network / High Pressure Zones',
    'Zone 5': 'Extended / Remote Network',
  };
  return map[zone] || 'Unclassified Sensor Region';
}

// ─────────────────────────────────────────────────────────────────
// Chart Rendering
// ─────────────────────────────────────────────────────────────────

function initCharts() {
  const errCtx = document.getElementById('errorChart').getContext('2d');
  const tsCtx = document.getElementById('timeseriesChart').getContext('2d');

  Chart.defaults.color = '#7986a1';
  Chart.defaults.font.family = "'Inter', sans-serif";

  errorChart = new Chart(errCtx, {
    type: 'bar',
    data: { labels: [], datasets: [] },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      animation: { duration: 600, easing: 'easeInOutQuart' },
      plugins: {
        legend: { display: false },
        tooltip: {
          backgroundColor: 'rgba(13,21,38,0.95)',
          borderColor: 'rgba(0,212,255,0.3)',
          borderWidth: 1,
          callbacks: {
            label: (ctx) => ` Error: ${ctx.raw.toFixed(6)}`
          }
        }
      },
      scales: {
        x: {
          grid: { color: 'rgba(255,255,255,0.04)' },
          ticks: { maxTicksLimit: 20, font: { family: 'JetBrains Mono', size: 10 } }
        },
        y: {
          grid: { color: 'rgba(255,255,255,0.06)' },
          ticks: { font: { family: 'JetBrains Mono', size: 10 } }
        }
      }
    }
  });

  timeseriesChart = new Chart(tsCtx, {
    type: 'line',
    data: { labels: [], datasets: [] },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      animation: { duration: 800 },
      interaction: { mode: 'index', intersect: false },
      plugins: {
        legend: {
          display: true,
          labels: { boxWidth: 12, padding: 16, font: { size: 11 } }
        },
        tooltip: {
          backgroundColor: 'rgba(13,21,38,0.95)',
          borderColor: 'rgba(0,212,255,0.3)',
          borderWidth: 1,
        }
      },
      scales: {
        x: {
          grid: { color: 'rgba(255,255,255,0.04)' },
          ticks: { maxTicksLimit: 12, font: { size: 10 } }
        },
        y: {
          grid: { color: 'rgba(255,255,255,0.06)' },
          ticks: { font: { size: 10 } }
        }
      }
    }
  });
}

function updateChart(sensorErrors, topSensors, threshold) {
  // Show every sensor (or sample if > 80)
  const n = sensorErrors.length;
  const step = n > 80 ? 2 : 1;
  const labels = [];
  const values = [];
  const colors = [];

  for (let i = 0; i < n; i += step) {
    const name = `n${i + 1}`;
    labels.push(name);
    values.push(sensorErrors[i]);

    // Colour: red if top sensor, amber if above threshold, else cyan
    if (topSensors.includes(name)) {
      colors.push('rgba(255, 71, 86, 0.85)');
    } else if (sensorErrors[i] > threshold) {
      colors.push('rgba(255, 145, 0, 0.7)');
    } else {
      colors.push('rgba(0, 212, 255, 0.5)');
    }
  }

  errorChart.data.labels = labels;
  errorChart.data.datasets = [
    {
      label: 'Reconstruction Error',
      data: values,
      backgroundColor: colors,
      borderRadius: 3,
      borderSkipped: false,
    }
  ];

  // Threshold annotation
  errorChart.options.plugins.annotation = {
    annotations: {
      thresholdLine: {
        type: 'line',
        yMin: threshold,
        yMax: threshold,
        borderColor: 'rgba(255, 71, 86, 0.8)',
        borderWidth: 2,
        borderDash: [6, 4],
        label: {
          display: true,
          content: `Threshold: ${threshold.toFixed(4)}`,
          position: 'end',
          backgroundColor: 'rgba(255,71,86,0.2)',
          color: '#ff4756',
          font: { size: 11, family: 'JetBrains Mono' }
        }
      }
    }
  };

  errorChart.update();
  document.getElementById('chartPlaceholder').style.display = 'none';
}

async function loadTimeseries() {
  const apiBase = getApiBase();
  try {
    const resp = await fetch(`${apiBase}/api/v1/timeseries?hours=24`);
    if (!resp.ok) return;
    const data = await resp.json();
    renderTimeseries(data.series);
  } catch {
    // Silently skip if backend not running
  }
}

function renderTimeseries(series) {
  if (!series || !series.length) return;

  const labels = series.map(p => p.timestamp.slice(11, 16));
  const pressure = series.map(p => p.pressure);
  const flow = series.map(p => p.flow);
  const anomalies = series.map(p => p.is_anomaly);

  const bgColors = anomalies.map(a => a ? 'rgba(255,71,86,0.12)' : 'transparent');

  timeseriesChart.data.labels = labels;
  timeseriesChart.data.datasets = [
    {
      label: 'Pressure (bar)',
      data: pressure,
      borderColor: '#00d4ff',
      backgroundColor: 'rgba(0,212,255,0.07)',
      borderWidth: 2,
      fill: true,
      tension: 0.4,
      pointRadius: 0,
    },
    {
      label: 'Flow (m³/h)',
      data: flow,
      borderColor: '#00e676',
      backgroundColor: 'rgba(0,230,118,0.05)',
      borderWidth: 1.5,
      fill: false,
      tension: 0.4,
      pointRadius: 0,
    }
  ];

  timeseriesChart.update();
}

// ─────────────────────────────────────────────────────────────────
// Request Log
// ─────────────────────────────────────────────────────────────────

function addLog(type, result, elapsed, error = null) {
  const logContainer = document.getElementById('logContainer');
  const now = new Date().toLocaleTimeString();

  let cls, badge, msg;
  const label = type.toUpperCase().replace('_', ' ');

  if (error) {
    cls = 'error-log';
    badge = `<span class="log-badge badge-error">ERROR</span>`;
    msg = `${label} request failed: ${error}`;
  } else if (result.is_anomaly) {
    cls = 'leak-log';
    const badgeText = type === 'synthetic_leak' ? 'SYNTH LEAK' : 'LEAK';
    badge = `<span class="log-badge badge-anomaly">${badgeText}</span>`;
    msg = `${label} → ${result.zone} | MSE ${result.mse.toFixed(5)} | ` +
      `Sensors: ${result.top_sensors.join(', ')} | ${elapsed}ms`;
  } else {
    cls = type === 'random' ? 'random-log' : 'normal-log';
    let badgeText = 'NORMAL';
    let badgeCls = 'badge-normal';
    if (type === 'random') {
      badgeText = 'RANDOM';
      badgeCls = 'badge-random';
    } else if (type === 'synthetic') {
      badgeText = 'SYNTH NORM';
      badgeCls = 'badge-random';
    }
    badge = `<span class="log-badge ${badgeCls}">${badgeText}</span>`;
    msg = `${label} → ${result.zone} | MSE ${result.mse.toFixed(5)} | ${elapsed}ms`;
  }

  const entry = document.createElement('div');
  entry.className = `log-entry ${cls}`;
  entry.innerHTML = `
    <span class="log-time">${now}</span>
    <span class="log-msg">${msg}</span>
    ${badge}
  `;

  logContainer.prepend(entry);

  // Keep only last 20 entries
  while (logContainer.children.length > 20) {
    logContainer.removeChild(logContainer.lastChild);
  }
}

// ─────────────────────────────────────────────────────────────────
// API Health Check
// ─────────────────────────────────────────────────────────────────

async function updateApiStatus() {
  const indicator = document.getElementById('connectionStatus');
  const label = document.getElementById('connectionLabel');
  const apiBase = getApiBase();

  try {
    const resp = await fetch(`${apiBase}/health`, { signal: AbortSignal.timeout(3000) });
    if (resp.ok) {
      const data = await resp.json();
      indicator.className = 'status-dot';
      indicator.style.background = '#00e676';
      indicator.style.boxShadow = '0 0 8px #00e676';
      label.textContent = `Connected · ${data.model_loaded ? '🧠 Model' : '⚙️ Mock'} · ${data.num_sensors} sensors`;
      document.getElementById('modelBadge').textContent =
        data.model_loaded ? '🧠 Real Model' : '⚙️ Mock Mode';
      return;
    }
  } catch { /* fall through */ }

  indicator.style.background = '#ff9100';
  indicator.style.boxShadow = '0 0 8px #ff9100';
  label.textContent = 'API Offline — start: uvicorn main:app --reload';
}

document.getElementById('apiUrl').addEventListener('change', () => updateApiStatus());

// Refresh health every 30 seconds
setInterval(updateApiStatus, 30_000);

// ── Broadcast Manual Alerts ───────────────────────────────────────

async function sendBroadcast() {
  const zone = document.getElementById('broadcastZone').value;
  const message = document.getElementById('broadcastMsg').value;
  const apiBase = getApiBase();

  if (!message) {
    alert("Please enter an alert message!");
    return;
  }

  try {
    const resp = await fetch(`${apiBase}/api/v1/broadcast`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ zone, message, severity: 'high' }),
    });

    if (!resp.ok) throw new Error(`HTTP ${resp.status}`);

    alert(`📡 Broadcast sent successfully to ${zone}!`);
    document.getElementById('broadcastMsg').value = '';

    // Trigger status update to show it's working
    updateApiStatus();
  } catch (err) {
    alert(`Failed to send broadcast: ${err.message}`);
  }
}

// ── Add Engineer Modal Logic ────────────────────────────────────────────────
function openEngModal() {
  document.getElementById('engModal').style.display = 'flex';
  document.getElementById('engMsg').style.display = 'none';
}

function closeEngModal() {
  document.getElementById('engModal').style.display = 'none';
  document.getElementById('engName').value = '';
  document.getElementById('engId').value = '';
  document.getElementById('engPass').value = '';
}

async function registerEngineer() {
  const name = document.getElementById('engName').value.trim();
  const id = document.getElementById('engId').value.trim();
  const pass = document.getElementById('engPass').value.trim();
  const msgDiv = document.getElementById('engMsg');
  const btn = document.getElementById('engSubmitBtn');
  
  // Use the API URL from the config input field on the dashboard
  const API_BASE = document.getElementById('apiUrl').value.replace(/\/$/, "");

  if (!name || !id || !pass) {
    msgDiv.style.display = 'block';
    msgDiv.style.backgroundColor = 'rgba(255, 71, 86, 0.1)';
    msgDiv.style.color = 'var(--red)';
    msgDiv.textContent = 'Please fill all fields.';
    return;
  }

  btn.disabled = true;
  btn.textContent = 'Registering...';

  try {
    const res = await fetch(`${API_BASE}/api/v1/auth/engineer/register`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name: name, engineer_id: id, password: pass })
    });

    const data = await res.json();

    msgDiv.style.display = 'block';
    if (res.ok) {
      msgDiv.style.backgroundColor = 'rgba(0, 230, 118, 0.1)';
      msgDiv.style.color = 'var(--green)';
      msgDiv.textContent = `Success! Engineer ${id} registered.`;
      setTimeout(closeEngModal, 2000);
    } else {
      msgDiv.style.backgroundColor = 'rgba(255, 71, 86, 0.1)';
      msgDiv.style.color = 'var(--red)';
      msgDiv.textContent = data.detail || 'Registration failed.';
    }
  } catch (err) {
    msgDiv.style.display = 'block';
    msgDiv.style.backgroundColor = 'rgba(255, 71, 86, 0.1)';
    msgDiv.style.color = 'var(--red)';
    msgDiv.textContent = 'Network Error: Could not connect to API.';
  } finally {
    btn.disabled = false;
    btn.textContent = 'Register';
  }
}

// ═══════════════════════════════════════════════════════════════
// LIVE NETWORK MAP — Zone State & Rendering
// ═══════════════════════════════════════════════════════════════

/**
 * Called after every successful prediction.
 * Computes the new zone status and schedules an auto-decay timer.
 */
function updateZoneState(result) {
  const zone = result.zone;
  if (!zoneState[zone]) return;

  const state = zoneState[zone];
  const isAnomaly = result.is_anomaly === 1;
  const conf = result.confidence;

  // Cancel any existing decay timer for this zone
  if (state.decayTimer) {
    clearTimeout(state.decayTimer);
    state.decayTimer = null;
  }

  // Determine status
  if (isAnomaly && conf >= 0.7) {
    state.status = 'red';
  } else if (isAnomaly || conf >= 0.4) {
    state.status = 'yellow';
  } else {
    state.status = 'green';
  }

  state.confidence  = conf;
  state.mse         = result.mse;
  state.lastUpdated = new Date();

  // Schedule decay back to green after 2 minutes (only for non-green states)
  if (state.status !== 'green') {
    state.decayTimer = setTimeout(() => {
      zoneState[zone].status = 'green';
      renderNetworkMap();
    }, 2 * 60 * 1000);
  }

  renderNetworkMap();
}

/**
 * Reads zoneState and updates all SVG elements + stat cards.
 * Pure DOM class toggling — very fast, no layout thrash.
 */
function renderNetworkMap() {
  const STATUSES = ['green', 'yellow', 'red'];
  const ICONS = { green: '💧', yellow: '⚠️', red: '🚨' };

  ZONES.forEach((zone, idx) => {
    const n    = idx + 1;                    // 1-based zone number
    const st   = zoneState[zone].status;
    const conf = zoneState[zone].confidence;
    const ts   = zoneState[zone].lastUpdated;

    // ── SVG node + border ────────────────────────────────────────
    const nodeEl   = document.getElementById(`zone${n}-node`);
    const borderEl = document.getElementById(`zone${n}-border`);
    const iconEl   = document.getElementById(`zone${n}-icon`);

    if (nodeEl) {
      STATUSES.forEach(s => nodeEl.classList.remove(`status-${s}`));
      nodeEl.classList.add(`status-${st}`);
    }
    if (borderEl) {
      STATUSES.forEach(s => borderEl.classList.remove(`status-${s}`));
      borderEl.classList.add(`status-${st}`);
    }
    if (iconEl) {
      iconEl.textContent = ICONS[st];
    }

    // ── Stat card ────────────────────────────────────────────────
    const card    = document.getElementById(`zcard-${zone}`);
    const dot     = document.getElementById(`zdot-${zone}`);
    const confEl  = document.getElementById(`zconf-${zone}`);
    const tsEl    = document.getElementById(`zts-${zone}`);

    if (card) {
      STATUSES.forEach(s => card.classList.remove(`status-${s}`));
      card.classList.add(`status-${st}`);
    }
    if (dot) {
      STATUSES.forEach(s => dot.classList.remove(`status-${s}`));
      dot.classList.add(`status-${st}`);
    }
    if (confEl) {
      confEl.classList.remove(...STATUSES.map(s => `status-${s}`));
      confEl.classList.add(`status-${st}`);
      confEl.textContent = conf !== null ? `${(conf * 100).toFixed(0)}%` : '—';
    }
    if (tsEl) {
      tsEl.textContent = ts ? ts.toLocaleTimeString() : 'No data yet';
    }
  });

  // ── Pipe colors (reflect upstream zone status) ───────────────
  Object.entries(PIPE_ZONE_MAP).forEach(([pipeId, srcZone]) => {
    const pipeEl = document.getElementById(pipeId);
    if (!pipeEl) return;
    const st = zoneState[srcZone].status;
    ['green', 'yellow', 'red'].forEach(s => pipeEl.classList.remove(`status-${s}`));
    pipeEl.classList.add(`status-${st}`);
  });

  // ── Sync geographic map ────────────────────────────────────
  updateGeoMap();
}

// ═══════════════════════════════════════════════════════════════
// AUTO-SIMULATION TOGGLE
// ═══════════════════════════════════════════════════════════════

function toggleAutoSim() {
  if (autoSimInterval) {
    stopAutoSim();
  } else {
    startAutoSim();
  }
}

function startAutoSim() {
  const btn       = document.getElementById('autoSimBtn');
  const iconEl    = document.getElementById('autoSimIcon');
  const labelEl   = document.getElementById('autoSimLabel');
  const cdEl      = document.getElementById('autoSimCountdown');

  // Kick off first prediction immediately
  sendData('random');

  autoSimCountdown = AUTO_SIM_INTERVAL_S;

  // Countdown ticker (updates every second)
  countdownTimer = setInterval(() => {
    autoSimCountdown--;
    cdEl.textContent = `${autoSimCountdown}s`;
    if (autoSimCountdown <= 0) autoSimCountdown = AUTO_SIM_INTERVAL_S;
  }, 1000);

  // Prediction interval
  autoSimInterval = setInterval(() => {
    autoSimCountdown = AUTO_SIM_INTERVAL_S;
    sendData('random');
  }, AUTO_SIM_INTERVAL_S * 1000);

  // UI
  btn.classList.add('running');
  iconEl.textContent   = '⏸';
  labelEl.textContent  = 'Stop Sim';
  cdEl.style.display   = 'inline';
  cdEl.textContent     = `${AUTO_SIM_INTERVAL_S}s`;
}

function stopAutoSim() {
  clearInterval(autoSimInterval);
  clearInterval(countdownTimer);
  autoSimInterval  = null;
  countdownTimer   = null;
  autoSimCountdown = 0;

  const btn     = document.getElementById('autoSimBtn');
  const iconEl  = document.getElementById('autoSimIcon');
  const labelEl = document.getElementById('autoSimLabel');
  const cdEl    = document.getElementById('autoSimCountdown');

  btn.classList.remove('running');
  iconEl.textContent  = '▶';
  labelEl.textContent = 'Auto-Simulate';
  cdEl.style.display  = 'none';
}

// ═══════════════════════════════════════════════════════════════
// GEOGRAPHIC LEAK MAP — Leaflet.js
// Zones mapped onto Alexandria, Egypt (fictional but geographically
// realistic coordinates matching actual city districts).
// ═══════════════════════════════════════════════════════════════

const ZONE_COORDS = [
  {
    zone:    'Zone 1',
    lat:     30.1236,
    lng:     31.2429,
    radius:  2200,
    desc:    'Shoubra El Kheima — Coastal Intake & Primary Pipes',
    sensors: 'n1 – n30',
  },
  {
    zone:    'Zone 2',
    lat:     30.0870,
    lng:     31.3217,
    radius:  2000,
    desc:    'Heliopolis — Central Distribution Hub',
    sensors: 'n31 – n60',
  },
  {
    zone:    'Zone 3',
    lat:     30.0626,
    lng:     31.3417,
    radius:  1800,
    desc:    'Nasr City — Main Residential Grid',
    sensors: 'n61 – n90',
  },
  {
    zone:    'Zone 4',
    lat:     29.9600,
    lng:     31.2600,
    radius:  2400,
    desc:    'Maadi — Industrial / High Pressure',
    sensors: 'n91 – n120',
  },
  {
    zone:    'Zone 5',
    lat:     30.0131,
    lng:     31.4800,
    radius:  3000,
    desc:    'New Cairo — Extended Remote Network',
    sensors: 'n121 – n300',
  },
];

// Color palette per status
const GEO_COLORS = {
  green:  { fill: 'rgba(0, 230, 118, 0.22)',  border: '#00e676' },
  yellow: { fill: 'rgba(255, 145, 0, 0.28)',  border: '#ff9100' },
  red:    { fill: 'rgba(255, 71, 86, 0.32)',   border: '#ff4756' },
};

// Holds Leaflet circle references keyed by zone name
const zoneCircles = {};
let geoMap = null;

/**
 * Initialise the Leaflet map. Called once on DOMContentLoaded.
 */
function initGeoMap() {
  if (typeof L === 'undefined') return;   // Leaflet not loaded yet (offline)

  geoMap = L.map('geoMap', {
    center:             [30.06, 31.35],
    zoom:               11,
    zoomControl:        true,
    attributionControl: true,
  });

  // OpenStreetMap tiles — free, no API key
  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom:     19,
    attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
  }).addTo(geoMap);

  // Draw one circle per zone
  ZONE_COORDS.forEach(({ zone, lat, lng, radius, desc, sensors }) => {
    const colors = GEO_COLORS.green;

    const circle = L.circle([lat, lng], {
      radius,
      color:       colors.border,
      fillColor:   colors.fill,
      fillOpacity: 1,
      weight:      2,
      opacity:     0.9,
    }).addTo(geoMap);

    // Bind popup (content updated dynamically in updateGeoMap)
    circle.bindPopup(buildPopupHtml(zone, desc, sensors, 'green', null, null));

    // Store reference
    zoneCircles[zone] = { circle, lat, lng, desc, sensors };
  });
}

/**
 * Build the styled popup HTML for a zone.
 */
function buildPopupHtml(zone, desc, sensors, status, confidence, ts) {
  const statusLabel = { green: '✅ Normal', yellow: '⚠️ Warning', red: '🚨 Leak Detected' }[status];
  const statusColor = { green: '#00e676',   yellow: '#ff9100',     red: '#ff4756' }[status];

  const confLine = confidence !== null
    ? `<div style="margin-top:6px; font-family:'JetBrains Mono',monospace; font-size:18px; font-weight:700; color:${statusColor};">
         ${(confidence * 100).toFixed(0)}%
         <span style="font-size:11px; font-weight:400; color:#7986a1; margin-left:4px;">confidence</span>
       </div>`
    : `<div style="margin-top:6px; color:#4a5568; font-size:12px;">No prediction yet</div>`;

  const tsLine = ts
    ? `<div style="margin-top:4px; font-family:'JetBrains Mono',monospace; font-size:10px; color:#4a5568;">${ts.toLocaleTimeString()}</div>`
    : '';

  return `
    <div>
      <div style="font-weight:700; font-size:14px; color:#e8eaf6;">${zone}</div>
      <div style="font-size:11px; color:#7986a1; margin-top:2px;">${desc}</div>
      <div style="font-size:10px; font-family:'JetBrains Mono',monospace; color:#4a5568; margin-top:2px;">${sensors}</div>
      <div style="margin-top:8px; padding-top:8px; border-top:1px solid rgba(255,255,255,0.07);">
        <span style="font-size:12px; font-weight:600; color:${statusColor};">${statusLabel}</span>
      </div>
      ${confLine}
      ${tsLine}
    </div>
  `;
}

/**
 * Sync circle colors + popups with the current zoneState.
 * Called at the end of renderNetworkMap() — zero extra API calls.
 */
function updateGeoMap() {
  if (!geoMap || typeof L === 'undefined') return;

  const autoFly = document.getElementById('autoFlyCheck')?.checked ?? true;
  let firstRedZone = null;

  ZONES.forEach(zone => {
    const ref = zoneCircles[zone];
    if (!ref) return;

    const { status, confidence, lastUpdated } = zoneState[zone];
    const colors = GEO_COLORS[status];

    // Recolor the circle
    ref.circle.setStyle({
      color:       colors.border,
      fillColor:   colors.fill,
      fillOpacity: 1,
      weight:      status === 'red' ? 3 : 2,
    });

    // Refresh popup content
    ref.circle.setPopupContent(
      buildPopupHtml(zone, ref.desc, ref.sensors, status, confidence, lastUpdated)
    );

    // Track first red zone for auto-fly
    if (status === 'red' && !firstRedZone) {
      firstRedZone = ref;
    }
  });

  // Fly to the first red zone if auto-fly is on
  if (autoFly && firstRedZone) {
    geoMap.flyTo([firstRedZone.lat, firstRedZone.lng], 13, {
      animate:  true,
      duration: 1.4,
    });
  }
}
