-- My Project Management v48: read-only compatibility check. No schema migration.
-- Run in the application's existing SQL Server database; does not change passwords or accounts.
IF OBJECT_ID(N'dbo.AppUsers', N'U') IS NULL
 THROW 50000, 'AppUsers is missing. Use the appropriate base database setup before installing v48.', 1;
IF COL_LENGTH(N'dbo.AppUsers',N'PasswordHash') IS NULL
 OR COL_LENGTH(N'dbo.AppUsers',N'SecurityStamp') IS NULL
 OR COL_LENGTH(N'dbo.AppUsers',N'MustChangePassword') IS NULL
 OR COL_LENGTH(N'dbo.AppUsers',N'FailedAttempts') IS NULL
 OR COL_LENGTH(N'dbo.AppUsers',N'LockedUntil') IS NULL
 THROW 50001, 'Required existing authentication columns are missing. Review the base database upgrade.', 1;
SELECT DB_NAME() AS DatabaseName, N'v48 authentication columns present; no migration required' AS Result;
