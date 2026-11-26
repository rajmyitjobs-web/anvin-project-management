using System.Text.Json.Nodes;
namespace MyProjectManagement;
public static class ProjectCompanies {
 public static void Validate(JsonObject row,JsonObject? old){
 foreach(var (key,min,max) in new[]{("companyCount",1,Math.Max(100,J.A(old,"companies").Count())),("businessUnitCount",0,10000)})if(row[key] is not null)J.Require(row[key] is JsonValue v&&v.TryGetValue<int>(out var count)&&count>=min&&count<=max&&(key!="companyCount"||count>=J.A(row,"companies").Count()),"Invalid "+key+"; retain the count of existing companies",400);
 if(row["companyWiseProjectTrackingRequired"] is not null)J.Require(row["companyWiseProjectTrackingRequired"] is JsonValue flag&&flag.TryGetValue<bool>(out _),"Company-wise Project Tracking Required must be a checkbox value",400);
 ProjectBusinessUnits.Validate(row,old);
 if(old is not null&&!J.B(row,"companyWiseProjectTrackingRequired")&&!JsonNode.DeepEquals(row["companies"],old["companies"]))J.Require(ScaffoldingOnly(row,old),"Enable Company-wise Project Tracking Required in Project Master before changing company details",400);
 if(old is not null&&row["companyCount"] is null)J.Require(J.A(row,"companies").Count()<=J.A(old,"companies").Count(),"Set Company Count in Project Master before adding companies",400);
 if(old is not null&&JsonNode.DeepEquals(row["companies"],old["companies"]))return;
 J.Require(row["companies"] is JsonArray,"Project companies must be a list",400);
 var companies=J.A(row,"companies").ToList();var previous=J.A(old,"companies").ToList();
 J.Require(companies.Count==row["companies"]!.AsArray().Count&&companies.Count>=1&&companies.Count<=Math.Max(100,previous.Count),"Enter between 1 and 100 project companies",400);
 var codes=companies.Select(c=>J.S(c,"code").Trim()).Where(c=>c!="").ToList();J.Require(codes.All(c=>c.Length<=50&&!c.Any(char.IsControl))&&codes.Distinct(StringComparer.OrdinalIgnoreCase).Count()==codes.Count,"Company codes must be unique within the project and at most 50 characters",400);
 var ids=new HashSet<string>();var names=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
 foreach(var c in companies){var id=J.S(c,"id");J.Require(id.Length is >0 and <=100&&ids.Add(id),"Company IDs must be present and unique",400);var prior=previous.FirstOrDefault(x=>J.S(x,"id")==id);var name=J.S(c,"name").Trim();J.Require(name.Length is >0 and <=100,"Enter a company name up to 100 characters",400);J.Require(names.Add(name)||prior is not null&&J.S(prior,"name").Trim()==name,"Company names must be unique within the project",400);}
 foreach(var group in companies.GroupBy(c=>J.S(c,"name").Trim(),StringComparer.OrdinalIgnoreCase))J.Require(group.Count()==1||previous.Count(c=>J.S(c,"name").Trim().Equals(group.Key,StringComparison.OrdinalIgnoreCase))>=group.Count(),"Company names must be unique within the project",400);
 J.Require(previous.All(c=>ids.Contains(J.S(c,"id"))),"Existing companies cannot be removed by changing the count; preserve their plans and history",400);
 }
 static bool ScaffoldingOnly(JsonObject row,JsonObject old){var before=J.A(old,"companies").ToList();var after=J.A(row,"companies").ToList();if(after.Count<=before.Count)return false;if(!before.All(c=>after.Any(n=>J.S(n,"id")==J.S(c,"id")&&JsonNode.DeepEquals(n,c))))return false;foreach(var c in after.Where(c=>!before.Any(p=>J.S(p,"id")==J.S(c,"id")))){bool legacy=before.Count==0&&after.Count==1&&J.S(c,"id")=="company-"+J.S(row,"id")&&(J.S(c,"name")==J.S(old,"name")||J.S(c,"name")==J.S(row,"name"));if(!legacy&&!J.S(c,"name").StartsWith("Company ",StringComparison.Ordinal)||J.S(c,"code")!=""||!JsonNode.DeepEquals(c["modules"],row["modules"])||J.S(c,"actualGoLive")!=""||J.S(c,"goLiveStatus")!="Not ready"||J.S(c,"notes")!=""||c["moduleGoLive"] is JsonObject g&&g.Count>0)return false;}return true;}
}
