// Before `ultraman run` on a CI runner: a home of its own for Ultraman under RUNNER_TEMP (no vault, nothing of a
// developer's machine), the checked-out project trusted in it, the secret → origin yeses the workflow gave (`allow`),
// and the environment's machine-only values (`local-env`), masked in the log. Never prints a value.
import { existsSync, lstatSync, mkdirSync, readFileSync, realpathSync, renameSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';

// A workflow command's data: the runner turns %25, %0D and %0A back into %, CR and LF, and ends the command at a raw one.
const escape = text => String(text).replace(/%/g, '%25').replace(/\r/g, '%0D').replace(/\n/g, '%0A');
const fail = message => { console.log(`::error::${escape(message)}`); process.exit(2); };

const ENV_NAME = /^[a-z0-9]+(-[a-z0-9]+)*$/; // an environment id, as Ultraman makes them (slug)
const VAR_NAME = /^[A-Za-z_][\w.-]*$/; // a variable name Ultraman accepts in an environment
const SECRET_NAME = /^[A-Za-z_$][\w$.-]*$/;
const RESERVED = new Set(['__proto__', 'constructor', 'prototype']);
// A plain value: no quotes, block or flow syntax, tags, anchors or comments, so what is masked is what Ultraman reads.
const PLAIN_VALUE = /^(?!['"|>{[&*!%@`#])(?:(?! #)[^\r\n])*[^\s]$/;

const home = process.env.RUNNER_TEMP ? join(process.env.RUNNER_TEMP, 'ultraman-home') : fail('RUNNER_TEMP is not set: this runs inside GitHub Actions');

// The folder holding ultraman/pipelines, from here up (as the CLI finds it).
function projectRoot() {
  for (let dir = realpathSync.native(process.cwd()); ; dir = dirname(dir)) {
    if (existsSync(join(dir, 'ultraman', 'pipelines'))) return dir;
    if (dirname(dir) === dir) fail(`no ultraman/pipelines folder in ${process.cwd()} or above it: set working-directory`);
  }
}

// actions/checkout leaves the job's token in .git/config unless `persist-credentials: false`, and a pipeline may send
// a file of the project as a body: refuse to run next to it.
function noCheckoutToken(root) {
  for (let dir = root; ; dir = dirname(dir)) {
    const config = join(dir, '.git', 'config');
    if (existsSync(config) && /^\s*extraheader\s*=/im.test(readFileSync(config, 'utf8'))) {
      fail(`${config} holds the job's GitHub token (actions/checkout's persist-credentials). A pipeline could send that file: check out with persist-credentials: false`);
    }
    if (dirname(dir) === dir) return;
  }
}

// `name=origin` per line → { name: [origin] }. An origin is http(s), a host and a port only if it isn't the default:
// what Ultraman asks its yes for (a trailing slash or a path is refused, not guessed).
function allowed(text) {
  const secrets = Object.create(null);
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    const at = line.indexOf('=');
    const name = line.slice(0, at).trim(), origin = line.slice(at + 1).trim().toLowerCase();
    let parsed;
    try { parsed = new URL(origin); } catch { parsed = undefined; }
    const valid = at > 0 && SECRET_NAME.test(name) && !RESERVED.has(name) && parsed && /^https?:$/.test(parsed.protocol) && parsed.origin === origin;
    if (!valid) fail(`allow: "${line}" isn't name=origin with an http(s) origin (like api_key=https://api.example.com)`);
    (secrets[name] ??= []).push(origin);
  }
  return secrets;
}

// Nothing under ultraman/ is written through a link, a dangling one included (a checked-out link could point anywhere).
function noLink(root, ...parts) {
  let path = root;
  for (const part of parts) {
    path = join(path, part);
    if (lstatSync(path, { throwIfNoEntry: false })?.isSymbolicLink()) fail(`${path} is a link: nothing is written through one`);
  }
  return path;
}

// `name: value` lines in a strict subset of YAML, each value masked before anything could print it, then written back
// JSON-quoted: the file Ultraman reads holds exactly the masked values.
function localValues(text) {
  const lines = [];
  for (const raw of text.split('\n')) {
    const line = raw.replace(/\r$/, '');
    if (!line.trim() || line.trimStart().startsWith('#')) continue;
    const match = /^([^:\s]+):[ \t]+(.*?)[ \t]*$/.exec(line);
    if (!match || !VAR_NAME.test(match[1]) || !PLAIN_VALUE.test(match[2])) {
      fail(`local-env: a line isn't "name: plain value" (no quotes, multi-line values, comments or YAML syntax): ${match ? match[1] : 'line'} ...`);
    }
    console.log(`::add-mask::${escape(match[2])}`);
    lines.push(`${match[1]}: ${JSON.stringify(match[2])}`);
  }
  return lines.join('\n') + '\n';
}

function writeLocalEnv(root, env, text) {
  if (!ENV_NAME.test(env)) fail(env ? `env: "${env}" isn't an environment id (lower case, digits and dashes)` : 'local-env needs env: which environment those values belong to');
  const contents = localValues(text);
  mkdirSync(noLink(root, 'ultraman', 'local', 'envs'), { recursive: true });
  const target = noLink(root, 'ultraman', 'local', 'envs', `${env}.yaml`);
  const temp = noLink(root, 'ultraman', 'local', 'envs', `.${env}.yaml.${process.pid}`);
  writeFileSync(temp, contents, { flag: 'wx', mode: 0o600 });
  renameSync(temp, target); // replaces a file, never follows a link
}

const root = projectRoot();
noCheckoutToken(root);
mkdirSync(home, { recursive: true, mode: 0o700 });
const secrets = allowed(process.env.INPUT_ALLOW ?? '');
writeFileSync(join(home, 'trust.json'), JSON.stringify({ projects: { [root]: { trusted: true, secrets } } }, null, 2), { mode: 0o600 });
if (process.env.INPUT_LOCAL_ENV?.trim()) writeLocalEnv(root, process.env.INPUT_ENV ?? '', process.env.INPUT_LOCAL_ENV);
const pairs = Object.entries(secrets).flatMap(([name, origins]) => origins.map(origin => `${name} → ${origin}`));
console.log(escape(`Ultraman: ${root} trusted for this run; ${pairs.length ? `secrets allowed: ${pairs.join(', ')}` : 'no secret allowed to leave'}.`));
