using System.Text.Json.Nodes;
namespace MyProjectManagement;
public static class ProjectCompanies {
 public static void Validate(JsonObject row,JsonObject? old){
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
