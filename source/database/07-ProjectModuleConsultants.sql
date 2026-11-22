-- My Project Management v26: optional read-only module-consultant report.
-- The application already stores these assignments in project JSON; no table migration is required.
USE [MyProjectManagement];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER VIEW dbo.vwProjectModuleConsultants AS
SELECT p.WorkspaceId,p.RecordId AS ProjectId,
 CONVERT(nvarchar(50),JSON_VALUE(p.Payload,'$.code')) AS ProjectCode,
 CONVERT(nvarchar(90),JSON_VALUE(p.Payload,'$.name')) AS ProjectName,
 CONVERT(nvarchar(100),JSON_VALUE(p.Payload,'$.lead')) AS ProjectInchargeId,
 CONVERT(nvarchar(80),JSON_VALUE(leadMember.Payload,'$.name')) AS ProjectInchargeName,
 CONVERT(nvarchar(60),module.[key]) COLLATE DATABASE_DEFAULT AS ModuleName,
 CONVERT(nvarchar(100),module.value) COLLATE DATABASE_DEFAULT AS ModuleConsultantId,
 CONVERT(nvarchar(80),JSON_VALUE(consultant.Payload,'$.name')) AS ModuleConsultantName,
 CONVERT(nvarchar(60),JSON_VALUE(consultant.Payload,'$.role')) AS ConsultantRole
FROM dbo.WorkspaceRecords p CROSS APPLY OPENJSON(p.Payload,'$.modules') module
LEFT JOIN dbo.TeamMembers consultant ON consultant.WorkspaceId=p.WorkspaceId
 AND consultant.MemberId COLLATE DATABASE_DEFAULT = CONVERT(nvarchar(100),module.value) COLLATE DATABASE_DEFAULT
LEFT JOIN dbo.TeamMembers leadMember ON leadMember.WorkspaceId=p.WorkspaceId
 AND leadMember.MemberId COLLATE DATABASE_DEFAULT = JSON_VALUE(p.Payload,'$.lead') COLLATE DATABASE_DEFAULT
WHERE p.Kind='project';
GO
IF DATABASE_PRINCIPAL_ID(N'IIS APPPOOL\MyProjectManagement') IS NOT NULL
 GRANT SELECT ON dbo.vwProjectModuleConsultants TO [IIS APPPOOL\MyProjectManagement];
GO
SELECT TOP(0) * FROM dbo.vwProjectModuleConsultants;
PRINT 'v26 module-consultant reporting view is ready.';
GO
