using System.Text.Json.Nodes;
namespace MyProjectManagement;
// Guards configuration changes only. Existing record deletion/actual/billing permissions remain unchanged.
public static class ProjectConfigurationGuard {
 public static void PreserveLegacyFields(JsonObject row,JsonObject? old){if(old is null)return;foreach(string key in new[]{"companyWiseProjectTrackingRequired","companyCount","businessUnitCount","companies","businessUnits","implementationPlanRows"})if(row[key] is null&&old[key] is not null)row[key]=old[key]!.DeepClone();}
 static IEnumerable<JsonObject> References(Snapshot s,JsonObject p)=>s.Records.Where(r=>(r.Key.StartsWith("task:")||r.Key.StartsWith("meeting:"))&&J.S(r.Value,"project")==J.S(p,"id")).Select(r=>r.Value).Concat(J.A(p,"implementationPlanRows"));
 public static void Project(Snapshot s,JsonObject row,JsonObject? old){if(old is null)return;var refs=References(s,old).ToList();var companies=J.A(row,"companies").ToList();
  var scoped=s.Records.Where(r=>J.S(r.Value,"project")==J.S(old,"id")&&(r.Key.StartsWith("task:")||r.Key.StartsWith("meeting:")&&(J.S(r.Value,"companyId")!=""||J.S(r.Value,"calendarSource")=="daily-allocation"))).Select(r=>r.Value).Concat(J.A(old,"implementationPlanRows"));
  if(!PlanningCompany.Enabled(old)&&PlanningCompany.Enabled(row))foreach(var r in scoped){string id=J.S(r,"companyId");J.Require(companies.Any(c=>J.S(c,"id")==id)||id==""&&companies.Count==1,"Cannot enable company-wise tracking: saved work has an unresolved company mapping. Review the mapping first",400);}
  var before=old["modules"] as JsonObject;var next=row["modules"] as JsonObject;
  if(before is not null)foreach(var m in before.Select(x=>x.Key).Where(m=>next?.ContainsKey(m)!=true))J.Require(!refs.Any(r=>J.S(r,"module")==m),"Cannot remove project module "+m+": saved work uses it. Retain the module and its history",400);
  foreach(var c in J.A(old,"companies")){var n=companies.FirstOrDefault(n=>J.S(n,"id")==J.S(c,"id"));if(n is null)continue;if(c["modules"] is JsonObject modules)foreach(string m in modules.Select(x=>x.Key).Where(m=>(n["modules"] as JsonObject)?.ContainsKey(m)!=true))J.Require(!refs.Any(r=>J.S(r,"companyId")==J.S(c,"id")&&J.S(r,"module")==m),"Cannot remove company module "+m+": saved work uses it. Retain the module and its history",400);}
  foreach(var u in J.A(old,"businessUnits")){var n=J.A(row,"businessUnits").FirstOrDefault(n=>J.S(n,"id")==J.S(u,"id"));if(n is not null&&J.S(n,"companyId")!=J.S(u,"companyId"))J.Require(!refs.Any(r=>J.S(r,"businessUnitId")==J.S(u,"id")),"Cannot move a business unit used by saved work to another company",400);}
  foreach(var r in J.A(old,"implementationPlanRows")){var n=J.A(row,"implementationPlanRows").FirstOrDefault(n=>J.S(n,"id")==J.S(r,"id"));J.Require(n is not null,"Existing imported plan rows must be retained when editing project configuration",400);foreach(string field in new[]{"companyId","module","taskId"})J.Require(J.S(n,field)==J.S(r,field),"Imported plan row mappings must be retained when editing project configuration",400);}
 }
 public static bool Linked(JsonObject t)=>J.A(t,"allocations").Any()||J.A(t,"sessions").Any()||J.A(t,"history").Any()||J.S(t,"actualStart")!=""||J.S(t,"actualFinish")!=""||J.S(t,"implementationPlanRowId")!=""||J.S(t,"planImportReference")!="";
 public static void Task(Snapshot s,JsonObject row,JsonObject? old){if(old is null||!Linked(old))return;J.Require(J.S(row,"project")==J.S(old,"project"),"Cannot move an activity with saved work to another project; create a new activity",400);var p=s.Records.GetValueOrDefault("project:"+J.S(old,"project"));
  bool legacyCompany=J.S(old,"companyId")==""&&(!PlanningCompany.Enabled(p)||J.A(p,"companies").Count()==1)&&J.S(row,"companyId")==J.S(J.A(p,"companies").FirstOrDefault(),"id");
  J.Require(J.S(row,"companyId")==J.S(old,"companyId")||legacyCompany,"Cannot change the company mapping of an activity with saved work; create a new activity",400);
  J.Require(J.S(row,"module")==J.S(old,"module")||J.S(old,"module")==""&&J.S(row,"module")=="General","Cannot change the module mapping of an activity with saved work; create a new activity",400);
  bool legacyActivity=J.S(old,"activityId")==""&&J.S(row,"title")==J.S(old,"title")&&J.A(s.Settings,"activityMaster").Any(a=>J.S(a,"id")==J.S(row,"activityId")&&J.S(a,"name")==J.S(old,"title")&&ActivityTypes.Id(a)==ActivityTypes.Id(old));
  J.Require(J.S(row,"activityId")==J.S(old,"activityId")||legacyActivity,"Cannot replace the master activity of saved work; create a new activity",400);
 }
}
