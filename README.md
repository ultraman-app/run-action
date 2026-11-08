# Ultraman run

Runs [Ultraman](https://ultraman-app.github.io/) pipelines, or a load test with its thresholds, in GitHub Actions.
It writes a JUnit report and the step fails like `ultraman run` does: exit 1 when a step or threshold fails, 2 when it
couldn't run (a usage error, a missing value, a secret nobody allowed to go where a pipeline sends it).

```yaml
- uses: actions/checkout@v4
  with:
    persist-credentials: false # the action refuses to run next to the job's token (see below)
- uses: ultraman-app/run-action@v1
  env:
    ULTRAMAN_SECRET_API_KEY: ${{ secrets.API_KEY }}
  with:
    args: --tag smoke
    env: staging
    allow: api_key=https://staging.example.com
```

## Inputs

| Input | What it does |
|---|---|
| `pipelines` | Pipelines to run, one per line. Leave it empty and use `args` for `--all`, `--tag X` or `--collection ID`. |
| `args` | More flags for `ultraman run`: `--all`, `--tag smoke`, `--parallel 4`, `--bail`… Split on spaces: a value with a space can't go here. |
| `load` | A load test to run instead (`ultraman run --load <test>`); its thresholds decide the exit code. |
| `env` | The environment (`ultraman/envs/<env>.yaml`). |
| `local-env` | The environment's machine-only values, as YAML `name: value` lines (see below). |
| `allow` | Which secret may go to which origin, one `name=origin` per line. |
| `yes` | `true` passes `--yes` (see the warning below). Default `false`. |
| `working-directory` | The folder that holds `ultraman/`. Default `.` |
| `junit` | The report's path, relative to `working-directory`. Default `ultraman-junit.xml`. |
| `version` | The Ultraman version to install, or `latest` (default). Pin it for repeatable runs. |

Outputs: `junit` (the report's path) and `exit-code` (0, 1 or 2).

## Secrets

In CI there is no vault. Each secret a pipeline uses as `{{secrets.name}}` comes from an `ULTRAMAN_SECRET_<NAME>`
variable (upper case; anything that isn't a letter or digit becomes `_`): map your GitHub secrets onto them in the step's
`env:`, only the ones the pipelines use. Ultraman hides their values in everything it prints and saves (`[secret:name]`),
and GitHub masks them in the log too.

## Where a secret may go: `allow`

On a developer's machine Ultraman asks before a secret goes to an origin for the first time. A runner has nobody to ask,
so the workflow says it beforehand: `allow` lists the origins each secret may reach (a scheme, a host and a port if it
isn't the default).

```yaml
allow: |
  api_key=https://staging.example.com
  admin_token=https://admin.staging.example.com
```

A pipeline that would send a secret anywhere else is refused before anything is sent (exit 2). So a pull request that
changes a pipeline, or an environment, to point a secret at another host can't send it there. An origin is written as
Ultraman asks for it: `https://host` or `http://host:port`, without a path or a trailing slash, and without the port when
it's the default one (`https://api.example.com`, not `https://api.example.com:443/`). Streams count as their http(s)
origin.

What `allow` can't cover: a pull request that changes the workflow file itself runs whatever it says. GitHub gives no
secrets to workflows from forks on `pull_request`; never check out a pull request's code under `pull_request_target`
or `workflow_run` with your secrets around.

### Files a request sends

Only files under `ultraman/files/` go out without a yes (the desktop app copies the files you pick there). A body,
multipart part, CA or stream message read from anywhere else in the repository needs a yes the first time, and a runner
has nobody to give it: the run stops (exit 2) before anything is sent. Keep the files your requests send in
`ultraman/files/`. `yes: true` lets them go too, with the same risk as below.

### The job's token

`actions/checkout` keeps the job's GitHub token in `.git/config` unless `persist-credentials: false`. Ultraman 0.6.2 and
later never send a file under `.git`, but the action stops (exit 2) when it finds that token next to the project anyway,
so a pinned older `version` or a later mistake can't send it: check out with `persist-credentials: false`. Other
credential files an earlier step leaves in the workspace are covered by the rule above (outside `ultraman/files/`, they
need a yes).

### `yes: true` is the risky way

`yes: true` lets every secret go wherever the pipelines say, with nothing asked. Anyone who can change a pipeline or an
environment in the branch being tested can then send your secrets to a server of theirs. Use it only for branches only
your team can push to, never on `pull_request` from forks, and prefer `allow`, which keeps the same protection the
desktop app gives.

## Values that live on a developer's machine: `local-env`

Some environment values aren't in git: they live in `ultraman/local/envs/<env>.yaml` on each machine. On a runner the
action writes that file from `local-env`, and masks each value in the log first. Each line is `name: value` with a
plain value: no quotes, comments, multi-line values or other YAML syntax (the action stops on one, so what it masks is
exactly what Ultraman reads). Anything that is a credential belongs in
`ULTRAMAN_SECRET_*` instead: those are hidden in the reports too, `local-env` values only in the log.

```yaml
with:
  env: staging
  local-env: |
    tenant: acme
    user: ${{ vars.TEST_USER }}
```

## The report

```yaml
- uses: ultraman-app/run-action@v1
  id: ultraman
  with:
    pipelines: create order
- uses: actions/upload-artifact@v4
  if: always()
  with:
    name: ultraman-junit
    path: ${{ steps.ultraman.outputs.junit }}
    retention-days: 7
```

Runs on `ubuntu-latest`, `macos-latest` and `windows-latest`. The action installs only the `ultraman` command, with the
Node it carries, from the release on ultraman-app.github.io, with its own copy of the installer (`install/`), which checks
the release's signed checksums. Your `ULTRAMAN_SECRET_*` variables are removed while it installs. It always runs the
pipelines in its own process (`--local`), never through an Ultraman already running on the runner.
