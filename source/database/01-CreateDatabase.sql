SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
-- Microsoft SQL Server 2022 / 2025. Run in SSMS as a database administrator.
-- This is T-SQL, not the former PostgreSQL/Supabase setup script.
IF DB_ID(N'MyProjectManagement') IS NULL EXEC(N'CREATE DATABASE [MyProjectManagement]');
GO
USE [MyProjectManagement];
GO
IF OBJECT_ID(N'dbo.Workspaces',N'U') IS NULL
CREATE TABLE dbo.Workspaces(
 Id uniqueidentifier NOT NULL CONSTRAINT PK_Workspaces PRIMARY KEY,
 Name nvarchar(120) NOT NULL, OwnerId uniqueidentifier NOT NULL,
 Revision bigint NOT NULL CONSTRAINT DF_Workspaces_Revision DEFAULT(0),
 SettingsJson nvarchar(max) NOT NULL CONSTRAINT CK_Workspaces_Settings CHECK(ISJSON(SettingsJson)=1),
 CreatedAt datetime2(0) NOT NULL CONSTRAINT DF_Workspaces_Created DEFAULT(SYSUTCDATETIME())
);
GO
IF OBJECT_ID(N'dbo.AppUsers',N'U') IS NULL
CREATE TABLE dbo.AppUsers(
 Id uniqueidentifier NOT NULL CONSTRAINT PK_AppUsers PRIMARY KEY,
 WorkspaceId uniqueidentifier NOT NULL CONSTRAINT FK_AppUsers_Workspace REFERENCES dbo.Workspaces(Id),
 Email nvarchar(254) NOT NULL, EmailNormalized nvarchar(254) NOT NULL,
 PasswordHash nvarchar(1000) NOT NULL, MemberId nvarchar(100) NULL,
 IsOwner bit NOT NULL CONSTRAINT DF_AppUsers_Owner DEFAULT(0),
 Disabled bit NOT NULL CONSTRAINT DF_AppUsers_Disabled DEFAULT(0),
 MustChangePassword bit NOT NULL CONSTRAINT DF_AppUsers_Change DEFAULT(1),
 FailedAttempts int NOT NULL CONSTRAINT DF_AppUsers_Failures DEFAULT(0),
 LockedUntil datetime2(0) NULL,
 SecurityStamp uniqueidentifier NOT NULL CONSTRAINT DF_AppUsers_Stamp DEFAULT(NEWID()),
 CONSTRAINT UQ_AppUsers_Email UNIQUE(EmailNormalized)
);
GO
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name=N'UX_AppUsers_Member' AND object_id=OBJECT_ID(N'dbo.AppUsers'))
 CREATE UNIQUE INDEX UX_AppUsers_Member ON dbo.AppUsers(WorkspaceId,MemberId) WHERE MemberId IS NOT NULL;
GO
IF OBJECT_ID(N'dbo.TeamMembers',N'U') IS NULL
CREATE TABLE dbo.TeamMembers(
 WorkspaceId uniqueidentifier NOT NULL CONSTRAINT FK_TeamMembers_Workspace REFERENCES dbo.Workspaces(Id),
 MemberId nvarchar(100) NOT NULL,
 Payload nvarchar(max) NOT NULL CONSTRAINT CK_TeamMembers_Payload CHECK(ISJSON(Payload)=1),
 CONSTRAINT PK_TeamMembers PRIMARY KEY(WorkspaceId,MemberId)
);
GO
IF OBJECT_ID(N'dbo.WorkspaceRecords',N'U') IS NULL
CREATE TABLE dbo.WorkspaceRecords(
 WorkspaceId uniqueidentifier NOT NULL CONSTRAINT FK_Records_Workspace REFERENCES dbo.Workspaces(Id),
 Kind varchar(12) NOT NULL CONSTRAINT CK_Records_Kind CHECK(Kind IN('project','task','meeting','activity')),
 RecordId nvarchar(100) NOT NULL,
 Payload nvarchar(max) NOT NULL CONSTRAINT CK_Records_Payload CHECK(ISJSON(Payload)=1),
 CONSTRAINT PK_WorkspaceRecords PRIMARY KEY(WorkspaceId,Kind,RecordId)
);
GO
-- Read-only views for SQL reporting. Application writes go through the ASP.NET API.
CREATE OR ALTER VIEW dbo.vwProjectTasks AS
SELECT WorkspaceId,RecordId AS TaskId,JSON_VALUE(Payload,'$.project') AS ProjectId,
 JSON_VALUE(Payload,'$.companyId') AS CompanyId,JSON_VALUE(Payload,'$.module') AS Module,
 JSON_VALUE(Payload,'$.title') AS Activity,JSON_VALUE(Payload,'$.assignee') AS PrimaryEmployeeId,
 JSON_VALUE(Payload,'$.status') AS Status,TRY_CONVERT(decimal(10,2),JSON_VALUE(Payload,'$.completion')) AS CompletionPercent,
 TRY_CONVERT(date,JSON_VALUE(Payload,'$.plannedStart')) AS PlannedStart,
 TRY_CONVERT(date,JSON_VALUE(Payload,'$.plannedFinish')) AS PlannedFinish,
 TRY_CONVERT(date,JSON_VALUE(Payload,'$.actualStart')) AS ActualStart,
 TRY_CONVERT(date,JSON_VALUE(Payload,'$.actualFinish')) AS ActualFinish,
 TRY_CONVERT(decimal(18,4),JSON_VALUE(Payload,'$.plannedSessions'))*4 AS PlannedHours
FROM dbo.WorkspaceRecords WHERE Kind='task';
GO
CREATE OR ALTER VIEW dbo.vwDailyAllocations AS
SELECT r.WorkspaceId,r.RecordId AS TaskId,a.AllocationId,a.EmployeeId,a.AllocationDate,TRY_CONVERT(date,NULLIF(a.ActualWorkDate,'')) AS ActualWorkDate,a.WorkMode,a.ChargeType,
 a.PlannedStart,a.PlannedEnd,t.ActualStart,t.ActualEnd,a.Status,a.Remarks,a.UpdatedBy,
 CAST((DATEDIFF(minute,a.PlannedStart,a.PlannedEnd)-COALESCE(a.PlannedBreak,0))/60.0 AS decimal(18,2)) AS PlannedHours,
 CAST(CASE WHEN t.ActualStart IS NOT NULL AND t.ActualEnd IS NOT NULL THEN (DATEDIFF(minute,t.ActualStart,t.ActualEnd)-COALESCE(a.ActualBreak,0))/60.0 ELSE COALESCE(a.DeliveredUnits,0)*4 END AS decimal(18,2)) AS ActualHours
FROM dbo.WorkspaceRecords r CROSS APPLY OPENJSON(r.Payload,'$.allocations') WITH(
 AllocationId nvarchar(100) '$.id', EmployeeId nvarchar(100) '$.assignee',
 AllocationDate date '$.date',ActualWorkDate nvarchar(10) '$.actualWorkDate',WorkMode nvarchar(20) '$.workMode',ChargeType nvarchar(20) '$.chargeType',
 PlannedStart time '$.plannedStartTime',PlannedEnd time '$.plannedEndTime',PlannedBreak int '$.plannedBreakMinutes',
 ActualStartText nvarchar(8) '$.actualStartTime',ActualEndText nvarchar(8) '$.actualEndTime',ActualBreak int '$.actualBreakMinutes',DeliveredUnits decimal(8,2) '$.deliveredUnits',
 Status nvarchar(60) '$.status',Remarks nvarchar(4000) '$.completionRemarks',UpdatedBy nvarchar(100) '$.actualSavedBy'
) a OUTER APPLY (SELECT TRY_CONVERT(time,NULLIF(a.ActualStartText,'')) AS ActualStart,TRY_CONVERT(time,NULLIF(a.ActualEndText,'')) AS ActualEnd) t WHERE r.Kind='task';
GO
-- Example reporting:
-- SELECT * FROM dbo.vwProjectTasks;
-- SELECT AllocationDate,EmployeeId,ChargeType,SUM(ActualHours) ActualHours FROM dbo.vwDailyAllocations GROUP BY AllocationDate,EmployeeId,ChargeType;
-- Grant your IIS service identity only required table CRUD and reporting SELECT.
-- No sa or db_owner credentials are needed by the application runtime.
