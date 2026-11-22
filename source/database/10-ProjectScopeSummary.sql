-- v29 optional read-only project scope report. No new tables or data changes.
USE [MyProjectManagement];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER VIEW dbo.vwProjectScopeSummary AS
SELECT p.WorkspaceId,p.RecordId AS ProjectId,
 CONVERT(nvarchar(50),JSON_VALUE(p.Payload,'$.code')) AS ProjectCode,
 CONVERT(nvarchar(90),JSON_VALUE(p.Payload,'$.name')) AS ProjectName,
 JSON_VALUE(p.Payload,'$.stageType') AS CurrentStage,
 (SELECT COUNT(*) FROM OPENJSON(p.Payload,'$.companies') c WHERE c.type=5) AS CompanyCount,
 (SELECT COUNT(*) FROM OPENJSON(p.Payload,'$.modules')) AS SelectedModuleCount,
 JSON_VALUE(p.Payload,'$.projectManager') AS ProjectManagerId,
 JSON_VALUE(p.Payload,'$.lead') AS ProjectInchargeId
FROM dbo.WorkspaceRecords p WHERE p.Kind='project';
GO
IF DATABASE_PRINCIPAL_ID(N'IIS APPPOOL\MyProjectManagement') IS NOT NULL
 GRANT SELECT ON dbo.vwProjectScopeSummary TO [IIS APPPOOL\MyProjectManagement];
GO
SELECT TOP(0) * FROM dbo.vwProjectScopeSummary;
PRINT 'v29 project scope summary ready; company count is derived from actual company records.';
GO
