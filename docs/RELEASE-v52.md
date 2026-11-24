My Project Management v52 / 52.0.0 — 24 November 2026, Qatar

WORD SERIAL NUMBERS
Mapped CRs retain the serial text from the document, including leading zeros, gaps and
values such as 007 / A.2. The editable Serial number field, preview, saved JSON and synchronized
Word document use that value. Serial numbers are not used as database keys: stable internal
point IDs retain decision/comment history when a serial is edited. Duplicate numbering across
modules is supported. New blank serials get a default number that the initiator can edit.
Numbers already overwritten by older versions cannot be recovered automatically. For an
editable draft/new revision, reload the original Word document from its document history or
upload the original again, then save. Historical submitted revisions remain unchanged.

POINT REVIEW / TRACKING
First level remains assigned Project Manager (or active authorized delegate); second remains
assigned CTO. Each numbered module/form requirement row has its own Proceed / Revision
required selection and remarks at both stages. Every point must be marked in the new form.
Revision required needs remarks. If any point requires revision, selecting overall Approve
returns it as an amendment instead; the server rejects contradictory approvals.
All points must Proceed for approval. CTO sees the current PM decisions and remarks beside
their point controls. General comments, paragraph comments and meeting requests remain.

The CR detail page starts with a Point approval tracker: serial/module/form, PM and CTO
columns, status text/color, remarks, actual reviewer and Qatar timestamp. Expand Requirement
and revision history for prior stage decisions and initiator responses. Prior comments and
amendment responses remain available below and in the approval screen. Returning creates
a new revision; it restarts PM -> CTO approval. Revision-required remarks require an initiator
response before resubmission; FYI remarks on Proceed points remain visible without requiring
a response. Earlier submitted reviews/documents are immutable.

Existing historical reviews show Legacy review when they have no point decisions; the system
does not invent decisions for them. Historical pending revisions remain compatible with the
old API, while this UI always submits per-point decisions. New/saved v52 mapped drafts enforce
per-point completion on the server. Legacy non-mapped CRs retain their existing review form.

IIS UPDATE FROM v51
Back up the publish folder and database, then stop MyProjectManagement application pool.
Copy the update ZIP's publish CONTENTS into the existing IIS publish folder. Preserve local
appsettings*.json, web.config and protected keys (excluded from the delta). Restart the pool,
refresh browser/reopen mobile app and confirm Version 52 / health version 52.0.0.
No SQL migration is needed. Serial values/point decisions are stored in existing
ChangeRequests.Payload JSON. Existing v35/v49/v50 tables and permissions remain in use.
Use the full package for older installations, preserving configuration and DB prerequisites.
Rollback: restore the backed-up v51 publish folder while stopped. Older versions cannot show
new per-point decisions, although the JSON remains. Use v52 to continue the detailed workflow.

VALIDATION
Tests cover serial preservation through import/save/Word rewrite, complete and unique point
marks, required remarks, contradictory approval rejection, targeted amendment responses,
independent stage display and browser routing. Existing security/shared-save/user/CR/delegation
checks remain. Test a real imported CR and both approvals on your IIS/SQL staging site first.
