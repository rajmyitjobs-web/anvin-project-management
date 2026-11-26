using System.Text.Json.Nodes;
namespace MyProjectManagement;
public static class PlanningCompany {
 public static bool Enabled(JsonObject? p)=>J.B(p,"companyWiseProjectTrackingRequired");
 public static void CheckContext(JsonObject p,JsonObject input){if(input["companyTrackingRequired"] is not null)J.Require(input["companyTrackingRequired"] is JsonValue v&&v.TryGetValue<bool>(out var expected)&&expected==Enabled(p),"Project company tracking changed. Reload the project and reopen the import",409);}
 public static JsonObject? Resolve(JsonObject? p,string value){if(p is null)return null;var companies=J.A(p,"companies").ToList();if(!Enabled(p))return companies.FirstOrDefault();if(value.Trim()=="")return null;var id=companies.FirstOrDefault(c=>J.S(c,"id")==value);if(id is not null)return id;var matches=companies.Where(c=>new[]{J.S(c,"name"),J.S(c,"code")}.Any(s=>s!=""&&s.Trim().Equals(value.Trim(),StringComparison.OrdinalIgnoreCase))).ToList();return matches.Count==1?matches[0]:null;}
 public static JsonObject? Modules(JsonObject? p,JsonObject? c)=>Enabled(p)?c?["modules"] as JsonObject:p?["modules"] as JsonObject;
}
