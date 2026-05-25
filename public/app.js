const palette = ["#4fb7ff", "#66e7a0", "#ffd166", "#ff6b83", "#b892ff", "#ff9f43", "#6ee7f9", "#9cff6e"];

const els = {
  statusDot: document.getElementById("statusDot"),
  statusText: document.getElementById("statusText"),
  totalSessions: document.getElementById("totalSessions"),
  avgPlaytime: document.getElementById("avgPlaytime"),
  avgRooms: document.getElementById("avgRooms"),
  totalDeaths: document.getElementById("totalDeaths"),
  refreshButton: document.getElementById("refreshButton"),
  deathLegend: document.getElementById("deathLegend"),
  miniSections: document.getElementById("miniSections"),
  rawJson: document.getElementById("rawJson")
};

function fmtNumber(value, digits = 0) {
  return Number(value || 0).toLocaleString(undefined, { maximumFractionDigits: digits });
}

function fmtTime(seconds) {
  const total = Math.round(Number(seconds || 0));
  const minutes = Math.floor(total / 60);
  const rem = total % 60;
  if (minutes >= 60) {
    const hours = Math.floor(minutes / 60);
    return `${hours}h ${minutes % 60}m`;
  }
  return `${minutes}m ${rem}s`;
}

function entries(obj) {
  return Object.entries(obj || {})
    .map(([label, value]) => [label, Number(value) || 0])
    .filter(([, value]) => value > 0)
    .sort((a, b) => b[1] - a[1]);
}

function clearCanvas(canvas) {
  const ctx = canvas.getContext("2d");
  const width = canvas.width;
  const height = canvas.height;
  ctx.clearRect(0, 0, width, height);
  ctx.fillStyle = "#141f2d";
  ctx.fillRect(0, 0, width, height);
  return ctx;
}

function drawEmpty(canvas, text) {
  const ctx = clearCanvas(canvas);
  ctx.fillStyle = "#8fa1b7";
  ctx.font = "700 16px Segoe UI";
  ctx.textAlign = "center";
  ctx.fillText(text, canvas.width / 2, canvas.height / 2);
}

function drawBarChart(canvas, labels, series) {
  if (!labels.length) {
    drawEmpty(canvas, "No hour data yet");
    return;
  }
  const ctx = clearCanvas(canvas);
  const pad = { left: 48, right: 22, top: 24, bottom: 58 };
  const chartW = canvas.width - pad.left - pad.right;
  const chartH = canvas.height - pad.top - pad.bottom;
  const max = Math.max(1, ...series.flatMap((item) => item.values));
  const groupW = chartW / labels.length;
  const barW = Math.max(8, Math.min(26, groupW / (series.length + 1)));

  ctx.strokeStyle = "#263446";
  ctx.lineWidth = 1;
  ctx.fillStyle = "#8fa1b7";
  ctx.font = "12px Segoe UI";
  ctx.textAlign = "right";
  for (let i = 0; i <= 4; i++) {
    const y = pad.top + chartH - (chartH * i) / 4;
    const value = Math.round((max * i) / 4);
    ctx.beginPath();
    ctx.moveTo(pad.left, y);
    ctx.lineTo(canvas.width - pad.right, y);
    ctx.stroke();
    ctx.fillText(value, pad.left - 8, y + 4);
  }

  labels.forEach((label, index) => {
    series.forEach((item, sIndex) => {
      const value = item.values[index] || 0;
      const h = (value / max) * chartH;
      const x = pad.left + index * groupW + groupW / 2 - barW * series.length / 2 + sIndex * barW;
      const y = pad.top + chartH - h;
      ctx.fillStyle = item.color;
      ctx.fillRect(x, y, barW - 2, h);
    });
    ctx.save();
    ctx.translate(pad.left + index * groupW + groupW / 2, canvas.height - 18);
    ctx.rotate(-0.55);
    ctx.fillStyle = "#8fa1b7";
    ctx.font = "11px Segoe UI";
    ctx.textAlign = "right";
    ctx.fillText(label.replace(":00:00Z", "Z").replace("T", " "), 0, 0);
    ctx.restore();
  });

  series.forEach((item, index) => {
    const x = pad.left + index * 110;
    ctx.fillStyle = item.color;
    ctx.fillRect(x, 10, 12, 12);
    ctx.fillStyle = "#c8d7e8";
    ctx.font = "700 12px Segoe UI";
    ctx.textAlign = "left";
    ctx.fillText(item.name, x + 18, 20);
  });
}

function drawPie(canvas, rows) {
  if (!rows.length) {
    drawEmpty(canvas, "No death data yet");
    return;
  }
  const ctx = clearCanvas(canvas);
  const total = rows.reduce((sum, [, value]) => sum + value, 0);
  const cx = canvas.width / 2;
  const cy = canvas.height / 2;
  const radius = Math.min(canvas.width, canvas.height) * 0.33;
  let angle = -Math.PI / 2;

  rows.forEach(([label, value], index) => {
    const slice = (value / total) * Math.PI * 2;
    ctx.beginPath();
    ctx.moveTo(cx, cy);
    ctx.arc(cx, cy, radius, angle, angle + slice);
    ctx.closePath();
    ctx.fillStyle = palette[index % palette.length];
    ctx.fill();
    angle += slice;
  });

  ctx.beginPath();
  ctx.arc(cx, cy, radius * 0.55, 0, Math.PI * 2);
  ctx.fillStyle = "#141f2d";
  ctx.fill();
  ctx.fillStyle = "#eef6ff";
  ctx.font = "800 28px Segoe UI";
  ctx.textAlign = "center";
  ctx.fillText(fmtNumber(total), cx, cy + 8);
}

function drawHorizontalBars(canvas, rows) {
  if (!rows.length) {
    drawEmpty(canvas, "No section data yet");
    return;
  }
  const ctx = clearCanvas(canvas);
  const top = rows.slice(0, 7);
  const max = Math.max(...top.map(([, value]) => value), 1);
  const pad = 28;
  const rowH = (canvas.height - pad * 2) / top.length;
  ctx.font = "700 13px Segoe UI";
  top.forEach(([label, value], index) => {
    const y = pad + index * rowH + 5;
    const w = ((canvas.width - 150) * value) / max;
    ctx.fillStyle = "#8fa1b7";
    ctx.textAlign = "left";
    ctx.fillText(label, 22, y + 16);
    ctx.fillStyle = palette[index % palette.length];
    ctx.fillRect(120, y, w, 18);
    ctx.fillStyle = "#eef6ff";
    ctx.textAlign = "right";
    ctx.fillText(fmtNumber(value), canvas.width - 20, y + 16);
  });
}

function renderMiniSections(rows) {
  els.miniSections.innerHTML = "";
  if (!rows.length) {
    els.miniSections.textContent = "No mini-section data yet.";
    return;
  }
  const max = Math.max(...rows.map(([, value]) => value), 1);
  rows.slice(0, 10).forEach(([label, value]) => {
    const row = document.createElement("div");
    row.className = "bar-row";
    row.innerHTML = `<span>${label}</span><div class="bar-track"><div class="bar-fill" style="width:${(value / max) * 100}%"></div></div><strong>${fmtNumber(value)}</strong>`;
    els.miniSections.append(row);
  });
}

function render(data) {
  els.totalSessions.textContent = fmtNumber(data.TotalSessions);
  els.avgPlaytime.textContent = fmtTime(data.AveragePlaytimeSeconds);
  els.avgRooms.textContent = fmtNumber(data.AverageRoomsTravelledBeforeLeave, 1);
  els.totalDeaths.textContent = fmtNumber(data.TotalDeaths);
  els.rawJson.textContent = JSON.stringify(data, null, 2);
  if (!Number(data.TotalSessions || 0)) {
    els.statusText.textContent = "Waiting for live Roblox data";
  }

  const hours = Array.from(new Set([
    ...Object.keys(data.JoinHoursUtc || {}),
    ...Object.keys(data.LeaveHoursUtc || {})
  ])).sort().slice(-14);
  drawBarChart(document.getElementById("hoursChart"), hours, [
    { name: "Joins", color: "#4fb7ff", values: hours.map((hour) => Number(data.JoinHoursUtc?.[hour] || 0)) },
    { name: "Leaves", color: "#ff6b83", values: hours.map((hour) => Number(data.LeaveHoursUtc?.[hour] || 0)) }
  ]);

  const deathRows = entries(data.DeathCauses);
  drawPie(document.getElementById("deathPie"), deathRows);
  els.deathLegend.innerHTML = "";
  deathRows.slice(0, 8).forEach(([label, value], index) => {
    const item = document.createElement("span");
    item.innerHTML = `<i style="background:${palette[index % palette.length]}"></i>${label} ${fmtNumber(value)}`;
    els.deathLegend.append(item);
  });

  drawHorizontalBars(document.getElementById("sectionsChart"), entries(data.SectionsCrossed));
  renderMiniSections(entries(data.MiniSectionsCrossed));
}

async function loadAnalytics() {
  try {
    const response = await fetch("/api/analytics", { cache: "no-store" });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const data = await response.json();
    render(data);
    els.statusText.textContent = Number(data.TotalSessions || 0)
      ? `Updated ${data.LastUpdatedUtc || "live"}`
      : "Waiting for live Roblox data";
    els.statusDot.style.background = "#66e7a0";
  } catch (error) {
    els.statusText.textContent = error.message;
    els.statusDot.style.background = "#ff6b83";
  }
}

els.refreshButton.addEventListener("click", loadAnalytics);
loadAnalytics();
setInterval(loadAnalytics, 30000);
