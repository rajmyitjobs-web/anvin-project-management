using System.Data;
using System.Text.Json.Nodes;
using Microsoft.Data.SqlClient;
namespace MyProjectManagement;
public record AppUser(Guid Id,Guid Workspace,string Email,string Hash,bool IsOwner,string? MemberId,bool Disabled,bool MustChange,int Failures,DateTime? LockedUntil,string Stamp);
public sealed class Snapshot {
 public Guid Id,Owner; public long Revision;public string Name="";public JsonObject Settings=new();
 public Dictionary<string,JsonObject> Members=new();public Dictionary<string,JsonObject> Records=new();
 public Snapshot Copy()=>new(){Id=Id,Owner=Owner,Revision=Revision,Name=Name,Settings=(JsonObject)Settings.DeepClone(),Members=Members.ToDictionary(x=>x.Key,x=>(JsonObject)x.Value.DeepClone()),Records=Records.ToDictionary(x=>x.Key,x=>(JsonObject)x.Value.DeepClone())};
}
public sealed class Db(string connectionString){
 public async Task<SqlConnection> Open(){var c=new SqlConnection(connectionString);await c.OpenAsync();return c;}
 public static async Task<int> Exec(SqlConnection c,SqlTransaction? tx,string sql,params (string,object?)[] values){await using var q=new SqlCommand(sql,c,tx);foreach(var(k,v)in values)q.Parameters.AddWithValue(k,v??DBNull.Value);return await q.ExecuteNonQueryAsync();}
 public async Task<AppUser?> User(string key,bool byEmail=false){await using var c=await Open();await using var q=new SqlCommand("SELECT Id,WorkspaceId,Email,PasswordHash,IsOwner,MemberId,Disabled,MustChangePassword,FailedAttempts,LockedUntil,SecurityStamp FROM dbo.AppUsers WHERE "+(byEmail?"EmailNormalized=@key":"Id=TRY_CONVERT(uniqueidentifier,@key)"),c);q.Parameters.AddWithValue("@key",byEmail?key.Trim().ToUpperInvariant():key);await using var r=await q.ExecuteReaderAsync();return await r.ReadAsync()?new(r.GetGuid(0),r.GetGuid(1),r.GetString(2),r.GetString(3),r.GetBoolean(4),r.IsDBNull(5)?null:r.GetString(5),r.GetBoolean(6),r.GetBoolean(7),r.GetInt32(8),r.IsDBNull(9)?null:r.GetDateTime(9),r.GetGuid(10).ToString()):null;}
 public async Task<Snapshot> Load(Guid id,SqlConnection c,SqlTransaction? tx=null){var snap=new Snapshot{Id=id};await using(var q=new SqlCommand("SELECT Name,OwnerId,Revision,SettingsJson FROM dbo.Workspaces "+(tx is null?"":"WITH (UPDLOCK,HOLDLOCK) ")+"WHERE Id=@id",c,tx)){q.Parameters.AddWithValue("@id",id);await using var r=await q.ExecuteReaderAsync();if(!await r.ReadAsync())throw new ApiError(404,"Workspace not found");snap.Name=r.GetString(0);snap.Owner=r.GetGuid(1);snap.Revision=r.GetInt64(2);snap.Settings=JsonNode.Parse(r.GetString(3))!.AsObject();}
 await using(var q=new SqlCommand("SELECT MemberId,Payload FROM dbo.TeamMembers WHERE WorkspaceId=@id",c,tx)){q.Parameters.AddWithValue("@id",id);await using var r=await q.ExecuteReaderAsync();while(await r.ReadAsync())snap.Members[r.GetString(0)]=JsonNode.Parse(r.GetString(1))!.AsObject();}
 await using(var q=new SqlCommand("SELECT Kind,RecordId,Payload FROM dbo.WorkspaceRecords WHERE WorkspaceId=@id",c,tx)){q.Parameters.AddWithValue("@id",id);await using var r=await q.ExecuteReaderAsync();while(await r.ReadAsync())snap.Records[r.GetString(0)+":"+r.GetString(1)]=JsonNode.Parse(r.GetString(2))!.AsObject();}return snap;}
 public async Task Save(Snapshot before,Snapshot after,SqlConnection c,SqlTransaction tx){foreach(var key in before.Records.Keys.Except(after.Records.Keys)){var pair=key.Split(':',2);await Exec(c,tx,"DELETE dbo.WorkspaceRecords WHERE WorkspaceId=@w AND Kind=@k AND RecordId=@id",("@w",after.Id),("@k",pair[0]),("@id",pair[1]));}
 foreach(var(k,v)in after.Records){if(before.Records.TryGetValue(k,out var old)&&JsonNode.DeepEquals(old,v))continue;var pair=k.Split(':',2);await Exec(c,tx,"UPDATE dbo.WorkspaceRecords SET Payload=@p WHERE WorkspaceId=@w AND Kind=@k AND RecordId=@id; IF @@ROWCOUNT=0 INSERT dbo.WorkspaceRecords(WorkspaceId,Kind,RecordId,Payload) VALUES(@w,@k,@id,@p)",("@w",after.Id),("@k",pair[0]),("@id",pair[1]),("@p",v.ToJsonString()));}
 foreach(var(id,v)in after.Members){
 if(before.Members.TryGetValue(id,out var priorAccount)&&(J.S(priorAccount,"email")!=J.S(v,"email")||J.S(priorAccount,"role")!=J.S(v,"role")||J.B(priorAccount,"active",true)!=J.B(v,"active",true))){
 await using(var emailCheck=new SqlCommand("SELECT COUNT(*) FROM dbo.AppUsers WHERE EmailNormalized=@en AND NOT(WorkspaceId=@w AND MemberId=@m AND IsOwner=0)",c,tx)){emailCheck.Parameters.AddWithValue("@en",J.S(v,"email").ToUpperInvariant());emailCheck.Parameters.AddWithValue("@w",after.Id);emailCheck.Parameters.AddWithValue("@m",id);J.Require(Convert.ToInt32(await emailCheck.ExecuteScalarAsync())==0,"This email belongs to another login account",409);}
 await Exec(c,tx,"UPDATE dbo.AppUsers SET Email=@e,EmailNormalized=@en,Disabled=@disabled,SecurityStamp=NEWID() WHERE WorkspaceId=@w AND MemberId=@m AND IsOwner=0",("@e",J.S(v,"email")),("@en",J.S(v,"email").ToUpperInvariant()),("@disabled",!J.B(v,"active",true)),("@w",after.Id),("@m",id));
 }
if(before.Members.TryGetValue(id,out var old)&&JsonNode.DeepEquals(old,v))continue;await Exec(c,tx,"UPDATE dbo.TeamMembers SET Payload=@p WHERE WorkspaceId=@w AND MemberId=@id; IF @@ROWCOUNT=0 INSERT dbo.TeamMembers(WorkspaceId,MemberId,Payload) VALUES(@w,@id,@p)",("@w",after.Id),("@id",id),("@p",v.ToJsonString()));}
 await Exec(c,tx,"UPDATE dbo.Workspaces SET SettingsJson=@s,Revision=Revision+1 WHERE Id=@w",("@s",after.Settings.ToJsonString()),("@w",after.Id));after.Revision=before.Revision+1;}
}
public sealed class ApiError(int status,string message):Exception(message){public int Status=>status;}
