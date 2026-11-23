const fs=require('fs'),vm=require('vm'),assert=require('assert/strict'),{JSDOM}=require('jsdom');
const dom=new JSDOM('<div id="app"></div><dialog id="modal"></dialog><div id="toast"></div>',{url:'https://company.test',runScripts:'outside-only'}),w=dom.window,c=dom.getInternalVMContext(),run=s=>vm.runInContext(s,c),$=s=>w.document.querySelector(s);w.TextEncoder=TextEncoder;w.TextDecoder=TextDecoder;w.Blob=Blob;w.DecompressionStream=DecompressionStream;w.scrollTo=()=>{};w.setInterval=()=>0;w.HTMLDialogElement.prototype.showModal=function(){this.open=true};w.HTMLDialogElement.prototype.close=function(){this.open=false;this.dispatchEvent(new w.Event('close'));};
for(const f of ['app.js','planner.js','cloud-config.js','cloud.js','module-master.js','time-allocation.js','employee-dashboard.js','user-role-master.js','activity-types-reports.js','excel-export.js','workforce-planning.js','amc-monitoring.js','project-module-owners.js','project-psr.js','simple-hours.js','user-guide.js','grouped-navigation.js','enterprise-theme.js','change-requests.js','spreadsheet-import.js','weekly-spreadsheet-import.js','project-plan-scope.js','amc-plan-actual.js','office-direct-work.js','quick-work.js','completion-tasks.js','master-spreadsheet-import.js','amc-period-edit.js','implementation-template.js'])run(fs.readFileSync(require('path').join(process.env.MPM_TEST_SOURCE||require('path').resolve(__dirname,'../../source'),'wwwroot',f),'utf8'));












(async()=>{
w.AbortController=AbortController;w.confirm=()=>true;let failLogout=false,calls=[];w.fetch=async(url,options)=>{calls.push({path:new URL(url).pathname,options});if(failLogout&&String(url).endsWith('auth/logout'))throw Error('offline');return {ok:true,json:async()=>({authenticated:false,csrf:'csrf-test'})};};run(fs.readFileSync(require('path').join(process.env.MPM_TEST_SOURCE||require('path').resolve(__dirname,'../../source'),'wwwroot/mssql.js'),'utf8'));await new Promise(r=>setTimeout(r,10));
run(`cloud.active=true;cloud.dirty=true;cloud.base={private:'client record'};cloud.config={workspace:'private-workspace'};data.projects=[{id:'private',name:'Sensitive customer'}];members=[{id:'secret'}];localStorage.setItem('implement.erp.v1','private');localStorage.setItem('mpm-ui-theme-v1','midnight');sessionStorage.setItem('implement.cloud.pending','private');sqlCsrf='csrf-test';`);await run('cloudSignOut()');assert.equal(run('cloud.base'),null);assert.equal(run('members.length'),0);assert.equal(run('data.projects.length'),0);assert.equal(w.localStorage.getItem('implement.erp.v1'),null);assert.equal(w.sessionStorage.getItem('implement.cloud.pending'),null);assert.equal(w.localStorage.getItem('mpm-ui-theme-v1'),'midnight');assert.equal(w.sessionStorage.getItem('mpm.logout.pending'),null);assert(calls.some(c=>c.path.endsWith('/auth/logout')&&c.options.headers['X-CSRF-Token']==='csrf-test'));assert($('#sqlLogin'));
failLogout=true;await run('cloudSignOut()');assert.equal(w.sessionStorage.getItem('mpm.logout.pending'),'1');assert($('#app').textContent.includes('could not be confirmed'));failLogout=false;await run('sqlFinishPendingLogout()');assert.equal(w.sessionStorage.getItem('mpm.logout.pending'),null);
let release;w.fetch=async(url,options)=>{if(String(url).includes('slow'))return await new Promise(r=>release=()=>r({ok:true,json:async()=>({private:'old response'})}));return {ok:true,json:async()=>({authenticated:false,csrf:'csrf-test'})};};let pending=run(`sqlRequest('slow').then(()=>false,()=>true)`);await run('cloudSignOut()');release();assert.equal(await pending,true);assert.equal(run('data.projects.length'),0);console.log('PASS v48 logout: unsaved discard, private state/storage cleanup, theme preservation, offline pending-server logout, replay prevention and stale response rejection.');dom.window.close();
})().catch(e=>{console.error(e);process.exitCode=1});
