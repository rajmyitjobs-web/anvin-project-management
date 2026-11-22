# My Project Management release history

| Version | Main change | Package type |
| --- | --- | --- |
| v36 / 36.0.0 | Project Plan/Activity Master Excel and CSV uploads, templates/reference sheets, row preview, duplicate prevention and atomic imports | Complete update; no new schema change over v35 |
| v35 / 35.0.0 | Change Request register, locked revisions, PM/CTO feasibility decisions, point/paragraph comments, private Word uploads and new-revision client feedback | Complete update + REQUIRED CR/Word SQL tables and role seed |
| v34 / 34.0.0 | Enterprise workspace redesign, KPI ribbon/register, three browser-selectable themes and table density; grouped menus retained | Complete update; no new schema change |
| v33 / 33.0.0 | Collapsible menu groups by form purpose; automatic active section, empty-group hiding, preserved role filtering; updated manual | Complete update; no new schema change |
| v32 / 32.0.0 | In-app manual/process flow, 11-page PDF + editable Word guide, dashboard/report loading sources and formulas | Complete update + standalone documentation; no new schema change |
| v31 / 31.0.0 | Daily allocation/actual entry use one activity date and hours; current new dates; untimed calendars; legacy timed hours retained | Complete app + required numeric-hours SQL reporting patch |
| v30 / 30.0.0 | Actual entry defaults from daily allocation dates/times/break; editable hours preview, preserved saved actuals and status-only shortcut | Complete app update; no schema change |
| v29 / 29.0.0 | Project module checkboxes and company count/name entry; add modules and companies at any stage, preserve IDs/overrides/history | Complete update; optional scope summary SQL view |
| v28 / 28.0.0 | Date-range PSR with editable period notes, status, client-deducted man-days, recent activities, issues, planned milestones, PDF and Excel | Complete update; optional SQL PSR procedure |
| v27 / 27.0.0 | Separate Project Manager, Project In-charge and multi-person module teams; scoped access and primary-owner compatibility | Complete app update; optional multi-person reporting SQL |
| v26 / 26.0.0 | Required project and module consultant/in-charge; preserve company overrides | Complete app update; optional module ownership SQL reporting view |
| v25 (SQL only; app v24) | Fix JSON-key/reporting collation conflicts and recreate missing dependent views; live SQL Server 2022 tested | SQL repair / corrected upgrade and full setup |
| v24 / 24.0.0 | AMC contract cycles, visit/hour compliance, staff scheduling suggestions and alerts; explicit versioning | Complete application update + cumulative SQL |
| v23 | Customer master, multi-person allocations, weekly visits, modal refresh protection, employee Excel timesheets and client-deduction audit | Complete application update + cumulative SQL; archived for rollback |
| v22 | Activity types, project stages and date-range project/timesheet reports | Complete application update + cumulative SQL |
| v21 | User and role masters; project code 50 and activity code/name 140 characters | Complete application update + SQL |
| v20 | Individual dashboards and pending work tracking | Frontend patch; requires matching base application |
| v19 | Save fix 2 for module master | Frontend patch; requires matching base application |

Every new release receives a versioned application and SQL filename. v24 is visible
in the app, `/api/health`, `release.json`, `VERSION.txt`, and the .NET file version.
Older releases before v24 may show their original feature labels rather than a
numeric in-app version; use the version manifest and package checksum to identify them.

To request a rollback, name the release (for example v23). Forward migration scripts
are not rollback scripts. Keep a paired site/database backup before upgrading. A full
rollback restores that pair while preserving connection settings and authentication
keys. Restoring a database backup discards work entered after the backup time.
