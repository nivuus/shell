# Nivuus Shell - Test Suite

Comprehensive test suite for Nivuus Shell using zunit framework.

## Running Tests

```bash
# Run all tests
npm test
# or
./bin/test

# Run specific test suites
npm run test:unit          # Unit tests only
npm run test:integration   # Integration tests
npm run test:performance   # Performance tests (<300ms validation)
npm run test:e2e           # End-to-end tests

# Watch mode (re-run on file changes)
npm run test:watch

# With coverage report
npm run test:coverage
```

## Test Organization

```
tests/
├── unit/            # Unit tests for individual functions (~900 tests)
├── integration/     # Integration tests for complete workflows (~100 tests)
├── performance/     # Performance validation tests (~50 tests)
├── e2e/             # End-to-end installation tests (~40 tests)
├── helpers/         # Test utilities (assertions, mocks)
└── fixtures/        # Test data (mock repos, configs)
```

## Writing Tests

### Using zunit

```zsh
#!/usr/bin/env zunit

@test 'function returns correct value' {
    source config/14-functions.zsh

    result=$(some_function "input")

    assert "$result" same_as "expected"
}

@test 'function handles errors' {
    run some_function "bad_input"

    assert $state equals 1
    assert "$output" contains "error"
}
```

### Custom Assertions

Located in `tests/helpers/assertions.zsh`:

- `assert_performance` - Validate execution time
- `assert_color` - Check Nord color codes
- `assert_cached` - Verify caching behavior
- `assert_file_compiled` - Check .zwc compilation

### Mocking

Located in `tests/helpers/mocks.zsh`:

- `mock_gemini` - Mock gemini-cli responses
- `mock_git` - Mock git commands
- `mock_env` - Mock environment variables
- `mock_ssh` - Simulate SSH session

## Performance Requirements

**Critical**: Startup time MUST be < 300ms

Performance tests validate:
- Full shell load time (average of 10 runs)
- Individual module load times
- Prompt generation speed (<100ms)
- Cache effectiveness

## CI/CD

Tests run automatically on:
- Every push to `main`
- Every pull request

CI is configured in `.github/workflows/ci.yml`, which delegates to the
reusable workflows published in `nivuus/.github` (policy, security, and the
shell job that runs `bats`, `shellcheck` and the zsh syntax check).

## Debugging Failed Tests

```bash
# Run specific test file
zunit tests/unit/test_prompt.zsh

# Verbose output
./bin/test --verbose

# Debug single test
zunit tests/unit/test_prompt.zsh --tap | grep -A10 "FAIL"
```

## Coverage Goals

- **Unit tests**: 100% function coverage
- **Integration tests**: All major workflows
- **Performance tests**: <300ms guarantee
- **E2E tests**: Both install modes (user/system)

## Test Fixtures

Located in `tests/fixtures/`:

- `git_repo/` - Mock git repository
- `.firebaserc` - Firebase config samples
- `.nvmrc` - NVM version files
- `package.json` - Node.js project samples
- `requirements.txt` - Python project samples
- `venv_dirs/` - Mock Python virtual environments

## Contributing

When adding new features:

1. Write tests FIRST (TDD approach)
2. Ensure all tests pass: `npm test`
3. Check performance: `npm run test:performance`
4. Update this README if needed

## Resources

- [zunit Documentation](https://zunit.xyz/)
- [ZSH Testing Guide](https://github.com/zsh-users/zsh/blob/master/Test/README)
- [Project Style Guide](../CLAUDE.md)
