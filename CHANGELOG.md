# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-01-27
### Added
- JSON and CSV import flow with analysis and clear issue reporting.
- Export preflight checks with optional auto-fix for invalid references.
- Collaborator notes included in export payloads and summaries.
- Symptom entry deletion from the entry editor.

### Changed
- Quick add now refreshes after imports.
- Local `.derivedData/` output is ignored by git.

### Fixed
- CSV journal metadata handling for round-trip imports.
- Import validation for synthetic schedule IDs.
- Quick log initial load behavior.
- As-needed intake task initialization.
- Sync status fallback for stuck syncing indicators.
- As-needed intake timestamp test stability.

## [0.1.0] - 2026-01-26
### Added
- Initial release.
