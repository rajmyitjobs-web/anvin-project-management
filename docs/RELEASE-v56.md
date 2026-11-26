My Project Management v56 / 56.0.0 — 26 November 2026 (Qatar)

PROJECT MASTER
Open Projects and click Edit project on the project row, or open the project
and click Edit project in Company configuration. Project fields, customer, stage,
manager/in-charge, modules/people, dates, Company Count, Business Unit Count and
Company-wise Project Tracking Required are saved through the existing project editor.
AMC contract fields remain available on AMC projects. Existing permission checks apply.

PROJECT COMPANY MASTER
Only accessible projects with Company-wise Project Tracking Required ticked and saved
in Project Master appear in this page's project list. Unticked projects are excluded;
a stale selection is cleared. If none qualify, instructions explain how to enable one.
Select a project, then Edit company / go-live on its existing company cards. These
include company slots already created when Project Master Company Count was saved.
Maintain company code/name, module overrides, go-live and company notes here.
Use Add business unit or Edit in the Business units table for unit details and status.
This page does not edit the project name, project settings or count limits. Change
those through Projects > Edit project. Existing companies and units count toward the
saved limits, including inactive units; increase the limit in Project Master first.
Project Master may retain/create internal company slots for compatibility with plans;
detailed names and business unit records are maintained on Project Company Master.

DATA / VALIDATION
No SQL schema migration or database update script is required. Existing JSON project
records already support these fields. Company/unit IDs, task/plan links and actuals
are retained. Unticking hides the project from company maintenance, without deleting
its saved details. Re-ticking makes those details available again. Server-side count,
tracking and permission checks remain unchanged. v55.1 planning/import mode behavior,
AMC/Office workflows and other features are retained.

LOCAL IIS UPDATE (from v55.1)
1. Back up the publish folder and SQL database.
2. Stop the MyProjectManagement application pool.
3. Copy the update ZIP's publish CONTENTS into the existing IIS publish folder.
   Preserve appsettings*.json, web.config and protected key storage. The delta ZIP
   excludes publish configuration. Do not place the ZIP's source folder in the site.
4. Restart the pool and hard-refresh/reopen the browser. Confirm Version 56 / health 56.0.0.
Use the full package for older app versions, preserving configuration and existing
SQL prerequisites. Do not rerun initial owner/database setup on an existing workspace.
Rollback: stop the pool and restore the backed-up publish folder. No schema rollback
is needed. The separately discussed v52 rollback remains paused.

VERIFICATION
Regression tests cover the project-row editor/save, tracking-only dropdown and stale
selection, company/unit editing, retained IDs/task data, count limits and read-only
roles. Existing planning, login security and change-request checks are also run.
Verify saving on a staging copy of your own local IIS/SQL database before production use.
