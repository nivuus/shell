# Testing Guide - Nivuus Shell

Nivuus is tested with [bats](https://github.com/bats-core/bats-core). Four
levels, four directories, one command each. This page replaces the three
progress reports that used to live next to it: a report describes a moment,
a documentation describes a product, and `git log` is the journal.

## Running the suites

```bash
./bin/test                 # everything
./bin/test --unit          # tests/unit/        — pure functions, grep-level rules
./bin/test --integration   # tests/integration/ — modules combined
./bin/test --e2e           # tests/e2e/         — install, uninstall, reversibility
./bin/test --performance   # tests/performance/ — the enforced startup budget
./bin/test --verbose       # show every assertion
```

A single file works too: `bats tests/unit/test_prompt.bats`.

The CI runs them through `tests/ci/bats-run.sh`, which is also the way to
reproduce a CI failure locally. Two families of tests are **excluded by
default** there: those tagged `docker` (they pull whole images) and `network`
(they leave for github.com). Set `NIVUUS_CI_DOCKER=1` or `NIVUUS_CI_NETWORK=1`
to include them.

`./bin/test-count` prints how many tests each suite holds, and
`./bin/test-count --check` fails when a suite shrinks. The floor lives in
`tests/baseline-counts.tsv`; raise it with `--update` in the same commit that
adds the tests. No count is copied into this page: a copied number is wrong
at the next commit.

Before any suite that reads `config/*.zsh`, run `rm -f config/*.zwc`: zsh
prefers stale bytecode over a newer source, and a test can pass against a
module you did not write.

## What each level proves

| Level | Directory | What it confronts |
|---|---|---|
| Unit | `tests/unit/` | One module, or one rule, in isolation. Includes the documentation rules: `test_readme_claims.bats`, `test_readme_badges.bats`, `test_docs_index.bats`, `test_manpage.bats`. |
| Integration | `tests/integration/` | Several modules loaded together: prompt with theme, AI dispatcher with a backend, autoupdate with the manifest. |
| End-to-end | `tests/e2e/` | The real thing: `install.sh` in a throwaway `$HOME`, then `nivuus uninstall`, then a fingerprint of `$HOME` that must come back identical (`test_reversibility.bats`). This is the central test of the project. |
| Performance | `tests/performance/` | The startup budget, enforced: `test_startup.bats` fails past `NIVUUS_STARTUP_BUDGET_MS` (300 by default). |

## Environment

Tests never touch your real home. Each one gets a temporary `$HOME` and
`NIVUUS_SHELL_DIR` pointing at the checkout:

```bash
export NIVUUS_SHELL_DIR="$(pwd)"
```

Shared helpers live in `tests/helpers/`:

| Helper | What it gives you |
|---|---|
| `assertions.zsh` | `assert_*` shorthands for zsh-level tests |
| `mocks.zsh` | fake `curl`, fake AI backend, fake package manager |
| `fingerprint.bash` | `fs_fingerprint`, the `$HOME` hash used by the reversibility test |
| `portable.bash` | POSIX shims so the same test runs on BusyBox and bash 3.2 |
| `release.bash`, `signing.bash` | build and sign a fake release locally |
| `legacy.bash` | reproduce a pre-3.1 git-based installation |

## Writing a new test

```bash
#!/usr/bin/env bats

setup() {
    ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
}

@test "ce que la propriété garantit, en français" {
    run "$ROOT/bin/nivuus" help
    [ "$status" -eq 0 ]
}
```

Conventions:

- Test names and comments are in French, like every existing test; commit
  messages and user-facing docs are in English.
- A test that needs Docker carries `# bats test_tags=docker` on the line
  above `@test`; one that needs the network carries `network`.
- Every new test raises the ratchet: run `./bin/test-count --update` and
  commit `tests/baseline-counts.tsv` in the same commit.

## CI

`.github/workflows/tests.yml` runs the four levels on every push, through the
composite action `.github/actions/setup-tests`. **No workflow installs a
package directly** — `tests/unit/test_ci_workflows.bats` forbids it; new
dependencies go into `tests/ci/install-deps.sh`.

`.github/workflows/matrix.yml` installs and uninstalls Nivuus on nine targets
(see `.github/matrix.json`) and checks the `$HOME` fingerprint each time. That
is what the *uninstall verified* badge reports.
