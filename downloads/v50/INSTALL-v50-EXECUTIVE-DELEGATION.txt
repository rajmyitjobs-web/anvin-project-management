My Project Management v50 (50.0.0) — 24 November 2026, Qatar
Upgrade from v49. Keep v49 and a database backup for rollback.

LOCAL IIS UPGRADE
1. Back up the database, current publish folder, appsettings*.json and protected keys.
2. Stop the MyProjectManagement application pool.
3. Run Database-Executive-Delegation-v50.sql in SQL Server Management Studio as administrator.
   The existing v49/v35 database must already be installed. This patch adds role defaults,
   preserves explicit permissions, and does not delete data or create accounts/passwords.
4. Copy the update ZIP's publish folder CONTENTS over your existing IIS physical folder:
   C:\inetpub\wwwroot\MyProjectManagement-IIS-SQLServer2022-2025\publish
   Keep your local appsettings*.json, web.config and keys. The update ZIP excludes them.
5. Start the application pool. Refresh browser/mobile app and confirm Version 50.
   Existing hosting bundle and SQL connection settings remain in use.

PROFILES AND RIGHTS
Under Team management / User master, add real CTO and CEO profiles with company email.
Assign the CTO or CEO role, then create their company login under SQL Server & accounts.
Do not share a manager's login. Existing initial-password-change rules still apply.
Owner configures permissions under Role permissions. Existing explicit choices are preserved;
if an existing CTO profile lacks dashboard access, enable viewExecutiveDashboard,
viewAllProjects and viewAllChangeRequests as appropriate.
CEO defaults: executive dashboard, project/team/report visibility and read-only CR oversight.
CTO defaults: the same oversight plus assigned second-level technical approval.
CEO does not add a third approval stage. CTO remains final technical approver.

CHANGE REQUESTS
Consultant, Team lead, Project lead and Project manager can initiate with project access
and createChangeRequests permission. First review is always Project Manager; second is CTO.
For CRs initiated by the project's own PM, select another active PM as first reviewer.
Create that independent manager profile first if necessary. No self-approval is permitted.
Word import, dynamic mapped forms, revision responses and prior comments remain available.

LEAVE DELEGATION
Open Authority delegation on desktop, or More > Authority delegation on mobile.
The manager selects a Project lead, one or more of their own projects, From and Through dates,
and a reason. The owner can configure this for a manager. Dates include both boundary days
in Qatar time. Future grants do not activate early. At midnight after the last day, temporary
rights expire automatically on server requests; no SQL job, role swap or login sharing is used.
The original manager assignment and access are retained. Use Revoke now for early return.
To amend a period or its projects, revoke the grant and create another; history remains.
Overlapping periods for the same manager/project are rejected. Delegates cannot chain,
extend or revoke the manager's grant. Inactive users/roles cannot act.

Delegated scope (only when the original manager has the respective permission):
project planning and task/daily allocation, weekly planning, meeting scheduling,
actual corrections, client-hour deduction choices and first-level PM CR decisions.
It does not grant account/role/master administration, project creation/deletion or CTO rights.
A delegate cannot approve a CR they initiated, nor fill PM and CTO stages on the same CR.
The CR still names its PM; decisions record the actual actor, onBehalfOf and delegation ID.
Previous manager/delegate comments remain visible during amendment review and require checking.
A project manager initiating a CR still needs another PM reviewer, even during delegation.
If the permanent project manager changes, the old manager's grants stop applying to that project.
Spreadsheet upload rights remain controlled by the existing import role permissions.

DASHBOARD DATA
Executive dashboard: currently accessible project records, daily allocations and actualHours.
Pending work excludes Completed; overdue means non-completed allocation date before today.
Actual hours are employee allocation hours (not client billable deductions or AMC visit hours).
Approval queue comes from the latest 200 accessible CRs, using each latest revision state.
Click a CR to view its form/Word and decide only at your assigned active approval stage.
Use Refresh to reload workspace and approval data. Dashboard review is read-only.
Existing project reports, AMC compliance, timesheets and team dashboards remain available
according to role permissions. Neither dashboard values nor exports grant editing authority.

DATABASE / AUDIT
No new physical table is needed. Grant records are in dbo.Workspaces.SettingsJson at
$.authorityDelegations. Review audit is in dbo.ChangeRequests.Payload, revisions[].reviews[].
The dedicated API locks the workspace, checks revision and writes transactionally.
The generic settings endpoint cannot forge, extend, remove or replace grant history.
Server date checks apply even if a stale browser still displays an old action button.

ROLLBACK
Restore the backed-up v49 publish folder while the pool is stopped. Retain your local settings
and keys. v50 reuses existing tables; v49 ignores new delegation JSON. If rolling back database
state too, restore the matching backup, understanding work after that backup will be lost.
Use the versioned v49 download; do not overwrite your known-good backup.

VALIDATION
Policy/workflow and browser tests cover scope, inclusive dates, expiry, revocation, independent
review, self-review denial, PM-to-CTO sequence and audit identity. Login security regression
checks are retained. Test real company logins and SQL persistence in your IIS staging site
before using the new approval/delegation workflow for live work.
