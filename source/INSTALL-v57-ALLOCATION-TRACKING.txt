My Project Management v57 / 57.0.0 — 26 November 2026 (Qatar)

ACTIVITY AND TASK ALLOCATION
Company-wise Project Tracking Required is saved in Projects > Edit project.
When ticked, select a company from that project's Project Company Master to allocate
new work. The module list follows the selected company. Daily allocations, quick
self-work and follow-up/sign-off forms require an explicit company selection.
When unticked, Company is hidden and not required. New work uses the project module
list. No company data needs to be entered. An internal compatibility link is retained
so daily allocations, calendar entries, actuals and employee timesheets keep working.
Existing tasks keep their saved company IDs when tracking is turned off. Editing a
schedule or adding an allocation to an existing task does not reassign its history.

DAILY / MOBILE
Create task and allocation together as before, with one activity date and planned
hours and multiple people where required. Existing planned-task choices are filtered
by the selected company in tracking mode. Choosing an existing task loads its scope;
inconsistent project/company/module/activity combinations cannot be submitted.
Quick work follows the same setting and still allocates only to the signed-in person.
Sign-off/follow-up tasks also follow the setting and remain pending until completed;
completion-only tasks continue to generate no timesheet hours.
The mobile app uses the same allocation forms. Tracked company names appear on daily
allocation rows/mobile task cards. Project-level rows do not show internal company names.
Actual-hours, client-deduction choices, employee timesheets and permission rules remain.

WEEKLY ALLOCATION
The weekly worksheet requires Company only on rows for company-tracked projects.
Project-level rows show Project level without a company selector. Different companies
are not grouped into one task, even when their activity/date/time match.
AMC suggestions for tracked projects need a company selected before saving.
The mixed-project weekly Excel template retains a Company column because one file may
contain both tracking modes. For project-level rows leave it blank; the column may be
omitted if all rows are project-level. Tracked rows must provide a registered company
ID, code or name. The editable preview has no Company selector on project-level rows.
Project-plan Excel templates continue to use the v55.1 project-specific columns.

SERVER VALIDATION / DATA
Server saves validate the project setting and company/module scope. New project-level
work uses the stable internal company link, ignoring supplied company overrides.
Existing saved tasks/actuals retain their original links. Existing role permissions,
activity types, statuses, project plans, AMC/Office rules and CR approvals remain.
No SQL schema migration or SQL update script is required: existing task JSON fields
already store company and project IDs. No production data has been deleted or reset.

LOCAL IIS UPDATE FROM v56
1. Back up the publish folder and SQL database.
2. Stop the MyProjectManagement application pool.
3. Copy the update ZIP's publish CONTENTS into the existing IIS publish folder.
   Preserve appsettings*.json, web.config and protected key storage. The update ZIP
   excludes publish configuration. Do not copy its source folder into the site.
4. Restart the pool and hard-refresh/reopen the browser. Confirm Version 57 / health 57.0.0.
Use the full package for older versions, preserving existing configuration and SQL
prerequisites. Do not rerun owner/database initialization for an existing workspace.
Rollback: stop the pool and restore the backed-up v56 publish folder; no schema rollback
is needed. The earlier v52 rollback remains paused.

VALIDATION
Tests cover required/hidden company fields, project/company modules, multi-person
allocations, historical links, actual hours and client billing, self-work, sign-off,
company-separated weekly allocation, optional weekly Company data and real task-save
policy validation. Existing browser, login security and CR/planning regressions run.
Verify saving against your own local IIS/SQL staging copy before production use.
