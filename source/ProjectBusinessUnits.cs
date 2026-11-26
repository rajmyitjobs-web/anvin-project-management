using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
namespace MyProjectManagement;
public static class ProjectBusinessUnits {
 public static void Validate(JsonObject row,JsonObject? old){
  var previous=J.A(old,"businessUnits").ToList();var units=J.A(row,"businessUnits").ToList();
  J.Require(row["businessUnits"] is null||row["businessUnits"] is JsonArray a&&a.Count==units.Count,"Business units must be a list",400);
  J.Require(units.Count<=J.N(row,"businessUnitCount",J.N(old,"businessUnitCount")),"Business unit count exceeds Project Master. Increase Business Unit Count there first",400);
  if(JsonNode.DeepEquals(row["businessUnits"],old?["businessUnits"]))return;
  J.Require(J.B(row,"companyWiseProjectTrackingRequired"),"Enable Company-wise Project Tracking Required before maintaining business units",400);
  var ids=new HashSet<string>();var codes=new HashSet<string>(StringComparer.OrdinalIgnoreCase);var names=new HashSet<string>(StringComparer.OrdinalIgnoreCase);var companies=J.A(row,"companies").Select(c=>J.S(c,"id")).ToHashSet();
  foreach(var u in units){string id=J.S(u,"id"),company=J.S(u,"companyId"),code=J.S(u,"code").Trim(),name=J.S(u,"name").Trim();J.Require(id.Length is >0 and <=100&&ids.Add(id),"Business unit IDs must be present and unique",400);J.Require(companies.Contains(company),"Select a company from this project for each business unit",400);J.Require(Regex.IsMatch(code,"^[A-Za-z0-9][A-Za-z0-9_. /-]{0,49}$")&&name.Length is >0 and <=100&&!name.Any(char.IsControl)&&J.S(u,"notes").Length<=2000,"Enter business unit code (50 max), name (100 max) and notes (2000 max)",400);J.Require(codes.Add(company+"|"+code)&&names.Add(company+"|"+name),"Business unit codes and names must be unique within each company",400);J.Require(u["active"] is JsonValue flag&&flag.TryGetValue<bool>(out _),"Choose an Active/Inactive business unit status",400);}
  J.Require(previous.All(u=>ids.Contains(J.S(u,"id"))),"Deactivate business units instead of deleting their history",400);
 }
}
