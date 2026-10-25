// High level DEX operations. Every call becomes a job for the Lua poller.
import { queue } from "./queue.js";
import type { JobOp, JobResult } from "./types.js";

const DEFAULT_TIMEOUT = 30_000;
const EXECUTE_TIMEOUT = 60_000;
const DECOMPILE_TIMEOUT = 120_000;

export class DexError extends Error {
  constructor(message: string, readonly op: string) {
    super(message);
    this.name = "DexError";
  }
}

function ensureOnline(): void {
  if (!queue.isClientOnline(8000)) {
    const since = queue.sinceLastPoll();
    throw new DexError(
      since === null
        ? "DEX client has never polled. Is dex_mcp_poller.lua running in the executor?"
        : `DEX client offline (last poll ${since}ms ago). Check BridgeURL and that the poller is still running.`,
      "connection",
    );
  }
}

async function call<T = unknown>(
  op: JobOp,
  args: Record<string, unknown> = {},
  timeout = DEFAULT_TIMEOUT,
): Promise<T> {
  ensureOnline();
  const res: JobResult = await queue.submit(op, args, timeout);
  if (!res.ok) throw new DexError(res.error ?? "unknown error", op);
  return res.data as T;
}

// ---------- read ----------
export const snapshot = () => call<Record<string, unknown>>("snapshot");
export const describe = (path: string) => call("describe", { path });
export const resolve = (path: string) => call("resolve", { path });
export const buildPath = (path: string) => call("buildpath", { path });

export const tree = (path = "game", depth = 2, limit = 300) =>
  call("tree", { path, depth, limit });

export const props = (path: string) => call("props", { path });

export const source = (path: string, mode?: string) =>
  call("source", { path, mode }, DECOMPILE_TIMEOUT);

// ---------- write ----------
export const select = (paths: string[] | string, additive = false) =>
  call("select", { paths, additive });

export const setProp = (path: string, prop: string, value: string) =>
  call("setprop", { path, prop, value });

export const setProps = (path: string, propsObj: Record<string, string>) =>
  call("setprops", { path, props: propsObj });

export const run = (code: string, wantReturn = true) =>
  call("run", { code, wantReturn }, EXECUTE_TIMEOUT);

export const app = (name: string, open = true) => call("app", { name, open });

export const openScript = (path: string, mode?: string) =>
  call("openscript", { path, mode }, DECOMPILE_TIMEOUT);

export const refresh = () => call("refresh");

// ---------- queue handoff ----------
export const pending = () => call("pending");
export const takePending = () => call("takepending");
