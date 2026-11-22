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
