using System.Text.Json.Nodes;
namespace MyProjectManagement;
public static class PointReviews {
 public static JsonArray Capture(JsonObject revision,JsonObject body,string decision,JsonArray comments){
  var result=new JsonArray();if(revision["header"] is not JsonObject)return result;
  if(body["pointDecisions"] is null&&!J.B(revision,"pointReviewRequired"))return result; // Historical pending revisions remain readable/compatible.
  var points=J.A(revision,"points").ToList();var rows=J.A(body,"pointDecisions").ToList();
  J.Require(body["pointDecisions"] is JsonArray a&&a.Count==rows.Count&&rows.Count==points.Count&&rows.Select(r=>J.S(r,"point")).Distinct().Count()==rows.Count,"Mark Proceed or Revision required against every point",400);
  foreach(var p in points){var r=rows.FirstOrDefault(r=>J.S(r,"point")==J.S(p,"id"));J.Require(r is not null,"Unknown or missing review point",400);string status=J.S(r,"status"),remarks=J.S(r,"remarks").Trim();J.Require(status is "Proceed" or "Revision required","Choose a decision for every point",400);J.Require(remarks.Length<=2000&&(status!="Revision required"||remarks!=""),"Revision required needs remarks (maximum 2000 characters)",400);J.Require(decision!="Approve"||status=="Proceed","A revision-required point must be returned to the initiator before approval",400);
   result.Add(new JsonObject{["point"]=J.S(p,"id"),["serial"]=J.S(p,"serial"),["module"]=J.S(p,"module"),["formName"]=J.S(p,"formName"),["status"]=status,["remarks"]=remarks});
   if(remarks!=""){var existing=comments.OfType<JsonObject>().FirstOrDefault(c=>J.S(c,"point")==J.S(p,"id")&&J.S(c,"text")==remarks);if(existing is not null)existing["pointStatus"]=status;else comments.Add(new JsonObject{["point"]=J.S(p,"id"),["text"]=remarks,["pointStatus"]=status});}
  }return result;
 }
}
