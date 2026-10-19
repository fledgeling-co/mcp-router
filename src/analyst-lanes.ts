/**
 * Which CLI judges, with which model; how often the analyst is meant to run; and the settings that choose between them.
 * Ported from AnalystLane.swift, AnalystSettings.swift and the cadence half of AnalystLane.swift.
 *
 * The lane set is closed. The analyst costs nothing and needs no key because it runs through a binary the user is
 * already signed into. A lane the user could type would be a binary the router spawns without knowing what it is.
 */

export const ANALYST_LANES = ['claude', 'cursor', 'grok', 'codex', 'gemini'] as const;
export type AnalystLane = (typeof ANALYST_LANES)[number];

interface LaneSpec {
  /** Resolved on PATH at run time, never as an absolute path. */
  binary: string;
  model: string;
  /** The design's own spelling, as the Insights card shows it. */
  label: string;
  /** The whole argument vector, prompt included, with no shell anywhere. */
  arguments: (prompt: string) => string[];
}

/**
 * Each lane's effort is pinned rather than inherited: a lane running at its config default is not the lane that was
 * chosen, and the run would report a model it did not use.
 */
const LANES: Record<AnalystLane, LaneSpec> = {
  claude: {
    binary: 'claude',
    model: 'claude-haiku-4-5',
    label: 'Claude CLI · haiku',
    arguments: (prompt) => ['--model', 'claude-haiku-4-5', '-p', prompt],
  },
  cursor: {
    binary: 'cursor-agent',
    model: 'composer',
    label: 'Cursor CLI · composer',
    // No --force: that flag approves every tool call without asking. The prompt carries the user's own shell history,
    // so a command written into it must not be able to run. Print mode without it answers with text and nothing else.
    arguments: (prompt) => ['-p', '--model', 'composer', prompt],
  },
  grok: {
    binary: 'grok',
    model: 'grok-4.6',
    label: 'Grok CLI · grok-4.6 medium',
    arguments: (prompt) => ['-m', 'grok-4.6', '--effort', 'medium', '-p', prompt],
  },
  codex: {
    binary: 'codex',
    model: 'gpt-5.6-luna',
    label: 'Codex CLI · gpt-5.6-luna low',
    arguments: (prompt) => [
      'exec',
      '-m',
      'gpt-5.6-luna',
      '-c',
      'model_reasoning_effort="low"',
      '-s',
      'read-only',
      prompt,
    ],
  },
  gemini: {
    binary: 'agy',
    model: 'gemini-3.7-flash-high',
    label: 'Antigravity · gemini-3.7-flash-high',
    arguments: (prompt) => ['--new-project', '--model', 'gemini-3.7-flash-high', '-p', prompt],
  },
};

export const isAnalystLane = (value: unknown): value is AnalystLane =>
  typeof value === 'string' && (ANALYST_LANES as readonly string[]).includes(value);

export const laneBinary = (lane: AnalystLane): string => LANES[lane].binary;
export const laneModel = (lane: AnalystLane): string => LANES[lane].model;
export const laneLabel = (lane: AnalystLane): string => LANES[lane].label;
export const laneArguments = (lane: AnalystLane, prompt: string): string[] => LANES[lane].arguments(prompt);

export const ANALYST_CADENCES = ['manual', 'sixHourly', 'twelveHourly', 'daily'] as const;
export type AnalystCadence = (typeof ANALYST_CADENCES)[number];

const HOUR = 3_600_000;
const CADENCES: Record<AnalystCadence, { label: string; intervalMilliseconds: number | null }> = {
  manual: { label: 'Only when I ask', intervalMilliseconds: null },
  sixHourly: { label: 'Every 6 hours', intervalMilliseconds: 6 * HOUR },
  twelveHourly: { label: 'Every 12 hours', intervalMilliseconds: 12 * HOUR },
  daily: { label: 'Once a day', intervalMilliseconds: 24 * HOUR },
};

export const cadenceLabel = (cadence: AnalystCadence): string => CADENCES[cadence].label;

/**
 * When a run would next be due, or null when there is no cadence or no run to count from. Derived, so the readout is
 * computed from the last run rather than asserted. The router does not act on it: the wire carries `scheduled: false`.
 */
export function cadenceNextRunAt(cadence: AnalystCadence, lastRunMilliseconds: number | null): number | null {
  const interval = CADENCES[cadence].intervalMilliseconds;
  if (interval === null || lastRunMilliseconds === null) return null;
  return lastRunMilliseconds + interval;
}

export interface AnalystSettings {
  primary: AnalystLane;
  /** Optional: a ladder with one rung is a coherent choice. */
  fallback: AnalystLane | null;
  cadence: AnalystCadence;
}

export const DEFAULT_SETTINGS: AnalystSettings = { primary: 'claude', fallback: 'grok', cadence: 'sixHourly' };

/**
 * The rungs in the order they are tried. A fallback equal to the primary collapses rather than being refused:
 * the second rung is the first one again, and running the same failing binary twice would report two attempts
 * where the machine made one.
 */
export function ladderOf(settings: AnalystSettings): AnalystLane[] {
  if (settings.fallback === null || settings.fallback === settings.primary) return [settings.primary];
  return [settings.primary, settings.fallback];
}

/** Why a settings change was refused, with enough in it for a 422 to name the member to fix. */
export class AnalystSettingsRefusal extends Error {
  readonly member: string;
  readonly value: string;

  constructor(member: string, value: string) {
    const accepted = (member === 'cadence' ? ANALYST_CADENCES : ANALYST_LANES).join(', ');
    super(`${member}: "${value}" is not one of ${accepted}`);
    this.name = 'AnalystSettingsRefusal';
    this.member = member;
    this.value = value;
  }
}

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

function laneFrom(raw: unknown, member: string): AnalystLane {
  const text = typeof raw === 'string' ? raw : '';
  if (!isAnalystLane(text)) throw new AnalystSettingsRefusal(member, text);
  return text;
}

/**
 * Apply a settings object to `current`. An absent member keeps its value, which is what makes PATCH a patch. A member
 * that is present and unrecognised is refused rather than dropped. An explicit null fallback clears the fallback.
 */
export function applySettings(patch: unknown, current: AnalystSettings): AnalystSettings {
  const body = isRecord(patch) ? patch : {};
  const next: AnalystSettings = { ...current };
  if ('primary' in body) next.primary = laneFrom(body.primary, 'primary');
  if ('fallback' in body) next.fallback = body.fallback === null ? null : laneFrom(body.fallback, 'fallback');
  if ('cadence' in body) {
    const text = typeof body.cadence === 'string' ? body.cadence : '';
    if (!(ANALYST_CADENCES as readonly string[]).includes(text)) throw new AnalystSettingsRefusal('cadence', text);
    next.cadence = text as AnalystCadence;
  }
  return next;
}

/** The stored form, read back by `parseSettings`. */
export function encodeSettings(settings: AnalystSettings): Record<string, string | null> {
  return { primary: settings.primary, fallback: settings.fallback, cadence: settings.cadence };
}

/**
 * Read stored settings, falling back to the defaults for anything the file does not hold. Lenient where
 * `applySettings` is strict, because a stored file may have been written by an older build, and refusing it would leave
 * the analyst unrunnable with no route back.
 */
export function parseSettings(stored: unknown): AnalystSettings {
  try {
    return applySettings(stored, DEFAULT_SETTINGS);
  } catch {
    return { ...DEFAULT_SETTINGS };
  }
}
