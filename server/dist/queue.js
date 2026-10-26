// Task queue: AI side enqueues, Lua side polls and returns results.
import { randomUUID } from "node:crypto";
const DEFAULT_TIMEOUT = 30_000;
const MAX_EVENTS = 500;
const MAX_RESULTS = 200;
export class JobQueue {
    jobs = [];
    waiters = new Map();
    results = new Map();
    events = [];
    seq = 0;
    stats = {
        delivered: 0,
        completed: 0,
        timeouts: 0,
        lastPollAt: 0,
        lastResultAt: 0,
    };
    // ---------- producer ----------
    submit(op, args = {}, timeoutMs = DEFAULT_TIMEOUT) {
        const id = randomUUID();
        const now = Date.now();
        const job = { id, op, args, queuedAt: now, deadline: now + timeoutMs };
        return new Promise((resolve, reject) => {
            const timer = setTimeout(() => {
                this.waiters.delete(id);
                this.results.delete(id);
                const idx = this.jobs.findIndex((j) => j.id === id);
                if (idx >= 0)
                    this.jobs.splice(idx, 1);
                this.stats.timeouts++;
                reject(new Error(`job ${op} timed out after ${timeoutMs}ms (is DEX++ running with dex_mcp_poller.lua?)`));
            }, timeoutMs);
            this.waiters.set(id, { resolve, reject, timer });
            this.jobs.push(job);
            // trim expired jobs
            const t = Date.now();
            this.jobs = this.jobs.filter((j) => j.deadline > t || this.waiters.has(j.id));
        });
    }
    // ---------- consumer (Lua) ----------
    /** Returns the next job for the Lua client, or null if queue is empty. */
    take() {
        const now = Date.now();
        while (this.jobs.length > 0) {
            const job = this.jobs.shift();
            if (job.deadline <= now)
                continue; // expired, skip
            if (!this.waiters.has(job.id))
                continue; // abandoned
            this.stats.delivered++;
            this.stats.lastPollAt = now;
            return job;
        }
        this.stats.lastPollAt = now;
        return null;
    }
    /** Lua posts a result back. */
    complete(result) {
        this.stats.lastResultAt = Date.now();
        const waiter = this.waiters.get(result.id);
        if (!waiter) {
            // late result, keep briefly for diagnostics
            this.results.set(result.id, result);
            while (this.results.size > MAX_RESULTS) {
                const first = this.results.keys().next().value;
                if (first === undefined)
                    break;
                this.results.delete(first);
            }
            return false;
        }
        clearTimeout(waiter.timer);
        this.waiters.delete(result.id);
        this.stats.completed++;
        waiter.resolve(result);
        return true;
    }
    // ---------- events ----------
    pushEvent(evt) {
        this.seq++;
        const full = { ...evt, seq: this.seq, at: Date.now() };
        this.events.push(full);
        while (this.events.length > MAX_EVENTS)
            this.events.shift();
        return full;
    }
    /** Events after `sinceSeq` (exclusive). */
    getEvents(sinceSeq) {
        if (sinceSeq === undefined)
            return [...this.events];
        return this.events.filter((e) => e.seq > sinceSeq);
    }
    clearEvents() {
        const n = this.events.length;
        this.events = [];
        return n;
    }
    get lastSeq() {
        return this.seq;
    }
    // ---------- status ----------
    pendingCount() {
        return this.jobs.filter((j) => this.waiters.has(j.id)).length;
    }
    /** Milliseconds since the Lua side last polled. */
    sinceLastPoll() {
        return this.stats.lastPollAt ? Date.now() - this.stats.lastPollAt : null;
    }
    /** Lua is considered online if it polled within `windowMs`. */
    isClientOnline(windowMs = 5000) {
        const d = this.sinceLastPoll();
        return d !== null && d <= windowMs;
    }
}
export const queue = new JobQueue();
