using System.Security.Claims;
using System.Text;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Antiforgery;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Identity;
using Microsoft.Data.SqlClient;
namespace MyProjectManagement;
public static class PasswordPolicy {
 // Local blocklist: no passwords are sent to an external service. Extend through Security:BlockedPasswords.
 static readonly HashSet<string> Blocked=new(new[]{"password","password123","password123456789","password1234567890","123456789012345","1234567890123456","qwertyuiopasdfgh","administrator123","changeme123456789","welcome123456789","letmein123456789","myprojectmanagement","myprojectmanagement123"},StringComparer.OrdinalIgnoreCase);
 public static void Validate(string password,IConfiguration configuration){int length=password.EnumerateRunes().Count();J.Require(length is >=15 and <=128,"Use a passphrase of 15–128 characters",400);var normal=password.Normalize(NormalizationForm.FormKC);J.Require(!normal.Any(char.IsControl)&&!Blocked.Contains(normal)&&!configuration.GetSection("Security:BlockedPasswords").Get<string[]>().OrEmpty().Contains(normal,StringComparer.OrdinalIgnoreCase)&&normal.Distinct().Count()>2,"Choose a less predictable passphrase; this password is blocked",400);}
 static IEnumerable<string> OrEmpty(this string[]? value)=>value??[];
}
public interface IAccountStore {
 Task<AppUser?> Find(string key,bool email=false);
 Task<Snapshot> Workspace(AppUser user);
 Task Failed(AppUser user);
 Task<AppUser?> SignedIn(AppUser user,string? upgradedHash);
 Task<AppUser?> Password(AppUser user,string hash);
 Task Revoke(AppUser user);
}
public sealed class SqlAccountStore(Db db):IAccountStore {
 public Task<AppUser?> Find(string key,bool email=false)=>db.User(key,email);
 public async Task<Snapshot> Workspace(AppUser user){await using var c=await db.Open();return await db.Load(user.Workspace,c);}
 public async Task Failed(AppUser user){await using var c=await db.Open();await Db.Exec(c,null,"UPDATE dbo.AppUsers SET FailedAttempts=FailedAttempts+1,LockedUntil=CASE WHEN FailedAttempts>=4 THEN DATEADD(minute,15,SYSUTCDATETIME()) ELSE LockedUntil END WHERE Id=@id",("@id",user.Id));}
 public async Task<AppUser?> SignedIn(AppUser user,string? upgradedHash){await using var c=await db.Open();int n=await Db.Exec(c,null,"UPDATE dbo.AppUsers SET FailedAttempts=0,LockedUntil=NULL,PasswordHash=COALESCE(@h,PasswordHash) WHERE Id=@id AND SecurityStamp=@s AND PasswordHash=@old AND Disabled=0 AND (LockedUntil IS NULL OR LockedUntil<=SYSUTCDATETIME())",("@h",upgradedHash),("@id",user.Id),("@s",Guid.Parse(user.Stamp)),("@old",user.Hash));return n==1?await Find(user.Id.ToString()):null;}
 public async Task<AppUser?> Password(AppUser user,string hash){await using var c=await db.Open();int n=await Db.Exec(c,null,"UPDATE dbo.AppUsers SET PasswordHash=@h,MustChangePassword=0,SecurityStamp=NEWID() WHERE Id=@id AND SecurityStamp=@s AND Disabled=0",("@h",hash),("@id",user.Id),("@s",Guid.Parse(user.Stamp)));return n==1?await Find(user.Id.ToString()):null;}
 public async Task Revoke(AppUser user){await using var c=await db.Open();await Db.Exec(c,null,"UPDATE dbo.AppUsers SET SecurityStamp=NEWID() WHERE Id=@id AND SecurityStamp=@s",("@id",user.Id),("@s",Guid.Parse(user.Stamp)));}
}
public sealed class LoginHash(PasswordHasher<AppUser> hasher){public readonly AppUser Dummy=new(Guid.Empty,Guid.Empty,"","",false,null,false,false,0,null,"");public string Hash {get;}=hasher.HashPassword(new(Guid.Empty,Guid.Empty,"","",false,null,false,false,0,null,""),Convert.ToHexString(System.Security.Cryptography.RandomNumberGenerator.GetBytes(32)));}
public static class AuthEndpoints {
 public const string InvalidLogin="Invalid credentials or account temporarily locked";
 public static async Task<AppUser> Current(HttpContext ctx,IAccountStore store,bool allowChange=false){var user=await store.Find(ctx.User.FindFirstValue(ClaimTypes.NameIdentifier)??"");J.Require(user is not null&&!user.Disabled&&ctx.User.FindFirstValue("stamp")==user.Stamp,"Sign in first",401);J.Require(allowChange||!user!.MustChange,"Change your initial password before using the workspace",403);J.Require(new Policy(await store.Workspace(user!),user!).Active,"This account is inactive");return user!;}
 static async Task<JsonObject> Body(HttpContext ctx){J.Require(ctx.Request.ContentLength is null or <=16384,"Login request too large",400);return (await JsonNode.ParseAsync(ctx.Request.Body))?.AsObject()??throw new ApiError(400,"JSON object required");}
 static Task SignIn(HttpContext ctx,AppUser user)=>ctx.SignInAsync(CookieAuthenticationDefaults.AuthenticationScheme,new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.NameIdentifier,user.Id.ToString()),new Claim("stamp",user.Stamp)],CookieAuthenticationDefaults.AuthenticationScheme)));
 public static void Map(WebApplication app){
 app.MapGet("/api/session",async(HttpContext ctx,IAccountStore store,IAntiforgery anti)=>{var id=ctx.User.FindFirstValue(ClaimTypes.NameIdentifier);var user=id is null?null:await store.Find(id);bool active=user is not null&&!user.Disabled&&ctx.User.FindFirstValue("stamp")==user.Stamp&&new Policy(await store.Workspace(user),user).Active;return active?Results.Json(new{authenticated=true,csrf=anti.GetAndStoreTokens(ctx).RequestToken,workspace=user!.Workspace,email=user.Email,mustChangePassword=user.MustChange}):Results.Json(new{authenticated=false,csrf=anti.GetAndStoreTokens(ctx).RequestToken});});
 app.MapPost("/api/auth/login",async(HttpContext ctx,IAccountStore store,PasswordHasher<AppUser> hasher,LoginHash dummy)=>{var body=await Body(ctx);string email=J.S(body,"email").Trim(),password=J.S(body,"password");J.Require(email.Length<=254&&password.Length<=256,InvalidLogin,401);var user=await store.Find(email,true);var result=hasher.VerifyHashedPassword(user??dummy.Dummy,user?.Hash??dummy.Hash,password);bool valid=user is not null&&!user.Disabled&&!(user.LockedUntil>DateTime.UtcNow)&&result!=PasswordVerificationResult.Failed;if(!valid){if(user is not null)await store.Failed(user);throw new ApiError(401,InvalidLogin);}J.Require(new Policy(await store.Workspace(user!),user!).Active,InvalidLogin,401);var current=await store.SignedIn(user!,result==PasswordVerificationResult.SuccessRehashNeeded?hasher.HashPassword(user!,password):null);J.Require(current is not null,InvalidLogin,401);await SignIn(ctx,current!);return Results.Json(new{ok=true});}).RequireRateLimiting("login");
 // CSRF remains mandatory. Stale/expired browser cookies can still be cleared.
 app.MapPost("/api/auth/logout",async(HttpContext ctx,IAccountStore store)=>{var id=ctx.User.FindFirstValue(ClaimTypes.NameIdentifier);var user=id is null?null:await store.Find(id);if(user is not null&&ctx.User.FindFirstValue("stamp")==user.Stamp)await store.Revoke(user);await ctx.SignOutAsync();return Results.Json(new{ok=true});});
 app.MapPost("/api/auth/password",async(HttpContext ctx,IAccountStore store,PasswordHasher<AppUser> hasher,IConfiguration config)=>{var user=await Current(ctx,store,true);var body=await Body(ctx);string current=J.S(body,"currentPassword"),password=J.S(body,"password");J.Require(current.Length<=256,"Invalid current password",400);PasswordPolicy.Validate(password,config);J.Require(hasher.VerifyHashedPassword(user,user.Hash,current)!=PasswordVerificationResult.Failed,"Current password is incorrect",400);J.Require(password!=current,"Choose a password different from your current password",400);var updated=await store.Password(user,hasher.HashPassword(user,password));J.Require(updated is not null,"Sign in first",401);await SignIn(ctx,updated!);return Results.Json(new{ok=true});}).RequireAuthorization();
 }
}
