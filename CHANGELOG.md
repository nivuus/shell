# Changelog

All notable changes to Nivuus Shell will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- One command installs the whole machine: `install.sh` (and `nivuus install`)
  defaults to a system-wide install when root or sudo is available, re-running
  itself through sudo from an ordinary account. It installs the missing
  dependencies (zsh, git, curl) and the optional tools (jq, fzf, eza, bat, fd,
  ripgrep, timg, grc, git-delta) with the platform package manager, sources
  Nivuus from the global zshrc and makes zsh the login shell of every human
  account. Files and login shells are journaled and restored by
  `nivuus uninstall`; the packages it installed are kept.
- `nivuus install --user`, `--no-chsh`; `nivuus uninstall --system`
- `lib/deps.sh`: package names and install commands per package manager
- Automated GitHub Actions release workflow
- Release-based auto-update system with checksum verification
- Version tracking via `.version` file
- `nivuus-version` command to check current version

### Changed
- Auto-update system now uses GitHub Releases instead of git commits
- Update mechanism now downloads and verifies release archives
- Version synchronization between `package.json` and `install.sh`

### Fixed
- Prompt rendered two spaces between `>` and the path (`# >  /home/x`)
- `.zshrc` sourced twice in one shell (system-wide + per-user install) no
  longer loads Nivuus twice
- Shells that cannot write a system-wide install no longer try to compile or
  auto-update it

### Security
- Added SHA256 checksum verification for release downloads
- Improved backup system before updates

## [2.0.0] - 2025-01-23

### Added
- Comprehensive test suite with 401 tests
  - Unit tests for all core modules
  - Performance tests with <300ms startup time requirement
  - Integration and end-to-end tests
- GitHub Actions CI/CD pipeline
  - Automated testing on push/PR
  - Syntax validation
  - Test coverage reporting
- AI-powered terminal titles with exponential backoff
- Modular configuration system (26 modules)
- Nord-themed prompt with git integration
- Smart aliases and command replacements
- Auto-update system (git-based)
- Performance benchmarking tools
- Health check diagnostics

### Changed
- Reorganized documentation into `doc/` directory
- Improved prompt architecture with better git status
- Enhanced performance optimization

### Fixed
- Resolved failing unit tests
- Improved test reliability
- Fixed module loading issues

## [1.0.0] - Initial Release

### Added
- Initial release of Nivuus Shell
- Nord theme integration
- Basic ZSH configuration
- Core utilities and aliases
- Installation script

[Unreleased]: https://github.com/nivuus/shell/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/nivuus/shell/releases/tag/v2.0.0
[1.0.0]: https://github.com/nivuus/shell/releases/tag/v1.0.0
