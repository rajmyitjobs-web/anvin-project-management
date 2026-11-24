using System.Text.Json.Nodes;
namespace MyProjectManagement;
public static class UserProvisioning {
 // Only profile fields may reach workspace data; passwords stay in the account request.
 public static void AddProfile(Snapshot s,Policy policy,JsonObject body){
  J.Require(policy.Flag("manageTeam"),"Team management required");
  if(body["profile"] is not JsonObject profile)return;
  string id=J.S(body,"memberId");J.Require(!s.Members.ContainsKey(id),"Profile already exists; use Set / reset password",409);
  string[] allowed=["name","email","role","color","modules","whatsapp","initials"];
  J.Require(profile.All(x=>allowed.Contains(x.Key)),"Invalid profile fields",400);
  var member=J.Clone(profile);member["active"]=true;
  policy.Apply(new JsonObject{["members"]=new JsonArray(new JsonObject{["id"]=id,["payload"]=member})});
 }
}
