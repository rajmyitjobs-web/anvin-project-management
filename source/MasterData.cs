using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
namespace MyProjectManagement;
public static class MasterData {
 public static readonly string[] Builtins=["Project manager","Project lead","ERP consultant"];
 public static readonly string[] Flags=["viewAllProjects","createProjects","assignTasks","managePlans","manageModules","scheduleMeetings","updateTasks","manageTeam","exportReports","deleteTasks","deleteProjects","deleteMeetings","manageModuleMaster","manageActivityMaster","correctActualTimes","manageCustomers","manageWeeklyPlans","rescheduleAllocations","manageClientHours","viewAmcCompliance","createChangeRequests","reviewChangeRequestsPM","reviewChangeRequestsCTO","viewAllChangeRequests"];
 public static JsonArray Roles(JsonObject settings)=>settings["roleMaster"] is JsonArray roles?(JsonArray)roles.DeepClone():new JsonArray(Builtins.Select((name,i)=>(JsonNode)new JsonObject{["name"]=name,["label"]=name=="ERP consultant"?"Consultant":name,["code"]=new[]{"PM","PL","CONS"}[i],["baseRole"]=name,["active"]=true,["description"]=""}).ToArray());
 public static bool RoleActive(JsonObject settings,string role)=>Roles(settings).OfType<JsonObject>().Any(r=>J.S(r,"name")==role&&J.B(r,"active",true));
 public static string BaseRole(JsonObject settings,string role)=>Roles(settings).OfType<JsonObject>().Where(r=>J.S(r,"name")==role).Select(r=>J.S(r,"baseRole")).FirstOrDefault()??role;
 public static void ValidateSettings(JsonObject before,JsonObject after){
 ActivityTypes.ValidateSettings(before,after);Workforce.Customers(after["customers"] as JsonArray??new JsonArray(),before["customers"] as JsonArray??new JsonArray());
 var roles=Roles(after).OfType<JsonObject>().ToList();J.Require(roles.Count is >0 and <=50&&roles.Count==Roles(after).Count,"Use 1–50 valid roles",400);
 foreach(var key in new[]{"name","code","label"})J.Require(roles.Select(r=>J.S(r,key).Trim().ToUpperInvariant()).Distinct().Count()==roles.Count,"Role names, codes and labels must be unique",400);
 foreach(var r in roles){J.Require(Regex.IsMatch(J.S(r,"name"),"^[A-Za-z][A-Za-z0-9 _-]{0,59}$")&&!new[]{"constructor","prototype","__proto__","workspace owner"}.Contains(J.S(r,"name").ToLowerInvariant()),"Invalid or reserved role key",400);J.Require(Regex.IsMatch(J.S(r,"code"),"^[A-Z0-9][A-Z0-9_-]{0,29}$")&&J.S(r,"label").Trim().Length is >0 and <=80&&J.S(r,"description").Length<=1000&&Builtins.Contains(J.S(r,"baseRole"))&&r["active"] is JsonValue b&&b.TryGetValue<bool>(out _),"Invalid role master entry",400);
 J.Require(after["rolePermissions"]?[J.S(r,"name")] is JsonObject,"Every role requires a permission mapping",400);foreach(var (key,value) in after["rolePermissions"]![J.S(r,"name")]!.AsObject())J.Require(Flags.Contains(key)&&value is JsonValue v&&v.TryGetValue<bool>(out _),"Invalid role permission",400);
 }
 foreach(var old in Roles(before).OfType<JsonObject>())J.Require(roles.Any(r=>J.S(r,"name")==J.S(old,"name")&&J.S(r,"baseRole")==J.S(old,"baseRole")),"Role keys and base scopes are permanent; deactivate instead of deleting",400);
 }
 public static void ValidateCodes(Snapshot state){
 var projects=state.Records.Where(x=>x.Key.StartsWith("project:")).Select(x=>x.Value).ToList();
 foreach(var p in projects){var code=J.S(p,"code");if(code!="")J.Require(code.Trim()==code&&code.Length<=50&&!code.Any(char.IsControl),"Project code must contain at most 50 characters without control characters",400);}
 var codes=projects.Select(p=>J.S(p,"code")).Where(c=>c!="").Select(c=>c.ToUpperInvariant()).ToList();J.Require(codes.Distinct().Count()==codes.Count,"Project code already exists",400);
 foreach(var a in J.A(state.Settings,"activityMaster"))J.Require(J.S(a,"code").Length is >0 and <=140,"Activity code must be 1–140 characters, matching the name field capacity",400);
 }
}
