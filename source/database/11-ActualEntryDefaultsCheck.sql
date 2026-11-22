-- My Project Management v30: read-only deployment check.
-- No migration is required: planned/actual times remain in allocation JSON.
USE [MyProjectManagement];
GO
IF OBJECT_ID(N'dbo.WorkspaceRecords',N'U') IS NULL
 THROW 51030,'WorkspaceRecords is missing. Use the full setup only for a fresh database.',1;
IF COL_LENGTH(N'dbo.WorkspaceRecords',N'Payload') IS NULL
 THROW 51031,'WorkspaceRecords.Payload is missing.',1;
SELECT DB_NAME() AS DatabaseName,N'v30 actual-entry defaults require no schema change' AS Result;
GO
