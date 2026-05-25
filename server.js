const http = require("node:http");
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");

const PORT = Number(process.env.PORT || 8787);
const INGEST_TOKEN = process.env.ROOMS_ANALYTICS_TOKEN || "change-me-local-token";
const DEBUG = process.env.ROOMS_ANALYTICS_DEBUG === "1";
const ROOT = __dirname;
const PUBLIC_DIR = path.join(ROOT, "public");
const DATA_DIR = path.join(ROOT, "data");
const DATA_FILE = path.join(DATA_DIR, "analytics.json");
const DATA_BACKUP_FILE = path.join(DATA_DIR, "analytics.backup.json");

const EMPTY_DATA = {
  Version: 1,
  TotalSessions: 0,
  TotalPlaytimeSeconds: 0,
  AveragePlaytimeSeconds: 0,
  TotalDeaths: 0,
  TotalRoomsTravelled: 0,
  AverageRoomsTravelledBeforeLeave: 0,
  TotalSectionsCrossed: 0,
  AverageSectionsCrossedBeforeLeave: 0,
  TotalMiniSectionsCrossed: 0,
  AverageMiniSectionsCrossedBeforeLeave: 0,
  LastUpdatedUtc: null,
  JoinHoursUtc: {},
  LeaveHoursUtc: {},
  SessionsByDayUtc: {},
  DeathCauses: {},
  SectionsCrossed: {},
  MiniSectionsCrossed: {},
  Environments: {},
  AccountAgeGroups: {},
  Categories: {}
};

const DEMO_DATA = {
  Version: 1,
  TotalSessions: 42,
  TotalPlaytimeSeconds: 31860,
  AveragePlaytimeSeconds: 758.57,
  TotalDeaths: 67,
  TotalRoomsTravelled: 1931,
  AverageRoomsTravelledBeforeLeave: 45.98,
  TotalSectionsCrossed: 71,
  AverageSectionsCrossedBeforeLeave: 1.69,
  TotalMiniSectionsCrossed: 118,
  AverageMiniSectionsCrossedBeforeLeave: 2.81,
  LastUpdatedUtc: new Date().toISOString().replace(/\.\d{3}Z$/, "Z"),
  JoinHoursUtc: {
    "2026-05-24T18:00:00Z": 6,
    "2026-05-24T19:00:00Z": 8,
    "2026-05-24T20:00:00Z": 11,
    "2026-05-24T21:00:00Z": 9,
    "2026-05-24T22:00:00Z": 8
  },
  LeaveHoursUtc: {
    "2026-05-24T18:00:00Z": 3,
    "2026-05-24T19:00:00Z": 7,
    "2026-05-24T20:00:00Z": 10,
    "2026-05-24T21:00:00Z": 12,
    "2026-05-24T22:00:00Z": 10
  },
  SessionsByDayUtc: { "2026-05-24": 42 },
  DeathCauses: { "A-60": 21, "A-200": 14, "B-30": 18, Unknown: 14 },
  SectionsCrossed: { A: 42, B: 29 },
  MiniSectionsCrossed: { Office: 33, Basic: 41, Catwalk: 18, Kitchen: 12, "B-Basic": 14 },
  Environments: { Game: 38, InStudio: 4 },
  AccountAgeGroups: { "0-6 days": 3, "7-29 days": 8, "30-179 days": 12, "180-364 days": 9, "1-2 years": 6, "3+ years": 4 },
  Categories: {}
};

function ensureDataFile() {
  fs.mkdirSync(DATA_DIR, { recursive: true });
  if (!fs.existsSync(DATA_FILE)) {
    fs.writeFileSync(DATA_FILE, JSON.stringify(EMPTY_DATA, null, 2));
  }
}

function readAnalytics() {
  ensureDataFile();
  for (const file of [DATA_FILE, DATA_BACKUP_FILE]) {
    try {
      return JSON.parse(fs.readFileSync(file, "utf8"));
    } catch {
      // Try the next save file.
    }
  }
  return { ...EMPTY_DATA };
}

function writeAnalytics(data) {
  fs.mkdirSync(DATA_DIR, { recursive: true });
  const body = JSON.stringify(data, null, 2);
  const tempFile = path.join(DATA_DIR, `analytics.${process.pid}.tmp`);
  fs.writeFileSync(tempFile, body);
  fs.renameSync(tempFile, DATA_FILE);
  fs.writeFileSync(DATA_BACKUP_FILE, body);
}

function logDebug(...args) {
  if (DEBUG) {
    console.log("[analytics-debug]", ...args);
  }
}

function safeKey(value) {
  return String(value || "Unknown").replace(/[^\w.-]/g, "_").slice(0, 64) || "Unknown";
}

function addCount(map, key, amount = 1) {
  if (!map || typeof map !== "object") return;
  const cleanKey = safeKey(key);
  map[cleanKey] = Number(map[cleanKey] || 0) + Number(amount || 0);
}

function addRawCount(map, key, amount = 1) {
  if (!map || typeof map !== "object") return;
  const cleanKey = String(key || "Unknown").slice(0, 80) || "Unknown";
  map[cleanKey] = Number(map[cleanKey] || 0) + Number(amount || 0);
}

function asNumber(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : 0;
}

function mapCounts(source, keepRawKeys = false) {
  const out = {};
  if (!source || typeof source !== "object") return out;
  for (const [key, value] of Object.entries(source)) {
    if (keepRawKeys) addRawCount(out, key, value);
    else addCount(out, key, value);
  }
  return out;
}

function normalizeCategoryMap(source) {
  const out = {};
  if (!source || typeof source !== "object" || Array.isArray(source)) return out;
  for (const [name, value] of Object.entries(source)) {
    if (!value || typeof value !== "object" || Array.isArray(value)) continue;
    out[safeKey(name)] = normalizeAggregate(value);
  }
  return out;
}

function normalizeAggregate(input) {
  const totalSessions = Math.max(0, asNumber(input.TotalSessions));
  const totalPlaytime = Math.max(0, asNumber(input.TotalPlaytimeSeconds));
  const totalRooms = Math.max(0, asNumber(input.TotalRoomsTravelled));
  const totalSections = Math.max(0, asNumber(input.TotalSectionsCrossed));
  const totalMiniSections = Math.max(0, asNumber(input.TotalMiniSectionsCrossed));

  return {
    Version: 1,
    TotalSessions: totalSessions,
    TotalPlaytimeSeconds: totalPlaytime,
    AveragePlaytimeSeconds: totalSessions > 0 ? totalPlaytime / totalSessions : 0,
    TotalDeaths: Math.max(0, asNumber(input.TotalDeaths)),
    TotalRoomsTravelled: totalRooms,
    AverageRoomsTravelledBeforeLeave: totalSessions > 0 ? totalRooms / totalSessions : 0,
    TotalSectionsCrossed: totalSections,
    AverageSectionsCrossedBeforeLeave: totalSessions > 0 ? totalSections / totalSessions : 0,
    TotalMiniSectionsCrossed: totalMiniSections,
    AverageMiniSectionsCrossedBeforeLeave: totalSessions > 0 ? totalMiniSections / totalSessions : 0,
    LastUpdatedUtc: input.LastUpdatedUtc || input.leaveUtc || new Date().toISOString().replace(/\.\d{3}Z$/, "Z"),
    JoinHoursUtc: mapCounts(input.JoinHoursUtc, true),
    LeaveHoursUtc: mapCounts(input.LeaveHoursUtc, true),
    SessionsByDayUtc: mapCounts(input.SessionsByDayUtc, true),
    DeathCauses: mapCounts(input.DeathCauses),
    SectionsCrossed: mapCounts(input.SectionsCrossed),
    MiniSectionsCrossed: mapCounts(input.MiniSectionsCrossed),
    Environments: mapCounts(input.Environments || input.EnvironmentTotals),
    AccountAgeGroups: mapCounts(input.AccountAgeGroups || input.AgeGroups, true),
    Categories: normalizeCategoryMap(input.Categories)
  };
}

function mergeAnalytics(current, incoming, skipBreakdowns = false) {
  const merged = current && typeof current === "object" ? current : {};
  const sessionsBefore = asNumber(merged.TotalSessions);
  const sessionsIncoming = Math.max(0, asNumber(incoming.TotalSessions || 1));
  const totalSessions = sessionsBefore + sessionsIncoming;

  merged.Version = 1;
  merged.TotalSessions = totalSessions;
  merged.TotalPlaytimeSeconds = asNumber(merged.TotalPlaytimeSeconds) + asNumber(incoming.TotalPlaytimeSeconds || incoming.playtimeSeconds);
  merged.AveragePlaytimeSeconds = totalSessions > 0 ? merged.TotalPlaytimeSeconds / totalSessions : 0;
  merged.TotalDeaths = asNumber(merged.TotalDeaths) + asNumber(incoming.TotalDeaths || incoming.deaths);
  merged.TotalRoomsTravelled = asNumber(merged.TotalRoomsTravelled) + asNumber(incoming.TotalRoomsTravelled || incoming.roomsTravelled);
  merged.AverageRoomsTravelledBeforeLeave = totalSessions > 0 ? merged.TotalRoomsTravelled / totalSessions : 0;
  merged.TotalSectionsCrossed = asNumber(merged.TotalSectionsCrossed) + asNumber(incoming.TotalSectionsCrossed || incoming.sectionsCrossed);
  merged.AverageSectionsCrossedBeforeLeave = totalSessions > 0 ? merged.TotalSectionsCrossed / totalSessions : 0;
  merged.TotalMiniSectionsCrossed = asNumber(merged.TotalMiniSectionsCrossed) + asNumber(incoming.TotalMiniSectionsCrossed || incoming.miniSectionsCrossed);
  merged.AverageMiniSectionsCrossedBeforeLeave = totalSessions > 0 ? merged.TotalMiniSectionsCrossed / totalSessions : 0;
  merged.LastUpdatedUtc = incoming.LastUpdatedUtc || incoming.leaveUtc || new Date().toISOString().replace(/\.\d{3}Z$/, "Z");

  const sourceAliases = {
    JoinHoursUtc: incoming.JoinHoursUtc || (incoming.joinHourUtc ? { [incoming.joinHourUtc]: 1 } : {}),
    LeaveHoursUtc: incoming.LeaveHoursUtc || (incoming.leaveHourUtc ? { [incoming.leaveHourUtc]: 1 } : {}),
    SessionsByDayUtc: incoming.SessionsByDayUtc || (incoming.dayUtc ? { [incoming.dayUtc]: 1 } : {}),
    DeathCauses: incoming.DeathCauses || incoming.deathCauses || {},
    SectionsCrossed: incoming.SectionsCrossed || incoming.sections || {},
    MiniSectionsCrossed: incoming.MiniSectionsCrossed || incoming.miniSections || {}
  };

  for (const key of ["JoinHoursUtc", "LeaveHoursUtc", "SessionsByDayUtc", "DeathCauses", "SectionsCrossed", "MiniSectionsCrossed"]) {
    merged[key] = merged[key] && typeof merged[key] === "object" ? merged[key] : {};
    const source = sourceAliases[key] && typeof sourceAliases[key] === "object" ? sourceAliases[key] : {};
    const add = key === "JoinHoursUtc" || key === "LeaveHoursUtc" || key === "SessionsByDayUtc" ? addRawCount : addCount;
    for (const [name, amount] of Object.entries(source)) add(merged[key], name, amount);
  }

  const environment = safeKey(incoming.environment || incoming.Environment || incoming.category || incoming.Category || "Game");
  const accountAgeGroup = incoming.accountAgeGroup || incoming.AccountAgeGroup || incoming.ageGroup || incoming.AgeGroup || "Unknown";
  merged.Environments = merged.Environments && typeof merged.Environments === "object" ? merged.Environments : {};
  merged.AccountAgeGroups = merged.AccountAgeGroups && typeof merged.AccountAgeGroups === "object" ? merged.AccountAgeGroups : {};
  addCount(merged.Environments, environment, sessionsIncoming);
  addRawCount(merged.AccountAgeGroups, accountAgeGroup, sessionsIncoming);

  if (!skipBreakdowns) {
    merged.Categories = merged.Categories && typeof merged.Categories === "object" ? merged.Categories : {};
    merged.Categories[environment] = mergeAnalytics(merged.Categories[environment], incoming, true);
  }

  return merged;
}

function sendJson(res, status, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": Buffer.byteLength(body),
    "Cache-Control": "no-store"
  });
  res.end(body);
}

function serveStatic(req, res) {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const pathname = url.pathname === "/" ? "/index.html" : url.pathname;
  const resolved = path.normalize(path.join(PUBLIC_DIR, pathname));
  if (!resolved.startsWith(PUBLIC_DIR)) {
    res.writeHead(403);
    res.end("Forbidden");
    return;
  }

  fs.readFile(resolved, (err, data) => {
    if (err) {
      res.writeHead(404);
      res.end("Not found");
      return;
    }
    const ext = path.extname(resolved).toLowerCase();
    const type = ext === ".css" ? "text/css" : ext === ".js" ? "text/javascript" : "text/html";
    res.writeHead(200, {
      "Content-Type": `${type}; charset=utf-8`,
      "Cache-Control": "no-store"
    });
    res.end(data);
  });
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let body = "";
    req.on("data", (chunk) => {
      body += chunk;
      if (body.length > 1_000_000) {
        reject(new Error("Body too large"));
        req.destroy();
      }
    });
    req.on("end", () => resolve(body));
    req.on("error", reject);
  });
}

function tokenMatches(token) {
  const expected = Buffer.from(INGEST_TOKEN);
  const actual = Buffer.from(token || "");
  return expected.length === actual.length && crypto.timingSafeEqual(expected, actual);
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);

  if (req.method === "GET" && url.pathname === "/health") {
    sendJson(res, 200, {
      ok: true,
      service: "rooms-analytics-dashboard",
      uptimeSeconds: Math.round(process.uptime()),
      timestampUtc: new Date().toISOString().replace(/\.\d{3}Z$/, "Z")
    });
    return;
  }

  if (req.method === "GET" && (url.pathname === "/api/analytics" || url.pathname === "/analytics")) {
    logDebug("analytics read");
    sendJson(res, 200, readAnalytics());
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/ingest") {
    if (!tokenMatches(req.headers["x-rooms-token"])) {
      console.warn("[analytics] rejected ingest with invalid token");
      sendJson(res, 401, { ok: false, error: "Invalid ingest token" });
      return;
    }
    try {
      const payload = JSON.parse(await readBody(req));
      if (payload.TotalSessions !== undefined || payload.JoinHoursUtc !== undefined) {
        const liveAggregate = normalizeAggregate(payload);
        writeAnalytics(liveAggregate);
        console.log(`[analytics] replaced aggregate: sessions=${liveAggregate.TotalSessions} deaths=${liveAggregate.TotalDeaths}`);
        sendJson(res, 200, { ok: true, mode: "replace", totalSessions: liveAggregate.TotalSessions });
        return;
      }

      const merged = mergeAnalytics(readAnalytics(), payload);
      writeAnalytics(merged);
      console.log(`[analytics] merged session: sessions=${merged.TotalSessions} deaths=${merged.TotalDeaths}`);
      sendJson(res, 200, { ok: true, mode: "merge", totalSessions: merged.TotalSessions });
    } catch (error) {
      console.warn("[analytics] ingest failed:", error.message);
      sendJson(res, 400, { ok: false, error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/reset-live") {
    writeAnalytics(EMPTY_DATA);
    sendJson(res, 200, { ok: true });
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/demo-sample") {
    writeAnalytics(DEMO_DATA);
    sendJson(res, 200, { ok: true });
    return;
  }

  if (req.method === "GET") {
    serveStatic(req, res);
    return;
  }

  res.writeHead(405);
  res.end("Method not allowed");
});

ensureDataFile();
server.listen(PORT, () => {
  console.log(`[analytics] dashboard listening on port ${PORT}`);
  console.log(`[analytics] health endpoint: /health`);
  console.log(`[analytics] ingest endpoint: /api/ingest`);
});
