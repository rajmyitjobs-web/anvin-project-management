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


-- My Project Management: User/Role masters and code capacities.
-- SQL Server 2022/2025. Run in SSMS as a database administrator.
-- Back up the database first; stop the IIS application pool during the upgrade.
-- Existing IDs, codes, assignments, passwords and permissions are retained.
USE [MyProjectManagement];
GO
SET XACT_ABORT ON;
BEGIN TRY
 BEGIN TRANSACTION;
 IF OBJECT_ID(N'dbo.Workspaces',N'U') IS NULL
    OR OBJECT_ID(N'dbo.AppUsers',N'U') IS NULL
    OR OBJECT_ID(N'dbo.TeamMembers',N'U') IS NULL
    OR OBJECT_ID(N'dbo.WorkspaceRecords',N'U') IS NULL
    THROW 51000, 'Base tables are missing. Run 01-CreateDatabase.sql first.', 1;
 -- Existing JSON storage is nvarchar(max). No destructive column alteration is required.
 -- Field contracts: project code nvarchar(50); activity code/name nvarchar(140).
 IF EXISTS (SELECT 1 FROM dbo.WorkspaceRecords WHERE Kind='project'
     AND LEN(JSON_VALUE(Payload,'$.code'))>50)
    THROW 51001, 'An existing project code exceeds 50 characters. Review it before upgrading.', 1;
 IF EXISTS (SELECT 1 FROM dbo.Workspaces w
     CROSS APPLY OPENJSON(w.SettingsJson,'$.activityMaster')
     WITH (Code nvarchar(max) '$.code', Name nvarchar(max) '$.name') a
     WHERE LEN(a.Code)>140 OR LEN(a.Name)>140)
    THROW 51002, 'An existing activity code or name exceeds 140 characters. Review it before upgrading.', 1;
 IF EXISTS (SELECT WorkspaceId,UPPER(JSON_VALUE(Payload,'$.code'))
     FROM dbo.WorkspaceRecords WHERE Kind='project'
     AND NULLIF(JSON_VALUE(Payload,'$.code'),'') IS NOT NULL
     GROUP BY WorkspaceId,UPPER(JSON_VALUE(Payload,'$.code')) HAVING COUNT(*)>1)
    THROW 51003, 'Duplicate project codes exist within a workspace. Review duplicates before upgrading.', 1;
 DECLARE @roles nvarchar(max)=N'[
 {"name":"Project manager","code":"PM","label":"Project manager","baseRole":"Project manager","active":true,"description":"Project delivery management"},
 {"name":"Project lead","code":"PL","label":"Project lead","baseRole":"Project lead","active":true,"description":"Assigned project leadership"},
 {"name":"ERP consultant","code":"CONS","label":"Consultant","baseRole":"ERP consultant","active":true,"description":"Assigned implementation activities"}]';
 UPDATE dbo.Workspaces
 SET SettingsJson=JSON_MODIFY(SettingsJson,'$.roleMaster',JSON_QUERY(@roles)),
     Revision=Revision+1
 WHERE JSON_QUERY(SettingsJson,'$.roleMaster') IS NULL;
 COMMIT TRANSACTION;
END TRY
BEGIN CATCH
 IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
 THROW;
END CATCH;
GO
-- Reporting views reflect the same canonical JSON data the application updates.
CREATE OR ALTER VIEW dbo.vwRoleMaster AS
SELECT w.Id AS WorkspaceId,r.RoleKey,r.RoleCode,r.RoleName,r.BaseRole,r.Active,r.Description,
       JSON_QUERY(w.SettingsJson,'$.rolePermissions') AS WorkspaceRolePermissionsJson
FROM dbo.Workspaces w
CROSS APPLY OPENJSON(w.SettingsJson,'$.roleMaster') WITH (
 RoleKey nvarchar(60) '$.name',RoleCode nvarchar(30) '$.code',
 RoleName nvarchar(80) '$.label',BaseRole nvarchar(60) '$.baseRole',
 Active bit '$.active',Description nvarchar(1000) '$.description') r;
GO
CREATE OR ALTER VIEW dbo.vwRolePermissions AS
SELECT w.Id AS WorkspaceId,CONVERT(nvarchar(60),roles.[key]) AS RoleKey,
       CONVERT(nvarchar(60),flags.[key]) AS PermissionCode,
       CONVERT(bit,CASE WHEN flags.[value]='true' THEN 1 ELSE 0 END) AS Allowed
FROM dbo.Workspaces w
CROSS APPLY OPENJSON(w.SettingsJson,'$.rolePermissions') roles
CROSS APPLY OPENJSON(roles.[value]) flags;
GO
CREATE OR ALTER VIEW dbo.vwUserMaster AS
SELECT m.WorkspaceId,m.MemberId,
 CONVERT(nvarchar(80),JSON_VALUE(m.Payload,'$.name')) AS UserName,
 CONVERT(nvarchar(254),JSON_VALUE(m.Payload,'$.email')) AS ProfileEmail,
 CONVERT(nvarchar(60),JSON_VALUE(m.Payload,'$.role')) AS RoleKey,
 COALESCE(TRY_CONVERT(bit,CASE JSON_VALUE(m.Payload,'$.active') WHEN 'true' THEN '1' WHEN 'false' THEN '0' END),1) AS ProfileActive,
 r.RoleName,r.Active AS RoleActive,u.Id AS LoginId,u.Email AS LoginEmail,
 u.Disabled AS LoginDisabled,u.MustChangePassword
FROM dbo.TeamMembers m
LEFT JOIN dbo.AppUsers u ON u.WorkspaceId=m.WorkspaceId AND u.MemberId=m.MemberId
LEFT JOIN dbo.vwRoleMaster r ON r.WorkspaceId=m.WorkspaceId
 AND r.RoleKey=JSON_VALUE(m.Payload,'$.role');
GO
CREATE OR ALTER VIEW dbo.vwProjectMaster AS
SELECT WorkspaceId,RecordId AS ProjectId,
 CONVERT(nvarchar(50),JSON_VALUE(Payload,'$.code')) AS ProjectCode,
 CONVERT(nvarchar(90),JSON_VALUE(Payload,'$.name')) AS ProjectName,
 JSON_VALUE(Payload,'$.lead') AS ProjectInchargeId,
 TRY_CONVERT(date,JSON_VALUE(Payload,'$.start')) AS PlannedStart,
 TRY_CONVERT(date,JSON_VALUE(Payload,'$.due')) AS TargetGoLive
FROM dbo.WorkspaceRecords WHERE Kind='project';
GO
CREATE OR ALTER VIEW dbo.vwActivityMaster AS
SELECT w.Id AS WorkspaceId,a.ActivityId,a.ActivityCode,a.ActivityName,
 a.Description,a.Active
FROM dbo.Workspaces w
CROSS APPLY OPENJSON(w.SettingsJson,'$.activityMaster') WITH (
 ActivityId nvarchar(100) '$.id',ActivityCode nvarchar(140) '$.code',
 ActivityName nvarchar(140) '$.name',Description nvarchar(1000) '$.description',
 Active bit '$.active') a;
GO
-- Reporting permissions for the previously configured local IIS pool identity.
-- Application writes still use the existing four tables and the API.
IF DATABASE_PRINCIPAL_ID(N'IIS APPPOOL\MyProjectManagement') IS NOT NULL
BEGIN
 GRANT SELECT ON dbo.vwRoleMaster TO [IIS APPPOOL\MyProjectManagement];
 GRANT SELECT ON dbo.vwRolePermissions TO [IIS APPPOOL\MyProjectManagement];
 GRANT SELECT ON dbo.vwUserMaster TO [IIS APPPOOL\MyProjectManagement];
 GRANT SELECT ON dbo.vwProjectMaster TO [IIS APPPOOL\MyProjectManagement];
 GRANT SELECT ON dbo.vwActivityMaster TO [IIS APPPOOL\MyProjectManagement];
END;
GO
-- Verify the capacities and mappings without exposing password hashes.
SELECT v.name AS ViewName,c.name AS ColumnName,t.name AS DataType,
       c.max_length/2 AS MaximumCharacters
FROM sys.views v JOIN sys.columns c ON c.object_id=v.object_id
JOIN sys.types t ON t.user_type_id=c.user_type_id
WHERE (v.name='vwProjectMaster' AND c.name='ProjectCode')
   OR (v.name='vwActivityMaster' AND c.name IN ('ActivityCode','ActivityName'));
SELECT WorkspaceId,RoleCode,RoleName,BaseRole,Active FROM dbo.vwRoleMaster;
SELECT WorkspaceId,RoleKey,PermissionCode,Allowed FROM dbo.vwRolePermissions;
GO
