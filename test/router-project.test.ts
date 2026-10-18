import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { withCallerProject } from '../src/router.js';

const withProject = { type: 'object', properties: { project: { type: 'string' }, query: { type: 'string' } } };
const withoutProject = { type: 'object', properties: { query: { type: 'string' } } };

/** An identify() that records whether it was asked, so laziness is observable. */
function identifying(cwd: string | undefined) {
  const calls = { n: 0 };
  const identify = async () => {
    calls.n += 1;
    return { cwd };
  };
  return { identify, calls };
}

describe('withCallerProject', () => {
  test('injects the caller project for a tool that declares a project property', async () => {
    const { identify } = identifying('/Users/me/Dev/app');
    const args = await withCallerProject({ query: 'x' }, withProject, identify);
    assert.deepEqual(args, { query: 'x', project: '/Users/me/Dev/app' });
  });

  test('leaves the arguments alone for a tool that does not declare project, and never asks who called', async () => {
    const { identify, calls } = identifying('/Users/me/Dev/app');
    const args = await withCallerProject({ query: 'x' }, withoutProject, identify);
    assert.deepEqual(args, { query: 'x' });
    assert.equal(calls.n, 0);
  });

  test('leaves the arguments alone when the tool has no input schema at all', async () => {
    const { identify, calls } = identifying('/Users/me/Dev/app');
    assert.deepEqual(await withCallerProject({}, undefined, identify), {});
    assert.equal(calls.n, 0);
  });

  test("never overrides a project the caller set, and does not ask who called", async () => {
    const { identify, calls } = identifying('/Users/me/Dev/app');
    const args = await withCallerProject({ project: '/Users/me/Dev/other' }, withProject, identify);
    assert.deepEqual(args, { project: '/Users/me/Dev/other' });
    assert.equal(calls.n, 0);
  });

  test('no cwd means no injection, not an error', async () => {
    const { identify } = identifying(undefined);
    assert.deepEqual(await withCallerProject({ query: 'x' }, withProject, identify), { query: 'x' });
  });

  test('an identity lookup that fails means no injection, not a failed call', async () => {
    const identify = async () => {
      throw new Error('no socket');
    };
    assert.deepEqual(await withCallerProject({ query: 'x' }, withProject, identify), { query: 'x' });
  });

  test('does not mutate the caller-supplied object', async () => {
    const { identify } = identifying('/Users/me/Dev/app');
    const input = { query: 'x' };
    await withCallerProject(input, withProject, identify);
    assert.deepEqual(input, { query: 'x' });
  });
});
