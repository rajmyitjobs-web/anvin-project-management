My Project Management v58.1 / 58.1.0 — 27 November 2026 (Qatar)

PROJECT MONITORING
Open Dashboards > Project monitoring, click Monitor in the Projects list, or click
Monitor project inside an opened project. Select a project and an inclusive date range.
Company-wise Project Tracking Required is saved in Project Master and controls the view.

TRACKING ENABLED
The View list offers Consolidated project / all companies and individual registered
companies. Company summaries and activity rows show current activity status, planned
allocation hours, actual hours, client deducted hours and internal hours. Consolidated
hours sum accessible work across all companies; progress uses the existing weighted
activity calculation, not an average of company percentages. Historical tasks with no
matching company remain in a clearly labelled row so totals are not silently lost.
Implementation company readiness retains go-live status, target/actual dates and module
readiness. Company detail maintenance remains in Project Company Master.
Project reports also offer a company filter after a tracked project is selected.

TRACKING DISABLED
Monitoring has no company selector, summary table or activity company column. It
clears any stale company filter before loading totals and includes all retained
historical company links at project level. Project details and Office views omit
company configuration labels, company counts and internal company names. Project plan
and report CSV exports omit Company when a project-level view is selected. In mixed
reports the column is retained only if a tracked project is included; project-level
rows leave it blank. Internal IDs and saved records are not reassigned or deleted.
Implementation project completion no longer waits for hidden company readiness when
company-wise tracking is disabled; tracked projects retain the readiness check.

DATES, HOURS AND STATUS
Planned allocation hours use allocation.date. Actual hours use actualWorkDate, falling
back to allocation.date. Work planned outside the period but performed inside is
included as actual effort; work performed outside is not counted as period actuals.
Saved legacy sessions contribute their recorded half-day units x 4 hours; classification
uses the existing legacy project classification, otherwise Unclassified. Employee effort
sums all accessible attendees. Client deduction counts only Client-tagged work whose
deduction choice is not No. Internal, non-deducted client and unclassified hours remain
separate. Status/completion/go-live values are current, not reconstructed historical
snapshots. Activities appear if their baseline overlaps the period, they have period
work, or their status history was updated in the period.
Unallocated baseline effort is not added to planned allocation hours, avoiding double
counting. Existing project-plan views retain baseline versus actual implementation effort.

AMC, OFFICE, MOBILE AND EXPORT
AMC monitoring shows activity/employee effort without implementation progress or go-live
percentages. Its contract requirements remain at project level in AMC Plan vs Actual;
company effort does not split or duplicate contractual required visits/hours. Office
work has no baseline plan. The mobile Project status screen uses the same monitoring
scope/date controls and retains the AMC contract delivery section where permitted.
Export Excel respects the current project, company scope and dates; project-level
exports contain no Company column or company worksheet. Invalid dates show a message.
The client-ready PSR remains consolidated and does not inherit report company filters.

PERMISSIONS / DATA
Monitoring uses the existing accessible project/task/allocation permissions and saved
shared snapshot. It does not grant broader access or write task/actual data. Existing
allocation, billing, timesheet, user, CR and approval workflows remain. No SQL migration
or SQL update script is required; existing records already store all source data.

LOCAL IIS UPDATE FROM v57
1. Back up the publish folder and SQL database.
2. Stop the MyProjectManagement application pool.
3. Copy the update ZIP's publish CONTENTS into the existing IIS publish folder.
   Preserve appsettings*.json, web.config and protected keys. The delta excludes these
   publish configuration files. Do not copy its source folder into the live site.
4. Restart the pool and hard-refresh/reopen the browser. Confirm Version 58.1 / health 58.1.0.
Use the full package for older versions with existing configuration and SQL prerequisites.
Do not rerun initial owner/database setup on an existing workspace. To roll back, stop
the pool and restore the backed-up v57 publish folder; no schema rollback is needed.
The earlier v52 rollback remains paused.

VALIDATION
Monitoring tests cover company reconciliation, weighted progress, period boundaries,
legacy sessions, billing classifications, stale-scope reset, hidden fields/exports,
report filters, PSR isolation, AMC/Office semantics, permissions and the actual mobile
status route. Existing browser, login security and CR/planning checks also run.
Verify against your own local IIS/SQL staging data before production use.

FIRST-LOAD FIX
v58.1 displays Project monitoring navigation immediately on initial desktop load,
while preserving the existing SQL sign-in and password-change gate. It includes all
v58 monitoring changes. The update package supports both v57 and v58 installations.
