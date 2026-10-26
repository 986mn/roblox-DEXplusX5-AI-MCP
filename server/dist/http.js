// HTTP server: the channel between this MCP server and the Roblox executor.
import http from "node:http";
import { queue } from "./queue.js";
export const PORT = Number(process.env.PORT ?? 16384);
let mcpHandler = null;
export function setMcpHandler(h) {
    mcpHandler = h;
}
const MAX_BODY = 8 * 1024 * 1024;
function json(res, code, body) {
    const text = JSON.stringify(body);
    res.writeHead(code, {
        "Content-Type": "application/json; charset=utf-8",
        "Content-Length": Buffer.byteLength(text),
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "*",
        "Access-Control-Allow-Methods": "GET,POST,DELETE,OPTIONS",
    });
    res.end(text);
}
function noContent(res, code = 204) {
    res.writeHead(code, {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "*",
        "Access-Control-Allow-Methods": "GET,POST,DELETE,OPTIONS",
    });
    res.end();
}
async function readBody(req) {
    return new Promise((resolve, reject) => {
        let size = 0;
        const chunks = [];
        req.on("data", (c) => {
            size += c.length;
            if (size > MAX_BODY) {
                reject(new Error("body too large"));
                req.destroy();
                return;
            }
            chunks.push(c);
        });
        req.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
        req.on("error", reject);
    });
}
async function readJson(req) {
    try {
        const raw = await readBody(req);
        if (!raw)
            return null;
        return JSON.parse(raw);
    }
    catch {
        return null;
    }
}
/**
 * Routes:
 *   GET    /api/status        health + connection state
 *   GET    /api/log           poller log ring buffer (if pushed)
 *   GET    /dex/poll          Lua pulls a job (204 when empty)
 *   POST   /dex/result        Lua posts a result
 *   POST   /dex/event         Lua pushes a selection event
 *   GET    /dex/events        read events (?since=N)
 *   DELETE /dex/events        clear events
 *   GET    /dex/status        compact polller status (what Lua knows)
 *   POST   /dex/log           Lua pushes log lines
 *   GET    /                  tiny dashboard
 */
export function createHttpServer() {
    const serverLog = [];
    const pushLog = (line) => {
        serverLog.push(`${new Date().toISOString()} ${line}`);
        while (serverLog.length > 300)
            serverLog.shift();
    };
    const server = http.createServer(async (req, res) => {
        const url = new URL(req.url ?? "/", `http://${req.headers.host ?? "localhost"}`);
        const method = req.method ?? "GET";
        const path = url.pathname.replace(/\/+$/, "") || "/";
        if (path === "/mcp" && mcpHandler) {
            return await mcpHandler(req, res);
        }
        if (method === "OPTIONS")
            return noContent(res);
        try {
            // ---------- health ----------
            if (path === "/api/status" && method === "GET") {
                return json(res, 200, {
                    ok: true,
                    name: "roblox-dexplusx5-ai-mcp",
                    version: "1.0.0",
                    port: PORT,
                    uptime: Math.floor(process.uptime()),
                    clientOnline: queue.isClientOnline(),
                    msSinceLastPoll: queue.sinceLastPoll(),
                    pendingJobs: queue.pendingCount(),
                    lastSeq: queue.lastSeq,
                    stats: queue.stats,
                });
            }
            // ---------- queue ----------
            if (path === "/dex/poll" && method === "GET") {
                const job = queue.take();
                if (!job)
                    return noContent(res, 204);
                pushLog(`deliver ${job.op} ${job.id.slice(0, 8)}`);
                return json(res, 200, job);
            }
            if (path === "/dex/result" && method === "POST") {
                const body = await readJson(req);
                if (!body || typeof body.id !== "string") {
                    return json(res, 400, { ok: false, error: "invalid result body" });
                }
                const matched = queue.complete(body);
                pushLog(`result ${body.id.slice(0, 8)} ok=${body.ok} matched=${matched}`);
                return noContent(res, 204);
            }
            // ---------- events ----------
            if (path === "/dex/event" && method === "POST") {
                const body = await readJson(req);
                if (!body)
                    return json(res, 400, { ok: false, error: "invalid event body" });
                const evt = queue.pushEvent(body);
                pushLog(`event #${evt.seq} ${evt.type} paths=${evt.paths?.length ?? 0}`);
                return noContent(res, 204);
            }
            if (path === "/dex/events" && method === "GET") {
                const sinceRaw = url.searchParams.get("since");
                const since = sinceRaw === null ? undefined : Number(sinceRaw);
                const events = queue.getEvents(Number.isFinite(since) ? since : undefined);
                return json(res, 200, {
                    ok: true,
                    since: since ?? null,
                    lastSeq: queue.lastSeq,
                    count: events.length,
                    events,
                });
            }
            if (path === "/dex/events" && method === "DELETE") {
                const cleared = queue.clearEvents();
                return json(res, 200, { ok: true, cleared });
            }
            // ---------- diagnostics ----------
            if (path === "/api/log" && method === "GET") {
                return json(res, 200, { ok: true, lines: serverLog });
            }
            if (path === "/" && method === "GET") {
                const online = queue.isClientOnline();
                const html = `<!doctype html><html><head><meta charset="utf-8"><title>DEX++ MCP</title>
<style>body{font-family:system-ui,sans-serif;background:#1e1e1e;color:#ddd;padding:2rem;line-height:1.6}
code{background:#2d2d2d;padding:.15rem .4rem;border-radius:4px}
.ok{color:#7ee787}.bad{color:#ff7b72}</style></head><body>
<h2>roblox-DEXplusX5-AI-MCP</h2>
<p>Client: <b class="${online ? "ok" : "bad"}">${online ? "ONLINE" : "OFFLINE"}</b>
${queue.sinceLastPoll() !== null ? `(last poll ${queue.sinceLastPoll()}ms ago)` : "(never polled)"}</p>
<p>Pending jobs: <b>${queue.pendingCount()}</b> · Events: <b>${queue.lastSeq}</b> · Uptime: <b>${Math.floor(process.uptime())}s</b></p>
<p>In your executor:</p>
<pre><code>getgenv().BridgeURL = "${req.headers.host ?? "localhost:" + PORT}"</code></pre>
</body></html>`;
                res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
                return res.end(html);
            }
            return json(res, 404, { ok: false, error: `no route: ${method} ${path}` });
        }
        catch (err) {
            pushLog(`error ${path}: ${String(err)}`);
            return json(res, 500, { ok: false, error: String(err) });
        }
    });
    return server;
}
export function startHttp(port = PORT) {
    return new Promise((resolve, reject) => {
        const server = createHttpServer();
        server.once("error", reject);
        server.listen(port, "0.0.0.0", () => {
            resolve(server);
        });
    });
}
