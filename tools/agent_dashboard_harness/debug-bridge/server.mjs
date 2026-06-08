import express from "express";
import { createReadStream } from "node:fs";
import fs from "node:fs/promises";
import path from "node:path";
import readline from "node:readline";

const PORT = Number(process.env.RUSTDESK_DEBUG_BRIDGE_PORT || "17331");
const UPSTREAM = process.env.RUSTDESK_UPSTREAM_BRIDGE_URL || "http://127.0.0.1:17321";
const CODEX_HOME =
  process.env.CODEX_HOME ||
  (process.env.USERPROFILE
    ? path.join(process.env.USERPROFILE, ".codex")
    : path.join(process.cwd(), ".codex"));
const CODEX_HOME_SOURCE = process.env.CODEX_HOME
  ? "CODEX_HOME"
  : process.env.USERPROFILE
    ? "USERPROFILE"
    : "cwd";

const SESSION_INDEX = path.join(CODEX_HOME, "session_index.jsonl");
const SESSIONS_DIR = path.join(CODEX_HOME, "sessions");
const MAX_PAGE_SIZE = 100;
const SESSION_METADATA_SCAN_LINES = 24;
const SESSION_ID_PATTERN =
  /([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$/i;
const PROJECT_ID_ALIASES = new Map([["rustdesk", "rustdesk"]]);

let sessionFileIndexPromise = null;

const app = express();
app.use(express.json({ limit: "1mb" }));
app.use((_, res, next) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET,POST,PUT,DELETE,OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
  next();
});
app.options("*", (_, res) => res.status(204).end());

app.get("/health", (_, res) => {
  res.json({
    status: "ok",
    mode: "debug-bridge",
    codexHomeConfigured: Boolean(CODEX_HOME),
    codexHomeSource: CODEX_HOME_SOURCE,
    upstreamConfigured: Boolean(process.env.RUSTDESK_UPSTREAM_BRIDGE_URL),
  });
});

app.get("/agent/config", async (_, res) => {
  try {
    const upstream = await fetchJson("/agent/config");
    res.json(upstream);
  } catch {
    const projects = await buildFallbackProjects();
    res.json({
      enabled: true,
      port: PORT,
      command: "codex",
      require_confirmation: true,
      projects,
      errors: [],
    });
  }
});

app.get("/agent/sessions", async (_, res, next) => {
  try {
    const items = await loadSessionIndex();
    res.json(items);
  } catch (error) {
    next(error);
  }
});

app.get("/agent/sessions/:id", async (req, res, next) => {
  try {
    const pageSize = Math.min(
      MAX_PAGE_SIZE,
      Math.max(1, Number.parseInt(String(req.query.page_size ?? "200"), 10) || 200),
    );
    const detail = await loadSessionDetail(req.params.id, undefined, pageSize);
    res.json(detail);
  } catch (error) {
    next(error);
  }
});

app.get("/agent/sessions/:id/page", async (req, res, next) => {
  try {
    const cursor = Number.parseInt(String(req.query.cursor ?? ""), 10);
    const pageSize = Math.min(
      MAX_PAGE_SIZE,
      Math.max(1, Number.parseInt(String(req.query.page_size ?? "40"), 10) || 40),
    );
    const detail = await loadSessionDetail(
      req.params.id,
      Number.isFinite(cursor) ? cursor : undefined,
      pageSize,
    );
    res.json(detail);
  } catch (error) {
    next(error);
  }
});

for (const route of ["/agent/run", "/agent/confirm", "/agent/cancel", "/agent/skills", "/agent/skills/sync", "/agent/voice/transcribe"]) {
  app.post(route, async (req, res, next) => {
    try {
      if (route === "/agent/run") {
        logAgentRunRoute(req.body);
      }
      const response = await proxyJson("POST", route, req.body);
      res.status(response.status).json(response.body);
    } catch (error) {
      next(error);
    }
  });
}

app.delete("/agent/skills/:id", async (req, res, next) => {
  try {
    const response = await proxyJson("DELETE", `/agent/skills/${req.params.id}`);
    res.status(response.status).json(response.body);
  } catch (error) {
    next(error);
  }
});

app.get("/agent/skills", async (_, res, next) => {
  try {
    const response = await proxyJson("GET", "/agent/skills");
    res.status(response.status).json(response.body);
  } catch (error) {
    next(error);
  }
});

app.get("/agent/tasks/:id", async (req, res, next) => {
  try {
    const response = await proxyJson("GET", `/agent/tasks/${req.params.id}`);
    res.status(response.status).json(response.body);
  } catch (error) {
    next(error);
  }
});

app.use((error, _req, res, _next) => {
  const message = error instanceof Error ? error.message : String(error);
  res.status(500).json({ error: message });
});

app.listen(PORT, "127.0.0.1", () => {
  console.log(`[debug-bridge] listening on http://127.0.0.1:${PORT}`);
  console.log(
    `[debug-bridge] CODEX_HOME=<configured-codex-home> source=${CODEX_HOME_SOURCE}`,
  );
  console.log(
    `[debug-bridge] upstream=${
      process.env.RUSTDESK_UPSTREAM_BRIDGE_URL ? "<configured-upstream>" : UPSTREAM
    }`,
  );
});

function logAgentRunRoute(body) {
  const route = body?.route || parseEnvelopeRoute(body?.prompt);
  console.log(
    `[debug-bridge] /agent/run request_id=${String(body?.request_id || "")}` +
      ` project=${String(body?.project || "")}` +
      ` session=${String(body?.session || "")}` +
      ` resume_last=${String(body?.resume_last ?? "")}` +
      ` route_project=${String(route?.projectId || route?.project_id || "")}` +
      ` route_thread=${String(route?.threadMode || route?.thread_mode || "")}` +
      ` route_session=${String(route?.codexThreadId || route?.activeThreadId || "")}`,
  );
}

function parseEnvelopeRoute(prompt) {
  if (typeof prompt !== "string" || !prompt.trim().startsWith("{")) {
    return null;
  }
  try {
    return JSON.parse(prompt)?.route || null;
  } catch {
    return null;
  }
}

async function loadSessionIndex() {
  const raw = await fs.readFile(SESSION_INDEX, "utf8");
  const items = raw
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => JSON.parse(line))
    .map((item) => ({
      id: String(item.id || "").trim(),
      title: decodeTitle(String(item.thread_name || item.title || item.id || "").trim()),
      updatedAt: String(item.updated_at || ""),
      updated_at: String(item.updated_at || ""),
      projectId: canonicalProjectId(String(item.project_id || item.projectId || "").trim()),
      project_id: canonicalProjectId(String(item.project_id || item.projectId || "").trim()),
      projectPath: redactProjectPath(item.project_path || item.projectPath || ""),
      project_path: redactProjectPath(item.project_path || item.projectPath || ""),
    }))
    .filter((item) => item.id)
    .sort((a, b) => String(b.updated_at).localeCompare(String(a.updated_at)));
  await enrichSessionIndex(items);
  return items;
}

async function loadSessionDetail(sessionId, cursor, pageSize) {
  const sessions = await loadSessionIndex();
  const file = await findSessionFile(SESSIONS_DIR, sessionId);
  if (!file) {
    throw new Error(`Session file not found: ${sessionId}`);
  }
  const session = sessions.find((item) => item.id === sessionId);
  const fallbackMetadata = await readSessionProjectMetadata(file);
  const raw = await fs.readFile(file, "utf8");
  const lines = raw.split(/\r?\n/).filter((line) => line.trim());
  const end = Math.min(typeof cursor === "number" ? cursor : lines.length, lines.length);
  const start = Math.max(0, end - Math.max(1, pageSize));
  const chunk = lines.slice(start, end);
  const messages = [];
  const timeline = [];
  const rawEvents = [];
  for (const line of chunk) {
    const value = JSON.parse(line);
    if (rawEvents.length < 48) rawEvents.push(redactSessionEvent(value));
    if (value.type === "event_msg") {
      const summary = String(value?.payload?.message || "").trim();
      if (summary) {
        timeline.push({
          stage: String(value?.payload?.type || "event"),
          summary: truncate(summary),
          ts: Date.now(),
          raw: redactSessionEvent(value),
        });
      }
      continue;
    }
    if (value.type !== "response_item") continue;
    const payload = value.payload || {};
    const role = String(payload.role || payload?.message?.role || "assistant").toLowerCase();
    if (role === "developer" || role === "system") continue;
    const text = extractPayloadText(payload).trim();
    if (!text) continue;
    messages.push({
      role,
      text: redactSensitiveText(text),
      timestamp: String(value.timestamp || ""),
    });
  }
  return {
    id: session?.id || sessionId,
    title: session?.title || sessionId,
    updatedAt: session?.updated_at || "",
    updated_at: session?.updated_at || "",
    projectId:
      session?.project_id || session?.projectId || fallbackMetadata.projectId || "",
    project_id:
      session?.project_id || session?.projectId || fallbackMetadata.projectId || "",
    projectPath:
      redactProjectPath(
        session?.project_path || session?.projectPath || fallbackMetadata.projectPath || "",
      ),
    project_path:
      redactProjectPath(
        session?.project_path || session?.projectPath || fallbackMetadata.projectPath || "",
      ),
    messages,
    timeline,
    rawEvents: rawEvents,
    raw_events: rawEvents,
    nextCursor: start > 0 ? start : null,
    next_cursor: start > 0 ? start : null,
  };
}

function extractPayloadText(payload) {
  if (payload.message) {
    const nested = extractPayloadText(payload.message);
    if (nested.trim()) return nested;
  }
  if (Array.isArray(payload.content)) {
    return payload.content
      .map((item) => String(item?.text || "").trim())
      .filter(Boolean)
      .join("\n");
  }
  return String(payload.text || "");
}

async function findSessionFile(_dir, sessionId) {
  let index = await getSessionFileIndex();
  let found = lookupSessionFile(index, sessionId);
  if (found) {
    return found;
  }
  index = await getSessionFileIndex(true);
  found = lookupSessionFile(index, sessionId);
  return found ?? null;
}

async function enrichSessionIndex(items) {
  for (const item of items) {
    try {
      const sessionFile = await findSessionFile(SESSIONS_DIR, item.id);
      if (!sessionFile) {
        continue;
      }
      const metadata = await readSessionProjectMetadata(sessionFile);
      if (!metadata.projectId && !metadata.projectPath) {
        continue;
      }
      if (metadata.projectId) {
        item.projectId = metadata.projectId;
        item.project_id = metadata.projectId;
      }
      if (metadata.projectPath) {
        const publicPath = redactProjectPath(metadata.projectPath);
        item.projectPath = publicPath;
        item.project_path = publicPath;
      }
    } catch (error) {
      console.warn(
        `[debug-bridge] failed to enrich session ${item.id}: ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
    }
  }
}

async function readSessionProjectMetadata(sessionFile) {
  const stream = createReadStream(sessionFile, { encoding: "utf8" });
  const lines = readline.createInterface({
    input: stream,
    crlfDelay: Infinity,
  });
  let scanned = 0;
  try {
    for await (const rawLine of lines) {
      const line = String(rawLine || "").trim();
      if (!line) {
        continue;
      }
      scanned += 1;
      let value;
      try {
        value = JSON.parse(line);
      } catch {
        if (scanned >= SESSION_METADATA_SCAN_LINES) {
          break;
        }
        continue;
      }
      const metadata = metadataFromSessionEntry(value);
      if (metadata.projectId || metadata.projectPath) {
        return metadata;
      }
      if (scanned >= SESSION_METADATA_SCAN_LINES) {
        break;
      }
    }
  } finally {
    lines.close();
    stream.destroy();
  }
  return { projectId: "", projectPath: "" };
}

function metadataFromSessionEntry(value) {
  if (value?.type === "session_meta") {
    const cwd = String(value?.payload?.cwd || "").trim();
    if (cwd) {
      return metadataFromProjectPath(cwd);
    }
  }
  const projectPath = String(value?.project_path || value?.projectPath || "").trim();
  if (projectPath) {
    return metadataFromProjectPath(projectPath);
  }
  return { projectId: "", projectPath: "" };
}

function metadataFromProjectPath(rawPath) {
  const projectPath = normalizeProjectPath(rawPath);
  if (!projectPath) {
    return { projectId: "", projectPath: "" };
  }
  return {
    projectId: canonicalProjectId(projectIdFromPath(projectPath)),
    projectPath,
  };
}

function redactProjectPath(value) {
  return normalizeProjectPath(value) ? "<PROJECT_PATH>" : "";
}

function redactSessionEvent(value) {
  if (Array.isArray(value)) {
    return value.map((item) => redactSessionEvent(item));
  }
  if (!value || typeof value !== "object") {
    return typeof value === "string" ? redactSensitiveText(value) : value;
  }
  const out = {};
  for (const [key, nested] of Object.entries(value)) {
    const lower = key.toLowerCase();
    if (
      lower === "cwd" ||
      lower === "path" ||
      lower === "project_path" ||
      lower === "projectpath"
    ) {
      out[key] = redactProjectPath(nested);
      continue;
    }
    if (
      lower.includes("token") ||
      lower.includes("secret") ||
      lower.includes("password") ||
      lower.includes("authorization") ||
      lower.includes("cookie")
    ) {
      out[key] = "<redacted>";
      continue;
    }
    out[key] = redactSessionEvent(nested);
  }
  return out;
}

function redactSensitiveText(value) {
  return String(value || "")
    .replace(/Token:\s*\S+/gi, "Token: <redacted>")
    .replace(/[A-Za-z]:\\Users\\[^\\\s]+/g, "<USER_HOME>")
    .replace(/\\\\\?\\[A-Za-z]:\\/g, "<LOCAL_DRIVE>\\")
    .replace(/[A-Za-z]:\\[^\s"'`<>]+/g, "<LOCAL_PATH>");
}

function canonicalProjectId(projectId) {
  const trimmed = String(projectId || "").trim();
  if (!trimmed) {
    return "";
  }
  return PROJECT_ID_ALIASES.get(trimmed.toLowerCase()) || trimmed;
}

function normalizeProjectPath(rawPath) {
  return String(rawPath || "")
    .trim()
    .replace(/^\\\\\?\\/, "")
    .replace(/[\\/]+$/, "");
}

function projectIdFromPath(projectPath) {
  const normalized = normalizeProjectPath(projectPath);
  if (!normalized) {
    return "";
  }
  return canonicalProjectId(path.win32.basename(normalized) || "unknown");
}

async function fetchJson(route) {
  const response = await fetch(`${UPSTREAM}${route}`);
  const body = await response.json();
  if (!response.ok) {
    throw new Error(body?.error || `${response.status}`);
  }
  return body;
}

async function proxyJson(method, route, body) {
  const response = await fetch(`${UPSTREAM}${route}`, {
    method,
    headers: body ? { "Content-Type": "application/json" } : undefined,
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await response.text();
  const parsed = text ? JSON.parse(text) : {};
  return {
    status: response.status,
    body: parsed,
  };
}

function truncate(value) {
  return value.length > 12000 ? `${value.slice(0, 11997)}...` : value;
}

function decodeTitle(value) {
  return value || "Untitled session";
}

async function buildFallbackProjects() {
  const sessions = await loadSessionIndex();
  const seen = new Set();
  const projects = [];
  for (const session of sessions) {
    const projectPath = normalizeProjectPath(
      session.project_path || session.projectPath || "",
    );
    const projectId = canonicalProjectId(String(
      session.project_id || session.projectId || projectIdFromPath(projectPath),
    ).trim());
    if (!projectId || seen.has(projectId)) {
      continue;
    }
    seen.add(projectId);
    projects.push({
      id: projectId,
      path: redactProjectPath(projectPath),
      display_name: projectId,
      exists: Boolean(projectPath),
      executor: "codex",
      profile: "",
      session: "",
      resume_last: true,
      allow_workspace_write: false,
      thread_mode: "continue",
      tags: [],
      voice_language: "",
    });
  }
  if (projects.length > 0) {
    return projects;
  }
  return [
    {
      id: "rustdesk",
      path: redactProjectPath(
        process.env.RUSTDESK_DEBUG_BRIDGE_PROJECT_PATH || process.cwd(),
      ),
      display_name: "rustdesk",
      exists: true,
      executor: "codex",
      profile: "",
      session: "",
      resume_last: true,
      allow_workspace_write: false,
      thread_mode: "continue",
      tags: [],
      voice_language: "",
    },
  ];
}

async function getSessionFileIndex(forceRefresh = false) {
  if (!sessionFileIndexPromise || forceRefresh) {
    sessionFileIndexPromise = buildSessionFileIndex(SESSIONS_DIR);
  }
  return sessionFileIndexPromise;
}

async function buildSessionFileIndex(dir, index = new Map()) {
  const entries = await fs.readdir(dir, { withFileTypes: true });
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      await buildSessionFileIndex(full, index);
      continue;
    }
    if (!entry.name.endsWith(".jsonl")) {
      continue;
    }
    const stem = path.basename(entry.name, ".jsonl");
    index.set(stem, full);
    const match = stem.match(SESSION_ID_PATTERN);
    if (match?.[1]) {
      index.set(match[1], full);
    }
  }
  return index;
}

function lookupSessionFile(index, sessionId) {
  const exact = index.get(sessionId);
  if (exact) {
    return exact;
  }
  for (const [key, file] of index.entries()) {
    if (key.includes(sessionId)) {
      return file;
    }
  }
  return null;
}
