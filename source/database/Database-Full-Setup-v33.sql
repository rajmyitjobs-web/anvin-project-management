-- v33 grouped navigation; no schema change after v31.
-- v32 documentation release. No schema change after v31.
-- v31 hours-only activity entry
-- v30: actual-entry defaults are an application change; SQL schema unchanged from v29.
-- v29 project companies and modules
-- v28 PSR release
-- My Project Management v27
-- My Project Management v26 fresh setup.
-- v25 full setup with collation-safe joins
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


SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
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
LEFT JOIN dbo.AppUsers u ON u.WorkspaceId=m.WorkspaceId AND u.MemberId COLLATE DATABASE_DEFAULT = m.MemberId COLLATE DATABASE_DEFAULT
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


SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
-- Project stages, activity types and date-range timesheet reporting.
-- SQL Server 2022/2025. Stop the IIS pool and back up the database first.
-- Run 01 and 03 first if not already installed; the downloadable cumulative upgrade includes 03.
USE [MyProjectManagement];
GO
SET XACT_ABORT ON;
BEGIN TRY
 BEGIN TRANSACTION;
 DECLARE @affected TABLE(Id uniqueidentifier);
 DECLARE @types nvarchar(max)=N'[{"id":"implementation","name":"New Implementation","active":true},{"id":"amc","name":"AMC","active":true},{"id":"warranty","name":"Warranty","active":true},{"id":"office","name":"Office","active":true}]';
 UPDATE dbo.Workspaces SET SettingsJson=JSON_MODIFY(SettingsJson,'$.activityTypes',JSON_QUERY(@types))
 OUTPUT inserted.Id INTO @affected
 WHERE JSON_QUERY(SettingsJson,'$.activityTypes') IS NULL;
 UPDATE w SET SettingsJson=JSON_MODIFY(w.SettingsJson,'$.activityMaster',JSON_QUERY(a.Catalog))
 OUTPUT inserted.Id INTO @affected
 FROM dbo.Workspaces w
 CROSS APPLY (SELECT N'['+STRING_AGG(CONVERT(nvarchar(max),CASE WHEN NULLIF(JSON_VALUE(j.value,'$.typeId'),'') IS NULL THEN JSON_MODIFY(j.value,'$.typeId','implementation') ELSE j.value END),N',') WITHIN GROUP(ORDER BY CONVERT(int,j.[key]))+N']' AS Catalog
 FROM OPENJSON(w.SettingsJson,'$.activityMaster') j) a
 WHERE EXISTS(SELECT 1 FROM OPENJSON(w.SettingsJson,'$.activityMaster') j WHERE NULLIF(JSON_VALUE(j.value,'$.typeId'),'') IS NULL);
 UPDATE dbo.WorkspaceRecords SET Payload=JSON_MODIFY(Payload,'$.stageType','implementation')
 OUTPUT inserted.WorkspaceId INTO @affected
 WHERE Kind='project' AND NULLIF(JSON_VALUE(Payload,'$.stageType'),'') IS NULL;
 UPDATE t SET Payload=JSON_MODIFY(t.Payload,'$.typeId',COALESCE(NULLIF(JSON_VALUE(p.Payload,'$.stageType'),''),'implementation'))
 OUTPUT inserted.WorkspaceId INTO @affected
 FROM dbo.WorkspaceRecords t
 LEFT JOIN dbo.WorkspaceRecords p ON p.WorkspaceId=t.WorkspaceId AND p.Kind='project' AND p.RecordId=JSON_VALUE(t.Payload,'$.project')
 WHERE t.Kind='task' AND NULLIF(JSON_VALUE(t.Payload,'$.typeId'),'') IS NULL;
 DECLARE @allocationRows TABLE(WorkspaceId uniqueidentifier,TaskId nvarchar(100),Ordinal int,Payload nvarchar(max));
 INSERT @allocationRows(WorkspaceId,TaskId,Ordinal,Payload)
 SELECT t.WorkspaceId,t.RecordId,CONVERT(int,j.[key]),
 CASE WHEN NULLIF(JSON_VALUE(j.value,'$.typeId'),'') IS NULL
 THEN JSON_MODIFY(j.value,'$.typeId',COALESCE(NULLIF(JSON_VALUE(t.Payload,'$.typeId'),''),'implementation')) ELSE j.value END
 FROM dbo.WorkspaceRecords t CROSS APPLY OPENJSON(t.Payload,'$.allocations') j
 WHERE t.Kind='task' AND EXISTS(SELECT 1 FROM OPENJSON(t.Payload,'$.allocations') missing WHERE NULLIF(JSON_VALUE(missing.value,'$.typeId'),'') IS NULL);
 UPDATE t SET Payload=JSON_MODIFY(t.Payload,'$.allocations',JSON_QUERY(a.Allocations))
 OUTPUT inserted.WorkspaceId INTO @affected
 FROM dbo.WorkspaceRecords t JOIN (
 SELECT WorkspaceId,TaskId,N'['+STRING_AGG(CONVERT(nvarchar(max),Payload),N',') WITHIN GROUP(ORDER BY Ordinal)+N']' AS Allocations
 FROM @allocationRows GROUP BY WorkspaceId,TaskId) a
 ON a.WorkspaceId=t.WorkspaceId AND a.TaskId COLLATE DATABASE_DEFAULT = t.RecordId COLLATE DATABASE_DEFAULT
 WHERE t.Kind='task';
 UPDATE w SET Revision=Revision+1 FROM dbo.Workspaces w WHERE EXISTS(SELECT 1 FROM @affected a WHERE a.Id=w.Id);
 COMMIT TRANSACTION;
END TRY
BEGIN CATCH
 IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
 THROW;
END CATCH;
GO
CREATE OR ALTER VIEW dbo.vwActivityTypes AS
SELECT w.Id AS WorkspaceId,t.TypeId,t.TypeName,t.Active
FROM dbo.Workspaces w CROSS APPLY OPENJSON(w.SettingsJson,'$.activityTypes') WITH(
 TypeId nvarchar(40) '$.id',TypeName nvarchar(80) '$.name',Active bit '$.active') t;
GO
CREATE OR ALTER VIEW dbo.vwProjectMaster AS
SELECT r.WorkspaceId,r.RecordId AS ProjectId,
 CONVERT(nvarchar(50),JSON_VALUE(r.Payload,'$.code')) AS ProjectCode,
 CONVERT(nvarchar(90),JSON_VALUE(r.Payload,'$.name')) AS ProjectName,
 JSON_VALUE(r.Payload,'$.lead') AS ProjectInchargeId,
 TRY_CONVERT(date,JSON_VALUE(r.Payload,'$.start')) AS PlannedStart,
 TRY_CONVERT(date,JSON_VALUE(r.Payload,'$.due')) AS TargetGoLive,
 CONVERT(nvarchar(40),COALESCE(NULLIF(JSON_VALUE(r.Payload,'$.stageType'),''),'implementation')) AS StageTypeId,
 ty.TypeName AS CurrentStage
FROM dbo.WorkspaceRecords r LEFT JOIN dbo.vwActivityTypes ty ON ty.WorkspaceId=r.WorkspaceId
 AND ty.TypeId=COALESCE(NULLIF(JSON_VALUE(r.Payload,'$.stageType'),''),'implementation')
WHERE r.Kind='project';
GO
CREATE OR ALTER VIEW dbo.vwActivityMaster AS
SELECT w.Id AS WorkspaceId,a.ActivityId,a.ActivityCode,a.ActivityName,a.Description,a.Active,
 COALESCE(NULLIF(a.TypeId,''),'implementation') AS TypeId,ty.TypeName
FROM dbo.Workspaces w CROSS APPLY OPENJSON(w.SettingsJson,'$.activityMaster') WITH(
 ActivityId nvarchar(100) '$.id',ActivityCode nvarchar(140) '$.code',ActivityName nvarchar(140) '$.name',
 Description nvarchar(1000) '$.description',Active bit '$.active',TypeId nvarchar(40) '$.typeId') a
LEFT JOIN dbo.vwActivityTypes ty ON ty.WorkspaceId=w.Id AND ty.TypeId=COALESCE(NULLIF(a.TypeId,''),'implementation');
GO
CREATE OR ALTER VIEW dbo.vwTimesheetEntries AS
SELECT t.WorkspaceId,t.RecordId AS TaskId,a.AllocationId AS EntryId,
 CONVERT(nvarchar(100),JSON_VALUE(t.Payload,'$.project')) AS ProjectId,CONVERT(nvarchar(100),JSON_VALUE(t.Payload,'$.companyId')) AS CompanyId,
 CONVERT(nvarchar(100),JSON_VALUE(t.Payload,'$.activityId')) AS ActivityId,
 CONVERT(nvarchar(140),JSON_VALUE(t.Payload,'$.title')) AS ActivityName,
 CONVERT(nvarchar(60),JSON_VALUE(t.Payload,'$.module')) AS Module,
 CONVERT(nvarchar(40),COALESCE(NULLIF(a.TypeId,''),NULLIF(JSON_VALUE(t.Payload,'$.typeId'),''),'implementation')) AS TypeId,
 a.EmployeeId,a.PlannedDate,TRY_CONVERT(date,COALESCE(NULLIF(a.ActualDate,''),CONVERT(nvarchar(10),a.PlannedDate,23))) AS ActualDate,
 COALESCE(NULLIF(a.WorkMode,''),'Unclassified') AS WorkMode,COALESCE(NULLIF(a.ChargeType,''),'Unclassified') AS ChargeType,
 CONVERT(decimal(18,2),COALESCE((DATEDIFF(minute,a.PlannedStart,a.PlannedEnd)-COALESCE(a.PlannedBreak,0))/60.0,0)) AS PlannedHours,
 CONVERT(decimal(18,2),CASE WHEN x.ActualStart IS NOT NULL AND x.ActualEnd IS NOT NULL THEN (DATEDIFF(minute,x.ActualStart,x.ActualEnd)-COALESCE(a.ActualBreak,0))/60.0 ELSE COALESCE(a.DeliveredUnits,0)*4 END) AS ActualHours,
 a.Status AS CurrentEntryStatus,CONVERT(nvarchar(60),JSON_VALUE(t.Payload,'$.status')) AS CurrentActivityStatus,a.Remarks,
 CONVERT(nvarchar(20),'Daily allocation') AS EntrySource
FROM dbo.WorkspaceRecords t CROSS APPLY OPENJSON(t.Payload,'$.allocations') WITH(
 AllocationId nvarchar(100) '$.id',TypeId nvarchar(40) '$.typeId',EmployeeId nvarchar(100) '$.assignee',PlannedDate date '$.date',
 ActualDate nvarchar(10) '$.actualWorkDate',WorkMode nvarchar(20) '$.workMode',ChargeType nvarchar(20) '$.chargeType',
 PlannedStart time '$.plannedStartTime',PlannedEnd time '$.plannedEndTime',PlannedBreak int '$.plannedBreakMinutes',
 ActualStartText nvarchar(8) '$.actualStartTime',ActualEndText nvarchar(8) '$.actualEndTime',ActualBreak int '$.actualBreakMinutes',
 DeliveredUnits decimal(8,2) '$.deliveredUnits',Status nvarchar(60) '$.status',Remarks nvarchar(4000) '$.completionRemarks') a
OUTER APPLY(SELECT TRY_CONVERT(time,NULLIF(a.ActualStartText,'')) AS ActualStart,TRY_CONVERT(time,NULLIF(a.ActualEndText,'')) AS ActualEnd) x
WHERE t.Kind='task'
UNION ALL
SELECT t.WorkspaceId,t.RecordId,CONVERT(nvarchar(100),'session-'+s.[key]) COLLATE DATABASE_DEFAULT,
 CONVERT(nvarchar(100),JSON_VALUE(t.Payload,'$.project')),CONVERT(nvarchar(100),JSON_VALUE(t.Payload,'$.companyId')),CONVERT(nvarchar(100),JSON_VALUE(t.Payload,'$.activityId')),
 CONVERT(nvarchar(140),JSON_VALUE(t.Payload,'$.title')),CONVERT(nvarchar(60),JSON_VALUE(t.Payload,'$.module')),
 CONVERT(nvarchar(40),COALESCE(NULLIF(JSON_VALUE(t.Payload,'$.typeId'),''),'implementation')),
 CONVERT(nvarchar(100),COALESCE(NULLIF(JSON_VALUE(s.value,'$.assignee'),''),JSON_VALUE(t.Payload,'$.assignee'))),
 CONVERT(date,NULL),TRY_CONVERT(date,JSON_VALUE(s.value,'$.date')),CONVERT(nvarchar(20),'Unclassified'),
 CONVERT(nvarchar(20),COALESCE(NULLIF(JSON_VALUE(p.Payload,'$.legacyHoursClass'),''),'Unclassified')),CONVERT(decimal(18,2),0),
 CONVERT(decimal(18,2),COALESCE(TRY_CONVERT(decimal(8,2),JSON_VALUE(s.value,'$.units')),0)*4),
 CONVERT(nvarchar(60),JSON_VALUE(t.Payload,'$.status')),CONVERT(nvarchar(60),JSON_VALUE(t.Payload,'$.status')),CONVERT(nvarchar(4000),JSON_VALUE(s.value,'$.note')),
 CONVERT(nvarchar(20),'Legacy session')
FROM dbo.WorkspaceRecords t CROSS APPLY OPENJSON(t.Payload,'$.sessions') s
LEFT JOIN dbo.WorkspaceRecords p ON p.WorkspaceId=t.WorkspaceId AND p.Kind='project' AND p.RecordId=JSON_VALUE(t.Payload,'$.project')
WHERE t.Kind='task';
GO
CREATE OR ALTER PROCEDURE dbo.uspProjectStatusReport
 @WorkspaceId uniqueidentifier,@FromDate date,@ToDate date,
 @ProjectId nvarchar(100)=NULL,@TypeId nvarchar(40)=NULL,@WorkMode nvarchar(20)=NULL
AS
BEGIN
 SET NOCOUNT ON;
 IF @WorkspaceId IS NULL OR @FromDate IS NULL OR @ToDate IS NULL OR @FromDate>@ToDate
  THROW 51010,'Workspace and a valid inclusive date range are required.',1;
 IF @WorkMode IS NOT NULL AND @WorkMode NOT IN ('Onsite','Offsite','Unclassified')
  THROW 51011,'Use Onsite, Offsite, Unclassified or NULL for work mode.',1;
 SELECT e.WorkspaceId,e.TaskId,e.EntryId,e.ProjectId,e.CompanyId,e.ActivityId,e.ActivityName,e.Module,e.TypeId,
 p.ProjectCode,p.ProjectName,p.CurrentStage,pc.CompanyName,ty.TypeName,e.EmployeeId,m.UserName AS EmployeeName,
 e.PlannedDate,CASE WHEN e.ActualHours>0 THEN e.ActualDate END AS ActualDate,e.WorkMode,e.ChargeType,
 CONVERT(decimal(18,2),CASE WHEN e.PlannedDate BETWEEN @FromDate AND @ToDate THEN e.PlannedHours ELSE 0 END) AS PlannedHours,
 CONVERT(decimal(18,2),CASE WHEN e.ActualDate BETWEEN @FromDate AND @ToDate THEN e.ActualHours ELSE 0 END) AS ActualHours,
 e.CurrentEntryStatus,e.CurrentActivityStatus,e.Remarks,e.EntrySource
 INTO #Period
 FROM dbo.vwTimesheetEntries e LEFT JOIN dbo.vwProjectMaster p ON p.WorkspaceId=e.WorkspaceId AND p.ProjectId COLLATE DATABASE_DEFAULT = e.ProjectId COLLATE DATABASE_DEFAULT
 LEFT JOIN dbo.vwActivityTypes ty ON ty.WorkspaceId=e.WorkspaceId AND ty.TypeId COLLATE DATABASE_DEFAULT = e.TypeId COLLATE DATABASE_DEFAULT
 LEFT JOIN dbo.vwUserMaster m ON m.WorkspaceId=e.WorkspaceId AND m.MemberId COLLATE DATABASE_DEFAULT = e.EmployeeId COLLATE DATABASE_DEFAULT
 OUTER APPLY (SELECT JSON_VALUE(company.value,'$.name') AS CompanyName
 FROM dbo.WorkspaceRecords projectRecord CROSS APPLY OPENJSON(projectRecord.Payload,'$.companies') company
 WHERE projectRecord.WorkspaceId=e.WorkspaceId AND projectRecord.Kind='project'
 AND projectRecord.RecordId COLLATE DATABASE_DEFAULT = e.ProjectId COLLATE DATABASE_DEFAULT AND JSON_VALUE(company.value,'$.id')=e.CompanyId) pc
 WHERE e.WorkspaceId=@WorkspaceId AND (@ProjectId IS NULL OR e.ProjectId=@ProjectId)
 AND (@TypeId IS NULL OR e.TypeId=@TypeId) AND (@WorkMode IS NULL OR e.WorkMode=@WorkMode)
 AND (e.PlannedDate BETWEEN @FromDate AND @ToDate OR e.ActualHours>0 AND e.ActualDate BETWEEN @FromDate AND @ToDate);
 -- 1: Current project-stage portfolio; not a historical stage snapshot.
 SELECT StageTypeId,CurrentStage,COUNT_BIG(*) AS ProjectCount FROM dbo.vwProjectMaster
 WHERE WorkspaceId=@WorkspaceId AND (@ProjectId IS NULL OR ProjectId=@ProjectId)
 GROUP BY StageTypeId,CurrentStage;
 -- 2: Period totals.
 SELECT @FromDate AS FromDate,@ToDate AS ToDate,COALESCE(SUM(PlannedHours),0) AS PlannedHours,COALESCE(SUM(ActualHours),0) AS ActualHours,
 COALESCE(SUM(CASE WHEN ChargeType='Client' THEN ActualHours ELSE 0 END),0) AS ClientActualHours,
 COALESCE(SUM(CASE WHEN ChargeType='Internal' THEN ActualHours ELSE 0 END),0) AS InternalActualHours,
 COALESCE(SUM(CASE WHEN ChargeType NOT IN ('Client','Internal') THEN ActualHours ELSE 0 END),0) AS UnclassifiedActualHours FROM #Period;
 -- 3-6: Project, type, activity and mode breakdowns. These totals reconcile.
 SELECT ProjectId,ProjectCode,ProjectName,SUM(PlannedHours) AS PlannedHours,SUM(ActualHours) AS ActualHours,
 SUM(CASE WHEN ChargeType='Client' THEN ActualHours ELSE 0 END) AS ClientActualHours,
 SUM(CASE WHEN ChargeType='Internal' THEN ActualHours ELSE 0 END) AS InternalActualHours,
 SUM(CASE WHEN ChargeType NOT IN ('Client','Internal') THEN ActualHours ELSE 0 END) AS UnclassifiedActualHours
 FROM #Period GROUP BY ProjectId,ProjectCode,ProjectName;
 SELECT TypeId,TypeName,SUM(PlannedHours) AS PlannedHours,SUM(ActualHours) AS ActualHours,
 SUM(CASE WHEN ChargeType='Client' THEN ActualHours ELSE 0 END) AS ClientActualHours,
 SUM(CASE WHEN ChargeType='Internal' THEN ActualHours ELSE 0 END) AS InternalActualHours,
 SUM(CASE WHEN ChargeType NOT IN ('Client','Internal') THEN ActualHours ELSE 0 END) AS UnclassifiedActualHours
 FROM #Period GROUP BY TypeId,TypeName;
 SELECT ProjectId,TypeId,ActivityId,ActivityName,SUM(PlannedHours) AS PlannedHours,SUM(ActualHours) AS ActualHours,
 SUM(CASE WHEN ChargeType='Client' THEN ActualHours ELSE 0 END) AS ClientActualHours,
 SUM(CASE WHEN ChargeType='Internal' THEN ActualHours ELSE 0 END) AS InternalActualHours,
 SUM(CASE WHEN ChargeType NOT IN ('Client','Internal') THEN ActualHours ELSE 0 END) AS UnclassifiedActualHours
 FROM #Period GROUP BY ProjectId,TypeId,ActivityId,ActivityName;
 SELECT WorkMode,SUM(PlannedHours) AS PlannedHours,SUM(ActualHours) AS ActualHours,
 SUM(CASE WHEN ChargeType='Client' THEN ActualHours ELSE 0 END) AS ClientActualHours,
 SUM(CASE WHEN ChargeType='Internal' THEN ActualHours ELSE 0 END) AS InternalActualHours,
 SUM(CASE WHEN ChargeType NOT IN ('Client','Internal') THEN ActualHours ELSE 0 END) AS UnclassifiedActualHours
 FROM #Period GROUP BY WorkMode;
 -- 7: Activities planned, worked or updated during the period; status is CURRENT.
 SELECT r.RecordId AS TaskId,JSON_VALUE(r.Payload,'$.project') AS ProjectId,
 JSON_VALUE(r.Payload,'$.title') AS ActivityName,JSON_VALUE(r.Payload,'$.module') AS Module,
 COALESCE(NULLIF(JSON_VALUE(r.Payload,'$.typeId'),''),'implementation') AS TypeId,
 JSON_VALUE(r.Payload,'$.status') AS CurrentStatus,TRY_CONVERT(decimal(8,2),JSON_VALUE(r.Payload,'$.completion')) AS CurrentCompletionPercent,
 JSON_VALUE(r.Payload,'$.plannedStart') AS PlannedStart,JSON_VALUE(r.Payload,'$.plannedFinish') AS PlannedFinish,
 COALESCE((SELECT SUM(x.ActualHours) FROM #Period x WHERE x.TaskId COLLATE DATABASE_DEFAULT = r.RecordId COLLATE DATABASE_DEFAULT),0) AS PeriodActualHours,
 JSON_VALUE(r.Payload,'$.followupNote') AS LatestFollowup,JSON_VALUE(r.Payload,'$.nextSessionDate') AS NextSessionDate
 FROM dbo.WorkspaceRecords r WHERE r.WorkspaceId=@WorkspaceId AND r.Kind='task'
 AND (@ProjectId IS NULL OR JSON_VALUE(r.Payload,'$.project')=@ProjectId)
 AND (@TypeId IS NULL OR COALESCE(NULLIF(JSON_VALUE(r.Payload,'$.typeId'),''),'implementation')=@TypeId)
 AND (EXISTS(SELECT 1 FROM #Period x WHERE x.TaskId COLLATE DATABASE_DEFAULT = r.RecordId COLLATE DATABASE_DEFAULT)
 OR @WorkMode IS NULL AND (
 TRY_CONVERT(date,JSON_VALUE(r.Payload,'$.plannedStart'))<=@ToDate
 AND TRY_CONVERT(date,COALESCE(NULLIF(JSON_VALUE(r.Payload,'$.plannedFinish'),''),JSON_VALUE(r.Payload,'$.due')))>=@FromDate
 OR EXISTS(SELECT 1 FROM OPENJSON(r.Payload,'$.history') h
 WHERE CONVERT(date,SWITCHOFFSET(TRY_CONVERT(datetimeoffset,JSON_VALUE(h.value,'$.at')),'+03:00')) BETWEEN @FromDate AND @ToDate)));
 -- 8: Detailed timesheets.
 SELECT * FROM #Period ORDER BY COALESCE(ActualDate,PlannedDate),ProjectCode,ActivityName;
END;
GO
IF DATABASE_PRINCIPAL_ID(N'IIS APPPOOL\MyProjectManagement') IS NOT NULL
BEGIN
 GRANT SELECT ON dbo.vwActivityTypes TO [IIS APPPOOL\MyProjectManagement];
 GRANT SELECT ON dbo.vwTimesheetEntries TO [IIS APPPOOL\MyProjectManagement];
 GRANT EXECUTE ON dbo.uspProjectStatusReport TO [IIS APPPOOL\MyProjectManagement];
END;
GO
-- Example: copy an actual workspace ID and (optionally) project ID from these views.
-- SELECT Id,Name FROM dbo.Workspaces;
-- SELECT WorkspaceId,ProjectId,ProjectCode,CurrentStage FROM dbo.vwProjectMaster;
-- EXEC dbo.uspProjectStatusReport @WorkspaceId='YOUR-WORKSPACE-GUID',
--   @FromDate='2026-11-01',@ToDate='2026-11-30',@ProjectId=NULL,@TypeId=NULL,@WorkMode=NULL;
SELECT WorkspaceId,TypeId,TypeName,Active FROM dbo.vwActivityTypes;
GO


SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
-- Customers, weekly visit plans, employee timesheets and client deduction audit.
-- SQL Server 2022/2025. Stop IIS and back up the database before upgrading.
USE [MyProjectManagement];
GO
SET XACT_ABORT ON;
BEGIN TRY
 BEGIN TRANSACTION;
 DECLARE @affected TABLE(Id uniqueidentifier);
 UPDATE dbo.Workspaces SET SettingsJson=JSON_MODIFY(SettingsJson,'$.customers',JSON_QUERY('[]'))
 OUTPUT inserted.Id INTO @affected WHERE JSON_QUERY(SettingsJson,'$.customers') IS NULL;
 DECLARE @role nvarchar(60),@flag nvarchar(60),@value bit,@path nvarchar(300);
 DECLARE permission_cursor CURSOR LOCAL FAST_FORWARD FOR
 SELECT r.RoleName,f.FlagCode,CONVERT(bit,CASE WHEN r.RoleName='Project manager' OR r.RoleName='Project lead' AND f.FlagCode IN('manageWeeklyPlans','rescheduleAllocations') THEN 1 ELSE 0 END)
 FROM (VALUES(N'Project manager'),(N'Project lead'),(N'ERP consultant')) r(RoleName)
 CROSS JOIN (VALUES(N'manageCustomers'),(N'manageWeeklyPlans'),(N'rescheduleAllocations'),(N'manageClientHours')) f(FlagCode);
 OPEN permission_cursor;
 FETCH NEXT FROM permission_cursor INTO @role,@flag,@value;
 WHILE @@FETCH_STATUS=0
 BEGIN
  SET @path=N'$.rolePermissions."'+@role+N'".'+@flag;
  UPDATE dbo.Workspaces SET SettingsJson=JSON_MODIFY(SettingsJson,@path,@value)
  OUTPUT inserted.Id INTO @affected WHERE JSON_VALUE(SettingsJson,@path) IS NULL;
  FETCH NEXT FROM permission_cursor INTO @role,@flag,@value;
 END;
 CLOSE permission_cursor;DEALLOCATE permission_cursor;
 -- Retain legacy client-hour behavior; never overwrite an explicit Yes/No decision.
 DECLARE @allocationRows TABLE(WorkspaceId uniqueidentifier,TaskId nvarchar(100),Ordinal int,Payload nvarchar(max));
 INSERT @allocationRows
 SELECT t.WorkspaceId,t.RecordId,CONVERT(int,j.[key]),CASE WHEN JSON_VALUE(j.value,'$.billableToClient') IS NULL THEN JSON_MODIFY(j.value,'$.billableToClient',CONVERT(bit,1)) ELSE j.value END
 FROM dbo.WorkspaceRecords t CROSS APPLY OPENJSON(t.Payload,'$.allocations') j
 WHERE t.Kind='task' AND EXISTS(SELECT 1 FROM OPENJSON(t.Payload,'$.allocations') missing WHERE JSON_VALUE(missing.value,'$.billableToClient') IS NULL);
 UPDATE t SET Payload=JSON_MODIFY(t.Payload,'$.allocations',JSON_QUERY(a.RowsJson))
 OUTPUT inserted.WorkspaceId INTO @affected
 FROM dbo.WorkspaceRecords t JOIN(SELECT WorkspaceId,TaskId,N'['+STRING_AGG(CONVERT(nvarchar(max),Payload),N',') WITHIN GROUP(ORDER BY Ordinal)+N']' AS RowsJson FROM @allocationRows GROUP BY WorkspaceId,TaskId) a
 ON a.WorkspaceId=t.WorkspaceId AND a.TaskId COLLATE DATABASE_DEFAULT = t.RecordId COLLATE DATABASE_DEFAULT WHERE t.Kind='task';
 UPDATE w SET Revision=Revision+1 FROM dbo.Workspaces w WHERE EXISTS(SELECT 1 FROM @affected a WHERE a.Id=w.Id);
 COMMIT TRANSACTION;
END TRY
BEGIN CATCH
 IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
 THROW;
END CATCH;
GO
CREATE OR ALTER VIEW dbo.vwCustomerMaster AS
SELECT w.Id AS WorkspaceId,c.CustomerId,c.CustomerCode,c.CustomerName,c.Active
FROM dbo.Workspaces w CROSS APPLY OPENJSON(w.SettingsJson,'$.customers') WITH(
 CustomerId nvarchar(100) '$.id',CustomerCode nvarchar(50) '$.code',CustomerName nvarchar(160) '$.name',Active bit '$.active') c;
GO
CREATE OR ALTER VIEW dbo.vwProjectMaster AS
SELECT r.WorkspaceId,r.RecordId AS ProjectId,CONVERT(nvarchar(50),JSON_VALUE(r.Payload,'$.code')) AS ProjectCode,
 CONVERT(nvarchar(90),JSON_VALUE(r.Payload,'$.name')) AS ProjectName,JSON_VALUE(r.Payload,'$.lead') AS ProjectInchargeId,
 TRY_CONVERT(date,JSON_VALUE(r.Payload,'$.start')) AS PlannedStart,TRY_CONVERT(date,JSON_VALUE(r.Payload,'$.due')) AS TargetGoLive,
 CONVERT(nvarchar(40),COALESCE(NULLIF(JSON_VALUE(r.Payload,'$.stageType'),''),'implementation')) AS StageTypeId,ty.TypeName AS CurrentStage,
 CONVERT(nvarchar(100),JSON_VALUE(r.Payload,'$.customerId')) AS CustomerId,c.CustomerCode,c.CustomerName
FROM dbo.WorkspaceRecords r LEFT JOIN dbo.vwActivityTypes ty ON ty.WorkspaceId=r.WorkspaceId AND ty.TypeId=COALESCE(NULLIF(JSON_VALUE(r.Payload,'$.stageType'),''),'implementation')
LEFT JOIN dbo.vwCustomerMaster c ON c.WorkspaceId=r.WorkspaceId AND c.CustomerId=JSON_VALUE(r.Payload,'$.customerId') WHERE r.Kind='project';
GO
CREATE OR ALTER VIEW dbo.vwAllocationWorkforce AS
SELECT t.WorkspaceId,t.RecordId AS TaskId,a.AllocationId,a.WeeklyPlanId,a.WeeklyWeek,a.TeamGroupId,
 COALESCE(a.BillableToClient,CONVERT(bit,1)) AS BillableToClient,a.BillingConfirmed,a.BillingUpdatedBy,a.BillingUpdatedAt,a.Instructions
FROM dbo.WorkspaceRecords t CROSS APPLY OPENJSON(t.Payload,'$.allocations') WITH(
 AllocationId nvarchar(100) '$.id',WeeklyPlanId nvarchar(100) '$.weeklyPlanId',WeeklyWeek date '$.weeklyWeek',TeamGroupId nvarchar(100) '$.teamGroupId',
 BillableToClient bit '$.billableToClient',BillingConfirmed bit '$.billingConfirmed',BillingUpdatedBy nvarchar(100) '$.billingUpdatedBy',BillingUpdatedAt datetimeoffset '$.billingUpdatedAt',Instructions nvarchar(2000) '$.instructions') a
WHERE t.Kind='task';
GO
CREATE OR ALTER VIEW dbo.vwTimesheetBilling AS
SELECT e.WorkspaceId,e.TaskId,e.EntryId,e.ProjectId,e.CompanyId,e.ActivityId,e.ActivityName,e.Module,e.TypeId,e.EmployeeId,e.PlannedDate,e.ActualDate,e.WorkMode,
 CONVERT(nvarchar(30),CASE WHEN e.ChargeType='Client' AND a.BillableToClient=0 THEN 'Non-billable client' ELSE e.ChargeType END) AS ChargeType,
 e.PlannedHours,e.ActualHours,e.CurrentEntryStatus,e.CurrentActivityStatus,e.Remarks,e.EntrySource,
 COALESCE(a.BillableToClient,CONVERT(bit,1)) AS BillableToClient,
 CONVERT(decimal(18,2),CASE WHEN e.ChargeType='Client' AND COALESCE(a.BillableToClient,1)=1 THEN e.ActualHours ELSE 0 END) AS ClientDeductibleHours
FROM dbo.vwTimesheetEntries e LEFT JOIN dbo.vwAllocationWorkforce a ON a.WorkspaceId=e.WorkspaceId AND a.TaskId COLLATE DATABASE_DEFAULT = e.TaskId COLLATE DATABASE_DEFAULT AND a.AllocationId COLLATE DATABASE_DEFAULT = e.EntryId COLLATE DATABASE_DEFAULT;
GO
CREATE OR ALTER VIEW dbo.vwEmployeeDailyTimesheets AS
SELECT e.WorkspaceId,e.ActualDate AS WorkDate,e.EmployeeId,u.UserName AS EmployeeName,
 e.ProjectId,p.ProjectCode,p.ProjectName,p.CustomerId,p.CustomerCode,p.CustomerName,
 e.TypeId,ty.TypeName,e.ActivityId,COALESCE(am.ActivityCode,fallback.ActivityCode) AS ActivityCode,e.ActivityName,e.Module,
 e.Remarks AS Notes,e.ActualHours AS Hours,e.WorkMode,e.ChargeType,e.ClientDeductibleHours,e.TaskId,e.EntryId AS AllocationId
FROM dbo.vwTimesheetBilling e
LEFT JOIN dbo.vwProjectMaster p ON p.WorkspaceId=e.WorkspaceId AND p.ProjectId COLLATE DATABASE_DEFAULT = e.ProjectId COLLATE DATABASE_DEFAULT
LEFT JOIN dbo.vwUserMaster u ON u.WorkspaceId=e.WorkspaceId AND u.MemberId COLLATE DATABASE_DEFAULT = e.EmployeeId COLLATE DATABASE_DEFAULT
LEFT JOIN dbo.vwActivityTypes ty ON ty.WorkspaceId=e.WorkspaceId AND ty.TypeId COLLATE DATABASE_DEFAULT = e.TypeId COLLATE DATABASE_DEFAULT
LEFT JOIN dbo.vwActivityMaster am ON am.WorkspaceId=e.WorkspaceId AND am.ActivityId COLLATE DATABASE_DEFAULT = e.ActivityId COLLATE DATABASE_DEFAULT
OUTER APPLY(SELECT MIN(a.ActivityCode) AS ActivityCode FROM dbo.vwActivityMaster a WHERE a.WorkspaceId=e.WorkspaceId AND a.ActivityName COLLATE DATABASE_DEFAULT = e.ActivityName COLLATE DATABASE_DEFAULT AND a.TypeId COLLATE DATABASE_DEFAULT = e.TypeId COLLATE DATABASE_DEFAULT HAVING COUNT(*)=1) fallback
WHERE e.EntrySource='Daily allocation' AND e.ActualHours>0;
GO
CREATE OR ALTER VIEW dbo.vwEmployeeTimesheetTotals AS
SELECT WorkspaceId,WorkDate,EmployeeId,EmployeeName,SUM(Hours) AS Hours,SUM(ClientDeductibleHours) AS ClientDeductibleHours,
 SUM(CASE WHEN ChargeType='Internal' THEN Hours ELSE 0 END) AS InternalHours,
 SUM(CASE WHEN ChargeType='Non-billable client' THEN Hours ELSE 0 END) AS ClientHoursNotDeducted
FROM dbo.vwEmployeeDailyTimesheets GROUP BY WorkspaceId,WorkDate,EmployeeId,EmployeeName;
GO
CREATE OR ALTER VIEW dbo.vwWeeklySiteVisits AS
SELECT e.WorkspaceId,a.WeeklyPlanId,a.WeeklyWeek,e.EntryId AS AllocationId,e.TaskId,e.PlannedDate AS VisitDate,e.EmployeeId,u.UserName AS EmployeeName,
 p.CustomerId,p.CustomerCode,p.CustomerName,e.ProjectId,p.ProjectCode,p.ProjectName,e.TypeId,ty.TypeName,e.ActivityName,e.Module,
 times.StartTime,times.EndTime,e.WorkMode,e.CurrentEntryStatus,a.Instructions AS Notes
FROM dbo.vwTimesheetEntries e JOIN dbo.vwAllocationWorkforce a ON a.WorkspaceId=e.WorkspaceId AND a.TaskId COLLATE DATABASE_DEFAULT = e.TaskId COLLATE DATABASE_DEFAULT AND a.AllocationId COLLATE DATABASE_DEFAULT = e.EntryId COLLATE DATABASE_DEFAULT
LEFT JOIN dbo.vwProjectMaster p ON p.WorkspaceId=e.WorkspaceId AND p.ProjectId COLLATE DATABASE_DEFAULT = e.ProjectId COLLATE DATABASE_DEFAULT
LEFT JOIN dbo.vwUserMaster u ON u.WorkspaceId=e.WorkspaceId AND u.MemberId COLLATE DATABASE_DEFAULT = e.EmployeeId COLLATE DATABASE_DEFAULT
LEFT JOIN dbo.vwActivityTypes ty ON ty.WorkspaceId=e.WorkspaceId AND ty.TypeId COLLATE DATABASE_DEFAULT = e.TypeId COLLATE DATABASE_DEFAULT
LEFT JOIN dbo.vwDailyAllocations v ON v.WorkspaceId=e.WorkspaceId AND v.TaskId COLLATE DATABASE_DEFAULT = e.TaskId COLLATE DATABASE_DEFAULT AND v.AllocationId COLLATE DATABASE_DEFAULT = e.EntryId COLLATE DATABASE_DEFAULT
OUTER APPLY(SELECT v.PlannedStart AS StartTime,v.PlannedEnd AS EndTime) times
WHERE NULLIF(a.WeeklyPlanId,'') IS NOT NULL;
GO
CREATE OR ALTER VIEW dbo.vwClientHoursAudit AS
SELECT t.WorkspaceId,t.RecordId AS TaskId,JSON_VALUE(a.value,'$.id') AS AllocationId,
 JSON_VALUE(a.value,'$.assignee') AS EmployeeId,h.Deduct,h.Confirmed,h.UpdatedBy,h.UpdatedAt
FROM dbo.WorkspaceRecords t CROSS APPLY OPENJSON(t.Payload,'$.allocations') a
CROSS APPLY OPENJSON(a.value,'$.billingHistory') WITH(Deduct bit '$.deduct',Confirmed bit '$.confirmed',UpdatedBy nvarchar(100) '$.by',UpdatedAt datetimeoffset '$.at') h
WHERE t.Kind='task';
GO

CREATE OR ALTER PROCEDURE dbo.uspProjectStatusReport
 @WorkspaceId uniqueidentifier,@FromDate date,@ToDate date,
 @ProjectId nvarchar(100)=NULL,@TypeId nvarchar(40)=NULL,@WorkMode nvarchar(20)=NULL
AS
BEGIN
 SET NOCOUNT ON;
 IF @WorkspaceId IS NULL OR @FromDate IS NULL OR @ToDate IS NULL OR @FromDate>@ToDate
  THROW 51010,'Workspace and a valid inclusive date range are required.',1;
 IF @WorkMode IS NOT NULL AND @WorkMode NOT IN ('Onsite','Offsite','Unclassified')
  THROW 51011,'Use Onsite, Offsite, Unclassified or NULL for work mode.',1;
 SELECT e.WorkspaceId,e.TaskId,e.EntryId,e.ProjectId,e.CompanyId,e.ActivityId,e.ActivityName,e.Module,e.TypeId,
 p.ProjectCode,p.ProjectName,p.CurrentStage,pc.CompanyName,ty.TypeName,e.EmployeeId,m.UserName AS EmployeeName,
 e.PlannedDate,CASE WHEN e.ActualHours>0 THEN e.ActualDate END AS ActualDate,e.WorkMode,e.ChargeType,
 CONVERT(decimal(18,2),CASE WHEN e.PlannedDate BETWEEN @FromDate AND @ToDate THEN e.PlannedHours ELSE 0 END) AS PlannedHours,
 CONVERT(decimal(18,2),CASE WHEN e.ActualDate BETWEEN @FromDate AND @ToDate THEN e.ActualHours ELSE 0 END) AS ActualHours,
 e.CurrentEntryStatus,e.CurrentActivityStatus,e.Remarks,e.EntrySource
 INTO #Period
 FROM dbo.vwTimesheetBilling e LEFT JOIN dbo.vwProjectMaster p ON p.WorkspaceId=e.WorkspaceId AND p.ProjectId COLLATE DATABASE_DEFAULT = e.ProjectId COLLATE DATABASE_DEFAULT
 LEFT JOIN dbo.vwActivityTypes ty ON ty.WorkspaceId=e.WorkspaceId AND ty.TypeId COLLATE DATABASE_DEFAULT = e.TypeId COLLATE DATABASE_DEFAULT
 LEFT JOIN dbo.vwUserMaster m ON m.WorkspaceId=e.WorkspaceId AND m.MemberId COLLATE DATABASE_DEFAULT = e.EmployeeId COLLATE DATABASE_DEFAULT
 OUTER APPLY (SELECT JSON_VALUE(company.value,'$.name') AS CompanyName
 FROM dbo.WorkspaceRecords projectRecord CROSS APPLY OPENJSON(projectRecord.Payload,'$.companies') company
 WHERE projectRecord.WorkspaceId=e.WorkspaceId AND projectRecord.Kind='project'
 AND projectRecord.RecordId COLLATE DATABASE_DEFAULT = e.ProjectId COLLATE DATABASE_DEFAULT AND JSON_VALUE(company.value,'$.id')=e.CompanyId) pc
 WHERE e.WorkspaceId=@WorkspaceId AND (@ProjectId IS NULL OR e.ProjectId=@ProjectId)
 AND (@TypeId IS NULL OR e.TypeId=@TypeId) AND (@WorkMode IS NULL OR e.WorkMode=@WorkMode)
 AND (e.PlannedDate BETWEEN @FromDate AND @ToDate OR e.ActualHours>0 AND e.ActualDate BETWEEN @FromDate AND @ToDate);
 -- 1: Current project-stage portfolio; not a historical stage snapshot.
 SELECT StageTypeId,CurrentStage,COUNT_BIG(*) AS ProjectCount FROM dbo.vwProjectMaster
 WHERE WorkspaceId=@WorkspaceId AND (@ProjectId IS NULL OR ProjectId=@ProjectId)
 GROUP BY StageTypeId,CurrentStage;
 -- 2: Period totals.
 SELECT @FromDate AS FromDate,@ToDate AS ToDate,COALESCE(SUM(PlannedHours),0) AS PlannedHours,COALESCE(SUM(ActualHours),0) AS ActualHours,
 COALESCE(SUM(CASE WHEN ChargeType='Client' THEN ActualHours ELSE 0 END),0) AS ClientActualHours,
 COALESCE(SUM(CASE WHEN ChargeType='Internal' THEN ActualHours ELSE 0 END),0) AS InternalActualHours,
 COALESCE(SUM(CASE WHEN ChargeType NOT IN ('Client','Internal','Non-billable client') THEN ActualHours ELSE 0 END),0) AS UnclassifiedActualHours,COALESCE(SUM(CASE WHEN ChargeType='Non-billable client' THEN ActualHours ELSE 0 END),0) AS ClientHoursNotDeducted FROM #Period;
 -- 3-6: Project, type, activity and mode breakdowns. These totals reconcile.
 SELECT ProjectId,ProjectCode,ProjectName,SUM(PlannedHours) AS PlannedHours,SUM(ActualHours) AS ActualHours,
 SUM(CASE WHEN ChargeType='Client' THEN ActualHours ELSE 0 END) AS ClientActualHours,
 SUM(CASE WHEN ChargeType='Internal' THEN ActualHours ELSE 0 END) AS InternalActualHours,
 SUM(CASE WHEN ChargeType NOT IN ('Client','Internal','Non-billable client') THEN ActualHours ELSE 0 END) AS UnclassifiedActualHours,COALESCE(SUM(CASE WHEN ChargeType='Non-billable client' THEN ActualHours ELSE 0 END),0) AS ClientHoursNotDeducted
 FROM #Period GROUP BY ProjectId,ProjectCode,ProjectName;
 SELECT TypeId,TypeName,SUM(PlannedHours) AS PlannedHours,SUM(ActualHours) AS ActualHours,
 SUM(CASE WHEN ChargeType='Client' THEN ActualHours ELSE 0 END) AS ClientActualHours,
 SUM(CASE WHEN ChargeType='Internal' THEN ActualHours ELSE 0 END) AS InternalActualHours,
 SUM(CASE WHEN ChargeType NOT IN ('Client','Internal','Non-billable client') THEN ActualHours ELSE 0 END) AS UnclassifiedActualHours,COALESCE(SUM(CASE WHEN ChargeType='Non-billable client' THEN ActualHours ELSE 0 END),0) AS ClientHoursNotDeducted
 FROM #Period GROUP BY TypeId,TypeName;
 SELECT ProjectId,TypeId,ActivityId,ActivityName,SUM(PlannedHours) AS PlannedHours,SUM(ActualHours) AS ActualHours,
 SUM(CASE WHEN ChargeType='Client' THEN ActualHours ELSE 0 END) AS ClientActualHours,
 SUM(CASE WHEN ChargeType='Internal' THEN ActualHours ELSE 0 END) AS InternalActualHours,
 SUM(CASE WHEN ChargeType NOT IN ('Client','Internal','Non-billable client') THEN ActualHours ELSE 0 END) AS UnclassifiedActualHours,COALESCE(SUM(CASE WHEN ChargeType='Non-billable client' THEN ActualHours ELSE 0 END),0) AS ClientHoursNotDeducted
 FROM #Period GROUP BY ProjectId,TypeId,ActivityId,ActivityName;
 SELECT WorkMode,SUM(PlannedHours) AS PlannedHours,SUM(ActualHours) AS ActualHours,
 SUM(CASE WHEN ChargeType='Client' THEN ActualHours ELSE 0 END) AS ClientActualHours,
 SUM(CASE WHEN ChargeType='Internal' THEN ActualHours ELSE 0 END) AS InternalActualHours,
 SUM(CASE WHEN ChargeType NOT IN ('Client','Internal','Non-billable client') THEN ActualHours ELSE 0 END) AS UnclassifiedActualHours,COALESCE(SUM(CASE WHEN ChargeType='Non-billable client' THEN ActualHours ELSE 0 END),0) AS ClientHoursNotDeducted
 FROM #Period GROUP BY WorkMode;
 -- 7: Activities planned, worked or updated during the period; status is CURRENT.
 SELECT r.RecordId AS TaskId,JSON_VALUE(r.Payload,'$.project') AS ProjectId,
 JSON_VALUE(r.Payload,'$.title') AS ActivityName,JSON_VALUE(r.Payload,'$.module') AS Module,
 COALESCE(NULLIF(JSON_VALUE(r.Payload,'$.typeId'),''),'implementation') AS TypeId,
 JSON_VALUE(r.Payload,'$.status') AS CurrentStatus,TRY_CONVERT(decimal(8,2),JSON_VALUE(r.Payload,'$.completion')) AS CurrentCompletionPercent,
 JSON_VALUE(r.Payload,'$.plannedStart') AS PlannedStart,JSON_VALUE(r.Payload,'$.plannedFinish') AS PlannedFinish,
 COALESCE((SELECT SUM(x.ActualHours) FROM #Period x WHERE x.TaskId COLLATE DATABASE_DEFAULT = r.RecordId COLLATE DATABASE_DEFAULT),0) AS PeriodActualHours,
 JSON_VALUE(r.Payload,'$.followupNote') AS LatestFollowup,JSON_VALUE(r.Payload,'$.nextSessionDate') AS NextSessionDate
 FROM dbo.WorkspaceRecords r WHERE r.WorkspaceId=@WorkspaceId AND r.Kind='task'
 AND (@ProjectId IS NULL OR JSON_VALUE(r.Payload,'$.project')=@ProjectId)
 AND (@TypeId IS NULL OR COALESCE(NULLIF(JSON_VALUE(r.Payload,'$.typeId'),''),'implementation')=@TypeId)
 AND (EXISTS(SELECT 1 FROM #Period x WHERE x.TaskId COLLATE DATABASE_DEFAULT = r.RecordId COLLATE DATABASE_DEFAULT)
 OR @WorkMode IS NULL AND (
 TRY_CONVERT(date,JSON_VALUE(r.Payload,'$.plannedStart'))<=@ToDate
 AND TRY_CONVERT(date,COALESCE(NULLIF(JSON_VALUE(r.Payload,'$.plannedFinish'),''),JSON_VALUE(r.Payload,'$.due')))>=@FromDate
 OR EXISTS(SELECT 1 FROM OPENJSON(r.Payload,'$.history') h
 WHERE CONVERT(date,SWITCHOFFSET(TRY_CONVERT(datetimeoffset,JSON_VALUE(h.value,'$.at')),'+03:00')) BETWEEN @FromDate AND @ToDate)));
 -- 8: Detailed timesheets.
 SELECT * FROM #Period ORDER BY COALESCE(ActualDate,PlannedDate),ProjectCode,ActivityName;
END;
GO

IF DATABASE_PRINCIPAL_ID(N'IIS APPPOOL\MyProjectManagement') IS NOT NULL
BEGIN
 GRANT SELECT ON dbo.vwCustomerMaster TO [IIS APPPOOL\MyProjectManagement];
 GRANT SELECT ON dbo.vwAllocationWorkforce TO [IIS APPPOOL\MyProjectManagement];
 GRANT SELECT ON dbo.vwTimesheetBilling TO [IIS APPPOOL\MyProjectManagement];
 GRANT SELECT ON dbo.vwEmployeeDailyTimesheets TO [IIS APPPOOL\MyProjectManagement];
 GRANT SELECT ON dbo.vwEmployeeTimesheetTotals TO [IIS APPPOOL\MyProjectManagement];
 GRANT SELECT ON dbo.vwWeeklySiteVisits TO [IIS APPPOOL\MyProjectManagement];
 GRANT SELECT ON dbo.vwClientHoursAudit TO [IIS APPPOOL\MyProjectManagement];
END;
GO
-- Example employee/date report (add your WorkspaceId filter for your company):
-- SELECT WorkDate,EmployeeName,ProjectCode,ProjectName,TypeName,ActivityCode,ActivityName,Notes,Hours,ClientDeductibleHours
-- FROM dbo.vwEmployeeDailyTimesheets WHERE WorkDate BETWEEN '2026-11-01' AND '2026-11-30';
SELECT name FROM sys.views WHERE name IN('vwCustomerMaster','vwEmployeeDailyTimesheets','vwEmployeeTimesheetTotals','vwWeeklySiteVisits','vwClientHoursAudit');
GO


SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
-- Application release v24: AMC contract terms, required cycles and onsite visit compliance.
-- SQL Server 2022/2025. Back up the database and stop the IIS pool before updating.
USE [MyProjectManagement];
GO
SET XACT_ABORT ON;
BEGIN TRY
 BEGIN TRANSACTION;
 DECLARE @changed TABLE(Id uniqueidentifier);
 -- Preserve explicit false values and custom-role decisions.
 UPDATE dbo.Workspaces SET SettingsJson=JSON_MODIFY(SettingsJson,'$.rolePermissions."Project manager".viewAmcCompliance',CONVERT(bit,1))
 OUTPUT inserted.Id INTO @changed WHERE JSON_VALUE(SettingsJson,'$.rolePermissions."Project manager".viewAmcCompliance') IS NULL;
 UPDATE dbo.Workspaces SET SettingsJson=JSON_MODIFY(SettingsJson,'$.rolePermissions."Project lead".viewAmcCompliance',CONVERT(bit,1))
 OUTPUT inserted.Id INTO @changed WHERE JSON_VALUE(SettingsJson,'$.rolePermissions."Project lead".viewAmcCompliance') IS NULL;
 UPDATE dbo.Workspaces SET SettingsJson=JSON_MODIFY(SettingsJson,'$.rolePermissions."ERP consultant".viewAmcCompliance',CONVERT(bit,0))
 OUTPUT inserted.Id INTO @changed WHERE JSON_VALUE(SettingsJson,'$.rolePermissions."ERP consultant".viewAmcCompliance') IS NULL;
 UPDATE w SET Revision=Revision+1 FROM dbo.Workspaces w WHERE EXISTS(SELECT 1 FROM @changed c WHERE c.Id=w.Id);
 -- No contracts or visit targets are guessed for existing AMC projects. Configure them in the application.
 COMMIT TRANSACTION;
END TRY
BEGIN CATCH
 IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
 THROW;
END CATCH;
GO
CREATE OR ALTER VIEW dbo.vwAmcContracts AS
SELECT p.WorkspaceId,p.ProjectId,p.ProjectCode,p.ProjectName,p.CustomerId,p.CustomerCode,p.CustomerName,p.CurrentStage,
 CONVERT(nvarchar(60),JSON_VALUE(r.Payload,'$.amc.id')) AS ContractId,
 TRY_CONVERT(date,JSON_VALUE(r.Payload,'$.amc.start')) AS AmcStart,
 TRY_CONVERT(date,JSON_VALUE(r.Payload,'$.amc.end')) AS AmcEnd,
 CONVERT(nvarchar(20),JSON_VALUE(r.Payload,'$.amc.cycle')) AS VisitCycle,
 TRY_CONVERT(int,JSON_VALUE(r.Payload,'$.amc.visits')) AS VisitsPerCycle,
 TRY_CONVERT(decimal(8,2),JSON_VALUE(r.Payload,'$.amc.hours')) AS HoursPerVisit,
 CONVERT(nvarchar(5),JSON_VALUE(r.Payload,'$.amc.preferredStart')) AS PreferredStart,
 CONVERT(nvarchar(100),JSON_VALUE(r.Payload,'$.amc.activityId')) AS SuggestedActivityId,
 JSON_QUERY(r.Payload,'$.amc.staff') AS RequiredStaffJson
FROM dbo.vwProjectMaster p JOIN dbo.WorkspaceRecords r ON r.WorkspaceId=p.WorkspaceId AND r.Kind='project' AND r.RecordId COLLATE DATABASE_DEFAULT = p.ProjectId COLLATE DATABASE_DEFAULT
WHERE p.StageTypeId='amc';
GO
CREATE OR ALTER FUNCTION dbo.fnAmcContractCycles(@Start date,@Finish date,@Cycle nvarchar(20))
RETURNS TABLE
AS RETURN
WITH Numbers AS (SELECT TOP (4000) CONVERT(int,ROW_NUMBER() OVER(ORDER BY (SELECT NULL))-1) AS n FROM sys.all_objects a CROSS JOIN sys.all_objects b),
Bounds AS (SELECT CASE @Cycle WHEN 'daily' THEN 1 WHEN 'alternate-days' THEN 2 WHEN 'weekly' THEN 7 ELSE 0 END AS DayStep,
 CASE @Cycle WHEN 'monthly' THEN 1 WHEN 'quarterly' THEN 3 WHEN 'six-monthly' THEN 6 WHEN 'yearly' THEN 12 ELSE 0 END AS MonthStep),
Limits AS (SELECT DayStep,MonthStep,CASE WHEN DayStep>0 THEN DATEDIFF(day,@Start,@Finish)/DayStep+1 WHEN MonthStep>0 THEN DATEDIFF(month,@Start,@Finish)/MonthStep+1 ELSE 0 END AS CycleCount FROM Bounds),
Dates AS(SELECT n,CASE WHEN DayStep>0 THEN DATEADD(day,(CASE WHEN n<CycleCount THEN n ELSE 0 END)*DayStep,@Start) ELSE DATEADD(month,(CASE WHEN n<CycleCount THEN n ELSE 0 END)*MonthStep,@Start) END AS CycleStart,
 CASE WHEN DayStep>0 THEN DATEADD(day,(CASE WHEN n<CycleCount THEN n+1 ELSE 1 END)*DayStep,@Start) ELSE DATEADD(month,(CASE WHEN n<CycleCount THEN n+1 ELSE 1 END)*MonthStep,@Start) END AS NextStart
 FROM Numbers CROSS JOIN Limits WHERE n<CycleCount)
SELECT n AS CycleIndex,CycleStart,CASE WHEN DATEADD(day,-1,NextStart)>@Finish THEN @Finish ELSE DATEADD(day,-1,NextStart) END AS CycleEnd
FROM Dates WHERE CycleStart<=@Finish AND @Finish>=@Start;
GO
CREATE OR ALTER VIEW dbo.vwAmcAllocationEvidence AS
SELECT e.WorkspaceId,e.ProjectId,e.TaskId,e.EntryId,e.EmployeeId,e.PlannedDate,e.ActualDate,e.PlannedHours,e.ActualHours,
 CONVERT(nvarchar(180),COALESCE(NULLIF(a.VisitId,''),NULLIF(a.TeamGroupId,''),CONVERT(nvarchar(10),e.PlannedDate,23)+'|'+a.StartTime+'|'+a.EndTime)) AS PlannedVisitKey,
 CONVERT(nvarchar(180),COALESCE(NULLIF(a.VisitId,''),NULLIF(a.TeamGroupId,''),CONVERT(nvarchar(10),e.ActualDate,23)+'|'+a.StartTime+'|'+a.EndTime)) AS ActualVisitKey,
 a.VisitId,a.ContractId,a.LinkedCycleStart,a.DueDate,COALESCE(a.CountsAsVisit,CONVERT(bit,1)) AS CountsAsVisit
FROM dbo.vwTimesheetEntries e JOIN dbo.WorkspaceRecords t ON t.WorkspaceId=e.WorkspaceId AND t.Kind='task' AND t.RecordId COLLATE DATABASE_DEFAULT = e.TaskId COLLATE DATABASE_DEFAULT
CROSS APPLY OPENJSON(t.Payload,'$.allocations') WITH(
 AllocationId nvarchar(100) '$.id',VisitId nvarchar(180) '$.amcVisitId',ContractId nvarchar(60) '$.amcContractId',
 LinkedCycleStart date '$.amcCycleStart',DueDate date '$.amcDueDate',TeamGroupId nvarchar(100) '$.teamGroupId',
 StartTime nvarchar(5) '$.plannedStartTime',EndTime nvarchar(5) '$.plannedEndTime',CountsAsVisit bit '$.countsAsAmcVisit') a
WHERE e.EntryId COLLATE DATABASE_DEFAULT = a.AllocationId COLLATE DATABASE_DEFAULT AND e.EntrySource='Daily allocation' AND e.TypeId='amc' AND e.WorkMode='Onsite';
GO
CREATE OR ALTER VIEW dbo.vwAmcCycleCompliance AS
SELECT c.WorkspaceId,c.ProjectId,c.ProjectCode,c.ProjectName,c.CustomerName,c.ContractId,c.VisitCycle,
 cy.CycleStart,cy.CycleEnd,c.VisitsPerCycle AS RequiredVisits,c.VisitsPerCycle*c.HoursPerVisit AS RequiredHours,c.HoursPerVisit,
 COALESCE(a.AttendedVisits,0) AS AttendedVisits,COALESCE(a.QualifiedVisits,0) AS QualifiedVisits,COALESCE(a.ActualHours,0) AS OnsiteHoursCountedOnce,
 COALESCE(p.ScheduledVisits,0) AS ScheduledVisits,COALESCE(p.PlannedHours,0) AS PlannedHoursCountedOnce,
 CASE WHEN c.VisitsPerCycle>COALESCE(a.QualifiedVisits,0) THEN c.VisitsPerCycle-COALESCE(a.QualifiedVisits,0) ELSE 0 END AS VisitsGap,
 CASE WHEN c.VisitsPerCycle*c.HoursPerVisit>COALESCE(a.ActualHours,0) THEN c.VisitsPerCycle*c.HoursPerVisit-COALESCE(a.ActualHours,0) ELSE 0 END AS HoursGap,
 CONVERT(bit,CASE WHEN cy.CycleEnd<CONVERT(date,DATEADD(hour,3,SYSUTCDATETIME())) THEN 1 ELSE 0 END) AS ClosedCycle
FROM dbo.vwAmcContracts c CROSS APPLY dbo.fnAmcContractCycles(c.AmcStart,c.AmcEnd,c.VisitCycle) cy
OUTER APPLY(
 SELECT COUNT(*) AS AttendedVisits,SUM(qualified.CreditedHours) AS ActualHours,SUM(qualified.Qualifies) AS QualifiedVisits FROM(SELECT q.CreditedHours,CASE WHEN q.CreditedHours>=c.HoursPerVisit AND NOT EXISTS(
 SELECT 1 FROM OPENJSON(c.RequiredStaffJson) staff WHERE NOT EXISTS(SELECT 1 FROM dbo.vwAmcAllocationEvidence evidence
 WHERE evidence.WorkspaceId=c.WorkspaceId AND evidence.ProjectId COLLATE DATABASE_DEFAULT = c.ProjectId COLLATE DATABASE_DEFAULT AND evidence.ActualVisitKey COLLATE DATABASE_DEFAULT = q.VisitKey COLLATE DATABASE_DEFAULT AND evidence.EmployeeId COLLATE DATABASE_DEFAULT = staff.value COLLATE DATABASE_DEFAULT
 AND evidence.ActualDate BETWEEN cy.CycleStart AND cy.CycleEnd AND evidence.ActualHours>0 AND evidence.CountsAsVisit=1
 AND (evidence.ContractId IS NULL OR evidence.ContractId COLLATE DATABASE_DEFAULT = c.ContractId COLLATE DATABASE_DEFAULT) AND (evidence.LinkedCycleStart IS NULL OR evidence.LinkedCycleStart=cy.CycleStart))) THEN 1 ELSE 0 END AS Qualifies
 FROM(SELECT e.ActualVisitKey AS VisitKey,MAX(e.ActualHours) AS CreditedHours FROM dbo.vwAmcAllocationEvidence e
 WHERE e.WorkspaceId=c.WorkspaceId AND e.ProjectId COLLATE DATABASE_DEFAULT = c.ProjectId COLLATE DATABASE_DEFAULT AND e.ActualDate BETWEEN cy.CycleStart AND cy.CycleEnd AND e.ActualHours>0 AND e.CountsAsVisit=1
 AND (e.ContractId IS NULL OR e.ContractId COLLATE DATABASE_DEFAULT = c.ContractId COLLATE DATABASE_DEFAULT) AND (e.LinkedCycleStart IS NULL OR e.LinkedCycleStart=cy.CycleStart)
 GROUP BY e.ActualVisitKey) q) qualified
) a
OUTER APPLY(
 SELECT SUM(qualified.CreditedHours) AS PlannedHours,SUM(qualified.Qualifies) AS ScheduledVisits FROM(SELECT q.CreditedHours,CASE WHEN q.CreditedHours>=c.HoursPerVisit AND NOT EXISTS(
 SELECT 1 FROM OPENJSON(c.RequiredStaffJson) staff WHERE NOT EXISTS(SELECT 1 FROM dbo.vwAmcAllocationEvidence evidence
 WHERE evidence.WorkspaceId=c.WorkspaceId AND evidence.ProjectId COLLATE DATABASE_DEFAULT = c.ProjectId COLLATE DATABASE_DEFAULT AND evidence.PlannedVisitKey COLLATE DATABASE_DEFAULT = q.VisitKey COLLATE DATABASE_DEFAULT AND evidence.EmployeeId COLLATE DATABASE_DEFAULT = staff.value COLLATE DATABASE_DEFAULT
 AND evidence.PlannedDate BETWEEN cy.CycleStart AND cy.CycleEnd AND evidence.PlannedHours>=c.HoursPerVisit
 AND (evidence.ContractId IS NULL OR evidence.ContractId COLLATE DATABASE_DEFAULT = c.ContractId COLLATE DATABASE_DEFAULT) AND (evidence.LinkedCycleStart IS NULL OR evidence.LinkedCycleStart=cy.CycleStart))) THEN 1 ELSE 0 END AS Qualifies
 FROM(SELECT e.PlannedVisitKey AS VisitKey,MAX(e.PlannedHours) AS CreditedHours FROM dbo.vwAmcAllocationEvidence e
 WHERE e.WorkspaceId=c.WorkspaceId AND e.ProjectId COLLATE DATABASE_DEFAULT = c.ProjectId COLLATE DATABASE_DEFAULT AND e.PlannedDate BETWEEN cy.CycleStart AND cy.CycleEnd
 AND (e.ContractId IS NULL OR e.ContractId COLLATE DATABASE_DEFAULT = c.ContractId COLLATE DATABASE_DEFAULT) AND (e.LinkedCycleStart IS NULL OR e.LinkedCycleStart=cy.CycleStart)
 GROUP BY e.PlannedVisitKey) q) qualified
) p;
GO
CREATE OR ALTER VIEW dbo.vwAmcVisitRequirements AS
SELECT c.WorkspaceId,c.ProjectId,c.ProjectCode,c.ProjectName,c.ContractId,cy.CycleStart,cy.CycleEnd,
 n.n AS VisitIndex,CONVERT(nvarchar(180),c.ProjectId+'/'+c.ContractId+'/'+CONVERT(nvarchar(10),cy.CycleStart,23)+'/'+CONVERT(nvarchar(3),n.n)) AS VisitId,
 DATEADD(day,n.n*(DATEDIFF(day,cy.CycleStart,cy.CycleEnd)+1)/NULLIF(c.VisitsPerCycle,0),cy.CycleStart) AS SuggestedDueDate,
 c.HoursPerVisit,c.PreferredStart,c.SuggestedActivityId,c.RequiredStaffJson
FROM dbo.vwAmcContracts c CROSS APPLY dbo.fnAmcContractCycles(c.AmcStart,c.AmcEnd,c.VisitCycle) cy
CROSS APPLY(SELECT TOP (366) CONVERT(int,ROW_NUMBER() OVER(ORDER BY (SELECT NULL))-1) AS n FROM sys.all_objects) n
WHERE n.n<c.VisitsPerCycle AND c.VisitsPerCycle>0;
GO
CREATE OR ALTER VIEW dbo.vwAmcAlerts AS
SELECT WorkspaceId,ProjectId,ProjectCode,ProjectName,CycleStart,CycleEnd,RequiredVisits,RequiredHours,QualifiedVisits,OnsiteHoursCountedOnce,VisitsGap,HoursGap
FROM dbo.vwAmcCycleCompliance WHERE ClosedCycle=1 AND (VisitsGap>0 OR HoursGap>0);
GO
CREATE OR ALTER PROCEDURE dbo.uspAmcComplianceReport
 @WorkspaceId uniqueidentifier,@From date,@To date,@ProjectId nvarchar(100)=NULL
AS
BEGIN
 SET NOCOUNT ON;
 IF @WorkspaceId IS NULL OR @From IS NULL OR @To IS NULL OR @From>@To THROW 51020,'Workspace and valid inclusive dates required.',1;
 SELECT * FROM dbo.vwAmcContracts WHERE WorkspaceId=@WorkspaceId AND (@ProjectId IS NULL OR ProjectId=@ProjectId);
 SELECT * FROM dbo.vwAmcCycleCompliance WHERE WorkspaceId=@WorkspaceId AND CycleStart<=@To AND CycleEnd>=@From AND (@ProjectId IS NULL OR ProjectId=@ProjectId) ORDER BY ProjectCode,CycleStart;
 SELECT * FROM dbo.vwAmcAlerts WHERE WorkspaceId=@WorkspaceId AND CycleStart<=@To AND CycleEnd>=@From AND (@ProjectId IS NULL OR ProjectId=@ProjectId) ORDER BY ProjectCode,CycleStart;
 SELECT * FROM dbo.vwAmcVisitRequirements WHERE WorkspaceId=@WorkspaceId AND SuggestedDueDate BETWEEN @From AND @To AND (@ProjectId IS NULL OR ProjectId=@ProjectId) ORDER BY ProjectCode,SuggestedDueDate,VisitIndex;
END;
GO
IF DATABASE_PRINCIPAL_ID(N'IIS APPPOOL\MyProjectManagement') IS NOT NULL
BEGIN
 GRANT SELECT ON dbo.vwAmcContracts TO [IIS APPPOOL\MyProjectManagement];
 GRANT SELECT ON dbo.vwAmcAllocationEvidence TO [IIS APPPOOL\MyProjectManagement];
 GRANT SELECT ON dbo.vwAmcCycleCompliance TO [IIS APPPOOL\MyProjectManagement];
 GRANT SELECT ON dbo.vwAmcVisitRequirements TO [IIS APPPOOL\MyProjectManagement];
 GRANT SELECT ON dbo.vwAmcAlerts TO [IIS APPPOOL\MyProjectManagement];
 GRANT SELECT ON dbo.fnAmcContractCycles TO [IIS APPPOOL\MyProjectManagement];
 GRANT EXECUTE ON dbo.uspAmcComplianceReport TO [IIS APPPOOL\MyProjectManagement];
END;
GO
SELECT name FROM sys.views WHERE name LIKE 'vwAmc%';
GO


-- My Project Management v25 -- SQL collation repair for v23/v24 installations.
-- No data, users, passwords, database collation or table collation is changed.
-- Stop the IIS pool, back up the database, and run the complete script in SSMS.
USE [MyProjectManagement];
GO
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
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
LEFT JOIN dbo.AppUsers u ON u.WorkspaceId=m.WorkspaceId AND u.MemberId COLLATE DATABASE_DEFAULT = m.MemberId COLLATE DATABASE_DEFAULT
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
CREATE OR ALTER VIEW dbo.vwActivityTypes AS
SELECT w.Id AS WorkspaceId,t.TypeId,t.TypeName,t.Active
FROM dbo.Workspaces w CROSS APPLY OPENJSON(w.SettingsJson,'$.activityTypes') WITH(
 TypeId nvarchar(40) '$.id',TypeName nvarchar(80) '$.name',Active bit '$.active') t;
GO
CREATE OR ALTER VIEW dbo.vwProjectMaster AS
SELECT r.WorkspaceId,r.RecordId AS ProjectId,
 CONVERT(nvarchar(50),JSON_VALUE(r.Payload,'$.code')) AS ProjectCode,
 CONVERT(nvarchar(90),JSON_VALUE(r.Payload,'$.name')) AS ProjectName,
 JSON_VALUE(r.Payload,'$.lead') AS ProjectInchargeId,
 TRY_CONVERT(date,JSON_VALUE(r.Payload,'$.start')) AS PlannedStart,
 TRY_CONVERT(date,JSON_VALUE(r.Payload,'$.due')) AS TargetGoLive,
 CONVERT(nvarchar(40),COALESCE(NULLIF(JSON_VALUE(r.Payload,'$.stageType'),''),'implementation')) AS StageTypeId,
 ty.TypeName AS CurrentStage
FROM dbo.WorkspaceRecords r LEFT JOIN dbo.vwActivityTypes ty ON ty.WorkspaceId=r.WorkspaceId
 AND ty.TypeId=COALESCE(NULLIF(JSON_VALUE(r.Payload,'$.stageType'),''),'implementation')
WHERE r.Kind='project';
GO
CREATE OR ALTER VIEW dbo.vwActivityMaster AS
SELECT w.Id AS WorkspaceId,a.ActivityId,a.ActivityCode,a.ActivityName,a.Description,a.Active,
 COALESCE(NULLIF(a.TypeId,''),'implementation') AS TypeId,ty.TypeName
FROM dbo.Workspaces w CROSS APPLY OPENJSON(w.SettingsJson,'$.activityMaster') WITH(
 ActivityId nvarchar(100) '$.id',ActivityCode nvarchar(140) '$.code',ActivityName nvarchar(140) '$.name',
 Description nvarchar(1000) '$.description',Active bit '$.active',TypeId nvarchar(40) '$.typeId') a
LEFT JOIN dbo.vwActivityTypes ty ON ty.WorkspaceId=w.Id AND ty.TypeId=COALESCE(NULLIF(a.TypeId,''),'implementation');
GO
CREATE OR ALTER VIEW dbo.vwTimesheetEntries AS
SELECT t.WorkspaceId,t.RecordId AS TaskId,a.AllocationId AS EntryId,
 CONVERT(nvarchar(100),JSON_VALUE(t.Payload,'$.project')) AS ProjectId,CONVERT(nvarchar(100),JSON_VALUE(t.Payload,'$.companyId')) AS CompanyId,
 CONVERT(nvarchar(100),JSON_VALUE(t.Payload,'$.activityId')) AS ActivityId,
 CONVERT(nvarchar(140),JSON_VALUE(t.Payload,'$.title')) AS ActivityName,
 CONVERT(nvarchar(60),JSON_VALUE(t.Payload,'$.module')) AS Module,
 CONVERT(nvarchar(40),COALESCE(NULLIF(a.TypeId,''),NULLIF(JSON_VALUE(t.Payload,'$.typeId'),''),'implementation')) AS TypeId,
 a.EmployeeId,a.PlannedDate,TRY_CONVERT(date,COALESCE(NULLIF(a.ActualDate,''),CONVERT(nvarchar(10),a.PlannedDate,23))) AS ActualDate,
 COALESCE(NULLIF(a.WorkMode,''),'Unclassified') AS WorkMode,COALESCE(NULLIF(a.ChargeType,''),'Unclassified') AS ChargeType,
 CONVERT(decimal(18,2),COALESCE((DATEDIFF(minute,a.PlannedStart,a.PlannedEnd)-COALESCE(a.PlannedBreak,0))/60.0,0)) AS PlannedHours,
 CONVERT(decimal(18,2),CASE WHEN x.ActualStart IS NOT NULL AND x.ActualEnd IS NOT NULL THEN (DATEDIFF(minute,x.ActualStart,x.ActualEnd)-COALESCE(a.ActualBreak,0))/60.0 ELSE COALESCE(a.DeliveredUnits,0)*4 END) AS ActualHours,
 a.Status AS CurrentEntryStatus,CONVERT(nvarchar(60),JSON_VALUE(t.Payload,'$.status')) AS CurrentActivityStatus,a.Remarks,
 CONVERT(nvarchar(20),'Daily allocation') AS EntrySource
FROM dbo.WorkspaceRecords t CROSS APPLY OPENJSON(t.Payload,'$.allocations') WITH(
 AllocationId nvarchar(100) '$.id',TypeId nvarchar(40) '$.typeId',EmployeeId nvarchar(100) '$.assignee',PlannedDate date '$.date',
 ActualDate nvarchar(10) '$.actualWorkDate',WorkMode nvarchar(20) '$.workMode',ChargeType nvarchar(20) '$.chargeType',
 PlannedStart time '$.plannedStartTime',PlannedEnd time '$.plannedEndTime',PlannedBreak int '$.plannedBreakMinutes',
 ActualStartText nvarchar(8) '$.actualStartTime',ActualEndText nvarchar(8) '$.actualEndTime',ActualBreak int '$.actualBreakMinutes',
 DeliveredUnits decimal(8,2) '$.deliveredUnits',Status nvarchar(60) '$.status',Remarks nvarchar(4000) '$.completionRemarks') a
OUTER APPLY(SELECT TRY_CONVERT(time,NULLIF(a.ActualStartText,'')) AS ActualStart,TRY_CONVERT(time,NULLIF(a.ActualEndText,'')) AS ActualEnd) x
WHERE t.Kind='task'
UNION ALL
SELECT t.WorkspaceId,t.RecordId,CONVERT(nvarchar(100),'session-'+s.[key]) COLLATE DATABASE_DEFAULT,
 CONVERT(nvarchar(100),JSON_VALUE(t.Payload,'$.project')),CONVERT(nvarchar(100),JSON_VALUE(t.Payload,'$.companyId')),CONVERT(nvarchar(100),JSON_VALUE(t.Payload,'$.activityId')),
 CONVERT(nvarchar(140),JSON_VALUE(t.Payload,'$.title')),CONVERT(nvarchar(60),JSON_VALUE(t.Payload,'$.module')),
 CONVERT(nvarchar(40),COALESCE(NULLIF(JSON_VALUE(t.Payload,'$.typeId'),''),'implementation')),
 CONVERT(nvarchar(100),COALESCE(NULLIF(JSON_VALUE(s.value,'$.assignee'),''),JSON_VALUE(t.Payload,'$.assignee'))),
 CONVERT(date,NULL),TRY_CONVERT(date,JSON_VALUE(s.value,'$.date')),CONVERT(nvarchar(20),'Unclassified'),
 CONVERT(nvarchar(20),COALESCE(NULLIF(JSON_VALUE(p.Payload,'$.legacyHoursClass'),''),'Unclassified')),CONVERT(decimal(18,2),0),
 CONVERT(decimal(18,2),COALESCE(TRY_CONVERT(decimal(8,2),JSON_VALUE(s.value,'$.units')),0)*4),
 CONVERT(nvarchar(60),JSON_VALUE(t.Payload,'$.status')),CONVERT(nvarchar(60),JSON_VALUE(t.Payload,'$.status')),CONVERT(nvarchar(4000),JSON_VALUE(s.value,'$.note')),
 CONVERT(nvarchar(20),'Legacy session')
FROM dbo.WorkspaceRecords t CROSS APPLY OPENJSON(t.Payload,'$.sessions') s
LEFT JOIN dbo.WorkspaceRecords p ON p.WorkspaceId=t.WorkspaceId AND p.Kind='project' AND p.RecordId=JSON_VALUE(t.Payload,'$.project')
WHERE t.Kind='task';
GO
CREATE OR ALTER PROCEDURE dbo.uspProjectStatusReport
 @WorkspaceId uniqueidentifier,@FromDate date,@ToDate date,
 @ProjectId nvarchar(100)=NULL,@TypeId nvarchar(40)=NULL,@WorkMode nvarchar(20)=NULL
AS
BEGIN
 SET NOCOUNT ON;
 IF @WorkspaceId IS NULL OR @FromDate IS NULL OR @ToDate IS NULL OR @FromDate>@ToDate
  THROW 51010,'Workspace and a valid inclusive date range are required.',1;
 IF @WorkMode IS NOT NULL AND @WorkMode NOT IN ('Onsite','Offsite','Unclassified')
  THROW 51011,'Use Onsite, Offsite, Unclassified or NULL for work mode.',1;
 SELECT e.WorkspaceId,e.TaskId,e.EntryId,e.ProjectId,e.CompanyId,e.ActivityId,e.ActivityName,e.Module,e.TypeId,
 p.ProjectCode,p.ProjectName,p.CurrentStage,pc.CompanyName,ty.TypeName,e.EmployeeId,m.UserName AS EmployeeName,
 e.PlannedDate,CASE WHEN e.ActualHours>0 THEN e.ActualDate END AS ActualDate,e.WorkMode,e.ChargeType,
 CONVERT(decimal(18,2),CASE WHEN e.PlannedDate BETWEEN @FromDate AND @ToDate THEN e.PlannedHours ELSE 0 END) AS PlannedHours,
 CONVERT(decimal(18,2),CASE WHEN e.ActualDate BETWEEN @FromDate AND @ToDate THEN e.ActualHours ELSE 0 END) AS ActualHours,
 e.CurrentEntryStatus,e.CurrentActivityStatus,e.Remarks,e.EntrySource
 INTO #Period
 FROM dbo.vwTimesheetEntries e LEFT JOIN dbo.vwProjectMaster p ON p.WorkspaceId=e.WorkspaceId AND p.ProjectId COLLATE DATABASE_DEFAULT = e.ProjectId COLLATE DATABASE_DEFAULT
 LEFT JOIN dbo.vwActivityTypes ty ON ty.WorkspaceId=e.WorkspaceId AND ty.TypeId COLLATE DATABASE_DEFAULT = e.TypeId COLLATE DATABASE_DEFAULT
 LEFT JOIN dbo.vwUserMaster m ON m.WorkspaceId=e.WorkspaceId AND m.MemberId COLLATE DATABASE_DEFAULT = e.EmployeeId COLLATE DATABASE_DEFAULT
 OUTER APPLY (SELECT JSON_VALUE(company.value,'$.name') AS CompanyName
 FROM dbo.WorkspaceRecords projectRecord CROSS APPLY OPENJSON(projectRecord.Payload,'$.companies') company
 WHERE projectRecord.WorkspaceId=e.WorkspaceId AND projectRecord.Kind='project'
 AND projectRecord.RecordId COLLATE DATABASE_DEFAULT = e.ProjectId COLLATE DATABASE_DEFAULT AND JSON_VALUE(company.value,'$.id')=e.CompanyId) pc
 WHERE e.WorkspaceId=@WorkspaceId AND (@ProjectId IS NULL OR e.ProjectId=@ProjectId)
 AND (@TypeId IS NULL OR e.TypeId=@TypeId) AND (@WorkMode IS NULL OR e.WorkMode=@WorkMode)
 AND (e.PlannedDate BETWEEN @FromDate AND @ToDate OR e.ActualHours>0 AND e.ActualDate BETWEEN @FromDate AND @ToDate);
 -- 1: Current project-stage portfolio; not a historical stage snapshot.
 SELECT StageTypeId,CurrentStage,COUNT_BIG(*) AS ProjectCount FROM dbo.vwProjectMaster
 WHERE WorkspaceId=@WorkspaceId AND (@ProjectId IS NULL OR ProjectId=@ProjectId)
 GROUP BY StageTypeId,CurrentStage;
 -- 2: Period totals.
 SELECT @FromDate AS FromDate,@ToDate AS ToDate,COALESCE(SUM(PlannedHours),0) AS PlannedHours,COALESCE(SUM(ActualHours),0) AS ActualHours,
 COALESCE(SUM(CASE WHEN ChargeType='Client' THEN ActualHours ELSE 0 END),0) AS ClientActualHours,
 COALESCE(SUM(CASE WHEN ChargeType='Internal' THEN ActualHours ELSE 0 END),0) AS InternalActualHours,
 COALESCE(SUM(CASE WHEN ChargeType NOT IN ('Client','Internal') THEN ActualHours ELSE 0 END),0) AS UnclassifiedActualHours FROM #Period;
 -- 3-6: Project, type, activity and mode breakdowns. These totals reconcile.
 SELECT ProjectId,ProjectCode,ProjectName,SUM(PlannedHours) AS PlannedHours,SUM(ActualHours) AS ActualHours,
 SUM(CASE WHEN ChargeType='Client' THEN ActualHours ELSE 0 END) AS ClientActualHours,
 SUM(CASE WHEN ChargeType='Internal' THEN ActualHours ELSE 0 END) AS InternalActualHours,
 SUM(CASE WHEN ChargeType NOT IN ('Client','Internal') THEN ActualHours ELSE 0 END) AS UnclassifiedActualHours
 FROM #Period GROUP BY ProjectId,ProjectCode,ProjectName;
 SELECT TypeId,TypeName,SUM(PlannedHours) AS PlannedHours,SUM(ActualHours) AS ActualHours,
 SUM(CASE WHEN ChargeType='Client' THEN ActualHours ELSE 0 END) AS ClientActualHours,
 SUM(CASE WHEN ChargeType='Internal' THEN ActualHours ELSE 0 END) AS InternalActualHours,
 SUM(CASE WHEN ChargeType NOT IN ('Client','Internal') THEN ActualHours ELSE 0 END) AS UnclassifiedActualHours
 FROM #Period GROUP BY TypeId,TypeName;
 SELECT ProjectId,TypeId,ActivityId,ActivityName,SUM(PlannedHours) AS PlannedHours,SUM(ActualHours) AS ActualHours,
 SUM(CASE WHEN ChargeType='Client' THEN ActualHours ELSE 0 END) AS ClientActualHours,
 SUM(CASE WHEN ChargeType='Internal' THEN ActualHours ELSE 0 END) AS InternalActualHours,
 SUM(CASE WHEN ChargeType NOT IN ('Client','Internal') THEN ActualHours ELSE 0 END) AS UnclassifiedActualHours
 FROM #Period GROUP BY ProjectId,TypeId,ActivityId,ActivityName;
 SELECT WorkMode,SUM(PlannedHours) AS PlannedHours,SUM(ActualHours) AS ActualHours,
 SUM(CASE WHEN ChargeType='Client' THEN ActualHours ELSE 0 END) AS ClientActualHours,
 SUM(CASE WHEN ChargeType='Internal' THEN ActualHours ELSE 0 END) AS InternalActualHours,
 SUM(CASE WHEN ChargeType NOT IN ('Client','Internal') THEN ActualHours ELSE 0 END) AS UnclassifiedActualHours
 FROM #Period GROUP BY WorkMode;
 -- 7: Activities planned, worked or updated during the period; status is CURRENT.
 SELECT r.RecordId AS TaskId,JSON_VALUE(r.Payload,'$.project') AS ProjectId,
 JSON_VALUE(r.Payload,'$.title') AS ActivityName,JSON_VALUE(r.Payload,'$.module') AS Module,
 COALESCE(NULLIF(JSON_VALUE(r.Payload,'$.typeId'),''),'implementation') AS TypeId,
 JSON_VALUE(r.Payload,'$.status') AS CurrentStatus,TRY_CONVERT(decimal(8,2),JSON_VALUE(r.Payload,'$.completion')) AS CurrentCompletionPercent,
 JSON_VALUE(r.Payload,'$.plannedStart') AS PlannedStart,JSON_VALUE(r.Payload,'$.plannedFinish') AS PlannedFinish,
 COALESCE((SELECT SUM(x.ActualHours) FROM #Period x WHERE x.TaskId COLLATE DATABASE_DEFAULT = r.RecordId COLLATE DATABASE_DEFAULT),0) AS PeriodActualHours,
 JSON_VALUE(r.Payload,'$.followupNote') AS LatestFollowup,JSON_VALUE(r.Payload,'$.nextSessionDate') AS NextSessionDate
 FROM dbo.WorkspaceRecords r WHERE r.WorkspaceId=@WorkspaceId AND r.Kind='task'
 AND (@ProjectId IS NULL OR JSON_VALUE(r.Payload,'$.project')=@ProjectId)
 AND (@TypeId IS NULL OR COALESCE(NULLIF(JSON_VALUE(r.Payload,'$.typeId'),''),'implementation')=@TypeId)
 AND (EXISTS(SELECT 1 FROM #Period x WHERE x.TaskId COLLATE DATABASE_DEFAULT = r.RecordId COLLATE DATABASE_DEFAULT)
 OR @WorkMode IS NULL AND (
 TRY_CONVERT(date,JSON_VALUE(r.Payload,'$.plannedStart'))<=@ToDate
 AND TRY_CONVERT(date,COALESCE(NULLIF(JSON_VALUE(r.Payload,'$.plannedFinish'),''),JSON_VALUE(r.Payload,'$.due')))>=@FromDate
 OR EXISTS(SELECT 1 FROM OPENJSON(r.Payload,'$.history') h
 WHERE CONVERT(date,SWITCHOFFSET(TRY_CONVERT(datetimeoffset,JSON_VALUE(h.value,'$.at')),'+03:00')) BETWEEN @FromDate AND @ToDate)));
 -- 8: Detailed timesheets.
 SELECT * FROM #Period ORDER BY COALESCE(ActualDate,PlannedDate),ProjectCode,ActivityName;
END;
GO
CREATE OR ALTER VIEW dbo.vwCustomerMaster AS
SELECT w.Id AS WorkspaceId,c.CustomerId,c.CustomerCode,c.CustomerName,c.Active
FROM dbo.Workspaces w CROSS APPLY OPENJSON(w.SettingsJson,'$.customers') WITH(
 CustomerId nvarchar(100) '$.id',CustomerCode nvarchar(50) '$.code',CustomerName nvarchar(160) '$.name',Active bit '$.active') c;
GO
CREATE OR ALTER VIEW dbo.vwProjectMaster AS
SELECT r.WorkspaceId,r.RecordId AS ProjectId,CONVERT(nvarchar(50),JSON_VALUE(r.Payload,'$.code')) AS ProjectCode,
 CONVERT(nvarchar(90),JSON_VALUE(r.Payload,'$.name')) AS ProjectName,JSON_VALUE(r.Payload,'$.lead') AS ProjectInchargeId,
 TRY_CONVERT(date,JSON_VALUE(r.Payload,'$.start')) AS PlannedStart,TRY_CONVERT(date,JSON_VALUE(r.Payload,'$.due')) AS TargetGoLive,
 CONVERT(nvarchar(40),COALESCE(NULLIF(JSON_VALUE(r.Payload,'$.stageType'),''),'implementation')) AS StageTypeId,ty.TypeName AS CurrentStage,
 CONVERT(nvarchar(100),JSON_VALUE(r.Payload,'$.customerId')) AS CustomerId,c.CustomerCode,c.CustomerName
FROM dbo.WorkspaceRecords r LEFT JOIN dbo.vwActivityTypes ty ON ty.WorkspaceId=r.WorkspaceId AND ty.TypeId=COALESCE(NULLIF(JSON_VALUE(r.Payload,'$.stageType'),''),'implementation')
LEFT JOIN dbo.vwCustomerMaster c ON c.WorkspaceId=r.WorkspaceId AND c.CustomerId=JSON_VALUE(r.Payload,'$.customerId') WHERE r.Kind='project';
GO
CREATE OR ALTER VIEW dbo.vwAllocationWorkforce AS
SELECT t.WorkspaceId,t.RecordId AS TaskId,a.AllocationId,a.WeeklyPlanId,a.WeeklyWeek,a.TeamGroupId,
 COALESCE(a.BillableToClient,CONVERT(bit,1)) AS BillableToClient,a.BillingConfirmed,a.BillingUpdatedBy,a.BillingUpdatedAt,a.Instructions
FROM dbo.WorkspaceRecords t CROSS APPLY OPENJSON(t.Payload,'$.allocations') WITH(
 AllocationId nvarchar(100) '$.id',WeeklyPlanId nvarchar(100) '$.weeklyPlanId',WeeklyWeek date '$.weeklyWeek',TeamGroupId nvarchar(100) '$.teamGroupId',
 BillableToClient bit '$.billableToClient',BillingConfirmed bit '$.billingConfirmed',BillingUpdatedBy nvarchar(100) '$.billingUpdatedBy',BillingUpdatedAt datetimeoffset '$.billingUpdatedAt',Instructions nvarchar(2000) '$.instructions') a
WHERE t.Kind='task';
GO
CREATE OR ALTER VIEW dbo.vwTimesheetBilling AS
SELECT e.WorkspaceId,e.TaskId,e.EntryId,e.ProjectId,e.CompanyId,e.ActivityId,e.ActivityName,e.Module,e.TypeId,e.EmployeeId,e.PlannedDate,e.ActualDate,e.WorkMode,
 CONVERT(nvarchar(30),CASE WHEN e.ChargeType='Client' AND a.BillableToClient=0 THEN 'Non-billable client' ELSE e.ChargeType END) AS ChargeType,
 e.PlannedHours,e.ActualHours,e.CurrentEntryStatus,e.CurrentActivityStatus,e.Remarks,e.EntrySource,
 COALESCE(a.BillableToClient,CONVERT(bit,1)) AS BillableToClient,
 CONVERT(decimal(18,2),CASE WHEN e.ChargeType='Client' AND COALESCE(a.BillableToClient,1)=1 THEN e.ActualHours ELSE 0 END) AS ClientDeductibleHours
FROM dbo.vwTimesheetEntries e LEFT JOIN dbo.vwAllocationWorkforce a ON a.WorkspaceId=e.WorkspaceId AND a.TaskId COLLATE DATABASE_DEFAULT = e.TaskId COLLATE DATABASE_DEFAULT AND a.AllocationId COLLATE DATABASE_DEFAULT = e.EntryId COLLATE DATABASE_DEFAULT;
GO
CREATE OR ALTER VIEW dbo.vwEmployeeDailyTimesheets AS
SELECT e.WorkspaceId,e.ActualDate AS WorkDate,e.EmployeeId,u.UserName AS EmployeeName,
 e.ProjectId,p.ProjectCode,p.ProjectName,p.CustomerId,p.CustomerCode,p.CustomerName,
 e.TypeId,ty.TypeName,e.ActivityId,COALESCE(am.ActivityCode,fallback.ActivityCode) AS ActivityCode,e.ActivityName,e.Module,
 e.Remarks AS Notes,e.ActualHours AS Hours,e.WorkMode,e.ChargeType,e.ClientDeductibleHours,e.TaskId,e.EntryId AS AllocationId
FROM dbo.vwTimesheetBilling e
LEFT JOIN dbo.vwProjectMaster p ON p.WorkspaceId=e.WorkspaceId AND p.ProjectId COLLATE DATABASE_DEFAULT = e.ProjectId COLLATE DATABASE_DEFAULT
LEFT JOIN dbo.vwUserMaster u ON u.WorkspaceId=e.WorkspaceId AND u.MemberId COLLATE DATABASE_DEFAULT = e.EmployeeId COLLATE DATABASE_DEFAULT
LEFT JOIN dbo.vwActivityTypes ty ON ty.WorkspaceId=e.WorkspaceId AND ty.TypeId COLLATE DATABASE_DEFAULT = e.TypeId COLLATE DATABASE_DEFAULT
LEFT JOIN dbo.vwActivityMaster am ON am.WorkspaceId=e.WorkspaceId AND am.ActivityId COLLATE DATABASE_DEFAULT = e.ActivityId COLLATE DATABASE_DEFAULT
OUTER APPLY(SELECT MIN(a.ActivityCode) AS ActivityCode FROM dbo.vwActivityMaster a WHERE a.WorkspaceId=e.WorkspaceId AND a.ActivityName COLLATE DATABASE_DEFAULT = e.ActivityName COLLATE DATABASE_DEFAULT AND a.TypeId COLLATE DATABASE_DEFAULT = e.TypeId COLLATE DATABASE_DEFAULT HAVING COUNT(*)=1) fallback
WHERE e.EntrySource='Daily allocation' AND e.ActualHours>0;
GO
CREATE OR ALTER VIEW dbo.vwEmployeeTimesheetTotals AS
SELECT WorkspaceId,WorkDate,EmployeeId,EmployeeName,SUM(Hours) AS Hours,SUM(ClientDeductibleHours) AS ClientDeductibleHours,
 SUM(CASE WHEN ChargeType='Internal' THEN Hours ELSE 0 END) AS InternalHours,
 SUM(CASE WHEN ChargeType='Non-billable client' THEN Hours ELSE 0 END) AS ClientHoursNotDeducted
FROM dbo.vwEmployeeDailyTimesheets GROUP BY WorkspaceId,WorkDate,EmployeeId,EmployeeName;
GO
CREATE OR ALTER VIEW dbo.vwWeeklySiteVisits AS
SELECT e.WorkspaceId,a.WeeklyPlanId,a.WeeklyWeek,e.EntryId AS AllocationId,e.TaskId,e.PlannedDate AS VisitDate,e.EmployeeId,u.UserName AS EmployeeName,
 p.CustomerId,p.CustomerCode,p.CustomerName,e.ProjectId,p.ProjectCode,p.ProjectName,e.TypeId,ty.TypeName,e.ActivityName,e.Module,
 times.StartTime,times.EndTime,e.WorkMode,e.CurrentEntryStatus,a.Instructions AS Notes
FROM dbo.vwTimesheetEntries e JOIN dbo.vwAllocationWorkforce a ON a.WorkspaceId=e.WorkspaceId AND a.TaskId COLLATE DATABASE_DEFAULT = e.TaskId COLLATE DATABASE_DEFAULT AND a.AllocationId COLLATE DATABASE_DEFAULT = e.EntryId COLLATE DATABASE_DEFAULT
LEFT JOIN dbo.vwProjectMaster p ON p.WorkspaceId=e.WorkspaceId AND p.ProjectId COLLATE DATABASE_DEFAULT = e.ProjectId COLLATE DATABASE_DEFAULT
LEFT JOIN dbo.vwUserMaster u ON u.WorkspaceId=e.WorkspaceId AND u.MemberId COLLATE DATABASE_DEFAULT = e.EmployeeId COLLATE DATABASE_DEFAULT
LEFT JOIN dbo.vwActivityTypes ty ON ty.WorkspaceId=e.WorkspaceId AND ty.TypeId COLLATE DATABASE_DEFAULT = e.TypeId COLLATE DATABASE_DEFAULT
LEFT JOIN dbo.vwDailyAllocations v ON v.WorkspaceId=e.WorkspaceId AND v.TaskId COLLATE DATABASE_DEFAULT = e.TaskId COLLATE DATABASE_DEFAULT AND v.AllocationId COLLATE DATABASE_DEFAULT = e.EntryId COLLATE DATABASE_DEFAULT
OUTER APPLY(SELECT v.PlannedStart AS StartTime,v.PlannedEnd AS EndTime) times
WHERE NULLIF(a.WeeklyPlanId,'') IS NOT NULL;
GO
CREATE OR ALTER VIEW dbo.vwClientHoursAudit AS
SELECT t.WorkspaceId,t.RecordId AS TaskId,JSON_VALUE(a.value,'$.id') AS AllocationId,
 JSON_VALUE(a.value,'$.assignee') AS EmployeeId,h.Deduct,h.Confirmed,h.UpdatedBy,h.UpdatedAt
FROM dbo.WorkspaceRecords t CROSS APPLY OPENJSON(t.Payload,'$.allocations') a
CROSS APPLY OPENJSON(a.value,'$.billingHistory') WITH(Deduct bit '$.deduct',Confirmed bit '$.confirmed',UpdatedBy nvarchar(100) '$.by',UpdatedAt datetimeoffset '$.at') h
WHERE t.Kind='task';
GO
CREATE OR ALTER PROCEDURE dbo.uspProjectStatusReport
 @WorkspaceId uniqueidentifier,@FromDate date,@ToDate date,
 @ProjectId nvarchar(100)=NULL,@TypeId nvarchar(40)=NULL,@WorkMode nvarchar(20)=NULL
AS
BEGIN
 SET NOCOUNT ON;
 IF @WorkspaceId IS NULL OR @FromDate IS NULL OR @ToDate IS NULL OR @FromDate>@ToDate
  THROW 51010,'Workspace and a valid inclusive date range are required.',1;
 IF @WorkMode IS NOT NULL AND @WorkMode NOT IN ('Onsite','Offsite','Unclassified')
  THROW 51011,'Use Onsite, Offsite, Unclassified or NULL for work mode.',1;
 SELECT e.WorkspaceId,e.TaskId,e.EntryId,e.ProjectId,e.CompanyId,e.ActivityId,e.ActivityName,e.Module,e.TypeId,
 p.ProjectCode,p.ProjectName,p.CurrentStage,pc.CompanyName,ty.TypeName,e.EmployeeId,m.UserName AS EmployeeName,
 e.PlannedDate,CASE WHEN e.ActualHours>0 THEN e.ActualDate END AS ActualDate,e.WorkMode,e.ChargeType,
 CONVERT(decimal(18,2),CASE WHEN e.PlannedDate BETWEEN @FromDate AND @ToDate THEN e.PlannedHours ELSE 0 END) AS PlannedHours,
 CONVERT(decimal(18,2),CASE WHEN e.ActualDate BETWEEN @FromDate AND @ToDate THEN e.ActualHours ELSE 0 END) AS ActualHours,
 e.CurrentEntryStatus,e.CurrentActivityStatus,e.Remarks,e.EntrySource
 INTO #Period
 FROM dbo.vwTimesheetBilling e LEFT JOIN dbo.vwProjectMaster p ON p.WorkspaceId=e.WorkspaceId AND p.ProjectId COLLATE DATABASE_DEFAULT = e.ProjectId COLLATE DATABASE_DEFAULT
 LEFT JOIN dbo.vwActivityTypes ty ON ty.WorkspaceId=e.WorkspaceId AND ty.TypeId COLLATE DATABASE_DEFAULT = e.TypeId COLLATE DATABASE_DEFAULT
 LEFT JOIN dbo.vwUserMaster m ON m.WorkspaceId=e.WorkspaceId AND m.MemberId COLLATE DATABASE_DEFAULT = e.EmployeeId COLLATE DATABASE_DEFAULT
 OUTER APPLY (SELECT JSON_VALUE(company.value,'$.name') AS CompanyName
 FROM dbo.WorkspaceRecords projectRecord CROSS APPLY OPENJSON(projectRecord.Payload,'$.companies') company
 WHERE projectRecord.WorkspaceId=e.WorkspaceId AND projectRecord.Kind='project'
 AND projectRecord.RecordId COLLATE DATABASE_DEFAULT = e.ProjectId COLLATE DATABASE_DEFAULT AND JSON_VALUE(company.value,'$.id')=e.CompanyId) pc
 WHERE e.WorkspaceId=@WorkspaceId AND (@ProjectId IS NULL OR e.ProjectId=@ProjectId)
 AND (@TypeId IS NULL OR e.TypeId=@TypeId) AND (@WorkMode IS NULL OR e.WorkMode=@WorkMode)
 AND (e.PlannedDate BETWEEN @FromDate AND @ToDate OR e.ActualHours>0 AND e.ActualDate BETWEEN @FromDate AND @ToDate);
 -- 1: Current project-stage portfolio; not a historical stage snapshot.
 SELECT StageTypeId,CurrentStage,COUNT_BIG(*) AS ProjectCount FROM dbo.vwProjectMaster
 WHERE WorkspaceId=@WorkspaceId AND (@ProjectId IS NULL OR ProjectId=@ProjectId)
 GROUP BY StageTypeId,CurrentStage;
 -- 2: Period totals.
 SELECT @FromDate AS FromDate,@ToDate AS ToDate,COALESCE(SUM(PlannedHours),0) AS PlannedHours,COALESCE(SUM(ActualHours),0) AS ActualHours,
 COALESCE(SUM(CASE WHEN ChargeType='Client' THEN ActualHours ELSE 0 END),0) AS ClientActualHours,
 COALESCE(SUM(CASE WHEN ChargeType='Internal' THEN ActualHours ELSE 0 END),0) AS InternalActualHours,
 COALESCE(SUM(CASE WHEN ChargeType NOT IN ('Client','Internal','Non-billable client') THEN ActualHours ELSE 0 END),0) AS UnclassifiedActualHours,COALESCE(SUM(CASE WHEN ChargeType='Non-billable client' THEN ActualHours ELSE 0 END),0) AS ClientHoursNotDeducted FROM #Period;
 -- 3-6: Project, type, activity and mode breakdowns. These totals reconcile.
 SELECT ProjectId,ProjectCode,ProjectName,SUM(PlannedHours) AS PlannedHours,SUM(ActualHours) AS ActualHours,
 SUM(CASE WHEN ChargeType='Client' THEN ActualHours ELSE 0 END) AS ClientActualHours,
 SUM(CASE WHEN ChargeType='Internal' THEN ActualHours ELSE 0 END) AS InternalActualHours,
 SUM(CASE WHEN ChargeType NOT IN ('Client','Internal','Non-billable client') THEN ActualHours ELSE 0 END) AS UnclassifiedActualHours,COALESCE(SUM(CASE WHEN ChargeType='Non-billable client' THEN ActualHours ELSE 0 END),0) AS ClientHoursNotDeducted
 FROM #Period GROUP BY ProjectId,ProjectCode,ProjectName;
 SELECT TypeId,TypeName,SUM(PlannedHours) AS PlannedHours,SUM(ActualHours) AS ActualHours,
 SUM(CASE WHEN ChargeType='Client' THEN ActualHours ELSE 0 END) AS ClientActualHours,
 SUM(CASE WHEN ChargeType='Internal' THEN ActualHours ELSE 0 END) AS InternalActualHours,
 SUM(CASE WHEN ChargeType NOT IN ('Client','Internal','Non-billable client') THEN ActualHours ELSE 0 END) AS UnclassifiedActualHours,COALESCE(SUM(CASE WHEN ChargeType='Non-billable client' THEN ActualHours ELSE 0 END),0) AS ClientHoursNotDeducted
 FROM #Period GROUP BY TypeId,TypeName;
 SELECT ProjectId,TypeId,ActivityId,ActivityName,SUM(PlannedHours) AS PlannedHours,SUM(ActualHours) AS ActualHours,
 SUM(CASE WHEN ChargeType='Client' THEN ActualHours ELSE 0 END) AS ClientActualHours,
 SUM(CASE WHEN ChargeType='Internal' THEN ActualHours ELSE 0 END) AS InternalActualHours,
 SUM(CASE WHEN ChargeType NOT IN ('Client','Internal','Non-billable client') THEN ActualHours ELSE 0 END) AS UnclassifiedActualHours,COALESCE(SUM(CASE WHEN ChargeType='Non-billable client' THEN ActualHours ELSE 0 END),0) AS ClientHoursNotDeducted
 FROM #Period GROUP BY ProjectId,TypeId,ActivityId,ActivityName;
 SELECT WorkMode,SUM(PlannedHours) AS PlannedHours,SUM(ActualHours) AS ActualHours,
 SUM(CASE WHEN ChargeType='Client' THEN ActualHours ELSE 0 END) AS ClientActualHours,
 SUM(CASE WHEN ChargeType='Internal' THEN ActualHours ELSE 0 END) AS InternalActualHours,
 SUM(CASE WHEN ChargeType NOT IN ('Client','Internal','Non-billable client') THEN ActualHours ELSE 0 END) AS UnclassifiedActualHours,COALESCE(SUM(CASE WHEN ChargeType='Non-billable client' THEN ActualHours ELSE 0 END),0) AS ClientHoursNotDeducted
 FROM #Period GROUP BY WorkMode;
 -- 7: Activities planned, worked or updated during the period; status is CURRENT.
 SELECT r.RecordId AS TaskId,JSON_VALUE(r.Payload,'$.project') AS ProjectId,
 JSON_VALUE(r.Payload,'$.title') AS ActivityName,JSON_VALUE(r.Payload,'$.module') AS Module,
 COALESCE(NULLIF(JSON_VALUE(r.Payload,'$.typeId'),''),'implementation') AS TypeId,
 JSON_VALUE(r.Payload,'$.status') AS CurrentStatus,TRY_CONVERT(decimal(8,2),JSON_VALUE(r.Payload,'$.completion')) AS CurrentCompletionPercent,
 JSON_VALUE(r.Payload,'$.plannedStart') AS PlannedStart,JSON_VALUE(r.Payload,'$.plannedFinish') AS PlannedFinish,
 COALESCE((SELECT SUM(x.ActualHours) FROM #Period x WHERE x.TaskId COLLATE DATABASE_DEFAULT = r.RecordId COLLATE DATABASE_DEFAULT),0) AS PeriodActualHours,
 JSON_VALUE(r.Payload,'$.followupNote') AS LatestFollowup,JSON_VALUE(r.Payload,'$.nextSessionDate') AS NextSessionDate
 FROM dbo.WorkspaceRecords r WHERE r.WorkspaceId=@WorkspaceId AND r.Kind='task'
 AND (@ProjectId IS NULL OR JSON_VALUE(r.Payload,'$.project')=@ProjectId)
 AND (@TypeId IS NULL OR COALESCE(NULLIF(JSON_VALUE(r.Payload,'$.typeId'),''),'implementation')=@TypeId)
 AND (EXISTS(SELECT 1 FROM #Period x WHERE x.TaskId COLLATE DATABASE_DEFAULT = r.RecordId COLLATE DATABASE_DEFAULT)
 OR @WorkMode IS NULL AND (
 TRY_CONVERT(date,JSON_VALUE(r.Payload,'$.plannedStart'))<=@ToDate
 AND TRY_CONVERT(date,COALESCE(NULLIF(JSON_VALUE(r.Payload,'$.plannedFinish'),''),JSON_VALUE(r.Payload,'$.due')))>=@FromDate
 OR EXISTS(SELECT 1 FROM OPENJSON(r.Payload,'$.history') h
 WHERE CONVERT(date,SWITCHOFFSET(TRY_CONVERT(datetimeoffset,JSON_VALUE(h.value,'$.at')),'+03:00')) BETWEEN @FromDate AND @ToDate)));
 -- 8: Detailed timesheets.
 SELECT * FROM #Period ORDER BY COALESCE(ActualDate,PlannedDate),ProjectCode,ActivityName;
END;
GO
CREATE OR ALTER VIEW dbo.vwAmcContracts AS
SELECT p.WorkspaceId,p.ProjectId,p.ProjectCode,p.ProjectName,p.CustomerId,p.CustomerCode,p.CustomerName,p.CurrentStage,
 CONVERT(nvarchar(60),JSON_VALUE(r.Payload,'$.amc.id')) AS ContractId,
 TRY_CONVERT(date,JSON_VALUE(r.Payload,'$.amc.start')) AS AmcStart,
 TRY_CONVERT(date,JSON_VALUE(r.Payload,'$.amc.end')) AS AmcEnd,
 CONVERT(nvarchar(20),JSON_VALUE(r.Payload,'$.amc.cycle')) AS VisitCycle,
 TRY_CONVERT(int,JSON_VALUE(r.Payload,'$.amc.visits')) AS VisitsPerCycle,
 TRY_CONVERT(decimal(8,2),JSON_VALUE(r.Payload,'$.amc.hours')) AS HoursPerVisit,
 CONVERT(nvarchar(5),JSON_VALUE(r.Payload,'$.amc.preferredStart')) AS PreferredStart,
 CONVERT(nvarchar(100),JSON_VALUE(r.Payload,'$.amc.activityId')) AS SuggestedActivityId,
 JSON_QUERY(r.Payload,'$.amc.staff') AS RequiredStaffJson
FROM dbo.vwProjectMaster p JOIN dbo.WorkspaceRecords r ON r.WorkspaceId=p.WorkspaceId AND r.Kind='project' AND r.RecordId COLLATE DATABASE_DEFAULT = p.ProjectId COLLATE DATABASE_DEFAULT
WHERE p.StageTypeId='amc';
GO
CREATE OR ALTER FUNCTION dbo.fnAmcContractCycles(@Start date,@Finish date,@Cycle nvarchar(20))
RETURNS TABLE
AS RETURN
WITH Numbers AS (SELECT TOP (4000) CONVERT(int,ROW_NUMBER() OVER(ORDER BY (SELECT NULL))-1) AS n FROM sys.all_objects a CROSS JOIN sys.all_objects b),
Bounds AS (SELECT CASE @Cycle WHEN 'daily' THEN 1 WHEN 'alternate-days' THEN 2 WHEN 'weekly' THEN 7 ELSE 0 END AS DayStep,
 CASE @Cycle WHEN 'monthly' THEN 1 WHEN 'quarterly' THEN 3 WHEN 'six-monthly' THEN 6 WHEN 'yearly' THEN 12 ELSE 0 END AS MonthStep),
Limits AS (SELECT DayStep,MonthStep,CASE WHEN DayStep>0 THEN DATEDIFF(day,@Start,@Finish)/DayStep+1 WHEN MonthStep>0 THEN DATEDIFF(month,@Start,@Finish)/MonthStep+1 ELSE 0 END AS CycleCount FROM Bounds),
Dates AS(SELECT n,CASE WHEN DayStep>0 THEN DATEADD(day,(CASE WHEN n<CycleCount THEN n ELSE 0 END)*DayStep,@Start) ELSE DATEADD(month,(CASE WHEN n<CycleCount THEN n ELSE 0 END)*MonthStep,@Start) END AS CycleStart,
 CASE WHEN DayStep>0 THEN DATEADD(day,(CASE WHEN n<CycleCount THEN n+1 ELSE 1 END)*DayStep,@Start) ELSE DATEADD(month,(CASE WHEN n<CycleCount THEN n+1 ELSE 1 END)*MonthStep,@Start) END AS NextStart
 FROM Numbers CROSS JOIN Limits WHERE n<CycleCount)
SELECT n AS CycleIndex,CycleStart,CASE WHEN DATEADD(day,-1,NextStart)>@Finish THEN @Finish ELSE DATEADD(day,-1,NextStart) END AS CycleEnd
FROM Dates WHERE CycleStart<=@Finish AND @Finish>=@Start;
GO
CREATE OR ALTER VIEW dbo.vwAmcAllocationEvidence AS
SELECT e.WorkspaceId,e.ProjectId,e.TaskId,e.EntryId,e.EmployeeId,e.PlannedDate,e.ActualDate,e.PlannedHours,e.ActualHours,
 CONVERT(nvarchar(180),COALESCE(NULLIF(a.VisitId,''),NULLIF(a.TeamGroupId,''),CONVERT(nvarchar(10),e.PlannedDate,23)+'|'+a.StartTime+'|'+a.EndTime)) AS PlannedVisitKey,
 CONVERT(nvarchar(180),COALESCE(NULLIF(a.VisitId,''),NULLIF(a.TeamGroupId,''),CONVERT(nvarchar(10),e.ActualDate,23)+'|'+a.StartTime+'|'+a.EndTime)) AS ActualVisitKey,
 a.VisitId,a.ContractId,a.LinkedCycleStart,a.DueDate,COALESCE(a.CountsAsVisit,CONVERT(bit,1)) AS CountsAsVisit
FROM dbo.vwTimesheetEntries e JOIN dbo.WorkspaceRecords t ON t.WorkspaceId=e.WorkspaceId AND t.Kind='task' AND t.RecordId COLLATE DATABASE_DEFAULT = e.TaskId COLLATE DATABASE_DEFAULT
CROSS APPLY OPENJSON(t.Payload,'$.allocations') WITH(
 AllocationId nvarchar(100) '$.id',VisitId nvarchar(180) '$.amcVisitId',ContractId nvarchar(60) '$.amcContractId',
 LinkedCycleStart date '$.amcCycleStart',DueDate date '$.amcDueDate',TeamGroupId nvarchar(100) '$.teamGroupId',
 StartTime nvarchar(5) '$.plannedStartTime',EndTime nvarchar(5) '$.plannedEndTime',CountsAsVisit bit '$.countsAsAmcVisit') a
WHERE e.EntryId COLLATE DATABASE_DEFAULT = a.AllocationId COLLATE DATABASE_DEFAULT AND e.EntrySource='Daily allocation' AND e.TypeId='amc' AND e.WorkMode='Onsite';
GO
CREATE OR ALTER VIEW dbo.vwAmcCycleCompliance AS
SELECT c.WorkspaceId,c.ProjectId,c.ProjectCode,c.ProjectName,c.CustomerName,c.ContractId,c.VisitCycle,
 cy.CycleStart,cy.CycleEnd,c.VisitsPerCycle AS RequiredVisits,c.VisitsPerCycle*c.HoursPerVisit AS RequiredHours,c.HoursPerVisit,
 COALESCE(a.AttendedVisits,0) AS AttendedVisits,COALESCE(a.QualifiedVisits,0) AS QualifiedVisits,COALESCE(a.ActualHours,0) AS OnsiteHoursCountedOnce,
 COALESCE(p.ScheduledVisits,0) AS ScheduledVisits,COALESCE(p.PlannedHours,0) AS PlannedHoursCountedOnce,
 CASE WHEN c.VisitsPerCycle>COALESCE(a.QualifiedVisits,0) THEN c.VisitsPerCycle-COALESCE(a.QualifiedVisits,0) ELSE 0 END AS VisitsGap,
 CASE WHEN c.VisitsPerCycle*c.HoursPerVisit>COALESCE(a.ActualHours,0) THEN c.VisitsPerCycle*c.HoursPerVisit-COALESCE(a.ActualHours,0) ELSE 0 END AS HoursGap,
 CONVERT(bit,CASE WHEN cy.CycleEnd<CONVERT(date,DATEADD(hour,3,SYSUTCDATETIME())) THEN 1 ELSE 0 END) AS ClosedCycle
FROM dbo.vwAmcContracts c CROSS APPLY dbo.fnAmcContractCycles(c.AmcStart,c.AmcEnd,c.VisitCycle) cy
OUTER APPLY(
 SELECT COUNT(*) AS AttendedVisits,SUM(qualified.CreditedHours) AS ActualHours,SUM(qualified.Qualifies) AS QualifiedVisits FROM(SELECT q.CreditedHours,CASE WHEN q.CreditedHours>=c.HoursPerVisit AND NOT EXISTS(
 SELECT 1 FROM OPENJSON(c.RequiredStaffJson) staff WHERE NOT EXISTS(SELECT 1 FROM dbo.vwAmcAllocationEvidence evidence
 WHERE evidence.WorkspaceId=c.WorkspaceId AND evidence.ProjectId COLLATE DATABASE_DEFAULT = c.ProjectId COLLATE DATABASE_DEFAULT AND evidence.ActualVisitKey COLLATE DATABASE_DEFAULT = q.VisitKey COLLATE DATABASE_DEFAULT AND evidence.EmployeeId COLLATE DATABASE_DEFAULT = staff.value COLLATE DATABASE_DEFAULT
 AND evidence.ActualDate BETWEEN cy.CycleStart AND cy.CycleEnd AND evidence.ActualHours>0 AND evidence.CountsAsVisit=1
 AND (evidence.ContractId IS NULL OR evidence.ContractId COLLATE DATABASE_DEFAULT = c.ContractId COLLATE DATABASE_DEFAULT) AND (evidence.LinkedCycleStart IS NULL OR evidence.LinkedCycleStart=cy.CycleStart))) THEN 1 ELSE 0 END AS Qualifies
 FROM(SELECT e.ActualVisitKey AS VisitKey,MAX(e.ActualHours) AS CreditedHours FROM dbo.vwAmcAllocationEvidence e
 WHERE e.WorkspaceId=c.WorkspaceId AND e.ProjectId COLLATE DATABASE_DEFAULT = c.ProjectId COLLATE DATABASE_DEFAULT AND e.ActualDate BETWEEN cy.CycleStart AND cy.CycleEnd AND e.ActualHours>0 AND e.CountsAsVisit=1
 AND (e.ContractId IS NULL OR e.ContractId COLLATE DATABASE_DEFAULT = c.ContractId COLLATE DATABASE_DEFAULT) AND (e.LinkedCycleStart IS NULL OR e.LinkedCycleStart=cy.CycleStart)
 GROUP BY e.ActualVisitKey) q) qualified
) a
OUTER APPLY(
 SELECT SUM(qualified.CreditedHours) AS PlannedHours,SUM(qualified.Qualifies) AS ScheduledVisits FROM(SELECT q.CreditedHours,CASE WHEN q.CreditedHours>=c.HoursPerVisit AND NOT EXISTS(
 SELECT 1 FROM OPENJSON(c.RequiredStaffJson) staff WHERE NOT EXISTS(SELECT 1 FROM dbo.vwAmcAllocationEvidence evidence
 WHERE evidence.WorkspaceId=c.WorkspaceId AND evidence.ProjectId COLLATE DATABASE_DEFAULT = c.ProjectId COLLATE DATABASE_DEFAULT AND evidence.PlannedVisitKey COLLATE DATABASE_DEFAULT = q.VisitKey COLLATE DATABASE_DEFAULT AND evidence.EmployeeId COLLATE DATABASE_DEFAULT = staff.value COLLATE DATABASE_DEFAULT
 AND evidence.PlannedDate BETWEEN cy.CycleStart AND cy.CycleEnd AND evidence.PlannedHours>=c.HoursPerVisit
 AND (evidence.ContractId IS NULL OR evidence.ContractId COLLATE DATABASE_DEFAULT = c.ContractId COLLATE DATABASE_DEFAULT) AND (evidence.LinkedCycleStart IS NULL OR evidence.LinkedCycleStart=cy.CycleStart))) THEN 1 ELSE 0 END AS Qualifies
 FROM(SELECT e.PlannedVisitKey AS VisitKey,MAX(e.PlannedHours) AS CreditedHours FROM dbo.vwAmcAllocationEvidence e
 WHERE e.WorkspaceId=c.WorkspaceId AND e.ProjectId COLLATE DATABASE_DEFAULT = c.ProjectId COLLATE DATABASE_DEFAULT AND e.PlannedDate BETWEEN cy.CycleStart AND cy.CycleEnd
 AND (e.ContractId IS NULL OR e.ContractId COLLATE DATABASE_DEFAULT = c.ContractId COLLATE DATABASE_DEFAULT) AND (e.LinkedCycleStart IS NULL OR e.LinkedCycleStart=cy.CycleStart)
 GROUP BY e.PlannedVisitKey) q) qualified
) p;
GO
CREATE OR ALTER VIEW dbo.vwAmcVisitRequirements AS
SELECT c.WorkspaceId,c.ProjectId,c.ProjectCode,c.ProjectName,c.ContractId,cy.CycleStart,cy.CycleEnd,
 n.n AS VisitIndex,CONVERT(nvarchar(180),c.ProjectId+'/'+c.ContractId+'/'+CONVERT(nvarchar(10),cy.CycleStart,23)+'/'+CONVERT(nvarchar(3),n.n)) AS VisitId,
 DATEADD(day,n.n*(DATEDIFF(day,cy.CycleStart,cy.CycleEnd)+1)/NULLIF(c.VisitsPerCycle,0),cy.CycleStart) AS SuggestedDueDate,
 c.HoursPerVisit,c.PreferredStart,c.SuggestedActivityId,c.RequiredStaffJson
FROM dbo.vwAmcContracts c CROSS APPLY dbo.fnAmcContractCycles(c.AmcStart,c.AmcEnd,c.VisitCycle) cy
CROSS APPLY(SELECT TOP (366) CONVERT(int,ROW_NUMBER() OVER(ORDER BY (SELECT NULL))-1) AS n FROM sys.all_objects) n
WHERE n.n<c.VisitsPerCycle AND c.VisitsPerCycle>0;
GO
CREATE OR ALTER VIEW dbo.vwAmcAlerts AS
SELECT WorkspaceId,ProjectId,ProjectCode,ProjectName,CycleStart,CycleEnd,RequiredVisits,RequiredHours,QualifiedVisits,OnsiteHoursCountedOnce,VisitsGap,HoursGap
FROM dbo.vwAmcCycleCompliance WHERE ClosedCycle=1 AND (VisitsGap>0 OR HoursGap>0);
GO
CREATE OR ALTER PROCEDURE dbo.uspAmcComplianceReport
 @WorkspaceId uniqueidentifier,@From date,@To date,@ProjectId nvarchar(100)=NULL
AS
BEGIN
 SET NOCOUNT ON;
 IF @WorkspaceId IS NULL OR @From IS NULL OR @To IS NULL OR @From>@To THROW 51020,'Workspace and valid inclusive dates required.',1;
 SELECT * FROM dbo.vwAmcContracts WHERE WorkspaceId=@WorkspaceId AND (@ProjectId IS NULL OR ProjectId=@ProjectId);
 SELECT * FROM dbo.vwAmcCycleCompliance WHERE WorkspaceId=@WorkspaceId AND CycleStart<=@To AND CycleEnd>=@From AND (@ProjectId IS NULL OR ProjectId=@ProjectId) ORDER BY ProjectCode,CycleStart;
 SELECT * FROM dbo.vwAmcAlerts WHERE WorkspaceId=@WorkspaceId AND CycleStart<=@To AND CycleEnd>=@From AND (@ProjectId IS NULL OR ProjectId=@ProjectId) ORDER BY ProjectCode,CycleStart;
 SELECT * FROM dbo.vwAmcVisitRequirements WHERE WorkspaceId=@WorkspaceId AND SuggestedDueDate BETWEEN @From AND @To AND (@ProjectId IS NULL OR ProjectId=@ProjectId) ORDER BY ProjectCode,SuggestedDueDate,VisitIndex;
END;
GO
-- Restore runtime permissions after all dependent objects have been recreated.
IF DATABASE_PRINCIPAL_ID(N'IIS APPPOOL\MyProjectManagement') IS NOT NULL
BEGIN
 GRANT SELECT ON dbo.vwProjectTasks TO [IIS APPPOOL\MyProjectManagement];
 GRANT SELECT ON dbo.vwDailyAllocations TO [IIS APPPOOL\MyProjectManagement];
 GRANT SELECT ON dbo.vwRoleMaster TO [IIS APPPOOL\MyProjectManagement];
 GRANT SELECT ON dbo.vwRolePermissions TO [IIS APPPOOL\MyProjectManagement];
 GRANT SELECT ON dbo.vwUserMaster TO [IIS APPPOOL\MyProjectManagement];
 GRANT SELECT ON dbo.vwProjectMaster TO [IIS APPPOOL\MyProjectManagement];
 GRANT SELECT ON dbo.vwActivityMaster TO [IIS APPPOOL\MyProjectManagement];
 GRANT SELECT ON dbo.vwActivityTypes TO [IIS APPPOOL\MyProjectManagement];
 GRANT SELECT ON dbo.vwTimesheetEntries TO [IIS APPPOOL\MyProjectManagement];
 GRANT EXECUTE ON dbo.uspProjectStatusReport TO [IIS APPPOOL\MyProjectManagement];
 GRANT SELECT ON dbo.vwCustomerMaster TO [IIS APPPOOL\MyProjectManagement];
 GRANT SELECT ON dbo.vwAllocationWorkforce TO [IIS APPPOOL\MyProjectManagement];
 GRANT SELECT ON dbo.vwTimesheetBilling TO [IIS APPPOOL\MyProjectManagement];
 GRANT SELECT ON dbo.vwEmployeeDailyTimesheets TO [IIS APPPOOL\MyProjectManagement];
 GRANT SELECT ON dbo.vwEmployeeTimesheetTotals TO [IIS APPPOOL\MyProjectManagement];
 GRANT SELECT ON dbo.vwWeeklySiteVisits TO [IIS APPPOOL\MyProjectManagement];
 GRANT SELECT ON dbo.vwClientHoursAudit TO [IIS APPPOOL\MyProjectManagement];
 GRANT SELECT ON dbo.vwAmcContracts TO [IIS APPPOOL\MyProjectManagement];
 GRANT SELECT ON dbo.fnAmcContractCycles TO [IIS APPPOOL\MyProjectManagement];
 GRANT SELECT ON dbo.vwAmcAllocationEvidence TO [IIS APPPOOL\MyProjectManagement];
 GRANT SELECT ON dbo.vwAmcCycleCompliance TO [IIS APPPOOL\MyProjectManagement];
 GRANT SELECT ON dbo.vwAmcVisitRequirements TO [IIS APPPOOL\MyProjectManagement];
 GRANT SELECT ON dbo.vwAmcAlerts TO [IIS APPPOOL\MyProjectManagement];
 GRANT EXECUTE ON dbo.uspAmcComplianceReport TO [IIS APPPOOL\MyProjectManagement];
END;
GO
-- Compile and exercise the repaired dependency chain (zero rows, no data changes).
SELECT TOP(0) * FROM dbo.vwTimesheetBilling;
SELECT TOP(0) * FROM dbo.vwEmployeeDailyTimesheets;
SELECT TOP(0) * FROM dbo.vwEmployeeTimesheetTotals;
SELECT TOP(0) * FROM dbo.vwWeeklySiteVisits;
SELECT TOP(0) * FROM dbo.vwAmcCycleCompliance;
SELECT CONVERT(nvarchar(128),DATABASEPROPERTYEX(DB_NAME(),'Collation')) AS DatabaseCollation;
SELECT name,collation_name FROM sys.columns WHERE object_id=OBJECT_ID('dbo.vwTimesheetEntries') AND name='EntryId';
PRINT 'v25 collation repair completed. Restart the application pool.';
GO


-- My Project Management v26: optional read-only module-consultant report.
-- The application already stores these assignments in project JSON; no table migration is required.
USE [MyProjectManagement];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER VIEW dbo.vwProjectModuleConsultants AS
SELECT p.WorkspaceId,p.RecordId AS ProjectId,
 CONVERT(nvarchar(50),JSON_VALUE(p.Payload,'$.code')) AS ProjectCode,
 CONVERT(nvarchar(90),JSON_VALUE(p.Payload,'$.name')) AS ProjectName,
 CONVERT(nvarchar(100),JSON_VALUE(p.Payload,'$.lead')) AS ProjectInchargeId,
 CONVERT(nvarchar(80),JSON_VALUE(leadMember.Payload,'$.name')) AS ProjectInchargeName,
 CONVERT(nvarchar(60),module.[key]) COLLATE DATABASE_DEFAULT AS ModuleName,
 CONVERT(nvarchar(100),module.value) COLLATE DATABASE_DEFAULT AS ModuleConsultantId,
 CONVERT(nvarchar(80),JSON_VALUE(consultant.Payload,'$.name')) AS ModuleConsultantName,
 CONVERT(nvarchar(60),JSON_VALUE(consultant.Payload,'$.role')) AS ConsultantRole
FROM dbo.WorkspaceRecords p CROSS APPLY OPENJSON(p.Payload,'$.modules') module
LEFT JOIN dbo.TeamMembers consultant ON consultant.WorkspaceId=p.WorkspaceId
 AND consultant.MemberId COLLATE DATABASE_DEFAULT = CONVERT(nvarchar(100),module.value) COLLATE DATABASE_DEFAULT
LEFT JOIN dbo.TeamMembers leadMember ON leadMember.WorkspaceId=p.WorkspaceId
 AND leadMember.MemberId COLLATE DATABASE_DEFAULT = JSON_VALUE(p.Payload,'$.lead') COLLATE DATABASE_DEFAULT
WHERE p.Kind='project';
GO
IF DATABASE_PRINCIPAL_ID(N'IIS APPPOOL\MyProjectManagement') IS NOT NULL
 GRANT SELECT ON dbo.vwProjectModuleConsultants TO [IIS APPPOOL\MyProjectManagement];
GO
SELECT TOP(0) * FROM dbo.vwProjectModuleConsultants;
PRINT 'v26 module-consultant reporting view is ready.';
GO

-- My Project Management v27. Optional reporting view; assignments use existing JSON storage.
-- No records are changed. Legacy single owners remain represented as one allocated person.
USE [MyProjectManagement];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER VIEW dbo.vwProjectModuleTeams AS
SELECT p.WorkspaceId,p.RecordId AS ProjectId,
 CONVERT(nvarchar(50),JSON_VALUE(p.Payload,'$.code')) AS ProjectCode,
 CONVERT(nvarchar(90),JSON_VALUE(p.Payload,'$.name')) AS ProjectName,
 JSON_VALUE(p.Payload,'$.projectManager') AS ProjectManagerId,
 JSON_VALUE(manager.Payload,'$.name') AS ProjectManagerName,
 JSON_VALUE(p.Payload,'$.lead') AS ProjectInchargeId,
 JSON_VALUE(leadMember.Payload,'$.name') AS ProjectInchargeName,
 CONVERT(nvarchar(60),module.[key]) COLLATE DATABASE_DEFAULT AS ModuleName,
 CONVERT(nvarchar(100),module.value) COLLATE DATABASE_DEFAULT AS PrimaryInchargeId,
 allocated.MemberId AS AllocatedMemberId,
 JSON_VALUE(member.Payload,'$.name') AS AllocatedMemberName,
 CONVERT(bit,CASE WHEN allocated.MemberId=CONVERT(nvarchar(100),module.value) COLLATE DATABASE_DEFAULT THEN 1 ELSE 0 END) AS IsPrimaryIncharge
FROM dbo.WorkspaceRecords p
CROSS APPLY OPENJSON(p.Payload,'$.modules') module
CROSS APPLY (
 SELECT CONVERT(nvarchar(100),module.value) COLLATE DATABASE_DEFAULT AS MemberId
 UNION
 SELECT CONVERT(nvarchar(100),person.value) COLLATE DATABASE_DEFAULT
 FROM OPENJSON(p.Payload,'$.moduleTeams') team
 CROSS APPLY OPENJSON(CASE WHEN team.type=4 THEN team.value ELSE N'[]' END) person
 WHERE team.[key] COLLATE DATABASE_DEFAULT=module.[key] COLLATE DATABASE_DEFAULT AND person.type=1
) allocated
LEFT JOIN dbo.TeamMembers member ON member.WorkspaceId=p.WorkspaceId AND member.MemberId COLLATE DATABASE_DEFAULT=allocated.MemberId
LEFT JOIN dbo.TeamMembers manager ON manager.WorkspaceId=p.WorkspaceId AND manager.MemberId COLLATE DATABASE_DEFAULT=JSON_VALUE(p.Payload,'$.projectManager') COLLATE DATABASE_DEFAULT
LEFT JOIN dbo.TeamMembers leadMember ON leadMember.WorkspaceId=p.WorkspaceId AND leadMember.MemberId COLLATE DATABASE_DEFAULT=JSON_VALUE(p.Payload,'$.lead') COLLATE DATABASE_DEFAULT
WHERE p.Kind='project';
GO
IF DATABASE_PRINCIPAL_ID(N'IIS APPPOOL\MyProjectManagement') IS NOT NULL
 GRANT SELECT ON dbo.vwProjectModuleTeams TO [IIS APPPOOL\MyProjectManagement];
GO
SELECT TOP(0) * FROM dbo.vwProjectModuleTeams;
PRINT 'v27 project manager and multi-person module team view is ready.';
GO

-- v28 optional PSR procedure. Existing JSON storage; no new tables or data changes.
USE [MyProjectManagement];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER PROCEDURE dbo.uspProjectPSR
 @WorkspaceId uniqueidentifier,@ProjectId nvarchar(100),@FromDate date,@ToDate date
AS
BEGIN
 SET NOCOUNT ON;
 IF @WorkspaceId IS NULL OR NULLIF(@ProjectId,'') IS NULL OR @FromDate IS NULL OR @ToDate IS NULL OR @FromDate>@ToDate
  THROW 51028,'Workspace, project and ordered inclusive dates are required.',1;
 DECLARE @p nvarchar(max);
 SELECT @p=Payload FROM dbo.WorkspaceRecords WHERE WorkspaceId=@WorkspaceId AND Kind='project' AND RecordId=@ProjectId;
 IF @p IS NULL THROW 51029,'Project not found in this workspace.',1;
 -- Header uses current project/task status, not historical reconstruction.
 SELECT @ProjectId AS ProjectId,JSON_VALUE(@p,'$.code') AS ProjectCode,JSON_VALUE(@p,'$.name') AS ProjectName,
 JSON_VALUE(@p,'$.projectManager') AS ProjectManagerId,JSON_VALUE(@p,'$.lead') AS ProjectInchargeId,
 @FromDate AS FromDate,@ToDate AS ToDate,
 CONVERT(decimal(18,2),COALESCE((SELECT SUM(ClientDeductibleHours) FROM dbo.vwTimesheetBilling WHERE WorkspaceId=@WorkspaceId AND ProjectId=@ProjectId AND ActualDate<=@ToDate),0)/8.0) AS ClientManDaysUsedThroughTo,
 TRY_CONVERT(decimal(18,2),JSON_VALUE(@p,'$.clientMandays')) AS ContractManDays,
 CONVERT(decimal(18,2),COALESCE((SELECT SUM(ActualHours) FROM dbo.vwTimesheetBilling WHERE WorkspaceId=@WorkspaceId AND ProjectId=@ProjectId AND ActualDate BETWEEN @FromDate AND @ToDate),0)) AS PeriodActualEmployeeHours,
 COALESCE((SELECT CONVERT(int,ROUND(100.0*SUM(CASE WHEN JSON_VALUE(Payload,'$.status')='Completed' THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0),0)) FROM dbo.WorkspaceRecords WHERE WorkspaceId=@WorkspaceId AND Kind='task' AND JSON_VALUE(Payload,'$.project')=@ProjectId),0) AS CurrentProjectPercentage;
 -- Recent recorded work, inclusive actual-work dates. Includes legacy sessions.
 SELECT TaskId,ActivityName,Module,EmployeeId,ActualDate,ActualHours,ClientDeductibleHours,Remarks,WorkMode,EntrySource
 FROM dbo.vwTimesheetBilling WHERE WorkspaceId=@WorkspaceId AND ProjectId=@ProjectId AND ActualDate BETWEEN @FromDate AND @ToDate AND ActualHours>0
 ORDER BY ActualDate,TaskId,EmployeeId;
 -- Planned, worked or next-session activities in the selected period.
 SELECT r.RecordId AS TaskId,JSON_VALUE(r.Payload,'$.title') AS ActivityName,JSON_VALUE(r.Payload,'$.module') AS Module,
 TRY_CONVERT(date,JSON_VALUE(r.Payload,'$.plannedStart')) AS PlannedStart,
 COALESCE(TRY_CONVERT(date,JSON_VALUE(r.Payload,'$.plannedFinish')),TRY_CONVERT(date,JSON_VALUE(r.Payload,'$.due'))) AS PlannedFinish,
 JSON_VALUE(r.Payload,'$.status') AS CurrentStatus,TRY_CONVERT(decimal(6,2),JSON_VALUE(r.Payload,'$.completion')) AS CurrentCompletion,
 JSON_VALUE(r.Payload,'$.followupNote') AS CurrentFollowupNote,TRY_CONVERT(date,JSON_VALUE(r.Payload,'$.nextSessionDate')) AS NextSessionDate
 FROM dbo.WorkspaceRecords r WHERE r.WorkspaceId=@WorkspaceId AND r.Kind='task' AND JSON_VALUE(r.Payload,'$.project')=@ProjectId
 AND ((COALESCE(TRY_CONVERT(date,JSON_VALUE(r.Payload,'$.plannedStart')),TRY_CONVERT(date,JSON_VALUE(r.Payload,'$.due')))<=@ToDate
 AND COALESCE(TRY_CONVERT(date,JSON_VALUE(r.Payload,'$.plannedFinish')),TRY_CONVERT(date,JSON_VALUE(r.Payload,'$.due')))>=@FromDate)
 OR TRY_CONVERT(date,JSON_VALUE(r.Payload,'$.nextSessionDate')) BETWEEN @FromDate AND @ToDate
 OR EXISTS(SELECT 1 FROM dbo.vwTimesheetBilling e WHERE e.WorkspaceId=r.WorkspaceId AND e.TaskId COLLATE DATABASE_DEFAULT=r.RecordId COLLATE DATABASE_DEFAULT AND e.ActualDate BETWEEN @FromDate AND @ToDate AND e.ActualHours>0));
 -- Manager-authored notes for exactly the requested period.
 SELECT n.* FROM OPENJSON(@p,'$.psrReports') WITH(
 [From] date '$.from',[To] date '$.to',ReportNumber nvarchar(150) '$.number',ReportDate date '$.reportDate',OverallStatus nvarchar(30) '$.status',
 RecentNotes nvarchar(max) '$.recent',Risks nvarchar(max) '$.risks',PlannedNotes nvarchar(max) '$.planned',Footer nvarchar(2000) '$.footer',UpdatedBy nvarchar(100) '$.updatedBy',UpdatedAt datetimeoffset '$.updatedAt') n
 WHERE n.[From]=@FromDate AND n.[To]=@ToDate;
END;
GO
IF DATABASE_PRINCIPAL_ID(N'IIS APPPOOL\MyProjectManagement') IS NOT NULL
 GRANT EXECUTE ON dbo.uspProjectPSR TO [IIS APPPOOL\MyProjectManagement];
GO
PRINT 'v28 optional Project Status Report procedure ready. Uses workspace/project parameters; application permissions still apply.';
-- EXEC dbo.uspProjectPSR @WorkspaceId='WORKSPACE-GUID',@ProjectId='PROJECT-ID',@FromDate='2026-11-01',@ToDate='2026-11-21';
GO

-- v29 optional read-only project scope report. No new tables or data changes.
USE [MyProjectManagement];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER VIEW dbo.vwProjectScopeSummary AS
SELECT p.WorkspaceId,p.RecordId AS ProjectId,
 CONVERT(nvarchar(50),JSON_VALUE(p.Payload,'$.code')) AS ProjectCode,
 CONVERT(nvarchar(90),JSON_VALUE(p.Payload,'$.name')) AS ProjectName,
 JSON_VALUE(p.Payload,'$.stageType') AS CurrentStage,
 (SELECT COUNT(*) FROM OPENJSON(p.Payload,'$.companies') c WHERE c.type=5) AS CompanyCount,
 (SELECT COUNT(*) FROM OPENJSON(p.Payload,'$.modules')) AS SelectedModuleCount,
 JSON_VALUE(p.Payload,'$.projectManager') AS ProjectManagerId,
 JSON_VALUE(p.Payload,'$.lead') AS ProjectInchargeId
FROM dbo.WorkspaceRecords p WHERE p.Kind='project';
GO
IF DATABASE_PRINCIPAL_ID(N'IIS APPPOOL\MyProjectManagement') IS NOT NULL
 GRANT SELECT ON dbo.vwProjectScopeSummary TO [IIS APPPOOL\MyProjectManagement];
GO
SELECT TOP(0) * FROM dbo.vwProjectScopeSummary;
PRINT 'v29 project scope summary ready; company count is derived from actual company records.';
GO

-- v31 REQUIRED reporting update for numeric plannedHours and actualHours.
-- Existing timed/session entries remain supported; numeric zero overrides old clock values.
-- No new tables and no data rewrite. Back up database before upgrading.
USE [MyProjectManagement];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER VIEW dbo.vwDailyAllocations AS
SELECT r.WorkspaceId,r.RecordId AS TaskId,a.AllocationId,a.EmployeeId,a.AllocationDate,TRY_CONVERT(date,NULLIF(a.ActualWorkDate,'')) AS ActualWorkDate,a.WorkMode,a.ChargeType,
 a.PlannedStart,a.PlannedEnd,t.ActualStart,t.ActualEnd,a.Status,a.Remarks,a.UpdatedBy,
 CAST(COALESCE(a.EnteredPlannedHours,(DATEDIFF(minute,a.PlannedStart,a.PlannedEnd)-COALESCE(a.PlannedBreak,0))/60.0,0) AS decimal(18,2)) AS PlannedHours,
 CAST(CASE WHEN a.EnteredActualHours IS NOT NULL THEN a.EnteredActualHours WHEN t.ActualStart IS NOT NULL AND t.ActualEnd IS NOT NULL THEN (DATEDIFF(minute,t.ActualStart,t.ActualEnd)-COALESCE(a.ActualBreak,0))/60.0 ELSE COALESCE(a.DeliveredUnits,0)*4 END AS decimal(18,2)) AS ActualHours
FROM dbo.WorkspaceRecords r CROSS APPLY OPENJSON(r.Payload,'$.allocations') WITH(
 AllocationId nvarchar(100) '$.id', EmployeeId nvarchar(100) '$.assignee',
 AllocationDate date '$.date',ActualWorkDate nvarchar(10) '$.actualWorkDate',WorkMode nvarchar(20) '$.workMode',ChargeType nvarchar(20) '$.chargeType',
 EnteredPlannedHours decimal(18,2) '$.plannedHours',EnteredActualHours decimal(18,2) '$.actualHours',PlannedStart time '$.plannedStartTime',PlannedEnd time '$.plannedEndTime',PlannedBreak int '$.plannedBreakMinutes',
 ActualStartText nvarchar(8) '$.actualStartTime',ActualEndText nvarchar(8) '$.actualEndTime',ActualBreak int '$.actualBreakMinutes',DeliveredUnits decimal(8,2) '$.deliveredUnits',
 Status nvarchar(60) '$.status',Remarks nvarchar(4000) '$.completionRemarks',UpdatedBy nvarchar(100) '$.actualSavedBy'
) a OUTER APPLY (SELECT TRY_CONVERT(time,NULLIF(a.ActualStartText,'')) AS ActualStart,TRY_CONVERT(time,NULLIF(a.ActualEndText,'')) AS ActualEnd) t WHERE r.Kind='task';
GO
CREATE OR ALTER VIEW dbo.vwTimesheetEntries AS
SELECT t.WorkspaceId,t.RecordId AS TaskId,a.AllocationId AS EntryId,
 CONVERT(nvarchar(100),JSON_VALUE(t.Payload,'$.project')) AS ProjectId,CONVERT(nvarchar(100),JSON_VALUE(t.Payload,'$.companyId')) AS CompanyId,
 CONVERT(nvarchar(100),JSON_VALUE(t.Payload,'$.activityId')) AS ActivityId,
 CONVERT(nvarchar(140),JSON_VALUE(t.Payload,'$.title')) AS ActivityName,
 CONVERT(nvarchar(60),JSON_VALUE(t.Payload,'$.module')) AS Module,
 CONVERT(nvarchar(40),COALESCE(NULLIF(a.TypeId,''),NULLIF(JSON_VALUE(t.Payload,'$.typeId'),''),'implementation')) AS TypeId,
 a.EmployeeId,a.PlannedDate,TRY_CONVERT(date,COALESCE(NULLIF(a.ActualDate,''),CONVERT(nvarchar(10),a.PlannedDate,23))) AS ActualDate,
 COALESCE(NULLIF(a.WorkMode,''),'Unclassified') AS WorkMode,COALESCE(NULLIF(a.ChargeType,''),'Unclassified') AS ChargeType,
 CONVERT(decimal(18,2),COALESCE(a.EnteredPlannedHours,(DATEDIFF(minute,a.PlannedStart,a.PlannedEnd)-COALESCE(a.PlannedBreak,0))/60.0,0)) AS PlannedHours,
 CONVERT(decimal(18,2),CASE WHEN a.EnteredActualHours IS NOT NULL THEN a.EnteredActualHours WHEN x.ActualStart IS NOT NULL AND x.ActualEnd IS NOT NULL THEN (DATEDIFF(minute,x.ActualStart,x.ActualEnd)-COALESCE(a.ActualBreak,0))/60.0 ELSE COALESCE(a.DeliveredUnits,0)*4 END) AS ActualHours,
 a.Status AS CurrentEntryStatus,CONVERT(nvarchar(60),JSON_VALUE(t.Payload,'$.status')) AS CurrentActivityStatus,a.Remarks,
 CONVERT(nvarchar(20),'Daily allocation') AS EntrySource
FROM dbo.WorkspaceRecords t CROSS APPLY OPENJSON(t.Payload,'$.allocations') WITH(
 AllocationId nvarchar(100) '$.id',TypeId nvarchar(40) '$.typeId',EmployeeId nvarchar(100) '$.assignee',PlannedDate date '$.date',
 ActualDate nvarchar(10) '$.actualWorkDate',WorkMode nvarchar(20) '$.workMode',ChargeType nvarchar(20) '$.chargeType',
 EnteredPlannedHours decimal(18,2) '$.plannedHours',EnteredActualHours decimal(18,2) '$.actualHours',PlannedStart time '$.plannedStartTime',PlannedEnd time '$.plannedEndTime',PlannedBreak int '$.plannedBreakMinutes',
 ActualStartText nvarchar(8) '$.actualStartTime',ActualEndText nvarchar(8) '$.actualEndTime',ActualBreak int '$.actualBreakMinutes',
 DeliveredUnits decimal(8,2) '$.deliveredUnits',Status nvarchar(60) '$.status',Remarks nvarchar(4000) '$.completionRemarks') a
OUTER APPLY(SELECT TRY_CONVERT(time,NULLIF(a.ActualStartText,'')) AS ActualStart,TRY_CONVERT(time,NULLIF(a.ActualEndText,'')) AS ActualEnd) x
WHERE t.Kind='task'
UNION ALL
SELECT t.WorkspaceId,t.RecordId,CONVERT(nvarchar(100),'session-'+s.[key]) COLLATE DATABASE_DEFAULT,
 CONVERT(nvarchar(100),JSON_VALUE(t.Payload,'$.project')),CONVERT(nvarchar(100),JSON_VALUE(t.Payload,'$.companyId')),CONVERT(nvarchar(100),JSON_VALUE(t.Payload,'$.activityId')),
 CONVERT(nvarchar(140),JSON_VALUE(t.Payload,'$.title')),CONVERT(nvarchar(60),JSON_VALUE(t.Payload,'$.module')),
 CONVERT(nvarchar(40),COALESCE(NULLIF(JSON_VALUE(t.Payload,'$.typeId'),''),'implementation')),
 CONVERT(nvarchar(100),COALESCE(NULLIF(JSON_VALUE(s.value,'$.assignee'),''),JSON_VALUE(t.Payload,'$.assignee'))),
 CONVERT(date,NULL),TRY_CONVERT(date,JSON_VALUE(s.value,'$.date')),CONVERT(nvarchar(20),'Unclassified'),
 CONVERT(nvarchar(20),COALESCE(NULLIF(JSON_VALUE(p.Payload,'$.legacyHoursClass'),''),'Unclassified')),CONVERT(decimal(18,2),0),
 CONVERT(decimal(18,2),COALESCE(TRY_CONVERT(decimal(8,2),JSON_VALUE(s.value,'$.units')),0)*4),
 CONVERT(nvarchar(60),JSON_VALUE(t.Payload,'$.status')),CONVERT(nvarchar(60),JSON_VALUE(t.Payload,'$.status')),CONVERT(nvarchar(4000),JSON_VALUE(s.value,'$.note')),
 CONVERT(nvarchar(20),'Legacy session')
FROM dbo.WorkspaceRecords t CROSS APPLY OPENJSON(t.Payload,'$.sessions') s
LEFT JOIN dbo.WorkspaceRecords p ON p.WorkspaceId=t.WorkspaceId AND p.Kind='project' AND p.RecordId=JSON_VALUE(t.Payload,'$.project')
WHERE t.Kind='task';
GO
PRINT 'v31 hours-only reporting ready. Timesheets, billing, PSR and AMC retain existing view contracts.';
GO

CREATE OR ALTER VIEW dbo.vwAmcAllocationEvidence AS
SELECT e.WorkspaceId,e.ProjectId,e.TaskId,e.EntryId,e.EmployeeId,e.PlannedDate,e.ActualDate,e.PlannedHours,e.ActualHours,
 CONVERT(nvarchar(180),COALESCE(NULLIF(a.VisitId,''),NULLIF(a.TeamGroupId,''),CASE WHEN a.EnteredPlannedHours IS NOT NULL THEN 'hours-'+a.AllocationId END,CONVERT(nvarchar(10),e.PlannedDate,23)+'|'+a.StartTime+'|'+a.EndTime)) AS PlannedVisitKey,
 CONVERT(nvarchar(180),COALESCE(NULLIF(a.VisitId,''),NULLIF(a.TeamGroupId,''),CASE WHEN a.EnteredPlannedHours IS NOT NULL THEN 'hours-'+a.AllocationId END,CONVERT(nvarchar(10),e.ActualDate,23)+'|'+a.StartTime+'|'+a.EndTime)) AS ActualVisitKey,
 a.VisitId,a.ContractId,a.LinkedCycleStart,a.DueDate,COALESCE(a.CountsAsVisit,CONVERT(bit,1)) AS CountsAsVisit
FROM dbo.vwTimesheetEntries e JOIN dbo.WorkspaceRecords t ON t.WorkspaceId=e.WorkspaceId AND t.Kind='task' AND t.RecordId COLLATE DATABASE_DEFAULT = e.TaskId COLLATE DATABASE_DEFAULT
CROSS APPLY OPENJSON(t.Payload,'$.allocations') WITH(
 AllocationId nvarchar(100) '$.id',VisitId nvarchar(180) '$.amcVisitId',ContractId nvarchar(60) '$.amcContractId',
 LinkedCycleStart date '$.amcCycleStart',DueDate date '$.amcDueDate',TeamGroupId nvarchar(100) '$.teamGroupId',
 EnteredPlannedHours decimal(18,2) '$.plannedHours',StartTime nvarchar(5) '$.plannedStartTime',EndTime nvarchar(5) '$.plannedEndTime',CountsAsVisit bit '$.countsAsAmcVisit') a
WHERE e.EntryId COLLATE DATABASE_DEFAULT = a.AllocationId COLLATE DATABASE_DEFAULT AND e.EntrySource='Daily allocation' AND e.TypeId='amc' AND e.WorkMode='Onsite';
GO
