using System.Text.Json.Nodes;
namespace MyProjectManagement;
public static class PlanningCompany {
 public static bool Enabled(JsonObject? p)=>J.B(p,"companyWiseProjectTrackingRequired");
 public static void CheckContext(JsonObject p,JsonObject input){if(input["companyTrackingRequired"] is not null)J.Require(input["companyTrackingRequired"] is JsonValue v&&v.TryGetValue<bool>(out var expected)&&expected==Enabled(p),"Project company tracking changed. Reload the project and reopen the import",409);}
 public static JsonObject? Resolve(JsonObject? p,string value){if(p is null)return null;var companies=J.A(p,"companies").ToList();if(!Enabled(p))return companies.FirstOrDefault();if(value.Trim()=="")return null;var id=companies.FirstOrDefault(c=>J.S(c,"id")==value);if(id is not null)return id;var matches=companies.Where(c=>new[]{J.S(c,"name"),J.S(c,"code")}.Any(s=>s!=""&&s.Trim().Equals(value.Trim(),StringComparison.OrdinalIgnoreCase))).ToList();return matches.Count==1?matches[0]:null;}
 public static void TaskScope(JsonObject p,JsonObject row,JsonObject? old){
  bool changed=old is null||J.S(row,"project")!=J.S(old,"project")||J.S(row,"companyId")!=J.S(old,"companyId")||J.S(row,"module")!=J.S(old,"module");
  bool added=J.A(row,"allocations").Any(a=>!J.A(old,"allocations").Any(b=>J.S(b,"id")==J.S(a,"id")));
  if(!changed&&!added)return;
  JsonObject? company;
  if(!Enabled(p)){
   string retained=old is not null&&J.S(old,"project")==J.S(row,"project")?J.S(old,"companyId"):"";
   company=J.A(p,"companies").FirstOrDefault(c=>retained!=""&&J.S(c,"id")==retained)??J.A(p,"companies").FirstOrDefault();
   J.Require(company is not null,"Project setup is incomplete: an internal company record is required",400);row["companyId"]=J.S(company,"id");
  }else{company=J.A(p,"companies").FirstOrDefault(c=>J.S(c,"id")==J.S(row,"companyId"));J.Require(company is not null,"Select a company from the project's Company Master",400);}
  if(changed){string module=J.S(row,"module");var map=Modules(p,company);J.Require(module=="General"||map is not null&&map.ContainsKey(module),Enabled(p)?"Select a module from the selected project company":"Select a module from the project",400);}
 }
 public static JsonObject? Modules(JsonObject? p,JsonObject? c)=>Enabled(p)?c?["modules"] as JsonObject:p?["modules"] as JsonObject;
}
