USE [MyProjectManagement];
GO
-- Find the workspace and project IDs for your authorized report.
SELECT Id AS WorkspaceId,Name AS WorkspaceName FROM dbo.Workspaces;
SELECT WorkspaceId,ProjectId,ProjectCode,ProjectName,CurrentStage FROM dbo.vwProjectMaster;
SELECT * FROM dbo.vwActivityTypes;
-- Replace the workspace GUID below, then uncomment the EXEC statement.
-- @ProjectId=NULL reports all projects in that workspace.
-- @TypeId can be NULL, implementation, amc, warranty, office or a custom type code.
-- @WorkMode can be NULL, Onsite, Offsite or Unclassified.
-- EXEC dbo.uspProjectStatusReport
--  @WorkspaceId='PASTE-REAL-WORKSPACE-GUID-HERE',
--  @FromDate='2026-11-01',@ToDate='2026-11-30',
--  @ProjectId=NULL,@TypeId=NULL,@WorkMode=NULL;
-- For an individual project, pass its exact ProjectId copied from vwProjectMaster.
GO

-- AMC v24: replace the workspace GUID and uncomment the following example.
-- EXEC dbo.uspAmcComplianceReport @WorkspaceId='YOUR-WORKSPACE-GUID',
--  @From='2026-11-01',@To='2026-11-30',@ProjectId=NULL;
