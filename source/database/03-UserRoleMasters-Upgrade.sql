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
