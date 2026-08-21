# Troubleshooting

Start here, always:

```bash
nivuus doctor
```

It checks the tree, the `~/.zshrc` block, the manifest, the signing keyring
and the login shell, and prints the command to run for each problem it finds.
Everything below is a symptom `doctor` does not yet diagnose by itself. If you
land on one of them, that is a gap in `doctor` worth an issue.

## The shell starts slowly

The startup budget is enforced at 300 ms in CI, so a slow shell is almost
always something local. Measure first:

```bash
benchmark
```

Then turn off what you do not need, in `~/.zsh_local`:

```bash
export ENABLE_SYNTAX_HIGHLIGHTING=false
export ENABLE_PROJECT_DETECTION=false
export GIT_PROMPT_CACHE_TTL=5
```

## AI commands do nothing

They need a key, and they name the variable they want. Pick the provider
first:

```bash
export AI_BACKEND=gemini        # or openai, or anthropic
export GOOGLE_API_KEY='...'     # OPENAI_API_KEY / ANTHROPIC_API_KEY
```

Without a key, every AI feature degrades to a message; nothing else in the
shell depends on it. See [FEATURES.md](FEATURES.md).

## The git segment does not appear in the prompt

```bash
git status                       # are you actually in a repository?
export GIT_PROMPT_CACHE_TTL=5    # raise the cache if the repo is large
```

## Vim shortcuts do nothing

```bash
vim --version | grep clipboard   # no clipboard support compiled in?
vim.ssh myfile                   # falls back to internal registers
```

## An old installation blocks updates

Installations made by the pre-3.1 one-liner left a git repository in
`~/.nivuus-shell`. `nivuus doctor` reports it, and `nivuus migrate` moves it
aside — moved, never deleted, and the new path is printed.

## Nothing above helped

Open an issue with the output of `nivuus doctor`:
<https://github.com/maximeallanic/nivuus-shell/issues>
