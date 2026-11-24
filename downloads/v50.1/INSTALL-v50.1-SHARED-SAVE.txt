My Project Management v50.1 (50.1.0) — 24 November 2026, Qatar

This update fixes the CR "Finish the current shared save first" blocker:
- Reading/rendering a shared snapshot no longer queues a save for display defaults.
- Opening/editing a CR waits for actual pending/in-flight workspace writes.
- A stale dirty flag is cleared only when the current data matches the saved baseline.
- Failed writes show the real error persistently, with explicit retry and backup options.
- Timeouts retain edits and leave an in-flight write running; no automatic reload/discard.

UPGRADE FROM v50
Back up your current publish folder and database. Stop the application pool.
Extract the update ZIP. Copy the CONTENTS of its publish folder into your existing IIS folder:
C:\inetpub\wwwroot\MyProjectManagement-IIS-SQLServer2022-2025\publish
Preserve appsettings*.json, web.config, and authentication keys. The delta excludes them.
Restart the application pool. Hard-refresh browser or close/reopen the installed mobile app.
Confirm Version 50.1 or /api/health version 50.1.0.
NO SQL SCRIPT IS REQUIRED. Database schema, grants and accounts remain unchanged.
Use the full package for an older installation, with the existing v50 database prerequisites.

IF A SAVE ERROR REMAINS
Open Change requests and choose New change request. Wait for any pending save.
If saving fails, the displayed error identifies the remaining issue. Retry shared save once
it is resolved. No edits are discarded. Download the unsaved backup before choosing Reload
shared records; reload requires confirmation and replaces unsaved workspace changes.
An earlier-session backup warning requires backing up/reloading explicitly, not a blind retry.
Do not clear browser storage or run SQL deletion scripts to fix a pending save.
If the error is a database/permission/validation error, share that exact message for diagnosis.

ROLLBACK
Stop the pool and restore the backed-up v50 publish folder. Keep local settings and keys.
No database rollback is required for this patch. Existing v50 functionality is retained.

TESTS
Browser regression tests cover stale flags, actual pending and in-flight saves, failed-save
backup retention, explicit retry, timeouts, render normalization, Word mapping and mobile CRs.
Existing login security and CR/delegation policy checks are retained.
