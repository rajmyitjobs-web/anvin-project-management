My Project Management v53 / 53.0.0 — 26 November 2026, Qatar

PROJECT MASTER
Company Count remains in Project Master. Business Unit Count is retained when already stored
and is available on create/edit. Company-wise Project Tracking Required is a project-level
checkbox, saved with the counts in the project's existing JSON record. It is independent of
other projects. New projects default to unchecked; legacy projects with multiple companies
show checked until explicitly saved otherwise. A missing Business Unit Count displays 0.
This release stores the flag without changing daily allocations, billing, reporting or plan logic.
Unchecking it does not remove companies or their history.

Company names, company-level module consultants and go-live details are now maintained in
Masters & Setup > Project company master. Project detail shows a summary and an Open master
button instead of the detailed editable company cards. Project-wide module defaults and
people assignments remain in Project Master; they no longer edit company overrides.

PROJECT COMPANY MASTER
Select a project to see only its companies. Existing company cards retain editing, go-live,
plan/template and activity links. Use Edit / go-live to configure placeholder company names,
module consultants and readiness. Adding a company also updates the project's Company Count.
Increasing Company Count in Project Master reserves named placeholder company records;
existing company IDs, names, consultants, dates and plans stay unchanged. Counts cannot be
reduced below existing company records, preserving their history.

Use Add missing project modules to companies when wanted. It adds only missing modules,
preserves existing company consultant overrides and actual dates, and sets company readiness
to Not ready when a new module is added. Detailed configuration is no longer done in the
project create/edit form. Existing Excel import formats remain unchanged.

PERMISSIONS / DATA
Existing project visibility and Manage project plans permission apply. Read-only staff can
view accessible project companies but cannot edit them. No new broad role permission is added.
Project fields: companyCount, businessUnitCount, companyWiseProjectTrackingRequired.
Company details stay in the existing project.companies list: this UI separation does not move
or duplicate database records. Existing company/task IDs remain linked.

LOCAL IIS UPDATE FROM v52
Back up publish folder/database, then stop MyProjectManagement application pool. Copy the
update ZIP's publish CONTENTS into your existing IIS publish folder. Preserve appsettings*.json,
web.config and protected keys (excluded from the delta). Restart the pool and refresh/reopen
browser/mobile. Confirm Version 53 / health 53.0.0. NO SQL schema migration is required.
Use the full package for older installations, preserving local configuration and prerequisites.
Rollback: restore the backed-up v52 publish folder while stopped. New fields remain in JSON;
older UI cannot edit them. Do not restore a DB backup unless you intend to discard newer data.

CHECKS
Tests cover counts/checkbox validation and saving, removed detail inputs, selected-project
master navigation/editing, retained IDs/overrides/go-live dates/tasks, missing-module defaults
and read-only controls. Existing login, CR, user provisioning, delegation and shared-save
regressions remain. Verify one project and its existing allocation links on local IIS after update.
