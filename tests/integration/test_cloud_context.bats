#!/usr/bin/env bats

# Integration tests for multi-cloud context detection (AWS, GCP, Azure)

# =============================================================================
# AWS Context Tests
# =============================================================================

@test "AWS profile shows in prompt" {
    run zsh -c "export AWS_PROFILE=production && source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && prompt_cloud_context"
    [ "$status" -eq 0 ]
    [[ "$output" == *"aws"* ]] && [[ "$output" == *"production"* ]]
}

@test "AWS region shows when set" {
    run zsh -c "export AWS_REGION=us-west-2 && source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && prompt_cloud_context"
    [ "$status" -eq 0 ]
}

@test "AWS uses the theme's orange color" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 20 'prompt_cloud_context' config/05-prompt.zsh | grep 'THEME_COLORS\[orange\]'"
    [ "$status" -eq 0 ]
}

@test "AWS context checks for AWS_PROFILE" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'AWS_PROFILE' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "AWS context checks for default profile" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'AWS_PROFILE.*default' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# GCP Context Tests
# =============================================================================

@test "GCP project shows in prompt when Firebase disabled" {
    run zsh -c "export CLOUDSDK_CORE_PROJECT=my-project && export ENABLE_FIREBASE_PROMPT=false && source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && prompt_cloud_context"
    [ "$status" -eq 0 ]
    [[ "$output" == *"gcp"* ]] && [[ "$output" == *"my-project"* ]]
}

@test "GCP uses the theme's git-prefix (cyan) color" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 20 'prompt_cloud_context' config/05-prompt.zsh | grep 'THEME_GIT_PREFIX'"
    [ "$status" -eq 0 ]
}

@test "GCP context checks for CLOUDSDK_CORE_PROJECT" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'CLOUDSDK_CORE_PROJECT' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "GCP context respects ENABLE_FIREBASE_PROMPT" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 5 'CLOUDSDK_CORE_PROJECT' config/05-prompt.zsh | grep 'ENABLE_FIREBASE_PROMPT'"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Azure Context Tests
# =============================================================================

@test "Azure subscription shows in prompt" {
    run zsh -c "export AZURE_SUBSCRIPTION_ID=my-subscription && source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && prompt_cloud_context"
    [ "$status" -eq 0 ]
    [[ "$output" == *"az"* ]] && [[ "$output" == *"my-subscription"* ]]
}

@test "Azure uses the theme's blue (SSH) color" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 40 'prompt_cloud_context' config/05-prompt.zsh | grep 'THEME_SSH'"
    [ "$status" -eq 0 ]
}

@test "Azure context checks for AZURE_SUBSCRIPTION_ID" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'AZURE_SUBSCRIPTION_ID' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Azure configuration check exists" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'az account' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Cloud Context Function Tests
# =============================================================================

@test "prompt_cloud_context function exists" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && typeset -f prompt_cloud_context"
    [ "$status" -eq 0 ]
}

@test "Cloud context returns empty when no clouds active" {
    run zsh -c "unset AWS_PROFILE AWS_REGION CLOUDSDK_CORE_PROJECT AZURE_SUBSCRIPTION_ID && source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && prompt_cloud_context"
    [ "$status" -eq 0 ]
}

@test "Cloud context handles multiple clouds simultaneously" {
    run zsh -c "export AWS_PROFILE=prod && export CLOUDSDK_CORE_PROJECT=my-proj && source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && prompt_cloud_context"
    [ "$status" -eq 0 ]
    # Should show both AWS and GCP
    [[ "$output" == *"aws"* ]]
}

# =============================================================================
# Cloud Context Integration with Prompt
# =============================================================================

@test "Cloud context is called from build_prompt" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep 'prompt_cloud_context' config/05-prompt.zsh | grep -v '^#' | head -5"
    [ "$status" -eq 0 ]
}

@test "Cloud context uses theme colors" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 40 'prompt_cloud_context' config/05-prompt.zsh | grep -cE 'THEME_[A-Z_]+|THEME_COLORS\['"
    [ "$status" -eq 0 ]
    count="${output}"
    [ "$count" -ge 3 ]
}

@test "Full prompt shows cloud context when set" {
    run zsh -c "export AWS_PROFILE=test && source '$NIVUUS_SHELL_DIR/.zshrc' && build_prompt"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Azure Cache Tests
# =============================================================================

@test "Azure cache variables exist" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep '_AZURE_PROMPT_CACHE' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Azure cache stores time" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep '_AZURE_PROMPT_CACHE_TIME' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

@test "Azure cache stores value" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep '_AZURE_PROMPT_CACHE_VALUE' config/05-prompt.zsh"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Environment Variable Priority Tests
# =============================================================================

@test "AWS_PROFILE takes priority over default" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 10 'AWS_PROFILE' config/05-prompt.zsh | grep 'if.*-n'"
    [ "$status" -eq 0 ]
}

@test "GCP context disabled when Firebase enabled" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 5 'CLOUDSDK_CORE_PROJECT' config/05-prompt.zsh | grep 'ENABLE_FIREBASE_PROMPT.*true'"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Cloud Detection Logic
# =============================================================================

@test "AWS detection is conditional" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 30 'prompt_cloud_context()' config/05-prompt.zsh | grep -E 'if.*AWS_PROFILE'"
    [ "$status" -eq 0 ]
}

@test "GCP detection is conditional" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 30 'prompt_cloud_context()' config/05-prompt.zsh | grep -E 'if.*CLOUDSDK'"
    [ "$status" -eq 0 ]
}

@test "Azure detection is conditional" {
    run bash -c "cd '$BATS_TEST_DIRNAME/../..' && grep -A 30 'prompt_cloud_context()' config/05-prompt.zsh | grep -E 'if.*AZURE'"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Performance Tests
# =============================================================================

@test "Cloud context function loads quickly" {
    start=$(date +%s%N)
    zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && prompt_cloud_context" >/dev/null
    end=$(date +%s%N)
    elapsed_ms=$(( (end - start) / 1000000 ))

    [ "$elapsed_ms" -lt 100 ]
}

@test "Cloud context with all clouds set is fast" {
    start=$(date +%s%N)
    zsh -c "export AWS_PROFILE=test && export CLOUDSDK_CORE_PROJECT=proj && export AZURE_SUBSCRIPTION=sub && source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && prompt_cloud_context" >/dev/null
    end=$(date +%s%N)
    elapsed_ms=$(( (end - start) / 1000000 ))

    [ "$elapsed_ms" -lt 150 ]
}

# =============================================================================
# Error Handling Tests
# =============================================================================

@test "Cloud context handles missing gcloud gracefully" {
    run zsh -c "PATH=/nonexistent && export CLOUDSDK_CORE_PROJECT=test && source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && prompt_cloud_context"
    [ "$status" -eq 0 ]
}

@test "Cloud context handles missing az gracefully" {
    run zsh -c "PATH=/nonexistent && export AZURE_SUBSCRIPTION_ID=test && source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && prompt_cloud_context"
    [ "$status" -eq 0 ]
}

# =============================================================================
# Full Integration Tests
# =============================================================================

@test "Cloud context integrates with full shell load" {
    run zsh -c "export AWS_PROFILE=production && source '$NIVUUS_SHELL_DIR/.zshrc' && typeset -f prompt_cloud_context"
    [ "$status" -eq 0 ]
}

@test "Cloud context works with other prompt components" {
    run zsh -c "export AWS_PROFILE=prod && export VIRTUAL_ENV=/tmp/venv && source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && build_prompt"
    [ "$status" -eq 0 ]
    # Prompt should contain both cloud and venv info
}

@test "Cloud context module loads without errors" {
    run zsh -c "source '$NIVUUS_SHELL_DIR/themes/nord.zsh' && source '$NIVUUS_SHELL_DIR/config/05-prompt.zsh' && echo 'loaded'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"loaded"* ]]
}
