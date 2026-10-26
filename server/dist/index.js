#!/usr/bin/env node
// MCP server entry point. Speaks MCP over stdio and serves HTTP on PORT.
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import { CallToolRequestSchema, ListToolsRequestSchema, } from "@modelcontextprotocol/sdk/types.js";
import { startHttp, PORT, setMcpHandler } from "./http.js";
import { queue } from "./queue.js";
import * as dex from "./bridge.js";
const TOOLS = [
    {
        name: "dex-snapshot",
        description: "Read the current DEX++ selection plus live state (dex version, place id, app list, decompiler modes). Use this first to see what the user is looking at.",
        inputSchema: { type: "object", properties: {}, additionalProperties: false },
    },
    {
        name: "dex-select",
        description: "Select one or more instances inside the DEX++ explorer by path. The user's DEX UI jumps to and highlights them. Set additive=true to extend the current selection instead of replacing it.",
        inputSchema: {
            type: "object",
            properties: {
                paths: {
                    oneOf: [
                        { type: "string", description: "single instance path" },
                        { type: "array", items: { type: "string" }, description: "multiple instance paths" },
                    ],
                },
                additive: { type: "boolean", description: "extend selection instead of replacing" },
            },
            required: ["paths"],
            additionalProperties: false,
        },
    },
    {
        name: "dex-tree",
        description: "Dump the instance hierarchy below a path as a nested tree. depth is 1-8, limit caps the total node count (1-4000).",
        inputSchema: {
            type: "object",
            properties: {
                path: { type: "string", description: "root path, default game" },
                depth: { type: "number", description: "1-8, default 2" },
                limit: { type: "number", description: "1-4000, default 300" },
            },
            additionalProperties: false,
        },
    },
    {
        name: "dex-props",
        description: "Read properties, Attributes and CollectionService tags of one instance. Values come back as strings.",
        inputSchema: {
            type: "object",
            properties: { path: { type: "string" } },
            required: ["path"],
            additionalProperties: false,
        },
    },
    {
        name: "dex-source",
        description: "Decompile a script using DEX's multi-backend pipeline. mode can be lua.expert/demo, Luaunveil, Konstant, AdvancedDecompiler, Shiny or Executor. Omit mode to use whatever the user picked in the DEX UI.",
        inputSchema: {
            type: "object",
            properties: {
                path: { type: "string" },
                mode: {
                    type: "string",
                    enum: ["lua.expert/demo", "Luaunveil", "Konstant", "AdvancedDecompiler", "Shiny", "Executor"],
                },
            },
            required: ["path"],
            additionalProperties: false,
        },
    },
    {
        name: "dex-setprop",
        description: "Set one property or Attribute on an instance. Values are strings and are coerced to the current type (number, boolean, Enum, Vector3, Color3). Prefix a value with lua: to evaluate an arbitrary Luau expression, e.g. lua:CFrame.new(0,50,0). DEX's property panel refreshes automatically.",
        inputSchema: {
            type: "object",
            properties: {
                path: { type: "string" },
                prop: { type: "string", description: "property or attribute name" },
                value: { type: "string" },
            },
            required: ["path", "prop", "value"],
            additionalProperties: false,
        },
    },
    {
        name: "dex-setprops",
        description: "Set several properties at once. Returns a per-property ok/fail report.",
        inputSchema: {
            type: "object",
            properties: {
                path: { type: "string" },
                props: {
                    type: "object",
                    additionalProperties: { type: "string" },
                    description: "map of property name to string value",
                },
            },
            required: ["path", "props"],
            additionalProperties: false,
        },
    },
    {
        name: "dex-execute",
        description: "Execute Luau in the Roblox client and optionally return the results. Use for anything the other tools cannot express. Keep code small and log via return values.",
        inputSchema: {
            type: "object",
            properties: {
                code: { type: "string", description: "Luau source" },
                wantReturn: { type: "boolean", description: "capture return values, default true" },
            },
            required: ["code"],
            additionalProperties: false,
        },
    },
    {
        name: "dex-app",
        description: "Open or close a DEX++ panel by name (Explorer, Properties, Notepad, Console, Save Instance, File Manager, spy, 3D Viewer, ...).",
        inputSchema: {
            type: "object",
            properties: {
                name: { type: "string" },
                open: { type: "boolean", description: "true to open, false to close, default true" },
            },
            required: ["name"],
            additionalProperties: false,
        },
    },
    {
        name: "dex-events",
        description: "Read the queue of objects the user explicitly sent from DEX (or recent selection changes). Use since=<lastSeq> for incremental reads. clear=true drains the buffer.",
        inputSchema: {
            type: "object",
            properties: {
                since: { type: "number", description: "only events with seq greater than this" },
                clear: { type: "boolean", description: "drain the buffer after reading" },
            },
            additionalProperties: false,
        },
    },
    {
        name: "dex-status",
        description: "Check whether the Roblox executor is connected and how healthy the bridge is.",
        inputSchema: { type: "object", properties: {}, additionalProperties: false },
    },
];
function text(value) {
    return {
        content: [
            {
                type: "text",
                text: typeof value === "string" ? value : JSON.stringify(value, null, 2),
            },
        ],
    };
}
function fail(message) {
    return {
        isError: true,
        content: [{ type: "text", text: message }],
    };
}
const server = new Server({ name: "roblox-dexplusx5-ai-mcp", version: "1.0.0" }, { capabilities: { tools: {} } });
server.setRequestHandler(ListToolsRequestSchema, async () => ({ tools: TOOLS }));
server.setRequestHandler(CallToolRequestSchema, async (req) => handleToolCall(req.params.name, (req.params.arguments ?? {})));
async function handleToolCall(name, args) {
    try {
        switch (name) {
            case "dex-snapshot":
                return text(await dex.snapshot());
            case "dex-select": {
                const paths = args.paths;
                return text(await dex.select(paths, Boolean(args.additive)));
            }
            case "dex-tree":
                return text(await dex.tree(args.path ?? "game", args.depth ?? 2, args.limit ?? 300));
            case "dex-props":
                return text(await dex.props(args.path));
            case "dex-source":
                return text(await dex.source(args.path, args.mode));
            case "dex-setprop":
                return text(await dex.setProp(args.path, args.prop, args.value));
            case "dex-setprops":
                return text(await dex.setProps(args.path, args.props));
            case "dex-execute":
                return text(await dex.run(args.code, args.wantReturn !== false));
            case "dex-app":
                return text(await dex.app(args.name, args.open !== false));
            case "dex-events": {
                const since = typeof args.since === "number" ? args.since : undefined;
                const events = queue.getEvents(since);
                const payload = {
                    lastSeq: queue.lastSeq,
                    count: events.length,
                    events,
                };
                if (args.clear === true)
                    queue.clearEvents();
                return text(payload);
            }
            case "dex-status":
                return text({
                    clientOnline: queue.isClientOnline(),
                    msSinceLastPoll: queue.sinceLastPoll(),
                    pendingJobs: queue.pendingCount(),
                    lastSeq: queue.lastSeq,
                    stats: queue.stats,
                });
            default:
                return fail(`unknown tool: ${name}`);
        }
    }
    catch (err) {
        return fail(err instanceof Error ? err.message : String(err));
    }
}
async function main() {
    // HTTP side (executor channel)
    let httpServer;
    try {
        httpServer = await startHttp(PORT);
        console.error(`[http] listening on 0.0.0.0:${PORT}`);
    }
    catch (err) {
        console.error(`[http] failed to bind ${PORT}: ${String(err)}`);
        console.error("[http] MCP will still start, but the executor cannot connect");
    }
    // MCP side (AI channel, local stdio)
    const transport = new StdioServerTransport();
    await server.connect(transport);
    console.error("[mcp] stdio transport ready");
    // Remote MCP (Streamable HTTP) — mount a second server instance on /mcp
    mountRemoteMcp(httpServer);
    console.error("[mcp] streamable HTTP ready at /mcp");
}
function mountRemoteMcp(_httpServer) {
    // Register the /mcp handler into the existing HTTP server.
    setMcpHandler(async (req, res) => {
        const remoteServer = new Server({ name: "roblox-dexplusx5-ai-mcp", version: "1.0.0" }, { capabilities: { tools: {} } });
        remoteServer.setRequestHandler(ListToolsRequestSchema, async () => ({ tools: TOOLS }));
        remoteServer.setRequestHandler(CallToolRequestSchema, async (r) => handleToolCall(r.params.name, (r.params.arguments ?? {})));
        const transport = new StreamableHTTPServerTransport({});
        await remoteServer.connect(transport);
        await transport.handleRequest(req, res);
    });
}
main().catch((err) => {
    console.error("[fatal]", err);
    process.exit(1);
});
