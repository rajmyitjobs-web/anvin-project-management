-- My Project Management v35: REQUIRED change request workflow / protected Word storage.
-- Back up first. Run as database administrator against MyProjectManagement.
USE [MyProjectManagement];
GO
SET XACT_ABORT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.ChangeRequests',N'U') IS NULL
BEGIN
 CREATE TABLE dbo.ChangeRequests(
 WorkspaceId uniqueidentifier NOT NULL,Id uniqueidentifier NOT NULL,ProjectId nvarchar(100) NOT NULL,
 InitiatorId nvarchar(100) NOT NULL,Number nvarchar(40) NOT NULL,Version int NOT NULL,
 Payload nvarchar(max) NOT NULL,UpdatedAt datetime2 NOT NULL DEFAULT SYSUTCDATETIME(),
 CONSTRAINT PK_ChangeRequests PRIMARY KEY(WorkspaceId,Id),
 CONSTRAINT UQ_ChangeRequestNumber UNIQUE(WorkspaceId,Number),
 CONSTRAINT FK_ChangeRequests_Workspace FOREIGN KEY(WorkspaceId) REFERENCES dbo.Workspaces(Id),
 CONSTRAINT CK_ChangeRequests_Json CHECK(ISJSON(Payload)=1),CONSTRAINT CK_ChangeRequests_Version CHECK(Version>0));
 CREATE INDEX IX_ChangeRequests_Project ON dbo.ChangeRequests(WorkspaceId,ProjectId,UpdatedAt DESC);
END;
IF OBJECT_ID(N'dbo.ChangeRequestDocuments',N'U') IS NULL
BEGIN
 CREATE TABLE dbo.ChangeRequestDocuments(
 WorkspaceId uniqueidentifier NOT NULL,Id uniqueidentifier NOT NULL,RequestId uniqueidentifier NOT NULL,
 RevisionNo int NOT NULL,FileName nvarchar(120) NOT NULL,ContentType nvarchar(100) NOT NULL,
 Content varbinary(max) NOT NULL,Sha256 char(64) NOT NULL,CreatedAt datetime2 NOT NULL DEFAULT SYSUTCDATETIME(),
 CONSTRAINT PK_ChangeRequestDocuments PRIMARY KEY(WorkspaceId,Id),
 CONSTRAINT FK_CRDocuments_Request FOREIGN KEY(WorkspaceId,RequestId) REFERENCES dbo.ChangeRequests(WorkspaceId,Id),
 CONSTRAINT CK_CRDocuments_Size CHECK(DATALENGTH(Content) BETWEEN 1 AND 5242880));
 CREATE INDEX IX_CRDocuments_Request ON dbo.ChangeRequestDocuments(WorkspaceId,RequestId,RevisionNo);
END;
GO
-- Seed workflow role templates and missing permission flags; existing explicit choices remain.
BEGIN TRANSACTION;
DECLARE @w uniqueidentifier,@s nvarchar(max),@roles nvarchar(max),@role nvarchar(60),@base nvarchar(60),@flag nvarchar(60),@path nvarchar(300),@value bit;
DECLARE workspaces CURSOR LOCAL FAST_FORWARD FOR SELECT Id,SettingsJson FROM dbo.Workspaces WITH(UPDLOCK,HOLDLOCK);
OPEN workspaces;FETCH NEXT FROM workspaces INTO @w,@s;
WHILE @@FETCH_STATUS=0
BEGIN
 SET @roles=COALESCE(JSON_QUERY(@s,'$.roleMaster'),N'[{"name":"Project manager","label":"Project manager","code":"PM","baseRole":"Project manager","active":true},{"name":"Project lead","label":"Project lead","code":"PL","baseRole":"Project lead","active":true},{"name":"ERP consultant","label":"Consultant","code":"CONS","baseRole":"ERP consultant","active":true}]');
 IF NOT EXISTS(SELECT 1 FROM OPENJSON(@roles) WITH(name nvarchar(60) '$.name') r WHERE name='CTO')
 BEGIN
  DECLARE @ctoCode nvarchar(30)=N'CTO',@ctoLabel nvarchar(80)=N'CTO';
  IF EXISTS(SELECT 1 FROM OPENJSON(@roles) WITH(code nvarchar(30) '$.code') WHERE code=@ctoCode) SET @ctoCode=N'CTO_'+LEFT(REPLACE(CONVERT(nvarchar(36),NEWID()),'-',''),8);
  IF EXISTS(SELECT 1 FROM OPENJSON(@roles) WITH(label nvarchar(80) '$.label') WHERE label=@ctoLabel) SET @ctoLabel=N'CTO technical approver '+LEFT(REPLACE(CONVERT(nvarchar(36),NEWID()),'-',''),4);
  SET @roles=JSON_MODIFY(@roles,'append $',JSON_QUERY(N'{"name":"CTO","label":"'+@ctoLabel+'","code":"'+@ctoCode+'","baseRole":"Project manager","active":true,"description":"Assigned technical change request approver"}'));
 END;
 IF NOT EXISTS(SELECT 1 FROM OPENJSON(@roles) WITH(name nvarchar(60) '$.name') r WHERE name='Team lead')
 AND NOT EXISTS(SELECT 1 FROM OPENJSON(@roles) WITH(code nvarchar(30) '$.code',label nvarchar(80) '$.label') r WHERE code='TL' OR label='Team lead')
 SET @roles=JSON_MODIFY(@roles,'append $',JSON_QUERY(N'{"name":"Team lead","label":"Team lead","code":"TL","baseRole":"Project lead","active":true,"description":"Team lead change request initiator"}'));
 SET @s=JSON_MODIFY(@s,'$.roleMaster',JSON_QUERY(@roles));
 IF JSON_QUERY(@s,'$.rolePermissions') IS NULL SET @s=JSON_MODIFY(@s,'$.rolePermissions',JSON_QUERY(N'{}'));
 DECLARE roles CURSOR LOCAL FAST_FORWARD FOR SELECT name,baseRole FROM OPENJSON(@roles) WITH(name nvarchar(60) '$.name',baseRole nvarchar(60) '$.baseRole');
 OPEN roles;FETCH NEXT FROM roles INTO @role,@base;
 WHILE @@FETCH_STATUS=0
 BEGIN
  SET @path=N'$.rolePermissions."'+@role+'"';
  IF JSON_QUERY(@s,@path) IS NULL SET @s=JSON_MODIFY(@s,@path,JSON_QUERY(N'{}'));
  DECLARE flags CURSOR LOCAL FAST_FORWARD FOR SELECT v FROM(VALUES(N'createChangeRequests'),(N'reviewChangeRequestsPM'),(N'reviewChangeRequestsCTO'),(N'viewAllChangeRequests')) f(v);
  OPEN flags;FETCH NEXT FROM flags INTO @flag;
  WHILE @@FETCH_STATUS=0
  BEGIN
   SET @value=CASE WHEN @flag='createChangeRequests' AND @role<>'CTO' AND @base IN ('Project manager','Project lead','ERP consultant') THEN 1 WHEN @flag='reviewChangeRequestsPM' AND @role<>'CTO' AND @base='Project manager' THEN 1 WHEN @flag='reviewChangeRequestsCTO' AND @role='CTO' THEN 1 ELSE 0 END;
   IF JSON_VALUE(@s,@path+N'."'+@flag+N'"') IS NULL SET @s=JSON_MODIFY(@s,@path+N'."'+@flag+N'"',@value);
   FETCH NEXT FROM flags INTO @flag;
  END;
  CLOSE flags;DEALLOCATE flags;FETCH NEXT FROM roles INTO @role,@base;
 END;
 CLOSE roles;DEALLOCATE roles;
 UPDATE dbo.Workspaces SET SettingsJson=@s,Revision=Revision+1 WHERE Id=@w AND SettingsJson<>@s;
 FETCH NEXT FROM workspaces INTO @w,@s;
END;
CLOSE workspaces;DEALLOCATE workspaces;
COMMIT;
GO
CREATE OR ALTER VIEW dbo.vwChangeRequestRegister AS
SELECT WorkspaceId,Id,ProjectId,InitiatorId,Number,Version,UpdatedAt,
 TRY_CONVERT(int,r.[key])+1 AS RevisionNumber,JSON_VALUE(r.value,'$.title') AS Title,
 JSON_VALUE(r.value,'$.state') AS RevisionStatus,JSON_VALUE(r.value,'$.pmId') AS ProjectManagerId,
 JSON_VALUE(r.value,'$.ctoId') AS CtoId,JSON_VALUE(r.value,'$.reason') AS RevisionReason,
 TRY_CONVERT(datetimeoffset,JSON_VALUE(r.value,'$.submittedAt')) AS SubmittedAt
FROM dbo.ChangeRequests c CROSS APPLY OPENJSON(c.Payload,'$.revisions') r;
GO
CREATE OR ALTER VIEW dbo.vwChangeRequestApprovals AS
SELECT c.WorkspaceId,c.Id AS RequestId,c.Number,TRY_CONVERT(int,r.[key])+1 AS RevisionNumber,
 JSON_VALUE(a.value,'$.stage') AS ApprovalStage,JSON_VALUE(a.value,'$.decision') AS Decision,
 JSON_VALUE(a.value,'$.by') AS ReviewerId,TRY_CONVERT(datetimeoffset,JSON_VALUE(a.value,'$.at')) AS ReviewedAt,
 JSON_VALUE(a.value,'$.comment') AS GeneralComment,JSON_QUERY(a.value,'$.comments') AS PointAndParagraphComments,
 TRY_CONVERT(date,JSON_VALUE(a.value,'$.meetingDate')) AS ProposedMeetingDate
FROM dbo.ChangeRequests c CROSS APPLY OPENJSON(c.Payload,'$.revisions') r CROSS APPLY OPENJSON(r.value,'$.reviews') a;
GO
IF DATABASE_PRINCIPAL_ID(N'IIS APPPOOL\MyProjectManagement') IS NOT NULL
BEGIN
 GRANT SELECT,INSERT,UPDATE ON dbo.ChangeRequests TO [IIS APPPOOL\MyProjectManagement];
 GRANT SELECT,INSERT ON dbo.ChangeRequestDocuments TO [IIS APPPOOL\MyProjectManagement];
 GRANT SELECT ON dbo.vwChangeRequestRegister TO [IIS APPPOOL\MyProjectManagement];
 GRANT SELECT ON dbo.vwChangeRequestApprovals TO [IIS APPPOOL\MyProjectManagement];
END;
PRINT 'v35 CR tables, Word storage, reporting views and role templates are ready. Assign CTO/team profiles and company logins.';
GO

-- v49 mapped Word form reporting. Existing CR storage tables remain unchanged.
GO
CREATE OR ALTER VIEW dbo.vwChangeRequestFormDetails AS
SELECT c.WorkspaceId,c.Id AS RequestId,c.Number AS RegisterNumber,c.ProjectId,
 JSON_VALUE(c.Payload,'$.customerId') AS CustomerId,
 TRY_CONVERT(int,r.[key])+1 AS RevisionNumber,
 JSON_VALUE(r.value,'$.state') AS RevisionStatus,
 JSON_VALUE(r.value,'$.header.externalNumber') AS ChangeRequestNumber,
 JSON_VALUE(r.value,'$.header.documentRevision') AS DocumentRevision,
 JSON_VALUE(r.value,'$.header.clientName') AS ClientName,
 JSON_VALUE(r.value,'$.header.projectName') AS DocumentProject,
 TRY_CONVERT(date,JSON_VALUE(r.value,'$.header.date')) AS DocumentDate,
 JSON_VALUE(r.value,'$.header.requestedBy') AS RequestedBy,
 f.PointId,f.ModuleName,f.FormName,f.RequiredChanges,f.Remarks
FROM dbo.ChangeRequests c
CROSS APPLY OPENJSON(c.Payload,'$.revisions') r
CROSS APPLY OPENJSON(r.value,'$.points') WITH (
 PointId nvarchar(40) '$.id',ModuleName nvarchar(140) '$.module',
 FormName nvarchar(240) '$.formName',RequiredChanges nvarchar(max) '$.text',
 Remarks nvarchar(2000) '$.remarks'
) f;
GO
CREATE OR ALTER VIEW dbo.vwChangeRequestAmendmentResponses AS
SELECT c.WorkspaceId,c.Id AS RequestId,c.Number AS RegisterNumber,c.ProjectId,
 TRY_CONVERT(int,r.[key])+1 AS RevisionNumber,a.CommentKey,a.InitiatorReply
FROM dbo.ChangeRequests c
CROSS APPLY OPENJSON(c.Payload,'$.revisions') r
CROSS APPLY OPENJSON(r.value,'$.amendmentResponses') WITH (
 CommentKey nvarchar(80) '$.key',InitiatorReply nvarchar(4000) '$.reply'
) a;
GO
-- Least-privilege permissions for the known local IIS application identity.
-- Other service identities should receive equivalent grants explicitly from their SQL administrator.
IF DATABASE_PRINCIPAL_ID(N'IIS APPPOOL\MyProjectManagement') IS NOT NULL
BEGIN
 GRANT SELECT,INSERT,UPDATE ON OBJECT::dbo.AppUsers TO [IIS APPPOOL\MyProjectManagement];
 GRANT SELECT,INSERT,UPDATE ON OBJECT::dbo.Workspaces TO [IIS APPPOOL\MyProjectManagement];
 GRANT SELECT,INSERT,UPDATE ON OBJECT::dbo.TeamMembers TO [IIS APPPOOL\MyProjectManagement];
 GRANT SELECT,INSERT,UPDATE,DELETE ON OBJECT::dbo.WorkspaceRecords TO [IIS APPPOOL\MyProjectManagement];
 GRANT SELECT,INSERT,UPDATE ON OBJECT::dbo.ChangeRequests TO [IIS APPPOOL\MyProjectManagement];
 GRANT SELECT,INSERT ON OBJECT::dbo.ChangeRequestDocuments TO [IIS APPPOOL\MyProjectManagement];
 GRANT SELECT ON OBJECT::dbo.vwChangeRequestFormDetails TO [IIS APPPOOL\MyProjectManagement];
 GRANT SELECT ON OBJECT::dbo.vwChangeRequestAmendmentResponses TO [IIS APPPOOL\MyProjectManagement];
END;
GO
