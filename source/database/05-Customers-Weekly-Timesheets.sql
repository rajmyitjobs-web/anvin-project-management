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
