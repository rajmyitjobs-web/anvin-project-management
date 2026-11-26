using System.Text.Json.Nodes;
using MyProjectManagement;
public static class ProjectConfigurationTests {
 static void Deny(Action f){try{f();}catch(ApiError){return;}throw new Exception("Expected project configuration denial");}
 public static void Run(){var old=new JsonObject{["companies"]=new JsonArray(new JsonObject{["id"]="existing",["name"]="Existing company"})};var row=J.Clone(old);row["companyCount"]=1;row["businessUnitCount"]=7;row["companyWiseProjectTrackingRequired"]=false;ProjectCompanies.Validate(row,old);if(!JsonNode.DeepEquals(old["companies"],row["companies"]))throw new Exception("Company records changed");
 foreach(var key in new[]{"companyCount","businessUnitCount"}){var bad=J.Clone(row);bad[key]=-1;Deny(()=>ProjectCompanies.Validate(bad,old));bad[key]=1.5;Deny(()=>ProjectCompanies.Validate(bad,old));}
 var flag=J.Clone(row);flag["companyWiseProjectTrackingRequired"]="false";Deny(()=>ProjectCompanies.Validate(flag,old));row["companyWiseProjectTrackingRequired"]=true;ProjectCompanies.Validate(row,old);var removed=J.Clone(row);removed["companies"]=new JsonArray();Deny(()=>ProjectCompanies.Validate(removed,old));ProjectCompanies.Validate(J.Clone(old),old);var expanded=J.Clone(row);expanded["companies"]!.AsArray().Add(new JsonObject{["id"]="added",["name"]="Added company"});ProjectCompanies.Validate(expanded,row);if(J.N(expanded,"companyCount")!=2)throw new Exception("Legacy company addition count not synchronized");
 Console.WriteLine("PASS v53: project-level checkbox/count validation, legacy payload compatibility and retained company identities.");}
}
