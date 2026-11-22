using System.Text.Json.Nodes;
namespace MyProjectManagement;
public static class Psr {
 public static void Validate(JsonObject row,JsonObject? old){
 if(JsonNode.DeepEquals(row["psrReports"],old?["psrReports"]))return;
 J.Require(row["psrReports"] is JsonArray,"Invalid PSR notes",400);
 var reports=(JsonArray)row["psrReports"]!;J.Require(reports.Count<=200,"Maximum 200 saved PSR periods per project",400);var keys=new HashSet<string>();
 foreach(var item in reports){J.Require(item is JsonObject,"Invalid PSR report",400);var r=(JsonObject)item!;var from=J.Day(J.S(r,"from"));var to=J.Day(J.S(r,"to"));J.Require(from<=to&&keys.Add(from+"/"+to),"PSR dates must be ordered and periods unique",400);J.Day(J.S(r,"reportDate"));J.Require(J.S(r,"number").Trim().Length is >0 and <=150,"PSR number is required (maximum 150 characters)",400);J.Require(new[]{"On Track","At Risk","High Risk","Off Track"}.Contains(J.S(r,"status")),"Choose a valid PSR status",400);foreach(var field in new[]{"recent","risks","planned"})J.Require(J.S(r,field).Length<=6000,"PSR notes are limited to 6000 characters",400);J.Require(J.S(r,"footer").Length<=2000,"PSR footer is limited to 2000 characters",400);}
 }
}
