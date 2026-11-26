using System.Text.Json.Nodes;
namespace MyProjectManagement;
public static class ProjectCompanies {
 public static void Validate(JsonObject row,JsonObject? old){
 // Older clients can add a company without knowing the explicit count field.
 if(old is not null&&row["companyCount"] is JsonValue declared&&declared.TryGetValue<int>(out var existingCount)&&J.A(row,"companies").Count()>J.A(old,"companies").Count()&&existingCount==(int)J.N(old,"companyCount",J.A(old,"companies").Count()))row["companyCount"]=Math.Max(existingCount,J.A(row,"companies").Count());
 foreach(var (key,min,max) in new[]{("companyCount",1,Math.Max(100,J.A(old,"companies").Count())),("businessUnitCount",0,10000)})if(row[key] is not null)J.Require(row[key] is JsonValue v&&v.TryGetValue<int>(out var count)&&count>=min&&count<=max&&(key!="companyCount"||count>=J.A(row,"companies").Count()),"Invalid "+key+"; retain the count of existing companies",400);
 if(row["companyWiseProjectTrackingRequired"] is not null)J.Require(row["companyWiseProjectTrackingRequired"] is JsonValue flag&&flag.TryGetValue<bool>(out _),"Company-wise Project Tracking Required must be a checkbox value",400);
 if(old is not null&&JsonNode.DeepEquals(row["companies"],old["companies"]))return;
 J.Require(row["companies"] is JsonArray,"Project companies must be a list",400);
 var companies=J.A(row,"companies").ToList();var previous=J.A(old,"companies").ToList();
 J.Require(companies.Count==row["companies"]!.AsArray().Count&&companies.Count>=1&&companies.Count<=Math.Max(100,previous.Count),"Enter between 1 and 100 project companies",400);
 var ids=new HashSet<string>();var names=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
 foreach(var c in companies){var id=J.S(c,"id");J.Require(id.Length is >0 and <=100&&ids.Add(id),"Company IDs must be present and unique",400);var prior=previous.FirstOrDefault(x=>J.S(x,"id")==id);var name=J.S(c,"name").Trim();J.Require(name.Length is >0 and <=100,"Enter a company name up to 100 characters",400);J.Require(names.Add(name)||prior is not null&&J.S(prior,"name").Trim()==name,"Company names must be unique within the project",400);}
 foreach(var group in companies.GroupBy(c=>J.S(c,"name").Trim(),StringComparer.OrdinalIgnoreCase))J.Require(group.Count()==1||previous.Count(c=>J.S(c,"name").Trim().Equals(group.Key,StringComparison.OrdinalIgnoreCase))>=group.Count(),"Company names must be unique within the project",400);
 J.Require(previous.All(c=>ids.Contains(J.S(c,"id"))),"Existing companies cannot be removed by changing the count; preserve their plans and history",400);
 }
}
