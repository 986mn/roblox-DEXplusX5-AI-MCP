// High level DEX operations. Every call becomes a job for the Lua poller.
import { queue } from "./queue.js";
const DEFAULT_TIMEOUT = 30_000;
const EXECUTE_TIMEOUT = 60_000;
const DECOMPILE_TIMEOUT = 120_000;
export class DexError extends Error {
    op;
    constructor(message, op) {
        super(message);
        this.op = op;
        this.name = "DexError";
    }
}
function ensureOnline() {
    if (!queue.isClientOnline(8000)) {
        const since = queue.sinceLastPoll();
        throw new DexError(since === null
            ? "DEX client has never polled. Is dex_mcp_poller.lua running in the executor?"
            : `DEX client offline (last poll ${since}ms ago). Check BridgeURL and that the poller is still running.`, "connection");
    }
}
async function call(op, args = {}, timeout = DEFAULT_TIMEOUT) {
    ensureOnline();
    const res = await queue.submit(op, args, timeout);
    if (!res.ok)
        throw new DexError(res.error ?? "unknown error", op);
    return res.data;
}
// ---------- read ----------
export const snapshot = () => call("snapshot");
export const describe = (path) => call("describe", { path });
export const resolve = (path) => call("resolve", { path });
export const buildPath = (path) => call("buildpath", { path });
export const tree = (path = "game", depth = 2, limit = 300) => call("tree", { path, depth, limit });
export const props = (path) => call("props", { path });
export const source = (path, mode) => call("source", { path, mode }, DECOMPILE_TIMEOUT);
// ---------- write ----------
export const select = (paths, additive = false) => call("select", { paths, additive });
export const setProp = (path, prop, value) => call("setprop", { path, prop, value });
export const setProps = (path, propsObj) => call("setprops", { path, props: propsObj });
export const run = (code, wantReturn = true) => call("run", { code, wantReturn }, EXECUTE_TIMEOUT);
export const app = (name, open = true) => call("app", { name, open });
export const openScript = (path, mode) => call("openscript", { path, mode }, DECOMPILE_TIMEOUT);
export const refresh = () => call("refresh");
// ---------- queue handoff ----------
export const pending = () => call("pending");
export const takePending = () => call("takepending");
