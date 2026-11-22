# MyProjectManagement v36

ASP.NET Core 10 project management application with a SQL Server backend. The C# project and browser interface are under `source/`. Version 36 includes project plan and activity master imports.

## Build for the Windows Azure pilot

From the repository root, use the .NET 10 SDK:

```sh
dotnet publish source/MyProjectManagement.csproj -c Release -r win-x86 --self-contained false -p:UseAppHost=false -o dist
```

Deploy the contents of `dist/` to the Web App. Configure the SQL connection through the server setting `ConnectionStrings__Default`. The versioned database setup scripts are in `source/database/`. The application requires a configured database for sign-in. See the project hosting plan for schema preparation and first-owner setup.
