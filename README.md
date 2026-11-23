# My Project Management v45

ASP.NET Core 10 and Microsoft SQL Server application for ERP implementation teams.
Source code is in `source/`. The desktop and installable mobile companion share the same company login, role permissions and database.

## Included in v45

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

See [IIS instructions](source/DEPLOY-IIS-SQLSERVER.txt), [v45 update guide](source/INSTALL-v45-MASTERS-AMC-PERIODS.txt) and [version history](source/VERSION-HISTORY.md).

## Database and Excel imports

Existing v44 databases need no new tables for v45. The optional [AMC period reporting view](source/database/15-AMC-Periods-v45.sql) does not modify business data. [Cumulative upgrade](source/database/Database-Upgrade-v45.sql) and [fresh setup](source/database/Database-Full-Setup-v45.sql) scripts are included; review the guide and back up the database before applying upgrades. Full setup is intended for a fresh database.

Import customers first, then projects. Download current reference templates from Customer Master or Projects. Blank [Customer Master](source/wwwroot/templates/Customer-Master-Upload-Template-v45.xlsx) and [Project Master](source/wwwroot/templates/Project-Master-Upload-Template-v45.xlsx) templates are also included. Existing codes are not overwritten.

## AMC period updates

Projects > AMC contract periods > Update AMC period. End-only changes retain the contract identity and visit links. Changing the start creates a new term and preserves contract history; existing task and actual records are retained.

## Install on iPhone or Android

Open the company HTTPS application URL followed by `/mobile.html`. iPhone: Safari > Share > Add to Home Screen. Android: Chrome > Install app / Add to Home screen. This is a PWA rather than an APK/IPA. A trusted certificate and access to the company server/network/VPN are required. See [mobile setup](source/MOBILE-SETUP-v45.txt).

## Existing Azure pilot workflow

The existing `.github/workflows/azure-pilot.yml` builds Windows x86 for the pilot. Pull requests run the build; pushes to `main` also deploy through Azure OIDC using repository settings. Runtime database configuration stays outside the repository. The workflow has been preserved.

## Validation

The v45 source was checked with .NET builds, policy/SQL syntax tests and DOM workflow tests for imports, AMC dates, mobile/quick work and pending tasks. Live IIS/SQL and physical phone acceptance testing remain necessary after deployment. Authentication keys, database contents and compiled releases are excluded from source publication.
