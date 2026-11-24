using MyProjectManagement;
using System.Text.Json.Nodes;
public static class UserProvisioningTests {
 static void Deny(Action f){try{f();}catch(ApiError){return;}throw new Exception("Expected user provisioning denial");}
 public static void Run(){var s=new Snapshot{Id=Guid.NewGuid(),Owner=Guid.NewGuid()};Authority.Seed(s.Settings);var owner=new Policy(s,new AppUser(s.Owner,s.Id,"","",true,null,false,false,0,null,""));
 JsonObject Body(string id,string email="user@example.invalid")=>new(){["memberId"]=id,["password"]="Synthetic test secret only 9081!",["profile"]=new JsonObject{["name"]="Test user",["email"]=email,["role"]="ERP consultant",["modules"]="",["color"]="green",["initials"]="TU",["whatsapp"]=""}};
 var b=Body("new-user");UserProvisioning.AddProfile(s,owner,b);if(s.Members["new-user"].ContainsKey("password")||s.Settings.ToJsonString().Contains(J.S(b,"password"))||s.Members["new-user"].ToJsonString().Contains(J.S(b,"password")))throw new Exception("Credential leaked into workspace data");
 Deny(()=>UserProvisioning.AddProfile(s,owner,b));var bad=Body("bad");bad["profile"]!["password"]="Must never persist";Deny(()=>UserProvisioning.AddProfile(s,owner,bad));Deny(()=>UserProvisioning.AddProfile(s,owner,Body("duplicate-email")));
 s.Members["actor"]=new JsonObject{["role"]="ERP consultant",["active"]=true};var restricted=new Policy(s,new AppUser(Guid.NewGuid(),s.Id,"","",false,"actor",false,false,0,null,""));Deny(()=>UserProvisioning.AddProfile(s,restricted,Body("unauthorized")));
 s.Settings["rolePermissions"]!["ERP consultant"]!["manageTeam"]=true;var high=Body("escalation","different@example.invalid");high["profile"]!["role"]="CTO";Deny(()=>UserProvisioning.AddProfile(s,restricted,high));
 Console.WriteLine("PASS v51: whitelisted user provisioning, no passwords in workspace payloads, duplicate and role-escalation denial.");}
}
