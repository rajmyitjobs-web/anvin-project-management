-- My Project Management v45: optional reporting view, no business-data updates.
-- Customer/project imports and AMC editing use existing JSON storage.
-- Run as a database administrator in the company application database.
USE [MyProjectManagement];
GO
IF OBJECT_ID(N'dbo.WorkspaceRecords',N'U') IS NULL
 THROW 51045,'WorkspaceRecords is missing. Use the full setup only for a fresh database.',1;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER VIEW dbo.vwAMCContractPeriods AS
SELECT p.WorkspaceId,p.RecordId AS ProjectId,
 CONVERT(nvarchar(50),JSON_VALUE(p.Payload,'$.code')) AS ProjectCode,
 CONVERT(nvarchar(90),JSON_VALUE(p.Payload,'$.name')) AS ProjectName,
 JSON_VALUE(p.Payload,'$.customerId') AS CustomerId,
 JSON_VALUE(p.Payload,'$.amc.id') AS ContractId,
 TRY_CONVERT(date,JSON_VALUE(p.Payload,'$.amc.start'),23) AS AMCStartDate,
 TRY_CONVERT(date,JSON_VALUE(p.Payload,'$.amc.end'),23) AS AMCEndDate,
 JSON_VALUE(p.Payload,'$.amc.cycle') AS VisitCycle,
 TRY_CONVERT(int,JSON_VALUE(p.Payload,'$.amc.visits')) AS VisitsPerCycle,
 TRY_CONVERT(decimal(12,2),JSON_VALUE(p.Payload,'$.amc.hours')) AS HoursPerVisit,
 JSON_QUERY(p.Payload,'$.amcHistory') AS PreviousContractHistory
FROM dbo.WorkspaceRecords AS p
WHERE p.Kind=N'project' AND JSON_VALUE(p.Payload,'$.stageType')=N'amc';
GO
SELECT TOP(0) * FROM dbo.vwAMCContractPeriods;
PRINT 'v45 AMC period reporting view is ready. No project/customer/contract data was changed.';
-- Example: SELECT * FROM dbo.vwAMCContractPeriods ORDER BY ProjectCode;
GO
