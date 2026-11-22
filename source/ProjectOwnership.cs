using System.Text.Json.Nodes;
namespace MyProjectManagement;
public static class ProjectOwnership {
 public static void Validate(Snapshot s,JsonObject row,JsonObject? old){
 bool Active(string id)=>s.Members.TryGetValue(id,out var m)&&J.B(m,"active",true)&&MasterData.RoleActive(s.Settings,J.S(m,"role"));
 var manager=J.S(row,"projectManager");J.Require(manager!=""&&(Active(manager)||old is not null&&manager==J.S(old,"projectManager"))||manager==""&&old is not null&&J.S(old,"projectManager")=="","Select an active Project Manager",400);
 var lead=J.S(row,"lead");J.Require(lead!=""&&(Active(lead)||old is not null&&lead==J.S(old,"lead")),"Select an active project in-charge",400);
 J.Require(row["modules"] is JsonObject,"Project modules are required",400);var modules=row["modules"]!.AsObject();var before=old?["modules"] as JsonObject;
 J.Require(modules.Count>0||old is not null&&before?.Count==0,"Select at least one project module and its consultant",400);
 foreach(var (name,value) in modules){J.Require(value is JsonValue v&&v.TryGetValue<string>(out _),"Module consultant must be a team member ID",400);var id=value!.GetValue<string>();bool same=before is not null&&J.S(before,name)==id;J.Require(id!=""&&(Active(id)||same),"Select an active consultant for module "+name,400);if(before?.ContainsKey(name)!=true)J.Require(name=="General"||J.A(s.Settings,"moduleMaster").Any(m=>J.S(m,"name")==name&&J.B(m,"active",true)),"Choose an active module",400);}
 if(row["moduleTeams"] is not null){J.Require(row["moduleTeams"] is JsonObject,"Invalid module team allocations",400);foreach(var (name,value) in row["moduleTeams"]!.AsObject()){J.Require(modules.ContainsKey(name)&&value is JsonArray,"Team allocation must belong to a project module",400);var ids=new HashSet<string>();foreach(var person in (JsonArray)value!){J.Require(person is JsonValue v&&v.TryGetValue<string>(out _),"Invalid allocated person",400);var id=person!.GetValue<string>();bool same=old?["moduleTeams"]?[name] is JsonArray prior&&prior.Any(x=>x?.ToString()==id)||old?["modules"] is JsonObject om&&J.S(om,name)==id;J.Require(id!=""&&ids.Add(id)&&(Active(id)||same),"Select active, unique module team members",400);}J.Require(ids.Contains(J.S(modules,name)),"Module team must include its primary in-charge",400);}}
 }
}
