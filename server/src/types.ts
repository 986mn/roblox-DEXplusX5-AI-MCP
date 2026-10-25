// Shared types for the DEX++ MCP bridge.

export type JobOp =
  | "snapshot"
  | "describe"
  | "resolve"
  | "buildpath"
  | "select"
  | "tree"
  | "props"
  | "source"
  | "setprop"
  | "setprops"
  | "run"
  | "app"
  | "openscript"
  | "refresh"
  | "pending"
  | "takepending";

export interface Job {
  id: string;
  op: JobOp;
  args?: Record<string, unknown>;
  /** epoch ms when queued */
  queuedAt: number;
  /** epoch ms deadline */
  deadline: number;
}

export interface JobResult {
  id: string;
  ok: boolean;
  data?: unknown;
  error?: string;
}

export interface DexEvent {
  seq: number;
  at: number;
  type: string;
  reason?: string;
  time?: string;
  paths?: string[];
  data?: unknown;
  clientId?: string;
}

export interface ClientState {
  /** last successful poll */
  lastSeen: number | null;
  /** total polls served */
  polls: number;
  /** jobs delivered */
  jobs: number;
  clientId?: string;
  jobId?: string;
  placeId?: number;
}
