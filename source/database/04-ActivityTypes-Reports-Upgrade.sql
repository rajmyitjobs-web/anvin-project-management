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
