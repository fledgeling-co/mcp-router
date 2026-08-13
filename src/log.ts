import { appendFileSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

let logFile: string | undefined;
let verbose = false;

export function configureLogging(file: string | undefined, isVerbose: boolean): void {
  logFile = file;
  verbose = isVerbose;
  if (logFile) mkdirSync(dirname(logFile), { recursive: true });
}

function emit(level: string, msg: string): void {
  const line = `${new Date().toISOString()} ${level.padEnd(5)} ${msg}`;
  // stdout is never used for logs: it stays clean in case this is ever run over stdio.
  process.stderr.write(line + '\n');
  if (logFile) {
    try {
      appendFileSync(logFile, line + '\n');
    } catch {
      /* logging must never take the router down */
    }
  }
}

export const log = {
  info: (msg: string) => emit('info', msg),
  warn: (msg: string) => emit('warn', msg),
  error: (msg: string) => emit('error', msg),
  debug: (msg: string) => {
    if (verbose) emit('debug', msg);
  },
};
