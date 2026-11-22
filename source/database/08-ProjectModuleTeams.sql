-- My Project Management v27. Optional reporting view; assignments use existing JSON storage.
-- No records are changed. Legacy single owners remain represented as one allocated person.
USE [MyProjectManagement];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
CREATE OR ALTER VIEW dbo.vwProjectModuleTeams AS
SELECT p.WorkspaceId,p.RecordId AS ProjectId,
 CONVERT(nvarchar(50),JSON_VALUE(p.Payload,'$.code')) AS ProjectCode,
 CONVERT(nvarchar(90),JSON_VALUE(p.Payload,'$.name')) AS ProjectName,
 JSON_VALUE(p.Payload,'$.projectManager') AS ProjectManagerId,
 JSON_VALUE(manager.Payload,'$.name') AS ProjectManagerName,
 JSON_VALUE(p.Payload,'$.lead') AS ProjectInchargeId,
 JSON_VALUE(leadMember.Payload,'$.name') AS ProjectInchargeName,
 CONVERT(nvarchar(60),module.[key]) COLLATE DATABASE_DEFAULT AS ModuleName,
 CONVERT(nvarchar(100),module.value) COLLATE DATABASE_DEFAULT AS PrimaryInchargeId,
 allocated.MemberId AS AllocatedMemberId,
 JSON_VALUE(member.Payload,'$.name') AS AllocatedMemberName,
 CONVERT(bit,CASE WHEN allocated.MemberId=CONVERT(nvarchar(100),module.value) COLLATE DATABASE_DEFAULT THEN 1 ELSE 0 END) AS IsPrimaryIncharge
FROM dbo.WorkspaceRecords p
CROSS APPLY OPENJSON(p.Payload,'$.modules') module
CROSS APPLY (
 SELECT CONVERT(nvarchar(100),module.value) COLLATE DATABASE_DEFAULT AS MemberId
 UNION
 SELECT CONVERT(nvarchar(100),person.value) COLLATE DATABASE_DEFAULT
 FROM OPENJSON(p.Payload,'$.moduleTeams') team
 CROSS APPLY OPENJSON(CASE WHEN team.type=4 THEN team.value ELSE N'[]' END) person
 WHERE team.[key] COLLATE DATABASE_DEFAULT=module.[key] COLLATE DATABASE_DEFAULT AND person.type=1
) allocated
LEFT JOIN dbo.TeamMembers member ON member.WorkspaceId=p.WorkspaceId AND member.MemberId COLLATE DATABASE_DEFAULT=allocated.MemberId
LEFT JOIN dbo.TeamMembers manager ON manager.WorkspaceId=p.WorkspaceId AND manager.MemberId COLLATE DATABASE_DEFAULT=JSON_VALUE(p.Payload,'$.projectManager') COLLATE DATABASE_DEFAULT
LEFT JOIN dbo.TeamMembers leadMember ON leadMember.WorkspaceId=p.WorkspaceId AND leadMember.MemberId COLLATE DATABASE_DEFAULT=JSON_VALUE(p.Payload,'$.lead') COLLATE DATABASE_DEFAULT
WHERE p.Kind='project';
GO
IF DATABASE_PRINCIPAL_ID(N'IIS APPPOOL\MyProjectManagement') IS NOT NULL
 GRANT SELECT ON dbo.vwProjectModuleTeams TO [IIS APPPOOL\MyProjectManagement];
GO
SELECT TOP(0) * FROM dbo.vwProjectModuleTeams;
PRINT 'v27 project manager and multi-person module team view is ready.';
GO
