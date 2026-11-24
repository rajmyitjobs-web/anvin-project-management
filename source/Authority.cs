using System.Text.Json.Nodes;
using Microsoft.Data.SqlClient;
namespace MyProjectManagement;
// Grants are evaluated on every request against Qatar dates; permanent roles are never changed.
public static class Authority {
 public static readonly string[] ProjectFlags=["assignTasks","managePlans","scheduleMeetings","updateTasks","correctActualTimes","manageWeeklyPlans","rescheduleAllocations","manageClientHours"];
 public static void Seed(JsonObject settings){
  ChangeRequests.Seed(settings);var roles=MasterData.Roles(settings);
  if(!roles.OfType<JsonObject>().Any(r=>J.S(r,"name")=="CEO"))roles.Add(new JsonObject{["name"]="CEO",["code"]=roles.OfType<JsonObject>().Any(r=>J.S(r,"code")=="CEO")?"CEO_OVERSIGHT":"CEO",["label"]=roles.OfType<JsonObject>().Any(r=>J.S(r,"label")=="CEO")?"CEO oversight":"CEO",["baseRole"]="Project manager",["active"]=true,["description"]="Executive dashboard and read-only CR oversight; CTO remains final technical approver"});
  settings["roleMaster"]=roles;var permissions=settings["rolePermissions"]!.AsObject();
  foreach(var role in new[]{"CEO","CTO"}){permissions[role]??=new JsonObject();foreach(var flag in MasterData.Flags.Append("createOwnWork"))if(permissions[role]![flag] is null)permissions[role]![flag]=flag is "viewAllProjects" or "viewAllChangeRequests" or "viewExecutiveDashboard" or "exportReports" or "viewAmcCompliance"||role=="CTO"&&flag=="reviewChangeRequestsCTO";}
  foreach(var r in roles.OfType<JsonObject>()){string role=J.S(r,"name");permissions[role]??=new JsonObject();permissions[role]!["viewExecutiveDashboard"]??=role=="Project manager";}
 }
 public static bool ActiveMember(Snapshot s,string id)=>s.Members.TryGetValue(id,out var m)&&J.B(m,"active",true)&&MasterData.RoleActive(s.Settings,J.S(m,"role"));
 public static bool Manager(Snapshot s,string id)=>ActiveMember(s,id)&&MasterData.BaseRole(s.Settings,J.S(s.Members[id],"role"))=="Project manager"&&J.S(s.Members[id],"role") is not ("CTO" or "CEO");
 public static bool ManagerFlag(Snapshot s,string id,string flag)=>Manager(s,id)&&new Policy(s,new AppUser(Guid.Empty,s.Id,"","",false,id,false,false,0,null,"")).Flag(flag);
 public static bool Lead(Snapshot s,string id)=>ActiveMember(s,id)&&MasterData.BaseRole(s.Settings,J.S(s.Members[id],"role"))=="Project lead";
 public static IEnumerable<JsonObject> ForProject(Snapshot s,string actor,string project,DateOnly? day=null)=>J.A(s.Settings,"authorityDelegations").Where(d=>J.S(d,"delegateId")==actor&&Lead(s,actor)&&Manager(s,J.S(d,"managerId"))&&J.S(d,"revokedAt")==""&&J.S(s.Records.GetValueOrDefault("project:"+project),"projectManager")==J.S(d,"managerId")&&(d["projectIds"] as JsonArray)?.Any(p=>p?.ToString()==project)==true&&DateOnly.TryParseExact(J.S(d,"from"),"yyyy-MM-dd",out var start)&&DateOnly.TryParseExact(J.S(d,"to"),"yyyy-MM-dd",out var end)&&start<=(day??J.Today)&&(day??J.Today)<=end);
 public static JsonObject? Find(Snapshot s,string actor,string project,string manager)=>ForProject(s,actor,project).FirstOrDefault(d=>J.S(d,"managerId")==manager&&ManagerFlag(s,manager,"reviewChangeRequestsPM"));
 public static JsonArray Visible(Snapshot s,Policy p)=>new(J.A(s.Settings,"authorityDelegations").Where(d=>p.Owner||p.Flag("viewExecutiveDashboard")||J.S(d,"managerId")==p.Actor||J.S(d,"delegateId")==p.Actor).Select(d=>(JsonNode)J.Clone(d)).ToArray());
 public static void Change(Snapshot s,Policy p,JsonObject body){
  J.Require(p.Active,"Inactive account");var now=DateTimeOffset.UtcNow.ToString("O");
  if(J.S(body,"action")=="revoke"){
   var old=J.A(s.Settings,"authorityDelegations").FirstOrDefault(d=>J.S(d,"id")==J.S(body,"id"));J.Require(old is not null,"Delegation not found",404);J.Require(p.Owner||Manager(s,p.Actor)&&p.Actor==J.S(old,"managerId"),"Only the original manager or owner may revoke delegation");J.Require(J.S(old,"revokedAt")=="","Delegation already revoked",409);old!["revokedAt"]=now;old["revokedBy"]=p.Actor;return;
  }
  J.Require(J.S(body,"action")=="create","Unknown delegation action",400);string manager=J.S(body,"managerId"),target=J.S(body,"delegateId");
  J.Require(Manager(s,manager)&&(p.Owner||p.Actor==manager),"A project manager may delegate only their own authority");J.Require(manager!=target&&Lead(s,target),"Select an active Project lead or a role based on Project lead",400);
  var from=J.Day(J.S(body,"from"));var to=J.Day(J.S(body,"to"));J.Require(from>=J.Today&&to>=from&&to.DayNumber-from.DayNumber<=366,"Choose a current/future period of at most 367 days",400);
  var ids=(body["projectIds"] as JsonArray)?.Select(x=>x?.GetValue<string>()??"").ToList()??[];J.Require(ids.Count is >0 and <=500&&ids.Distinct().Count()==ids.Count,"Select projects once each",400);
  foreach(var id in ids){J.Require(J.S(s.Records.GetValueOrDefault("project:"+id),"projectManager")==manager,"Only projects assigned to the delegating manager may be delegated");J.Require(!J.A(s.Settings,"authorityDelegations").Any(d=>J.S(d,"managerId")==manager&&J.S(d,"revokedAt")==""&&(d["projectIds"] as JsonArray)?.Any(x=>x?.ToString()==id)==true&&J.Day(J.S(d,"from"))<=to&&from<=J.Day(J.S(d,"to"))),"An overlapping delegation already covers this project; revoke it first",409);}
  var note=J.S(body,"note").Trim();J.Require(note.Length<=1000,"Reason must be at most 1000 characters",400);
  (s.Settings["authorityDelegations"]??=new JsonArray()).AsArray().Add(new JsonObject{["id"]=Guid.NewGuid().ToString(),["managerId"]=manager,["delegateId"]=target,["from"]=from.ToString("yyyy-MM-dd"),["to"]=to.ToString("yyyy-MM-dd"),["projectIds"]=new JsonArray(ids.Select(id=>(JsonNode)JsonValue.Create(id)!).ToArray()),["note"]=note,["createdBy"]=p.Actor,["createdAt"]=now});
 }
 public static void Map(WebApplication app,Func<HttpContext,Db,Task<AppUser>> current){
  app.MapPost("/api/authority-delegations",async(HttpContext ctx,Db db)=>{var u=await current(ctx,db);var body=(await JsonNode.ParseAsync(ctx.Request.Body))?.AsObject()??throw new ApiError(400,"JSON required");await using var c=await db.Open();await using var tx=(SqlTransaction)await c.BeginTransactionAsync();var before=await db.Load(u.Workspace,c,tx);J.Require(before.Revision==(long)J.N(body,"expectedRevision",-1),"CONFLICT: refresh before changing delegation",409);var after=before.Copy();Change(after,new Policy(after,u),body);await db.Save(before,after,c,tx);await tx.CommitAsync();return Results.Json(new Policy(after,u).Visible());}).RequireAuthorization();
 }
}
