using System.Text.Json.Nodes;
namespace MyProjectManagement;
public static class SelfWork {
 public static bool Default(string role,string flag)=>flag=="createOwnWork"&&new[]{"Project manager","Project lead","ERP consultant"}.Contains(role);
 public static bool Creation(Snapshot state,Policy policy,JsonObject row){
 if(!J.B(row,"selfCreated"))return false;
 J.Require(policy.Flag("createOwnWork")&&policy.Flag("updateTasks")&&policy.ProjectScope(J.S(row,"project")),"Self-work permission and project access required");
 var actor=policy.Actor;J.Require(state.Members.TryGetValue(actor,out var member)&&J.B(member,"active",true)&&MasterData.RoleActive(state.Settings,J.S(member,"role")),"Self work requires an active employee profile");
 var list=J.A(row,"allocations").ToList();J.Require(J.S(row,"assignee")==actor&&list.Count==1&&J.S(list[0],"assignee")==actor,"Self work can only allocate the signed-in employee");var a=list[0];var p=policy.Project(J.S(row,"project"));
 var company=J.A(p,"companies").FirstOrDefault(c=>J.S(c,"id")==J.S(row,"companyId"));J.Require(company is not null,"Choose a project company",400);
 var activity=J.A(state.Settings,"activityMaster").FirstOrDefault(x=>J.S(x,"id")==J.S(row,"activityId")&&J.B(x,"active",true));J.Require(activity is not null&&J.S(activity,"name")==J.S(row,"title")&&ActivityTypes.Id(activity)==ActivityTypes.Id(p,"stageType"),"Choose an active activity matching the project type",400);
 var module=J.S(row,"module");J.Require(module=="General"||company?["modules"] is JsonObject cm&&cm.ContainsKey(module)&&J.A(state.Settings,"moduleMaster").Any(m=>J.S(m,"name")==module&&J.B(m,"active",true)),"Choose an active project module",400);
 J.Require(J.S(row,"plannedStart")==J.S(a,"date")&&J.S(row,"plannedFinish")==J.S(a,"date")&&a["plannedHours"] is not null&&J.N(row,"plannedSessions")==J.N(a,"plannedHours")/4,"Quick work must use one date and matching hours",400);
 J.Require(!J.A(row,"sessions").Any()&&J.S(a,"weeklyPlanId")==""&&J.S(a,"teamGroupId")==""&&J.S(a,"amcVisitId")==""&&J.S(a,"amcContractId")=="","Quick work cannot create shared visits or rewrite schedules",400);
 J.Require(J.A(a,"actualHistory").All(h=>J.S(h,"by")==actor),"Quick-work audit must name the signed-in employee");row["selfCreatedBy"]=actor;J.Require(DateTimeOffset.TryParse(J.S(row,"selfCreatedAt"),out _),"Self-work creation time required",400);return true;
 }
}
