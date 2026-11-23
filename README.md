# My Project Management v48

ASP.NET Core 10 and Microsoft SQL Server application for ERP implementation teams.
Source code is in `source/`. The desktop and installable mobile companion share the same company login, role permissions and database.

## Included in v48

- Selected login security controls: stronger new/reset passphrases, old hash upgrades, login throttling, secure cookies, HTTPS/CSRF/headers and cross-device logout revocation with browser cleanup.
- Isolated actual-application HTTP integration tests and browser logout tests. Existing passwords remain valid until changed/reset.

- New Implementation plan Excel template matching activity / working-day start / planned days / sessions.
- Client or Us responsibilities, multiple employees and linked weekly schedules, daily allocations and calendar entries.
- Display-only phase headings and totals, editable import validation and duplicate protection.
- Separate New Implementation Project Master template without AMC details (v46).

- Customer Master and Project Master Excel/CSV imports with editable previews, reference lists and atomic validation.
- Project/company/module ownership, multiple consultants, activity planning and project status reports.
- AMC visit/hour compliance and explicit start/end period editing with contract history.
- Office direct allocations and actual updates, instant self-work, persistent pending sign-off tasks and employee timesheets.
- Mobile daily work, actuals, meetings, weekly site visits, project status and timesheets at `/mobile.html`.
- Change-request technical feasibility approval and protected Word document revisions.

## Build and publish to IIS

Install the .NET 10 SDK, then run from this repository root:

```sh
dotnet publish source/MyProjectManagement.csproj -c Release -r win-x64 --self-contained false -p:UseAppHost=false -o publish
```

Deploy the contents of `publish/` to IIS with the ASP.NET Core Hosting Bundle installed. Preserve existing runtime configuration, authentication key storage and database backups during upgrades.
Configure `ConnectionStrings__Default` and `DataProtection__KeyPath` on the server. The committed JSON settings are blank/placeholders; do not commit real SQL credentials, local environment settings, authentication keys or runtime data.

See [IIS instructions](source/DEPLOY-IIS-SQLSERVER.txt), [v47 update guide](source/INSTALL-v47-IMPLEMENTATION-PLAN.txt) and [version history](source/VERSION-HISTORY.md).

## Database and Excel imports

Existing v35+ databases need no new tables for v47. The optional [New Implementation plan reporting view](source/database/16-Implementation-Plan-v47.sql) exposes project baseline rows without changing business data. The optional [AMC period reporting view](source/database/15-AMC-Periods-v45.sql) does not modify business data. [Cumulative upgrade](source/database/Database-Upgrade-v47.sql) and [fresh setup](source/database/Database-Full-Setup-v47.sql) scripts are included; review the guide and back up the database before applying upgrades. Full setup is intended for a fresh database.

Import customers first, then projects. Download current reference templates from Customer Master or Projects. Blank [Customer Master](source/wwwroot/templates/Customer-Master-Upload-Template-v45.xlsx) and [Project Master](source/wwwroot/templates/Project-Master-Upload-Template-v45.xlsx) templates are also included. Existing codes are not overwritten.

## AMC period updates

Projects > AMC contract periods > Update AMC period. End-only changes retain the contract identity and visit links. Changing the start creates a new term and preserves contract history; existing task and actual records are retained.

## Install on iPhone or Android

Open the company HTTPS application URL followed by `/mobile.html`. iPhone: Safari > Share > Add to Home Screen. Android: Chrome > Install app / Add to Home screen. This is a PWA rather than an APK/IPA. A trusted certificate and access to the company server/network/VPN are required. See [mobile setup](source/MOBILE-SETUP-v45.txt).

## Existing Azure pilot workflow

The existing `.github/workflows/azure-pilot.yml` builds Windows x86 for the pilot. Pull requests run the build; pushes to `main` also deploy through Azure OIDC using repository settings. Runtime database configuration stays outside the repository. The workflow has been preserved.

## Validation

The v45 source was checked with .NET builds, policy/SQL syntax tests and DOM workflow tests for imports, AMC dates, mobile/quick work and pending tasks. Live IIS/SQL and physical phone acceptance testing remain necessary after deployment. Authentication keys, database contents and compiled releases are excluded from source publication.

## New Implementation project plans (v47)

Open Project plan, select a New Implementation project, then Upload / enter project plan. Choose company, kickoff date and working week. PLAN START is a working-day number; one session equals four hours. Client activities create tracked dependencies without employee allocations. Heading and Total rows do not create work. Us activities create daily allocations for every selected employee, with the same records feeding weekly schedules and calendar. Actual updates feed timesheets and retain the shared-session client-deduction decision.

Download the [formatted Excel plan template](source/wwwroot/templates/New-Implementation-Project-Plan-v47.xlsx). Use active activity codes and semicolon-separated employee IDs/names/emails, or correct them in the editable preview. The sample totals our 21 days / 42 sessions, excluding client work and headings. Duplicate rows are rejected; reschedule generated work through Daily allocations while retaining baseline dates. AMC and Office workflows remain unchanged.

Documentation: [user manual PDF](source/wwwroot/manual/User-Manual-v47.pdf), [process flow PDF](source/wwwroot/manual/Process-Flow-v47.pdf), and [HTML manual](source/wwwroot/manual/index.html).

Automated policy, import, date calculation, multi-person schedule, calendar and SQL syntax checks passed for v47. The application was published for Windows IIS locally; production IIS/SQL connectivity requires verification in your environment.

## Login security — v48

See [security instructions](source/INSTALL-v48-LOGIN-SECURITY.txt) and [updated checklist](docs/security/Login-Security-Checklist-v48.csv). New/reset passphrases require 15–128 characters and pass a local common-password blocklist; existing passwords continue to work. Logout ends existing sessions for that user across devices. There is no database schema migration. MFA and other unselected review items remain pending. Proxy client-IP handling, multiple-instance throttling, production credentials, SQL-backed authentication and infrastructure permissions still require deployment-specific verification.

Run the isolated HTTP tests (synthetic account store; no production database):

```sh
dotnet run --project tests/SecurityTests/SecurityTests.csproj
```

Run browser logout tests with Node.js 24:

```sh
npm ci --prefix tests/browser
npm test --prefix tests/browser
```

The GitHub workflow runs both before packaging/deployment.
