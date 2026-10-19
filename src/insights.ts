import type { DutyCycleReading } from './pool.js';
import { clientProcessName, harnessDisplayName, type HarnessReport } from './harness.js';
import type { UsageWindow } from './usage.js';

/**
 * The window `GET /insights` answers over. Fixed rather than a parameter: the usage log keeps one 8 MiB
 * generation, so a window is only as long as what survived, and `logHorizon` reports how far back it reaches.
 */
export const INSIGHTS_WINDOW_HOURS = 24;

/** What the route read, gathered by the caller so the envelope itself is a pure function of it. */
export interface InsightsReadings {
  now: number;
  usage: UsageWindow;
  children: { alive: number; declared: number };
  resident: Array<{ server: string; megabytes: number }>;
  duty: DutyCycleReading;
  /** One report per detected harness, or undefined when there is no inventory to read. */
  reports: HarnessReport[] | undefined;
}

/**
 * Every number on the Insights board, and nothing else. Ported from the base of ControlInsights.swift.
 *
 * Each member is counted or it is absent, never zero. `resident` is null when no child has a measurement, a
 * harness whose calls cannot be attributed carries `calls: null` with the reason, and there is no saving figure,
 * because the router never ran the world one would be subtracted from.
 */
export function insightsEnvelope(readings: InsightsReadings): Record<string, unknown> {
  const { now, usage, children, resident, duty } = readings;
  const harnesses = harnessRows(readings.reports ?? [], usage);
  return {
    generatedAt: new Date(now).toISOString(),
    windowHours: usage.windowHours,
    windowStart: usage.windowStart,
    logHorizon: usage.horizon,
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
    // Null until P6 ports the session analyst. The member is still sent, so a board draws its empty state from a
    // fact the router stated rather than from a key it failed to find.
    analyst: null,
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
