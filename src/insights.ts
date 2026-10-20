import type { DutyCycleReading } from './pool.js';
import { clientProcessName, harnessDisplayName, type HarnessReport } from './harness.js';
import { RETAIN_DAYS, type UsageRetention, type UsageWindow } from './usage.js';

/**
 * The windows `GET /insights?window=` answers over, by the name a client sends. The longest is the retention window
 * itself, so no window can ask for history the router has promised not to keep.
 */
export const INSIGHTS_WINDOWS = {
  '24h': 24,
  '7d': RETAIN_DAYS * 24,
} as const;

/** What a request with no `window` parameter gets. Existing clients were built against 24 hours and keep getting it. */
export const DEFAULT_INSIGHTS_WINDOW = '24h';

/**
 * The window hours a `window` parameter names, or undefined when it names none. An absent parameter is the default,
 * not an error. Only a value the router does not know is refused: a silent fallback would hand a client a shorter
 * window than it asked for and label it the one it asked for.
 */
export function insightsWindowHours(raw: string | null): number | undefined {
  const name = raw ?? DEFAULT_INSIGHTS_WINDOW;
  return Object.prototype.hasOwnProperty.call(INSIGHTS_WINDOWS, name)
    ? INSIGHTS_WINDOWS[name as keyof typeof INSIGHTS_WINDOWS]
    : undefined;
}

/** What the route read, gathered by the caller so the envelope itself is a pure function of it. */
export interface InsightsReadings {
  now: number;
  usage: UsageWindow;
  /** What retention has removed and what it keeps, so the board can say what the history is made of. */
  retention: UsageRetention;
  children: { alive: number; declared: number };
  resident: Array<{ server: string; megabytes: number }>;
  duty: DutyCycleReading;
  /** One report per detected harness, or undefined when there is no inventory to read. */
  reports: HarnessReport[] | undefined;
  /** The analyst's envelope, or null when the router has no analyst. Built by the caller from the analyst port. */
  analyst: Record<string, unknown> | null;
}

/**
 * Every number on the Insights board, and nothing else. Ported from the base of ControlInsights.swift.
 *
 * Each member is counted or it is absent, never zero. `resident` is null when no child has a measurement, a
 * harness whose calls cannot be attributed carries `calls: null` with the reason, and there is no saving figure,
 * because the router never ran the world one would be subtracted from. An hour the router did not observe in full
 * carries `calls: null` too, and `windowComplete` says whether the window as a whole was observed.
 */
export function insightsEnvelope(readings: InsightsReadings): Record<string, unknown> {
  const { now, usage, children, resident, duty } = readings;
  const harnesses = harnessRows(readings.reports ?? [], usage);
  return {
    generatedAt: new Date(now).toISOString(),
    windowHours: usage.windowHours,
    windowStart: usage.windowStart,
    logHorizon: usage.horizon,
    // When the router began counting. A window that starts before this is not whole, and `windowComplete` is false.
    observedSince: usage.observedSince,
    windowComplete: usage.complete,
    retention: readings.retention,
    children: { alive: children.alive, declared: children.declared },
    calls: {
      total: usage.totalCalls,
      failed: usage.failedCalls,
      unreadableLines: usage.unreadableLines,
    },
    resident: resident.length
      ? {
          megabytes: resident.reduce((sum, reading) => sum + reading.megabytes, 0),
          children: resident.length,
        }
      : null,
    callsByHarness: harnesses.rows,
    // What the bars do not claim, so the bars and the headline total reconcile instead of quietly disagreeing.
    otherCalls: Math.max(0, usage.totalCalls - harnesses.attributed),
    dutyCycle: {
      uptimeSeconds: Math.round(duty.uptimeMilliseconds / 1000),
      servers: duty.servers.map((server) => ({
        server: server.name,
        aliveSeconds: Math.round(server.aliveMilliseconds / 1000),
      })),
    },
    callsPerHour: usage.hours.map((hour) => ({ hourStart: hour.start, calls: hour.calls })),
    // Null when the router has no analyst. The member is still sent, so a board draws its empty state from a fact the
    // router stated rather than from a key it failed to find.
    analyst: readings.analyst,
  };
}

/**
 * One bar per detected harness, including the ones at zero, because a zero row is the finding: a harness at zero
 * is still calling its own servers rather than this endpoint.
 *
 * A row that cannot be counted carries null, never zero. The router sees a process name, and a harness whose name
 * is shared, or unknown, has no count to give. A zero there would be a fabricated finding.
 */
function harnessRows(
  reports: HarnessReport[],
  usage: UsageWindow
): { rows: Array<Record<string, unknown>>; attributed: number } {
  let attributed = 0;
  const rows = reports.map((report) => {
    const naming = clientProcessName(report.client);
    const displayName = harnessDisplayName(report.client);
    if (naming.kind === 'measured') {
      const calls = usage.callers.get(naming.name) ?? 0;
      attributed += calls;
      return { harness: report.client, displayName, calls, reason: null };
    }
    const reason =
      naming.kind === 'ambiguous'
        ? `calls arrive as ${naming.name} — ${naming.reason}`
        : "nothing has established what this harness's calls look like to the router";
    return { harness: report.client, displayName, calls: null, reason };
  });
  return { rows, attributed };
}
