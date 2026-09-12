#!/usr/bin/env bats

# Each module guards against being sourced twice with a NIVUUS_*_LOADED flag.
# Exporting one of those flags turns a per-shell guard into a per-process-tree
# one: `exec zsh`, or any nested zsh, inherits it and silently skips the whole
# module -- the shell comes up looking normal, minus the feature.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "no module exports its load guard" {
    run grep -rn "^[[:space:]]*export NIVUUS_[A-Z_]*_LOADED" "$REPO_ROOT/config"
    [ "$status" -ne 0 ]
}

@test "a nested zsh does not inherit the AI suggestions load guard" {
    # Scrub the flag from the ambient environment: a shell that already ran an
    # older, exporting version of the module would otherwise pass it down here
    # and the test would measure that instead of the code.
    run env -u NIVUUS_AI_SUGGESTIONS_LOADED zsh -c "
        source '$REPO_ROOT/themes/nord.zsh'
        source '$REPO_ROOT/config/09-ai-core.zsh'
        source '$REPO_ROOT/config/19-ai-suggestions.zsh'
        [[ -n \"\$NIVUUS_AI_SUGGESTIONS_LOADED\" ]] || { echo 'guard not set in own shell'; exit 1 }
        zsh -c 'echo \"CHILD=[\$NIVUUS_AI_SUGGESTIONS_LOADED]\"'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"CHILD=[]"* ]]
}
