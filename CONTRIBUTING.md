# Contributing

## Run the tests first

```bash
./bin/test                 # everything
./bin/test --unit          # the fast loop
./bin/test-count --check   # the suite may grow, never shrink
```

`rm -f config/*.zwc` before any run that touches `config/`: zsh prefers stale
bytecode over a newer source, and a test can pass against a module you did not
write. See [doc/TESTING.md](doc/TESTING.md).

## The documentation is tested — this is the surprising part

A pull request that reads well can still fail the build. The README is
confronted to the repository on every push:

- every command it shows must exist (`tests/unit/test_readme_claims.bats`)
- every environment variable it names must be read by a module
- the startup figure must be the one a test enforces
- it must stay under 200 lines, in English, with anchored bullets
- `doc/README.md` must list every file in `doc/`, and only those
  (`tests/unit/test_docs_index.bats`)
- every badge must be backed by something that can fail
  (`tests/unit/test_readme_badges.bats`)
- the demo scenario must still run (`tests/e2e/test_demo_scenario.bats`)

None of these are style rules. Each one exists because the README once said
something that was not true.

## Conventions

- Commit messages: `feat(scope): …`, `fix(scope): …`, `docs(scope): …`, in English.
- `config/*.zsh` is ZSH. `lib/*.sh`, `install.sh` and `tests/ci/*.sh` are POSIX
  sh — they run under `dash`, BusyBox `ash` and bash 3.2.
- Test names and comments are in French, like every existing test.
- Every write into the user's home goes through `lib/manifest.sh`. No exception:
  `tests/e2e/test_reversibility.bats` is the central test of this project.
- Startup stays under 300 ms, and a test enforces it.
- No workflow installs a package directly; dependencies go through
  `tests/ci/install-deps.sh` and the `setup-tests` composite action.

## Before opening the pull request

```bash
./bin/test && ./bin/test-count --check
```

Architecture and module layout: [doc/CLAUDE.md](doc/CLAUDE.md).
