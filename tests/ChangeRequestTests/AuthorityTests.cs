using MyProjectManagement;
using System.Text.Json.Nodes;
public static class AuthorityTests {
 static void Check(bool ok,string message){if(!ok)throw new Exception(message);}static void Deny(Action action){try{action();}catch(ApiError){return;}throw new Exception("Expected authority denial");}
 static AppUser User(Snapshot s,string id)=>new(Guid.NewGuid(),s.Id,"test@example.invalid","",false,id,false,false,0,null,"");
 public static void Run(){
  var s=new Snapshot{Id=Guid.NewGuid(),Owner=Guid.NewGuid()};Authority.Seed(s.Settings);
  foreach(var (id,role) in new[]{("pm","Project manager"),("pm2","Project manager"),("lead","Project lead"),("otherLead","Project lead"),("worker","ERP consultant"),("cto","CTO"),("ceo","CEO")})s.Members[id]=new JsonObject{["id"]=id,["name"]=id,["role"]=role,["active"]=true};
  foreach(var id in new[]{"p","outside"})s.Records["project:"+id]=new JsonObject{["id"]=id,["name"]=id,["projectManager"]=id=="p"?"pm":"pm2"};
  s.Settings["rolePermissions"]!["Project manager"]!["assignTasks"]=true;s.Settings["rolePermissions"]!["Project manager"]!["managePlans"]=true;
  var pm=new Policy(s,User(s,"pm"));var lead=new Policy(s,User(s,"lead"));var worker=new Policy(s,User(s,"worker"));var cto=new Policy(s,User(s,"cto"));var ceo=new Policy(s,User(s,"ceo"));
  Check(ceo.Flag("viewExecutiveDashboard")&&ceo.Flag("viewAllProjects")&&ceo.Flag("viewAllChangeRequests"),"CEO read-only oversight");foreach(var f in new[]{"createOwnWork","createChangeRequests","reviewChangeRequestsPM","reviewChangeRequestsCTO","manageTeam","assignTasks","managePlans"})Check(!ceo.Flag(f),"CEO must not inherit "+f);
  Check(cto.Flag("reviewChangeRequestsCTO")&&!cto.Flag("reviewChangeRequestsPM"),"CTO final stage only");
  JsonObject Grant(string target="lead",string from="",string to="",string project="p")=>new(){["action"]="create",["managerId"]="pm",["delegateId"]=target,["from"]=from==""?J.Today.ToString("yyyy-MM-dd"):from,["to"]=to==""?J.Today.ToString("yyyy-MM-dd"):to,["projectIds"]=new JsonArray(project)};
  Deny(()=>Authority.Change(s,worker,Grant()));Deny(()=>Authority.Change(s,lead,Grant()));Deny(()=>Authority.Change(s,pm,Grant("worker")));Deny(()=>Authority.Change(s,pm,Grant(project:"outside")));Deny(()=>Authority.Change(s,pm,Grant(from:J.Today.AddDays(-1).ToString("yyyy-MM-dd"))));
  Authority.Change(s,pm,Grant());var d=J.A(s.Settings,"authorityDelegations").Single();
  Check(Authority.ForProject(s,"lead","p",J.Today).Any()&&!Authority.ForProject(s,"lead","p",J.Today.AddDays(1)).Any()&&!Authority.ForProject(s,"lead","p",J.Today.AddDays(-1)).Any(),"Inclusive date boundaries and automatic expiry");
  Check(lead.ProjectScope("p")&&lead.Can("managePlans","p")&&!lead.Can("managePlans","outside")&&!lead.Flag("manageTeam")&&!lead.Flag("reviewChangeRequestsCTO"),"Project scoped grant without admin escalation");Deny(()=>Authority.Change(s,pm,Grant()));
  JsonObject Body(string reviewer="")=>new(){["projectId"]="p",["pmId"]=reviewer,["ctoId"]="cto",["title"]="Test CR",["description"]="Changes",["reason"]="Initial",["points"]=new JsonArray(new JsonObject{["text"]="Change field"})};
  var cr=ChangeRequests.Create(s,pm,Body("pm2"));Check(J.S(ChangeRequests.Latest(cr),"pmId")=="pm2","PM may initiate with independent PM reviewer");Deny(()=>ChangeRequests.Create(s,pm,Body()));Deny(()=>ChangeRequests.Create(s,pm,Body("cto")));
  // Consultants assigned to a module/project can initiate and delegation preserves PM -> CTO order.
  s.Records["project:p"]["modules"]=new JsonObject{["Finance"]="worker"};cr=ChangeRequests.Create(s,worker,Body());ChangeRequests.Latest(cr)["documentId"]="test-doc";ChangeRequests.Act(s,worker,cr,"submit",new JsonObject());
  var approve=new JsonObject{["decision"]="Approve"};Deny(()=>ChangeRequests.Act(s,cto,cr,"review",approve));ChangeRequests.Act(s,lead,cr,"review",approve);
  var review=J.A(ChangeRequests.Latest(cr),"reviews").Single();Check(J.S(review,"by")=="lead"&&J.S(review,"onBehalfOf")=="pm"&&J.S(review,"delegationId")==J.S(d,"id"),"Actual reviewer and delegated manager audited");Check(J.S(ChangeRequests.Latest(cr),"state")=="Pending CTO","Delegation never bypasses CTO");ChangeRequests.Act(s,cto,cr,"review",approve);Check(J.S(ChangeRequests.Latest(cr),"state")=="Technically feasible","CTO final technical approval");
  var own=ChangeRequests.Create(s,lead,Body());ChangeRequests.Latest(own)["documentId"]="test-doc";ChangeRequests.Act(s,lead,own,"submit",new JsonObject());Deny(()=>ChangeRequests.Act(s,lead,own,"review",approve));
  var settings=J.Clone(s.Settings);settings["authorityDelegations"]=new JsonArray();var owner=new Policy(s,new AppUser(s.Owner,s.Id,"","",true,null,false,false,0,null,""));Deny(()=>owner.Apply(new JsonObject{["settings"]=settings}));
  Deny(()=>Authority.Change(s,lead,new JsonObject{["action"]="revoke",["id"]=J.S(d,"id")}));Authority.Change(s,pm,new JsonObject{["action"]="revoke",["id"]=J.S(d,"id")});Check(!lead.DelegatedManager("p","pm")&&!lead.Can("managePlans","p"),"Revocation removes temporary rights immediately");
  var future=J.Today.AddDays(1).ToString("yyyy-MM-dd");Authority.Change(s,pm,Grant(from:future,to:future));Check(!lead.DelegatedManager("p","pm"),"Future delegation does not grant access early");
  s.Members["lead"]["active"]=false;Check(!Authority.ForProject(s,"lead","p",J.Today.AddDays(1)).Any(),"Inactive delegate cannot act");
  using(var sql=new StreamReader(Path.Combine(AppContext.BaseDirectory,"Fixtures/Database-Executive-Delegation-v50.sql"))){new Microsoft.SqlServer.TransactSql.ScriptDom.TSql160Parser(true).Parse(sql,out var errors);Check(errors.Count==0,"v50 SQL syntax: "+string.Join(";",errors.Select(e=>e.Message)));}
  foreach(var name in new[]{"Database-Upgrade-v50.sql","Database-Full-Setup-v50.sql"}){using var sql50=new StreamReader(Path.Combine(AppContext.BaseDirectory,"Fixtures",name));new Microsoft.SqlServer.TransactSql.ScriptDom.TSql160Parser(true).Parse(sql50,out var errors50);Check(errors50.Count==0,"v50 combined SQL syntax: "+string.Join(";",errors50.Select(e=>e.Message)));}
  Console.WriteLine("PASS v50: executive least privilege, independent PM initiation, date boundaries, project scope, overlap validation, no chaining/self-review, PM->CTO sequence, delegated audit, revocation and disabled users.");
 }
}
