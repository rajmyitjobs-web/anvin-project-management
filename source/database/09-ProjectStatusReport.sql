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
