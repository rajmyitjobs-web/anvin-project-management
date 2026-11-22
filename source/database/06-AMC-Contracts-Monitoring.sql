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
