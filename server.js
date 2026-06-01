const http = require("node:http");
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const net = require("node:net");
const tls = require("node:tls");

const PORT = Number(process.env.PORT || 8787);
const INGEST_TOKEN = process.env.ROOMS_ANALYTICS_TOKEN || "change-me-local-token";
const DEBUG = process.env.ROOMS_ANALYTICS_DEBUG === "1";
const ROOT = __dirname;
const PUBLIC_DIR = path.join(ROOT, "public");
const DATA_DIR = path.resolve(
  process.env.ROOMS_ANALYTICS_DATA_DIR ||
  process.env.RENDER_DISK_PATH ||
  path.join(ROOT, "data")
);
const DATA_FILE = path.join(DATA_DIR, "analytics.json");
const DATA_BACKUP_FILE = path.join(DATA_DIR, "analytics.backup.json");
const WIPE_CODE_RECIPIENT = "veltrixtheperson013@proton.me";
const WIPE_CODE_TTL_MS = 10 * 60 * 1000;
const WIPE_CODE_COOLDOWN_MS = 30 * 1000;
const WIPE_MAX_CODE_ATTEMPTS = 6;
const SMTP_TIMEOUT_MS = 15 * 1000;
const wipeSessions = new Map();
let lastWipeCodeSentAt = 0;

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
  AgeGroups: {},
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
  AgeGroups: { "13+": 16, Unverified: 10, "9+": 8, "16+": 6, "21+": 2 },
  AccountAgeGroups: {},
  Categories: {}
};

const MAP_FIELDS = [
  "JoinHoursUtc",
  "LeaveHoursUtc",
  "SessionsByDayUtc",
  "DeathCauses",
  "SectionsCrossed",
  "MiniSectionsCrossed",
  "Environments",
  "AgeGroups",
  "AccountAgeGroups",
  "Categories"
];

function ensureDataFile() {
  fs.mkdirSync(DATA_DIR, { recursive: true });
  if (!fs.existsSync(DATA_FILE)) {
    fs.writeFileSync(DATA_FILE, JSON.stringify(EMPTY_DATA, null, 2));
  }
}

function withDefaults(data) {
  const out = {
    ...EMPTY_DATA,
    ...(data && typeof data === "object" && !Array.isArray(data) ? data : {})
  };
  for (const field of MAP_FIELDS) {
    if (!out[field] || typeof out[field] !== "object" || Array.isArray(out[field])) {
      out[field] = {};
    }
  }
  return out;
}

function readAnalytics() {
  ensureDataFile();
  for (const file of [DATA_FILE, DATA_BACKUP_FILE]) {
    try {
      return withDefaults(JSON.parse(fs.readFileSync(file, "utf8")));
    } catch {
      // Try the next save file.
    }
  }
  return withDefaults();
}

function writeAnalytics(data) {
  fs.mkdirSync(DATA_DIR, { recursive: true });
  const body = JSON.stringify(withDefaults(data), null, 2);
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
    AgeGroups: mapCounts(input.AgeGroups || input.RobloxAgeGroups || input.UserAgeGroups, true),
    AccountAgeGroups: mapCounts(input.AccountAgeGroups, true),
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
  const ageGroup =
    incoming.ageGroup ||
    incoming.AgeGroup ||
    incoming.robloxAgeGroup ||
    incoming.RobloxAgeGroup ||
    incoming.userAgeGroup ||
    incoming.UserAgeGroup ||
    "Unknown";
  const accountAgeGroup = incoming.accountAgeGroup || incoming.AccountAgeGroup;
  merged.Environments = merged.Environments && typeof merged.Environments === "object" ? merged.Environments : {};
  merged.AgeGroups = merged.AgeGroups && typeof merged.AgeGroups === "object" ? merged.AgeGroups : {};
  merged.AccountAgeGroups = merged.AccountAgeGroups && typeof merged.AccountAgeGroups === "object" ? merged.AccountAgeGroups : {};
  addCount(merged.Environments, environment, sessionsIncoming);
  addRawCount(merged.AgeGroups, ageGroup, sessionsIncoming);
  if (accountAgeGroup) addRawCount(merged.AccountAgeGroups, accountAgeGroup, sessionsIncoming);

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

function readJsonBody(req) {
  return readBody(req).then((body) => {
    const trimmed = body.trim();
    return trimmed ? JSON.parse(trimmed) : {};
  });
}

function hashWipeCode(sessionId, code) {
  return crypto
    .createHash("sha256")
    .update(`${sessionId}:${String(code || "").trim()}`)
    .digest("hex");
}

function safeCompareText(a, b) {
  const left = Buffer.from(String(a || ""));
  const right = Buffer.from(String(b || ""));
  return left.length === right.length && crypto.timingSafeEqual(left, right);
}

function cleanupWipeSessions() {
  const now = Date.now();
  for (const [id, session] of wipeSessions.entries()) {
    if (!session || session.expiresAt <= now) {
      wipeSessions.delete(id);
    }
  }
}

function getWipeSession(sessionId) {
  cleanupWipeSessions();
  const session = wipeSessions.get(String(sessionId || ""));
  return session && session.expiresAt > Date.now() ? session : null;
}

function getClientIp(req) {
  const forwarded = String(req.headers["x-forwarded-for"] || "").split(",")[0].trim();
  return forwarded || req.socket.remoteAddress || "unknown";
}

function sanitizeHeader(value) {
  return String(value || "").replace(/[\r\n]+/g, " ").trim();
}

function extractEmailAddress(value) {
  const text = sanitizeHeader(value);
  const match = text.match(/<([^>]+)>/);
  return (match ? match[1] : text).trim();
}

function envFlag(name) {
  return /^(1|true|yes)$/i.test(String(process.env[name] || ""));
}

function getSmtpConfig() {
  const host = process.env.ROOMS_RESET_SMTP_HOST;
  const user = process.env.ROOMS_RESET_SMTP_USER;
  const pass = process.env.ROOMS_RESET_SMTP_PASS;
  const from = process.env.ROOMS_RESET_EMAIL_FROM || user;
  if (!host || !from) return null;

  const port = Number(process.env.ROOMS_RESET_SMTP_PORT || 587);
  return {
    host,
    port,
    user,
    pass,
    from,
    fromAddress: extractEmailAddress(from),
    secure: envFlag("ROOMS_RESET_SMTP_SECURE") || port === 465,
    startTls: process.env.ROOMS_RESET_SMTP_STARTTLS !== "0",
    helo: process.env.ROOMS_RESET_SMTP_HELO || "rooms-analytics.local",
    allowInvalidCert: envFlag("ROOMS_RESET_SMTP_ALLOW_INVALID_CERT")
  };
}

function connectSmtpSocket(config) {
  return new Promise((resolve, reject) => {
    let settled = false;
    const options = {
      host: config.host,
      port: config.port,
      servername: config.host,
      rejectUnauthorized: !config.allowInvalidCert
    };
    const socket = config.secure
      ? tls.connect(options, onConnect)
      : net.connect({ host: config.host, port: config.port }, onConnect);

    function finish(error) {
      if (settled) return;
      settled = true;
      socket.removeListener("error", finish);
      socket.removeListener("timeout", onTimeout);
      if (error) reject(error);
      else resolve(socket);
    }

    function onConnect() {
      socket.setEncoding("utf8");
      socket.setTimeout(SMTP_TIMEOUT_MS);
      finish();
    }

    function onTimeout() {
      finish(new Error("SMTP connection timed out"));
      socket.destroy();
    }

    socket.once("error", finish);
    socket.once("timeout", onTimeout);
  });
}

function upgradeSmtpSocket(socket, config) {
  return new Promise((resolve, reject) => {
    const secureSocket = tls.connect({
      socket,
      servername: config.host,
      rejectUnauthorized: !config.allowInvalidCert
    });

    secureSocket.once("secureConnect", () => {
      secureSocket.setEncoding("utf8");
      secureSocket.setTimeout(SMTP_TIMEOUT_MS);
      resolve(secureSocket);
    });
    secureSocket.once("error", reject);
  });
}

function createSmtpReader(socket) {
  let buffer = "";
  let pending = null;

  function parseResponse() {
    const match = buffer.match(/(?:^|\r?\n)\d{3} [^\r\n]*(?:\r?\n|$)/);
    if (!match) return null;
    const end = match.index + match[0].length;
    const response = buffer.slice(0, end).trim();
    buffer = buffer.slice(end);
    return response;
  }

  function parseCode(response) {
    const lines = response.split(/\r?\n/).filter(Boolean);
    const last = lines[lines.length - 1] || "";
    return Number(last.slice(0, 3));
  }

  function flush() {
    if (!pending) return;
    const response = parseResponse();
    if (!response) return;
    const { resolve, timer } = pending;
    pending = null;
    clearTimeout(timer);
    resolve(response);
  }

  function fail(error) {
    if (!pending) return;
    const { reject, timer } = pending;
    pending = null;
    clearTimeout(timer);
    reject(error);
  }

  function onData(chunk) {
    buffer += chunk;
    flush();
  }

  socket.on("data", onData);
  socket.on("error", fail);
  socket.on("timeout", () => fail(new Error("SMTP command timed out")));

  function waitResponse() {
    const ready = parseResponse();
    if (ready) return Promise.resolve(ready);
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        pending = null;
        reject(new Error("SMTP response timed out"));
      }, SMTP_TIMEOUT_MS);
      pending = { resolve, reject, timer };
    });
  }

  async function expect(codes) {
    const response = await waitResponse();
    const code = parseCode(response);
    if (!codes.includes(code)) {
      throw new Error(`SMTP returned ${code || "unknown"}: ${response}`);
    }
    return response;
  }

  async function command(line, codes) {
    socket.write(`${line}\r\n`);
    return expect(codes);
  }

  function detach() {
    socket.removeListener("data", onData);
    socket.removeListener("error", fail);
    socket.removeAllListeners("timeout");
    if (pending) {
      clearTimeout(pending.timer);
      pending = null;
    }
  }

  return { command, expect, detach };
}

async function sendSmtpMail({ to, subject, text }) {
  const config = getSmtpConfig();
  if (!config) {
    throw new Error("Email delivery is not configured. Set ROOMS_RESET_SMTP_HOST and ROOMS_RESET_EMAIL_FROM.");
  }

  let socket = await connectSmtpSocket(config);
  let smtp = createSmtpReader(socket);

  try {
    await smtp.expect([220]);
    await smtp.command(`EHLO ${config.helo}`, [250]);

    if (!config.secure && config.startTls) {
      await smtp.command("STARTTLS", [220]);
      smtp.detach();
      socket = await upgradeSmtpSocket(socket, config);
      smtp = createSmtpReader(socket);
      await smtp.command(`EHLO ${config.helo}`, [250]);
    }

    if (config.user && config.pass) {
      await smtp.command("AUTH LOGIN", [334]);
      await smtp.command(Buffer.from(config.user).toString("base64"), [334]);
      await smtp.command(Buffer.from(config.pass).toString("base64"), [235]);
    }

    await smtp.command(`MAIL FROM:<${config.fromAddress}>`, [250]);
    await smtp.command(`RCPT TO:<${to}>`, [250, 251]);
    await smtp.command("DATA", [354]);

    const message = [
      `From: ${sanitizeHeader(config.from)}`,
      `To: ${to}`,
      `Subject: ${sanitizeHeader(subject)}`,
      `Date: ${new Date().toUTCString()}`,
      `Message-ID: <${crypto.randomUUID()}@rooms-analytics.local>`,
      "MIME-Version: 1.0",
      "Content-Type: text/plain; charset=utf-8",
      "Content-Transfer-Encoding: 8bit",
      "",
      text
    ]
      .join("\r\n")
      .replace(/^\./gm, "..");

    socket.write(`${message}\r\n.\r\n`);
    await smtp.expect([250]);
    await smtp.command("QUIT", [221]).catch(() => {});
  } finally {
    smtp.detach();
    socket.end();
  }
}

async function sendWipeCodeEmail(code, req) {
  const expiresMinutes = Math.round(WIPE_CODE_TTL_MS / 60000);
  const subject = "Rooms Analytics wipe code";
  const text = [
    `Your Rooms Analytics wipe code is ${code}.`,
    "",
    `This code expires in ${expiresMinutes} minutes.`,
    `Requested at ${new Date().toISOString().replace(/\.\d{3}Z$/, "Z")}.`,
    `Request IP: ${getClientIp(req)}.`,
    "",
    "If you did not request a data wipe, ignore this email."
  ].join("\n");

  await sendSmtpMail({ to: WIPE_CODE_RECIPIENT, subject, text });
}

function generateMathProblems() {
  return Array.from({ length: 3 }, (_, index) => {
    const left = crypto.randomInt(2, 13);
    const right = crypto.randomInt(1, 10);
    const useSubtract = left > right && crypto.randomInt(0, 2) === 1;
    return {
      id: crypto.randomUUID(),
      prompt: useSubtract ? `${left} - ${right}` : `${left} + ${right}`,
      answer: useSubtract ? left - right : left + right,
      order: index
    };
  });
}

function publicMathProblems(problems) {
  return problems.map(({ id, prompt }) => ({ id, prompt }));
}

function validateMathAnswers(problems, answers) {
  if (!Array.isArray(answers) || answers.length !== problems.length) return false;
  const byId = new Map(answers.map((item) => [String(item.id || ""), Number(item.answer)]));
  return problems.every((problem) => byId.get(problem.id) === problem.answer);
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
    sendJson(res, 403, { ok: false, error: "Use the protected wipe flow." });
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/wipe/request-code") {
    cleanupWipeSessions();
    const now = Date.now();
    if (now - lastWipeCodeSentAt < WIPE_CODE_COOLDOWN_MS) {
      sendJson(res, 429, {
        ok: false,
        error: "A wipe code was requested recently. Wait a few seconds and try again."
      });
      return;
    }

    const sessionId = crypto.randomUUID();
    const code = String(crypto.randomInt(100000, 1000000));
    wipeSessions.set(sessionId, {
      id: sessionId,
      codeHash: hashWipeCode(sessionId, code),
      expiresAt: now + WIPE_CODE_TTL_MS,
      attempts: 0,
      stage: "code",
      mathProblems: null,
      requestedBy: getClientIp(req)
    });

    try {
      await sendWipeCodeEmail(code, req);
      lastWipeCodeSentAt = now;
      sendJson(res, 200, {
        ok: true,
        sessionId,
        email: WIPE_CODE_RECIPIENT,
        expiresInSeconds: Math.round(WIPE_CODE_TTL_MS / 1000)
      });
    } catch (error) {
      wipeSessions.delete(sessionId);
      console.warn("[analytics] wipe code email failed:", error.message);
      sendJson(res, 503, { ok: false, error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/wipe/verify-code") {
    try {
      const payload = await readJsonBody(req);
      const session = getWipeSession(payload.sessionId);
      if (!session) {
        sendJson(res, 404, { ok: false, error: "Wipe session expired. Request a new code." });
        return;
      }

      session.attempts += 1;
      if (session.attempts > WIPE_MAX_CODE_ATTEMPTS) {
        wipeSessions.delete(session.id);
        sendJson(res, 429, { ok: false, error: "Too many code attempts. Request a new code." });
        return;
      }

      const actualHash = hashWipeCode(session.id, payload.code);
      if (!safeCompareText(session.codeHash, actualHash)) {
        sendJson(res, 403, { ok: false, error: "Invalid wipe code." });
        return;
      }

      session.stage = "verified";
      sendJson(res, 200, { ok: true });
    } catch (error) {
      sendJson(res, 400, { ok: false, error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/wipe/confirm") {
    try {
      const payload = await readJsonBody(req);
      const session = getWipeSession(payload.sessionId);
      if (!session || session.stage !== "verified") {
        sendJson(res, 409, { ok: false, error: "Confirm the wipe code first." });
        return;
      }
      if (payload.confirm !== true) {
        sendJson(res, 400, { ok: false, error: "Confirmation is required." });
        return;
      }

      session.stage = "confirmed";
      sendJson(res, 200, { ok: true });
    } catch (error) {
      sendJson(res, 400, { ok: false, error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/wipe/clicks") {
    try {
      const payload = await readJsonBody(req);
      const session = getWipeSession(payload.sessionId);
      if (!session || session.stage !== "confirmed") {
        sendJson(res, 409, { ok: false, error: "Confirm the wipe first." });
        return;
      }
      if (Number(payload.clickCount) < 5) {
        sendJson(res, 400, { ok: false, error: "Five clicks are required." });
        return;
      }

      session.stage = "math";
      session.mathProblems = generateMathProblems();
      sendJson(res, 200, { ok: true, problems: publicMathProblems(session.mathProblems) });
    } catch (error) {
      sendJson(res, 400, { ok: false, error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/wipe/execute") {
    try {
      const payload = await readJsonBody(req);
      const session = getWipeSession(payload.sessionId);
      if (!session || session.stage !== "math" || !session.mathProblems) {
        sendJson(res, 409, { ok: false, error: "Finish the security checks first." });
        return;
      }
      if (!validateMathAnswers(session.mathProblems, payload.answers)) {
        session.mathProblems = generateMathProblems();
        sendJson(res, 403, {
          ok: false,
          error: "One or more answers were incorrect. Try the new problems.",
          problems: publicMathProblems(session.mathProblems)
        });
        return;
      }

      writeAnalytics(EMPTY_DATA);
      wipeSessions.delete(session.id);
      console.warn(`[analytics] data wiped after protected confirmation from ${session.requestedBy}`);
      sendJson(res, 200, { ok: true });
    } catch (error) {
      sendJson(res, 400, { ok: false, error: error.message });
    }
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
  console.log(`[analytics] data file: ${DATA_FILE}`);
  console.log(`[analytics] health endpoint: /health`);
  console.log(`[analytics] ingest endpoint: /api/ingest`);
});
