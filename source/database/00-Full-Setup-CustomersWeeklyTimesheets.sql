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
 ON a.WorkspaceId=t.WorkspaceId AND a.TaskId=t.RecordId
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
SELECT t.WorkspaceId,t.RecordId,CONVERT(nvarchar(100),'session-'+s.[key]),
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
 FROM dbo.vwTimesheetEntries e LEFT JOIN dbo.vwProjectMaster p ON p.WorkspaceId=e.WorkspaceId AND p.ProjectId=e.ProjectId
 LEFT JOIN dbo.vwActivityTypes ty ON ty.WorkspaceId=e.WorkspaceId AND ty.TypeId=e.TypeId
 LEFT JOIN dbo.vwUserMaster m ON m.WorkspaceId=e.WorkspaceId AND m.MemberId=e.EmployeeId
 OUTER APPLY (SELECT JSON_VALUE(company.value,'$.name') AS CompanyName
 FROM dbo.WorkspaceRecords projectRecord CROSS APPLY OPENJSON(projectRecord.Payload,'$.companies') company
 WHERE projectRecord.WorkspaceId=e.WorkspaceId AND projectRecord.Kind='project'
 AND projectRecord.RecordId=e.ProjectId AND JSON_VALUE(company.value,'$.id')=e.CompanyId) pc
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
 COALESCE((SELECT SUM(x.ActualHours) FROM #Period x WHERE x.TaskId=r.RecordId),0) AS PeriodActualHours,
 JSON_VALUE(r.Payload,'$.followupNote') AS LatestFollowup,JSON_VALUE(r.Payload,'$.nextSessionDate') AS NextSessionDate
 FROM dbo.WorkspaceRecords r WHERE r.WorkspaceId=@WorkspaceId AND r.Kind='task'
 AND (@ProjectId IS NULL OR JSON_VALUE(r.Payload,'$.project')=@ProjectId)
 AND (@TypeId IS NULL OR COALESCE(NULLIF(JSON_VALUE(r.Payload,'$.typeId'),''),'implementation')=@TypeId)
 AND (EXISTS(SELECT 1 FROM #Period x WHERE x.TaskId=r.RecordId)
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
 ON a.WorkspaceId=t.WorkspaceId AND a.TaskId=t.RecordId WHERE t.Kind='task';
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
FROM dbo.vwTimesheetEntries e LEFT JOIN dbo.vwAllocationWorkforce a ON a.WorkspaceId=e.WorkspaceId AND a.TaskId=e.TaskId AND a.AllocationId=e.EntryId;
GO
CREATE OR ALTER VIEW dbo.vwEmployeeDailyTimesheets AS
SELECT e.WorkspaceId,e.ActualDate AS WorkDate,e.EmployeeId,u.UserName AS EmployeeName,
 e.ProjectId,p.ProjectCode,p.ProjectName,p.CustomerId,p.CustomerCode,p.CustomerName,
 e.TypeId,ty.TypeName,e.ActivityId,COALESCE(am.ActivityCode,fallback.ActivityCode) AS ActivityCode,e.ActivityName,e.Module,
 e.Remarks AS Notes,e.ActualHours AS Hours,e.WorkMode,e.ChargeType,e.ClientDeductibleHours,e.TaskId,e.EntryId AS AllocationId
FROM dbo.vwTimesheetBilling e
LEFT JOIN dbo.vwProjectMaster p ON p.WorkspaceId=e.WorkspaceId AND p.ProjectId=e.ProjectId
LEFT JOIN dbo.vwUserMaster u ON u.WorkspaceId=e.WorkspaceId AND u.MemberId=e.EmployeeId
LEFT JOIN dbo.vwActivityTypes ty ON ty.WorkspaceId=e.WorkspaceId AND ty.TypeId=e.TypeId
LEFT JOIN dbo.vwActivityMaster am ON am.WorkspaceId=e.WorkspaceId AND am.ActivityId=e.ActivityId
OUTER APPLY(SELECT MIN(a.ActivityCode) AS ActivityCode FROM dbo.vwActivityMaster a WHERE a.WorkspaceId=e.WorkspaceId AND a.ActivityName=e.ActivityName AND a.TypeId=e.TypeId HAVING COUNT(*)=1) fallback
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
FROM dbo.vwTimesheetEntries e JOIN dbo.vwAllocationWorkforce a ON a.WorkspaceId=e.WorkspaceId AND a.TaskId=e.TaskId AND a.AllocationId=e.EntryId
LEFT JOIN dbo.vwProjectMaster p ON p.WorkspaceId=e.WorkspaceId AND p.ProjectId=e.ProjectId
LEFT JOIN dbo.vwUserMaster u ON u.WorkspaceId=e.WorkspaceId AND u.MemberId=e.EmployeeId
LEFT JOIN dbo.vwActivityTypes ty ON ty.WorkspaceId=e.WorkspaceId AND ty.TypeId=e.TypeId
LEFT JOIN dbo.vwDailyAllocations v ON v.WorkspaceId=e.WorkspaceId AND v.TaskId=e.TaskId AND v.AllocationId=e.EntryId
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
 FROM dbo.vwTimesheetBilling e LEFT JOIN dbo.vwProjectMaster p ON p.WorkspaceId=e.WorkspaceId AND p.ProjectId=e.ProjectId
 LEFT JOIN dbo.vwActivityTypes ty ON ty.WorkspaceId=e.WorkspaceId AND ty.TypeId=e.TypeId
 LEFT JOIN dbo.vwUserMaster m ON m.WorkspaceId=e.WorkspaceId AND m.MemberId=e.EmployeeId
 OUTER APPLY (SELECT JSON_VALUE(company.value,'$.name') AS CompanyName
 FROM dbo.WorkspaceRecords projectRecord CROSS APPLY OPENJSON(projectRecord.Payload,'$.companies') company
 WHERE projectRecord.WorkspaceId=e.WorkspaceId AND projectRecord.Kind='project'
 AND projectRecord.RecordId=e.ProjectId AND JSON_VALUE(company.value,'$.id')=e.CompanyId) pc
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
 COALESCE((SELECT SUM(x.ActualHours) FROM #Period x WHERE x.TaskId=r.RecordId),0) AS PeriodActualHours,
 JSON_VALUE(r.Payload,'$.followupNote') AS LatestFollowup,JSON_VALUE(r.Payload,'$.nextSessionDate') AS NextSessionDate
 FROM dbo.WorkspaceRecords r WHERE r.WorkspaceId=@WorkspaceId AND r.Kind='task'
 AND (@ProjectId IS NULL OR JSON_VALUE(r.Payload,'$.project')=@ProjectId)
 AND (@TypeId IS NULL OR COALESCE(NULLIF(JSON_VALUE(r.Payload,'$.typeId'),''),'implementation')=@TypeId)
 AND (EXISTS(SELECT 1 FROM #Period x WHERE x.TaskId=r.RecordId)
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
