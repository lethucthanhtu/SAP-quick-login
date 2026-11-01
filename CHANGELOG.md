# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Fixed

- Clients listed in `favoriteClient` are highlighted again (the script read `favoriteClients`;
  both keys are now accepted).
- `quicky.ps1` parses again when run as a local file in Windows PowerShell 5.1 (the file is now
  plain ASCII; the menu looks the same).
- An empty or missing `password` no longer sends `-pw=""`; SAP GUI asks for the password.

### Added

- README: review-before-run / pinned-commit instructions, credential warnings, uninstall.
- `SECURITY.md`, `.gitignore` for `sap-systems.json`, PSScriptAnalyzer in CI.
