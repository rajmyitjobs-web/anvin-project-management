-- My Project Management v47 — optional read-only reporting view.
-- Existing v35+ schema supports all application features without this view.
-- Run against the application database; no data changes or table changes.
CREATE OR ALTER VIEW dbo.vwImplementationPlanRows AS
SELECT r.WorkspaceId, r.RecordId AS ProjectId,
 JSON_VALUE(r.Payload,'$.code') AS ProjectCode,
 JSON_VALUE(r.Payload,'$.name') AS ProjectName,
 p.PlanRowId,p.CompanyId,p.ActivityLabel,p.RowType,p.Responsible,
 p.PlanStartDay,p.PlannedDays,p.PlannedSessions,p.BaselineStart,p.BaselineFinish,
 p.TaskId,p.ClientDependencyStatus,p.PeopleJson,
 CASE WHEN p.RowType='Activity' AND p.Responsible='Us' THEN p.PlannedDays ELSE 0 END AS OurPlannedDays,
 CASE WHEN p.RowType='Activity' AND p.Responsible='Us' THEN p.PlannedSessions ELSE 0 END AS OurPlannedSessions
FROM dbo.WorkspaceRecords r
CROSS APPLY OPENJSON(r.Payload,'$.implementationPlanRows') WITH (
 PlanRowId nvarchar(100) '$.id',CompanyId nvarchar(100) '$.companyId',
 ActivityLabel nvarchar(140) '$.label',RowType nvarchar(20) '$.kind',Responsible nvarchar(10) '$.responsible',
 PlanStartDay int '$.offset',PlannedDays decimal(12,2) '$.days',PlannedSessions int '$.sessions',
 BaselineStart date '$.start',BaselineFinish date '$.finish',TaskId nvarchar(100) '$.taskId',
 ClientDependencyStatus nvarchar(80) '$.status',PeopleJson nvarchar(max) '$.people' AS JSON
) p
WHERE r.Kind='project';
GO
