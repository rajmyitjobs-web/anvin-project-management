-- My Project Management v50. Run as database administrator after backing up.
-- Existing v49/v35 tables are reused. Delegations are stored in Workspaces.SettingsJson,
-- reviewed CR actions (actual actor + onBehalfOf + delegationId) in ChangeRequests.Payload.
USE [MyProjectManagement];
GO
SET XACT_ABORT ON;
GO
BEGIN TRANSACTION;
IF OBJECT_ID(N'dbo.Workspaces',N'U') IS NULL THROW 50000,'Install the existing application database first.',1;
DECLARE @id uniqueidentifier,@s nvarchar(max),@old nvarchar(max),@role nvarchar(60),@path nvarchar(200),@flag nvarchar(80);
DECLARE workspaces CURSOR LOCAL FAST_FORWARD FOR SELECT Id,SettingsJson FROM dbo.Workspaces WITH (UPDLOCK,HOLDLOCK);
OPEN workspaces;
FETCH NEXT FROM workspaces INTO @id,@s;
WHILE @@FETCH_STATUS=0
BEGIN
 SET @old=@s;
 IF ISJSON(@s)<>1 THROW 50001,'Invalid workspace settings JSON; no changes committed.',1;
 IF JSON_QUERY(@s,'$.roleMaster') IS NULL THROW 50002,'Run previous role master migrations before v50.',1;
 IF NOT EXISTS(SELECT 1 FROM OPENJSON(@s,'$.roleMaster') WHERE JSON_VALUE(value,'$.name') COLLATE DATABASE_DEFAULT=N'CEO')
 BEGIN
  IF EXISTS(SELECT 1 FROM OPENJSON(@s,'$.roleMaster') WHERE JSON_VALUE(value,'$.code') COLLATE DATABASE_DEFAULT=N'CEO' OR JSON_VALUE(value,'$.label') COLLATE DATABASE_DEFAULT=N'CEO')
   THROW 50003,'CEO code/label is already in use. Resolve it in Role Master before this patch.',1;
  SET @s=JSON_MODIFY(@s,'append $.roleMaster',JSON_QUERY(N'{"name":"CEO","code":"CEO","label":"CEO","baseRole":"Project manager","active":true,"description":"Executive dashboard and read-only CR oversight"}'));
 END;
 IF JSON_QUERY(@s,'$.rolePermissions') IS NULL SET @s=JSON_MODIFY(@s,'$.rolePermissions',JSON_QUERY(N'{}'));
 DECLARE executive_roles CURSOR LOCAL FAST_FORWARD FOR SELECT value FROM (VALUES(N'CEO'),(N'CTO')) r(value);
 OPEN executive_roles;FETCH NEXT FROM executive_roles INTO @role;
 WHILE @@FETCH_STATUS=0
 BEGIN
  SET @path=N'$.rolePermissions."'+@role+N'"';
  IF JSON_QUERY(@s,@path) IS NULL SET @s=JSON_MODIFY(@s,@path,JSON_QUERY(N'{}'));
  DECLARE flags CURSOR LOCAL FAST_FORWARD FOR SELECT value FROM STRING_SPLIT(N'viewAllProjects,createProjects,assignTasks,managePlans,manageModules,scheduleMeetings,updateTasks,manageTeam,exportReports,deleteTasks,deleteProjects,deleteMeetings,manageModuleMaster,manageActivityMaster,correctActualTimes,manageCustomers,manageWeeklyPlans,rescheduleAllocations,manageClientHours,viewAmcCompliance,createChangeRequests,reviewChangeRequestsPM,reviewChangeRequestsCTO,viewAllChangeRequests,viewExecutiveDashboard,createOwnWork',N',');
  OPEN flags;FETCH NEXT FROM flags INTO @flag;
  WHILE @@FETCH_STATUS=0
  BEGIN
   SET @path=N'$.rolePermissions."'+@role+N'"."'+@flag+N'"';
   IF JSON_VALUE(@s,@path) IS NULL
    SET @s=JSON_MODIFY(@s,@path,CONVERT(bit,CASE WHEN @flag IN(N'viewAllProjects',N'viewAllChangeRequests',N'viewExecutiveDashboard',N'exportReports',N'viewAmcCompliance') OR (@role=N'CTO' AND @flag=N'reviewChangeRequestsCTO') THEN 1 ELSE 0 END));
   FETCH NEXT FROM flags INTO @flag;
  END;
  CLOSE flags;DEALLOCATE flags;
  FETCH NEXT FROM executive_roles INTO @role;
 END;
 CLOSE executive_roles;DEALLOCATE executive_roles;
 IF JSON_QUERY(@s,'$.rolePermissions."Project manager"') IS NULL SET @s=JSON_MODIFY(@s,'$.rolePermissions."Project manager"',JSON_QUERY(N'{}'));
 IF JSON_VALUE(@s,'$.rolePermissions."Project manager".viewExecutiveDashboard') IS NULL SET @s=JSON_MODIFY(@s,'$.rolePermissions."Project manager".viewExecutiveDashboard',CONVERT(bit,1));
 IF @s<>@old UPDATE dbo.Workspaces SET SettingsJson=@s,Revision=Revision+1 WHERE Id=@id;
 FETCH NEXT FROM workspaces INTO @id,@s;
END;
CLOSE workspaces;DEALLOCATE workspaces;
COMMIT;
SELECT N'v50 executive roles configured. Existing explicit permissions preserved. No user passwords or project assignments changed.' AS Result;
GO
