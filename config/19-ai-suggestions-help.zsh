#!/usr/bin/env zsh
# =============================================================================
# AI Command Suggestions - Help
# =============================================================================
# Part of the AI suggestions module. Sourced by config/19-ai-suggestions.zsh,
# which is the entry point listed in .zshrc -- this file is not loaded on its
# own.
# =============================================================================

[[ -n "${NIVUUS_AI_SUGGESTIONS_HELP_LOADED}" ]] && return
typeset -g NIVUUS_AI_SUGGESTIONS_HELP_LOADED=1

# Help
# =============================================================================

ai_suggestions_help() {
    cat <<'EOF'
AI Command Suggestions - Inline Mode

How it works:
  1. Type partial command (3+ chars): git s
  2. Either wait 2 seconds (auto-debounce) or press Ctrl+2/Ctrl+Space
  3. Spinner appears inline after cursor while generating
  4. Suggestion appears as green ghost text after cursor
  5. Press Ctrl+→ to accept suggestion (same key as word-accept from history)
  6. Press Enter to cancel generation and execute your typed command
  7. Navigate history (↑/↓/Ctrl+R) to cancel generation
  8. Continue typing to clear and reset timer

Features:
  • Nord color scheme (cyan spinner, green suggestions)
  • NO latency - Enter key responds instantly during generation
  • Async generation - never blocks your typing
  • ULTRA-RICH context for maximum relevance
  • Automatic cleanup on typing/accepting/canceling

Context provided to AI (ultra-enriched):
  • ALL files in directory (up to 50)
  • Recent command history (last 20 commands)
  • Git status + FULL diff (100 lines)
  • Project files content (package.json scripts, go.mod, Cargo.toml, requirements.txt)
  • README.md preview (20 lines)
  • Full environment (USER, SHELL, HOME, PATH)
  • Project type detection (Node.js, Go, Rust, Python)

Configuration:
  AI_SUGGESTION_MIN_CHARS=3       # Minimum chars to trigger
  AI_DEBOUNCE_DELAY=2             # Debounce delay in seconds
  ENABLE_AI_AUTO_DEBOUNCE=false   # Auto-trigger after typing pause
  AI_SUGGESTION_MODEL=gemini-3.1-flash-lite  # Model for suggestions (default)

Available models:
  gemini-3.1-flash-lite  # Fastest, no "thinking" overhead, best for inline completion (default)
  gemini-2.5-flash       # More capable, still fast
  gemini-2.5-pro         # Most capable, slower
  Note: "thinking" models (gemini-3.7-flash, gemini-flash-latest) spend the
  output token budget on internal reasoning and return empty completions here.

Keybindings:
  Ctrl+→     - Accept inline AI suggestion (or next word from history)
  Shift+Tab  - Clear inline AI suggestion
  Ctrl+2     - Trigger AI suggestion manually
  Ctrl+Space - Trigger AI suggestion manually

During generation:
  Enter      - Cancel generation and execute your command (NO LATENCY)
  Ctrl+C     - Cancel generation and return to prompt
  Ctrl+L     - Cancel generation and clear screen
  ↑/↓        - Cancel generation and navigate history
  Ctrl+R     - Cancel generation and search history
  Type       - Clear suggestion and reset debounce timer

Colors (Nord palette):
  Cyan (110)       - Spinner / generating indicator
  Green (143)      - Suggested command (ghost text)

EOF
}
