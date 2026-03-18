const http = require("http");
const fs = require("fs");
const fsp = require("fs/promises");
const path = require("path");

const ROOT_DIR = process.cwd();
const ENV_PATH = path.join(ROOT_DIR, ".env");

const MIME_TYPES = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "application/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".svg": "image/svg+xml",
  ".ico": "image/x-icon",
  ".txt": "text/plain; charset=utf-8"
};

function parseEnvFile(text) {
  const env = {};
  const lines = text.split(/\r?\n/);

  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;

    const separatorIndex = trimmed.indexOf("=");
    if (separatorIndex < 0) continue;

    const key = trimmed.slice(0, separatorIndex).trim();
    let value = trimmed.slice(separatorIndex + 1).trim();

    if (
      (value.startsWith('"') && value.endsWith('"'))
      || (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }

    env[key] = value;
  }

  return env;
}

function loadConfig() {
  let fileEnv = {};

  try {
    const raw = fs.readFileSync(ENV_PATH, "utf8");
    fileEnv = parseEnvFile(raw);
  } catch (error) {
    if (error.code !== "ENOENT") {
      console.error("Falha ao ler .env:", error);
    }
  }

  const merged = {
    ...fileEnv,
    ...Object.fromEntries(
      Object.entries(process.env).filter(([, value]) => typeof value === "string")
    )
  };

  return {
    host: String(merged.HOST || "127.0.0.1").trim() || "127.0.0.1",
    port: Math.max(1, Number(merged.PORT) || 4173),
    webhookUrl: String(merged.WEBHOOK_URL || "").trim(),
    authHeaderName: String(merged.WEBHOOK_AUTH_HEADER_NAME || "").trim(),
    authHeaderValue: String(merged.WEBHOOK_AUTH_HEADER_VALUE || "").trim(),
    timeoutMs: Math.max(5000, Number(merged.PROXY_TIMEOUT_MS) || 45000)
  };
}

function sendJson(res, statusCode, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(statusCode, {
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": Buffer.byteLength(body)
  });
  res.end(body);
}

function getSafeFilePath(urlPathname) {
  const decodedPath = decodeURIComponent(urlPathname);
  const targetPath = decodedPath === "/"
    ? "/index.html"
    : decodedPath;

  if (path.basename(targetPath).startsWith(".")) return null;

  const absolutePath = path.resolve(ROOT_DIR, "." + targetPath);
  if (!absolutePath.startsWith(ROOT_DIR)) return null;

  return absolutePath;
}

async function serveStaticFile(req, res, pathname) {
  const absolutePath = getSafeFilePath(pathname);
  if (!absolutePath) {
    sendJson(res, 403, { ok: false, message: "Acesso negado." });
    return;
  }

  try {
    const stats = await fsp.stat(absolutePath);
    if (!stats.isFile()) {
      sendJson(res, 404, { ok: false, message: "Arquivo nao encontrado." });
      return;
    }

    const ext = path.extname(absolutePath).toLowerCase();
    const contentType = MIME_TYPES[ext] || "application/octet-stream";
    res.writeHead(200, {
      "Content-Type": contentType,
      "Content-Length": stats.size
    });

    if (req.method === "HEAD") {
      res.end();
      return;
    }

    fs.createReadStream(absolutePath).pipe(res);
  } catch (error) {
    if (error.code === "ENOENT") {
      sendJson(res, 404, { ok: false, message: "Arquivo nao encontrado." });
      return;
    }

    console.error("Falha ao servir arquivo:", error);
    sendJson(res, 500, { ok: false, message: "Falha ao carregar a pagina." });
  }
}

async function handleProxySubmit(req, res) {
  const config = loadConfig();

  if (!config.webhookUrl) {
    sendJson(res, 200, {
      ok: true,
      mode: "local-only",
      message: "Servidor ativo, mas WEBHOOK_URL ainda nao foi configurado no arquivo .env."
    });
    return;
  }

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), config.timeoutMs);

  try {
    const headers = {
      "content-type": req.headers["content-type"] || "application/octet-stream"
    };

    if (req.headers["content-length"]) {
      headers["content-length"] = req.headers["content-length"];
    }

    if (config.authHeaderName && config.authHeaderValue) {
      headers[config.authHeaderName] = config.authHeaderValue;
    }

    const response = await fetch(config.webhookUrl, {
      method: "POST",
      headers,
      body: req,
      duplex: "half",
      signal: controller.signal
    });

    const responseText = await response.text();
    if (!response.ok) {
      sendJson(res, 502, {
        ok: false,
        mode: "webhook",
        status: response.status,
        message: responseText || "O webhook do n8n retornou erro."
      });
      return;
    }

    sendJson(res, 200, {
      ok: true,
      mode: "webhook",
      status: response.status,
      message: responseText || "Recebido pelo webhook do n8n."
    });
  } catch (error) {
    const timedOut = error?.name === "AbortError";
    sendJson(res, timedOut ? 504 : 500, {
      ok: false,
      mode: "proxy-error",
      message: timedOut
        ? "Tempo limite excedido ao comunicar com o webhook do n8n."
        : "Falha ao encaminhar o envio para o webhook do n8n."
    });
  } finally {
    clearTimeout(timeoutId);
  }
}

const server = http.createServer(async (req, res) => {
  const requestUrl = new URL(req.url, "http://127.0.0.1");
  const { pathname } = requestUrl;

  if (pathname === "/api/health" && req.method === "GET") {
    const config = loadConfig();
    sendJson(res, 200, {
      ok: true,
      host: config.host,
      port: config.port,
      webhookConfigured: Boolean(config.webhookUrl),
      configSource: ".env do servidor",
      timeoutMs: config.timeoutMs
    });
    return;
  }

  if (pathname === "/api/submit" && req.method === "POST") {
    await handleProxySubmit(req, res);
    return;
  }

  if (req.method === "GET" || req.method === "HEAD") {
    await serveStaticFile(req, res, pathname);
    return;
  }

  sendJson(res, 405, { ok: false, message: "Metodo nao suportado." });
});

const config = loadConfig();
server.listen(config.port, config.host, () => {
  console.log("Servidor Onix em http://" + config.host + ":" + config.port);
  console.log(
    config.webhookUrl
      ? "Webhook protegido carregado do .env."
      : "WEBHOOK_URL ainda nao configurado no .env."
  );
});
