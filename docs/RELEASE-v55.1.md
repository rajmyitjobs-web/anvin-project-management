My Project Management v55.1 / 55.1.0 — 26 November 2026, Qatar

PLANNING / IMPORT
Open a specific project in Project Planning before downloading its template or importing.
Templates are generated for that project's current Company-wise Project Tracking Required
setting. Use Download Excel template in the application, rather than an old bookmarked file.
New Implementation retains the first four supplied plan columns and working-day/session logic.
Company is appended when tracking is enabled. Generic project plans also follow this setting.

TRACKING ENABLED
Templates include Company and a reference sheet containing ONLY the selected project's
registered company IDs/codes/names/modules. Every row in a new-format implementation file
needs Company, including client dependencies, headings and totals. Values may be exact IDs,
codes or names from Project Company Master. Unknown/ambiguous/other-project references are
errors. Preview offers master-list selections to correct mismatches. Multiple companies may
be included in one file, with separate duplicate identities and per-company plan row limits.
Manual planning forms require a registered company selection. CTO/CR/user setup is unaffected.
Legacy implementation workbooks without Company remain supported only when the user explicitly
chooses the default company in the import dialog; that selection is validated against the master.

TRACKING DISABLED
Generated templates contain no company-related columns or company reference sheet. Import
requires no company value or default company selection, even if historical companies remain.
Planning company inputs and filters are hidden. Project modules (not company overrides) are
used. A stable internal company ID is attached to NEW work to preserve existing schedule,
allocation/calendar/timesheet compatibility; this is not a user data-entry requirement.
Legacy files containing Company are accepted; those values are ignored in project-wide mode.
Existing plan/task company IDs and actuals are NOT reassigned or deleted. Historical plan rows
remain visible at project level. Duplicate detection includes historical companies to avoid
recreating the same work. Existing company detail maintenance remains gated by v54 rules.

VALIDATION / SCOPE
Preview and commit revalidate the server's project setting and company references; no partial
batch is saved on errors. If the tracking setting changes during an import, reload the project
and reopen the import rather than importing under a stale mode. Existing permission, revision,
activity, employee, date, effort, weekly/daily generation and billing checks remain.
This change targets project planning and project-plan imports. Weekly site visit imports and
standalone daily allocation forms retain their existing company behavior unless updated in a
future feature. AMC/Office planning rules remain: AMC compliance and direct Office work.

LOCAL IIS UPDATE FROM v54
Back up publish folder/database, stop MyProjectManagement application pool, copy the update
ZIP's publish CONTENTS into the existing publish folder, keeping appsettings*.json, web.config
and protected keys. Restart and hard-refresh/reopen browser. Confirm Version 55.1 / health
55.1.0. No SQL schema migration is required. Use the full package for older app versions,
preserving configuration and existing database prerequisites.
Rollback: restore the backed-up v54 publish folder while stopped. New plan rows remain saved;
older UI may show internal company fields again. The prepared v52 rollback remains paused.

VALIDATION
Tests cover dynamic headers/reference sheets, company master references, project-only module
scope, required/hidden form inputs, per-company duplicates, legacy import context, mode changes
and invalid batch rejection. Existing company/unit/user/CR/security/shared-save regressions
remain. Verify a real plan import in both modes on local IIS/SQL staging before production use.

COMPATIBILITY FIX
v55.1 retains company names in the shared weekly-import preview lookup, while planning
previews use stable company IDs. This preserves editing/revalidation of weekly rows.
The update package is based on v54 and includes all v55 changes; it can also update v55.
