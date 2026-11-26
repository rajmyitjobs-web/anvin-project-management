My Project Management v59 / 59.0.0 — REVIEW CANDIDATE
Prepared 27 November 2026 (Qatar). Production deployment requires approval.

SCOPE
This is a focused update to the existing ASP.NET Core/SQL Server application, not a
regenerated application. Snapshot, Policy, WorkspaceRecords JSON, Workspaces revision,
existing company/unit/plan fields, formModal, company forms and existing UI styles
are reused. No new persistent tables, endpoints, framework or dependencies are added.
Hosting settings, web.config, appsettings, authentication keys and CI/CD workflow files
are unchanged. Existing header/mobile files receive version-label updates only.

SAFE CONFIGURATION CHANGES
Counts cannot fall below retained company/unit details. Used project/company modules
cannot be removed. Imported plan row IDs and their company/module/task links cannot
be discarded by a Project Master update. Business units referenced by saved work cannot
move to a different company. Name/code edits and unused configuration remain editable.
Turning tracking off retains company IDs and records. Turning it on checks scoped
work for resolvable company mappings; a single-company implicit legacy reference is
supported. Standalone project-level meetings need no company selection.

TRANSACTION LINKS
Activities with allocations, sessions, status history, actual dates or imported-plan
links retain their project, company, module and master activity identity. Create a new
activity for different work scope. Dates, instructions, permitted status/actual updates
and billing corrections keep existing permissions. Existing explicit deletion flows
are not changed; the new checks protect configuration edits, not unrelated modules.
Older project clients that omit configuration arrays/counts/flag/imported plan rows
retain the saved values. A legacy default company may initialize only with the same
canonical project-derived ID and project module defaults. Missing legacy module/master
identities may be materialized only with their existing implicit meaning. No bulk
remapping, truncation, transaction reset or account/password change is performed.
Client form checks mirror the safeguards for visible records; server checks use the
full workspace snapshot and remain authoritative for records not visible to a client.

SQL MIGRATION — database/20-Project-Configuration-v59.sql
The existing schema already supports these fields. The optional metadata migration
adds only missing/null project tracking/count values inside WorkspaceRecords.Payload.
Missing tracking defaults to false, matching v53-v58.1; explicit valid choices/counts
are not overwritten. Counts derive from retained details. Company/unit/plan JSON arrays
and all task/meeting/session/actual/billing/CR records are untouched. Workspace revision
increments once per affected workspace on apply, preserving shared-save concurrency.
The script uses a transaction, workspace-first locks, snapshot-hash checks, explicit
collations for JSON comparisons, rollback on failure, and mapping-preservation checks.
Reruns after successful apply should update zero records/revisions. No persistent
schema, database permission, compatibility level, hosting or security setting is changed.
SQL temporary staging tables are removed at completion. Run outside other transactions.

By default @Apply=0: PREVIEW ONLY, no persistent changes. It lists proposed metadata
changes and unresolved historical task mappings for review; it never repairs mappings
by guessing. Invalid JSON/configuration aborts without overwriting explicit values.
Use a backup/staging copy of MyProjectManagement on SQL Server 2022/2025 first. Inspect
preview output. Only after approval change @Apply to 1 in a separately reviewed copy.
Do not run initial owner/database setup on an existing workspace. The application does
not execute this script automatically, and normal operation remains compatible with
existing metadata when it has not been run.

VALIDATION / LIMITS
Automated tests cover real Policy.Apply rejection and permitted edits, legacy clients,
company/module/unit/plan links, tracking toggles, permitted actual corrections, client
form locks, preserved legacy module options, and existing allocation/monitoring/login/
change-request workflows. SQL is parsed using the SQL Server 2022 ScriptDom parser.
This environment has not executed the migration against a real SQL Server instance;
runtime staging validation and preview inspection remain required before production.

DELIVERABLE / DEPLOYMENT HOLD
The review ZIP is a delta from v58.1: changed publish files, changed source/tests/docs,
the SQL migration and a SHA-256 manifest. Publish configs and protected keys are excluded.
Source diff and checksums are supplied separately. No full application rebuild from a
new design is included. No production deployment, database migration execution, main
branch merge or CI/CD setting change is part of this review. Production remains v58.1.

After approval: back up the site/database, stop the IIS pool, copy only publish CONTENTS
into the existing folder, preserve configuration/keys, restart and refresh. Confirm
Version 59 / health 59.0.0 and validate in staging before a production cutover. SQL is
preview-first and separately approved. To revert app files, restore the prior publish
backup. Additive metadata is understood by v58.1; do not delete existing records/fields.
The earlier v52 rollback remains paused.
