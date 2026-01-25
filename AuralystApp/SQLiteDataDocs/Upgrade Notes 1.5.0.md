Notes

# SQLiteData 1.5.0 upgrade notes

This project moved from SQLiteData 1.3.0 to 1.5.0. The highlights below focus on
items that affect Auralyst's CloudKit sync, previews, and data fetching behavior.

## Release highlights (1.4.x -> 1.5.0)

- Added: Preview support for CloudKit-enabled apps.
- Added: `SyncEngine.isSynchronizing` and `SyncEngine.$isSynchronizing`.
- Fixed: Sharing child records could become unshareable due to stale iCloud data.
- Fixed: Metadata observation could miss updates in some cases.
- Fixed: CloudKit schema migration issues around `NOT NULL` columns.
- Fixed: `FetchKey` now propagates dependencies correctly.
- 1.4.0 added: `FetchTask` to tie database observation to view lifetime.
- 1.4.0 added: static `fetch` and `find` helpers.

## Auralyst-specific action items

- Sync status UI already uses `isSynchronizing` in `SyncStatusFeature`, so this
  feature is actively leveraged.
- Preview support is now officially available for CloudKit-enabled apps; current
  preview bootstrapping in `PreviewSupport.swift` should work without disabling
  sync, but we should verify previews in Xcode after dependency updates.
- Consider adopting `FetchTask` in any view/model that uses manual observation
  or long-lived `@FetchAll` wrappers outside SwiftUI views.

## Links

- Release 1.5.0: https://github.com/pointfreeco/sqlite-data/releases/tag/1.5.0
- Release 1.4.0: https://github.com/pointfreeco/sqlite-data/releases/tag/1.4.0
