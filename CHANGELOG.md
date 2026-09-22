# Changelog

All notable changes to StreamCue are documented in this file.
This project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

- Hide a show from the hero/upcoming sections once it has an episode
  sitting in Ready to watch, so it isn't shown twice

- Add a Watched button to the title preview sheet, alongside Add and Not
  interested

- Bump marketing version to 2.3.2

- Derive a show's watched state from episode progress instead of a manual
  toggle — caught up when nothing aired is still outstanding, un-caught-up
  again the moment a new episode airs

- Bump marketing version to 2.3.1

- Change background refresh from weekly to nightly

- Add OMDb attribution to Settings, required by its CC BY-NC licence

- Fix marking a movie watched/unwatched not syncing to the household list

- Add shared Xcode scheme

- Bump marketing version to 2.3.0

- Add Run Script phase to embed git commit hash in Info.plist

- Bump version to 2.2.1 (2)

- Fix CloudKit container identifier and enable remote-notification background mode

- Add CLAUDE.md

- Add app icon badge for pending episodes

- StreamCue v2

- Fixed Discover tab lag and stutter

- Added Background Refresh and Automated Reminder Add

## [2.2.0] - 2026-09-09
### Added
- Searchable cast view strip on all preview and detail pages
- Changelog with auto-append commit hook

### Fixed
- Corrected hero card callouts

## [2.1.0] - 2026-09-08
### Added
- Day offset for TV shows
- Scroll-to-top control
- Dedicated Help section

### Changed
- Moved Help out of Settings into its own menu

## [2.0.0] - 2026-09-07
### Added
- Multi-search in the Discover tab
- Dismiss and ignore options
- iCloud sync groundwork
- V2 alpha rewrite

## [1.0.0] - 2026-09-07
### Added
- Initial release
