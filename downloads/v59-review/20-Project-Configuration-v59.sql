/* My Project Management v59 REVIEW migration — SQL Server 2022/2025.
   NOT executed by the application. No persistent table/column/index/security/hosting changes.
   Back up the database, use a staging copy first, and obtain production approval.
   Default is PREVIEW ONLY. Set @Apply = 1 only for an approved execution.
   Adds missing/null configuration metadata; never rewrites company/unit/plan arrays
   or task, allocation, meeting, session, actual, billing or change-request records.
   Idempotent: rerunning after success changes zero records/revisions.
*/
USE [MyProjectManagement];
GO
IF @@TRANCOUNT<>0
BEGIN
 RAISERROR('Run this migration in a fresh query window outside an existing transaction.',16,1);
 RETURN;
END;
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @Apply bit = 0; -- 0 = preview; 1 = explicitly approved apply
BEGIN TRY
 IF TRY_CONVERT(int,SERVERPROPERTY('ProductMajorVersion')) < 16
  THROW 50000,'This reviewed script targets SQL Server 2022 or later.',1;
 IF OBJECT_ID(N'dbo.Workspaces',N'U') IS NULL OR OBJECT_ID(N'dbo.WorkspaceRecords',N'U') IS NULL
  THROW 50001,'Install the existing application tables first. No changes were made.',1;
 IF COL_LENGTH(N'dbo.Workspaces',N'Revision') IS NULL OR COL_LENGTH(N'dbo.WorkspaceRecords',N'Payload') IS NULL
  THROW 50002,'The existing workspace schema is incomplete. No changes were made.',1;
 IF (SELECT compatibility_level FROM sys.databases WHERE database_id=DB_ID()) < 130
  THROW 50003,'JSON support requires compatibility level 130 or later. This script does not change database settings.',1;
 BEGIN TRANSACTION;
 -- Use the application's workspace-first lock order, preserving revision concurrency.
 SELECT Id INTO #MPM59LockedWorkspaces FROM dbo.Workspaces WITH(UPDLOCK,HOLDLOCK);
 SELECT WorkspaceId,RecordId,Payload AS OldPayload,CONVERT(nvarchar(max),Payload) AS NextPayload
 INTO #MPM59Candidates FROM dbo.WorkspaceRecords WITH(UPDLOCK,HOLDLOCK) WHERE Kind='project';
 IF EXISTS(SELECT 1 FROM #MPM59Candidates WHERE ISJSON(OldPayload,OBJECT)<>1)
  THROW 50004,'Invalid project JSON. Review the project data; no changes committed.',1;
 IF EXISTS(SELECT 1 FROM #MPM59Candidates c CROSS APPLY OPENJSON(c.OldPayload) j
  WHERE j.[key] COLLATE Latin1_General_BIN2 IN(N'companies',N'businessUnits',N'implementationPlanRows') AND j.[type] NOT IN(0,4))
  THROW 50005,'Project collections must be arrays. No existing records will be replaced.',1;
 IF EXISTS(SELECT 1 FROM #MPM59Candidates c CROSS APPLY OPENJSON(c.OldPayload) j
  CROSS APPLY OPENJSON(CASE WHEN j.[type]=4 THEN j.value ELSE N'[]' END) item
  WHERE j.[key] COLLATE Latin1_General_BIN2 IN(N'companies',N'businessUnits',N'implementationPlanRows') AND item.[type]<>5)
  THROW 50012,'Project collections contain non-object entries. Review the data; no records were rewritten.',1;
 IF EXISTS(SELECT 1 FROM #MPM59Candidates c CROSS APPLY OPENJSON(c.OldPayload) j
  WHERE j.[key] COLLATE Latin1_General_BIN2 IN(N'companyWiseProjectTrackingRequired',N'companyCount',N'businessUnitCount',N'companies',N'businessUnits',N'implementationPlanRows')
  GROUP BY c.WorkspaceId,c.RecordId,j.[key] COLLATE Latin1_General_BIN2 HAVING COUNT(*)>1)
  THROW 50006,'Duplicate project configuration keys are ambiguous. No changes committed.',1;
 IF EXISTS(SELECT 1 FROM #MPM59Candidates c CROSS APPLY OPENJSON(c.OldPayload) j
  WHERE j.[key] COLLATE Latin1_General_BIN2=N'companyWiseProjectTrackingRequired' AND j.[type] NOT IN(0,3))
  THROW 50007,'An explicit tracking flag is not a JSON boolean. Review it; no value was overwritten.',1;
 IF EXISTS(SELECT 1 FROM #MPM59Candidates c CROSS APPLY OPENJSON(c.OldPayload) j
  WHERE j.[key] COLLATE Latin1_General_BIN2 IN(N'companyCount',N'businessUnitCount') AND j.[type]<>0
   AND (j.[type]<>2 OR TRY_CONVERT(int,j.value) IS NULL
    OR TRY_CONVERT(int,j.value)<CASE WHEN j.[key] COLLATE Latin1_General_BIN2=N'companyCount' THEN 1 ELSE 0 END
    OR TRY_CONVERT(int,j.value)<CASE WHEN j.[key] COLLATE Latin1_General_BIN2=N'companyCount'
      THEN (SELECT COUNT(*) FROM OPENJSON(c.OldPayload,'$.companies'))
      ELSE (SELECT COUNT(*) FROM OPENJSON(c.OldPayload,'$.businessUnits')) END))
  THROW 50008,'A configured count is invalid or below retained details. Review it; no explicit count was overwritten.',1;
 -- Missing/null tracking remains false, matching v53-v58.1 behavior. Do not infer
 -- tracking from company count: existing explicit choices/mappings remain untouched.
 UPDATE c SET NextPayload=JSON_MODIFY(c.NextPayload,'$.companyWiseProjectTrackingRequired',CAST(0 AS bit))
 FROM #MPM59Candidates c WHERE JSON_VALUE(c.OldPayload,'$.companyWiseProjectTrackingRequired') IS NULL;
 UPDATE c SET NextPayload=JSON_MODIFY(c.NextPayload,'$.companyCount',CASE WHEN n.CompanyCount<1 THEN 1 ELSE n.CompanyCount END)
 FROM #MPM59Candidates c CROSS APPLY(SELECT COUNT(*) AS CompanyCount FROM OPENJSON(c.OldPayload,'$.companies')) n
 WHERE JSON_VALUE(c.OldPayload,'$.companyCount') IS NULL;
 UPDATE c SET NextPayload=JSON_MODIFY(c.NextPayload,'$.businessUnitCount',n.UnitCount)
 FROM #MPM59Candidates c CROSS APPLY(SELECT COUNT(*) AS UnitCount FROM OPENJSON(c.OldPayload,'$.businessUnits')) n
 WHERE JSON_VALUE(c.OldPayload,'$.businessUnitCount') IS NULL;
 -- Defensive assertion: this migration can never rewrite any existing mappings/plans.
 IF EXISTS(SELECT 1 FROM #MPM59Candidates WHERE
  ISNULL(JSON_QUERY(OldPayload,'$.companies'),N'null') COLLATE Latin1_General_BIN2<>ISNULL(JSON_QUERY(NextPayload,'$.companies'),N'null') COLLATE Latin1_General_BIN2 OR
  ISNULL(JSON_QUERY(OldPayload,'$.businessUnits'),N'null') COLLATE Latin1_General_BIN2<>ISNULL(JSON_QUERY(NextPayload,'$.businessUnits'),N'null') COLLATE Latin1_General_BIN2 OR
  ISNULL(JSON_QUERY(OldPayload,'$.implementationPlanRows'),N'null') COLLATE Latin1_General_BIN2<>ISNULL(JSON_QUERY(NextPayload,'$.implementationPlanRows'),N'null') COLLATE Latin1_General_BIN2)
  THROW 50009,'Mapping-preservation assertion failed. No changes committed.',1;
 SELECT WorkspaceId,RecordId AS ProjectId,
  JSON_VALUE(OldPayload,'$.companyWiseProjectTrackingRequired') AS PreviousTracking,
  JSON_VALUE(NextPayload,'$.companyWiseProjectTrackingRequired') AS ProposedTracking,
  JSON_VALUE(NextPayload,'$.companyCount') AS CompanyCount,
  JSON_VALUE(NextPayload,'$.businessUnitCount') AS BusinessUnitCount
 FROM #MPM59Candidates WHERE HASHBYTES('SHA2_256',CONVERT(varbinary(max),OldPayload))<>HASHBYTES('SHA2_256',CONVERT(varbinary(max),NextPayload));
 -- Read-only diagnostics: unresolved historical mappings are listed, never repaired.
 SELECT r.WorkspaceId,r.RecordId AS TaskId,JSON_VALUE(r.Payload,'$.project') AS ProjectId,
  JSON_VALUE(r.Payload,'$.companyId') AS CompanyId,
  CASE WHEN p.RecordId IS NULL THEN N'Project not found'
       WHEN ISNULL(JSON_VALUE(r.Payload,'$.companyId'),N'')=N'' THEN N'Ambiguous missing company mapping'
       ELSE N'Company mapping not found' END AS ReviewReason
 FROM dbo.WorkspaceRecords r LEFT JOIN dbo.WorkspaceRecords p ON p.WorkspaceId=r.WorkspaceId AND p.Kind='project'
  AND p.RecordId COLLATE Latin1_General_BIN2=JSON_VALUE(r.Payload,'$.project') COLLATE Latin1_General_BIN2
 WHERE r.Kind='task' AND (p.RecordId IS NULL OR
  (NOT EXISTS(SELECT 1 FROM OPENJSON(p.Payload,'$.companies') c
    WHERE JSON_VALUE(c.value,'$.id') COLLATE Latin1_General_BIN2=JSON_VALUE(r.Payload,'$.companyId') COLLATE Latin1_General_BIN2)
   AND NOT(ISNULL(JSON_VALUE(r.Payload,'$.companyId'),N'')=N'' AND (SELECT COUNT(*) FROM OPENJSON(p.Payload,'$.companies'))=1)));
 DECLARE @Expected int=(SELECT COUNT(*) FROM #MPM59Candidates WHERE HASHBYTES('SHA2_256',CONVERT(varbinary(max),OldPayload))<>HASHBYTES('SHA2_256',CONVERT(varbinary(max),NextPayload)));
 IF @Apply=1
 BEGIN
  DECLARE @ChangedWorkspaces TABLE(WorkspaceId uniqueidentifier);
  UPDATE r SET Payload=c.NextPayload OUTPUT inserted.WorkspaceId INTO @ChangedWorkspaces
  FROM dbo.WorkspaceRecords r JOIN #MPM59Candidates c ON c.WorkspaceId=r.WorkspaceId AND c.RecordId=r.RecordId
  WHERE r.Kind='project' AND HASHBYTES('SHA2_256',CONVERT(varbinary(max),r.Payload))=HASHBYTES('SHA2_256',CONVERT(varbinary(max),c.OldPayload))
   AND HASHBYTES('SHA2_256',CONVERT(varbinary(max),c.OldPayload))<>HASHBYTES('SHA2_256',CONVERT(varbinary(max),c.NextPayload));
  IF @@ROWCOUNT<>@Expected THROW 50010,'Concurrent project change detected. No changes committed.',1;
  UPDATE w SET Revision=Revision+1 FROM dbo.Workspaces w WHERE EXISTS(SELECT 1 FROM @ChangedWorkspaces c WHERE c.WorkspaceId=w.Id);
  COMMIT TRANSACTION;
  SELECT N'Applied' AS MigrationMode,@Expected AS ProjectsUpdated;
 END
 ELSE
 BEGIN
  ROLLBACK TRANSACTION;
  SELECT N'Preview only: no persistent changes' AS MigrationMode,@Expected AS ProposedProjectUpdates;
 END;
 DROP TABLE IF EXISTS #MPM59Candidates;
 DROP TABLE IF EXISTS #MPM59LockedWorkspaces;
END TRY
BEGIN CATCH
 IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
 DROP TABLE IF EXISTS #MPM59Candidates;
 DROP TABLE IF EXISTS #MPM59LockedWorkspaces;
 THROW;
END CATCH;
GO
