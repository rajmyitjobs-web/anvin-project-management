-- OPTIONAL EXAMPLE ONLY. Replace DOMAIN\erp_web with the actual Windows service
-- identity used by your IIS application pool. Ask the SQL administrator to apply.
-- For remote SQL Server, use an appropriate domain service identity; a local
-- IIS APPPOOL virtual identity is not an ordinary login on a different machine.
-- Do not use sa or grant db_owner to the runtime application.
-- CREATE LOGIN [DOMAIN\erp_web] FROM WINDOWS;
-- GO
USE [MyProjectManagement];
GO
-- CREATE USER [DOMAIN\erp_web] FOR LOGIN [DOMAIN\erp_web];
-- GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.Workspaces TO [DOMAIN\erp_web];
-- GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.AppUsers TO [DOMAIN\erp_web];
-- GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.TeamMembers TO [DOMAIN\erp_web];
-- GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.WorkspaceRecords TO [DOMAIN\erp_web];
-- GRANT SELECT ON dbo.vwProjectTasks TO [DOMAIN\erp_web];
-- GRANT SELECT ON dbo.vwDailyAllocations TO [DOMAIN\erp_web];
