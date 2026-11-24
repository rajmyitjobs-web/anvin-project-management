My Project Management v51 / 51.0.0

USER MASTER
Choose Add user + login. Enter full name, user ID (company email), role, password and confirm
password. Save user + login creates the profile and login in a single database transaction.
If password validation or login creation fails, neither new record is committed.
Use Edit user / role afterward for WhatsApp/module expertise and other profile details.
Existing users: choose Set / reset password, confirm the displayed company-email user ID,
enter and confirm the new password, then Save password.
Owner passwords remain under Change password.

Only users with Team management permission can provision credentials. A manager cannot
create/reset a role with more permissions than their own. Inactive profiles/roles cannot log in.
Passwords must be 15–128 characters and meet the existing server policy. They are salted and
hashed by the server, never stored in workspace/browser backups, and cannot be retrieved.
Staff must change an initial/reset password at first sign-in. Reset revokes existing sessions.
Show password is only a temporary input toggle; closing the form clears the password fields.

LOCAL IIS UPDATE FROM v50.1
Back up the publish folder and database. Stop the MyProjectManagement application pool.
Copy the update ZIP's publish CONTENTS into the existing IIS physical publish folder.
Keep appsettings*.json, web.config and protected keys (excluded from the delta).
Restart the pool, refresh the browser and confirm Version 51 / health version 51.0.0.
No SQL migration or create-admin command is required. Existing tables and passwords remain.
Use the full application package for an older installation, preserving local configuration.
Rollback: stop the pool and restore the backed-up v50.1 publish folder; no schema rollback.

TESTS
Workflow tests cover profile whitelisting, duplicate and role-escalation denial, no plaintext
password in workspace state; browser tests cover confirmation, rejected/successful creation,
correct selected user ID, field retention on error and password clearing. Existing login security,
CR/delegation and shared-save checks remain. Verify real account creation in your IIS staging
site before creating production user accounts.
