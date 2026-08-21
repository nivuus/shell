# Testing Guide - Nivuus Shell

## Quick Start

```bash
# Install zunit
npm install

# Run all tests
npm test

# Run specific test suites
npm run test:unit
npm run test:performance
npm run test:integration

# Run with verbose output
./bin/test --verbose
```

## Current Test Coverage

### ✅ Implemented (Examples Created)

1. **Unit Tests** - `tests/unit/test_prompt.zsh`
   - 30+ tests for prompt module (05-prompt.zsh)
   - SSH/Root detection
   - Git prompt with caching
   - Python venv detection
   - Cloud context (AWS/GCP/Azure)
   - Firebase detection
   - Background jobs display
   - Nord color validation

2. **Performance Tests** - `tests/performance/test_startup.zsh`
   - **CRITICAL**: <300ms startup time validation
   - Prompt generation speed (<100ms)
   - Git cache performance (<50ms on cache hit)
   - Module load times
   - Compilation verification (.zwc files)
   - Memory footprint (<100MB)

3. **Integration Tests** - `tests/integration/test_ai_workflow.bats`
   - Backend dispatcher (model resolution, temperature, AI_BACKEND routing)
   - AI commands (`ask`, `why`, `explain`, `aihelp`) incl. missing credentials
   - Inline suggestions workflow (ZLE widgets, background generation)
   - Cache behavior (5min TTL, no duplicate backend call)
   - Context collection and secret redaction
   - Terminal titles and AI error capture hooks

### 📝 TODO - Remaining Test Files (15 more unit tests)

Complete coverage requires creating these additional test files:

```
tests/unit/
├── test_ai_commands.zsh        # 10-ai.zsh (why, explain, ask)
├── test_safety.zsh             # 21-safety.zsh (dangerous patterns)
├── test_python_venv.zsh        # 09-python.zsh (venv detection)
├── test_nodejs.zsh             # 09-nodejs.zsh (NVM lazy loading)
├── test_vim.zsh                # 08-vim.zsh (env detection)
├── test_functions.zsh          # 14-functions.zsh (20+ functions)
├── test_network.zsh            # 12-network.zsh (myip, weather, etc.)
├── test_system.zsh             # 13-system.zsh (healthcheck, benchmark)
├── test_git_aliases.zsh        # 06-git.zsh (all git aliases)
├── test_completion.zsh         # 03-completion.zsh (lazy loading)
├── test_keybindings.zsh        # 04-keybindings.zsh
├── test_history.zsh            # 02-history.zsh
├── test_colorization.zsh       # 17-colorization.zsh
├── test_files.zsh              # 11-files.zsh
└── test_aliases.zsh            # 15-aliases.zsh (50+ aliases)
```

### 📝 TODO - Remaining Integration Tests (4 more)

```
tests/integration/
├── test_module_loading.zsh     # Load order, dependencies
├── test_prompt_full.zsh        # All prompt components together
├── test_git_workflow.zsh       # Aliases + prompt integration
└── test_cloud_context.zsh      # Multi-cloud detection
```

### 📝 TODO - Remaining E2E Tests (4 files)

```
tests/e2e/
├── test_user_install.zsh       # ./install.sh (user mode)
├── test_system_install.zsh     # sudo ./install.sh --system
├── test_healthcheck.zsh        # bin/healthcheck
└── test_benchmark.zsh          # bin/benchmark
```

### 📝 TODO - GitHub Actions CI/CD

Create `.github/workflows/tests.yml`:
- Matrix: Ubuntu + macOS
- Separate jobs for each test suite
- Performance validation (<300ms REQUIRED)
- Coverage reporting
- CI badge for README

## Test Infrastructure Created

### ✅ Complete

- `package.json` - zunit dependency
- `tests/README.md` - Comprehensive test documentation
- `tests/helpers/assertions.zsh` - 15 custom assertions
- `tests/helpers/mocks.zsh` - Mock utilities for all dependencies
- `bin/test` - Main test runner with options
- `.gitignore` - Test artifacts excluded

### 🛠 Test Utilities Available

**Custom Assertions** (`tests/helpers/assertions.zsh`):
- `assert_performance` - Validate execution time
- `assert_color` - Check Nord color codes
- `assert_cached` - Verify caching behavior
- `assert_file_compiled` - Check .zwc compilation
- `assert_startup_time` - **CRITICAL** <300ms validation
- `assert_env_set`, `assert_function_exists`, `assert_alias_exists`
- `assert_matches`, `assert_file_contains`
- `assert_success`, `assert_failure`

**Mock Functions** (`tests/helpers/mocks.zsh`):
- `mock_gemini`, `mock_gemini_error` - AI responses
- `mock_git_repo`, `mock_git_clean`, `mock_git_dirty` - Git states
- `mock_ssh_session`, `mock_local_session` - Session types
- `mock_root_user`, `mock_regular_user` - User privileges
- `mock_aws_env`, `mock_gcp_env`, `mock_azure_env` - Cloud providers
- `mock_python_venv`, `mock_no_venv` - Python environments
- `mock_nvm_installed`, `mock_nvm_not_installed` - NVM states
- `mock_firebase_config` - Firebase projects
- `create_mock_git_repo`, `create_mock_nodejs_project`, `create_mock_python_project`

## Running Tests

### All Tests
```bash
npm test
```

### Specific Suites
```bash
npm run test:unit          # Unit tests only
npm run test:integration   # Integration tests only
npm run test:performance   # Performance validation
npm run test:e2e           # End-to-end tests
```

### Individual Test Files
```bash
zunit tests/unit/test_prompt.zsh
zunit tests/performance/test_startup.zsh
bats tests/integration/test_ai_workflow.bats
```

### With Verbose Output
```bash
./bin/test --verbose
./bin/test --unit --verbose
```

## Next Steps to Complete Test Suite

### Priority 1: Critical Tests

1. Complete unit tests for core modules:
   - `test_ai_commands.zsh` (AI integration)
   - `test_safety.zsh` (dangerous command detection)
   - `test_functions.zsh` (utility functions)

2. Add remaining performance tests:
   - Individual module benchmarks
   - Cache effectiveness metrics

3. Create GitHub Actions workflow:
   - Auto-run on push/PR
   - Fail build if startup >300ms
   - Generate coverage reports

### Priority 2: Full Coverage

4. Complete all 15 remaining unit test files
5. Add 4 remaining integration test files
6. Create 4 E2E test files

## Writing New Tests

### Example Unit Test

```zsh
#!/usr/bin/env zunit

# Load helpers
source tests/helpers/assertions.zsh
source tests/helpers/mocks.zsh

# Setup
@setup {
    source themes/nord.zsh
    source config/XX-module.zsh
}

# Test
@test 'function does something' {
    mock_env_as_needed

    result=$(your_function "input")

    assert "$result" same_as "expected"
}
```

### Example Performance Test

```zsh
@test 'function is fast' {
    assert_performance 100 "your_function"  # <100ms
}
```

## CI/CD Integration (TODO)

Create `.github/workflows/tests.yml`:

```yaml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest]

    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-node@v3
        with:
          node-version: '18'
      - run: npm install
      - run: npm test
      - name: Validate startup time
        run: npm run test:performance
```

## Current Status

**Infrastructure**: ✅ Complete (100%)
**Example Tests**: ✅ Created (3 comprehensive examples)
**Helpers/Mocks**: ✅ Complete (100%)
**Test Runner**: ✅ Complete (100%)
**Documentation**: ✅ Complete (100%)

**Total Tests to Write**: ~1000+
**Tests Created**: ~50 (5%)
**Ready for**: Development of remaining tests

The foundation is solid. You can now:
1. Run existing tests: `npm test`
2. Use examples as templates for new tests
3. Leverage all helpers and mocks
4. Add tests incrementally as you develop features
