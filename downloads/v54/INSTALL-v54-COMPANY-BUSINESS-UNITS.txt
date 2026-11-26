My Project Management v54 / 54.0.0 — 26 November 2026, Qatar

SETUP
1. In Project Master, enter Company Count and Business Unit Count.
2. Select Company-wise Project Tracking Required and save the project.
3. Open Masters & Setup > Project Company Master and select the project.
4. Edit the company slots/names, optional company codes, module consultants and go-live data.
5. Add business units: select the parent company, code, name, Active/Inactive and notes.

ENABLEMENT
Maintenance is enabled only when the project checkbox is explicitly saved as true. Legacy
projects without a saved checkbox must opt in through Project Master. With tracking off,
the master shows a disabled notice, and both direct form calls and server-side detail changes
are blocked. Existing company/unit data stays saved. Project-level counts may still be changed;
technical company placeholders can be reserved without enabling detailed configuration.
Initial project imports remain supported; detailed maintenance afterward requires enabling.

COUNT VALIDATION
Company Count and Business Unit Count are project-wide limits. Each business unit belongs
to one company in that project. Entries cannot exceed the saved limits. The master shows
configured totals and warns if setup is incomplete. Progressive saving below the limit is allowed.
Company Master does not auto-increase counts: change limits in Project Master first.
Project Master company-count growth reserves company slots; use Edit to name/configure them.
Business Unit Count 0 means no unit can be added. All retained units, including inactive units,
count toward the limit. Counts cannot be reduced below retained records. Units are deactivated
instead of deleted so IDs/history are preserved. Company codes are unique in the project
when entered; unit codes/names are unique within each parent company.

PERMISSIONS / DATA
Existing project scope and Manage project plans permission apply. Read-only users cannot
maintain details. New units are in the project's existing JSON under businessUnits:
id, companyId, code, name, active, notes. Company codes use companies[].code. Existing company
IDs remain unchanged. No new physical SQL table or schema migration is required.
Daily allocation, timesheet, billing, CR and existing plan behavior are not extended to business
unit-level transactions in this release; this change is master maintenance and validation.

LOCAL IIS UPDATE FROM v53
Back up publish folder/database. Stop MyProjectManagement application pool. Copy the update
ZIP's publish CONTENTS into the existing publish directory, preserving appsettings*.json,
web.config and protected keys (excluded from the delta). Restart and refresh/reopen browser.
Confirm Version 54 / health 54.0.0. No SQL migration or create-admin command is needed.
For older versions use the full package, retaining local configuration and DB prerequisites.
Rollback by restoring the backed-up v53 publish folder while stopped; JSON remains in the DB.
Older versions do not enforce the new unit/enablement rules, so avoid editing these records
through an older app until upgraded again. The prepared v52 rollback was not merged/deployed.

VALIDATION
Tests cover enablement, configured caps, parent-company scope, code/name/ID uniqueness,
disabled direct edits, inactive retention, unchanged limits and placeholder count growth.
Existing user, login, CR, delegation and shared-save checks remain. Verify a selected project
and a staff account's read-only access on local IIS/SQL staging before live maintenance.
