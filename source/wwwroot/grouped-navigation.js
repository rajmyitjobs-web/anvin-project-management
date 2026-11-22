/* v33: group existing authorized menu entries by purpose. */
const menuGroups=[
 {id:'dashboards',name:'Dashboards',pages:['overview','employee-dashboard'],open:true},
 {id:'masters',name:'Masters & Setup',pages:['customer-master','module-master','activity-types','activity-master']},
 {id:'planning',name:'Projects & Planning',pages:['projects','planning','weekly-plan','meetings'],open:true},
 {id:'work',name:'Daily Work',pages:['daily','tasks','employee-timesheets'],open:true},
 {id:'reports',name:'Reports & Performance',pages:['project-reports','psr','performance','amc-monitor']},
 {id:'admin',name:'Administration',pages:['team','user-master','role-master','permissions','connection','activity']},
 {id:'help',name:'Help',pages:['user-guide']}
];
const menuGroupState={};
const groupedShell=shell;shell=function(){let template=document.createElement('template');template.innerHTML=groupedShell();let nav=template.content.querySelector('nav.nav');if(!nav)return template.innerHTML;let buttons=[...nav.querySelectorAll('button[data-nav]')],byPage=new Map(buttons.map(b=>[b.dataset.nav,b])),used=new Set();nav.replaceChildren();nav.setAttribute('aria-label','Main navigation');let groups=[...menuGroups],unknown=buttons.filter(b=>!menuGroups.some(g=>g.pages.includes(b.dataset.nav))).map(b=>b.dataset.nav);if(unknown.length)groups.push({id:'other',name:'Other',pages:unknown});for(const group of groups){let entries=group.pages.map(p=>byPage.get(p)).filter(Boolean);if(!entries.length)continue;let details=document.createElement('details');details.className='menu-group';details.dataset.menuGroup=group.id;details.open=entries.some(b=>b.classList.contains('active'))||(Object.hasOwn(menuGroupState,group.id)?menuGroupState[group.id]:!!group.open);let summary=document.createElement('summary');summary.textContent=group.name;let body=document.createElement('div');body.className='menu-group-items';for(const entry of entries){if(used.has(entry.dataset.nav))continue;used.add(entry.dataset.nav);if(entry.classList.contains('active'))entry.setAttribute('aria-current','page');body.append(entry);}details.append(summary,body);nav.append(details);}return template.innerHTML;};
document.addEventListener('toggle',e=>{if(e.target.matches?.('details[data-menu-group]')&&e.target.closest('.sidebar'))menuGroupState[e.target.dataset.menuGroup]=e.target.open;},true);
render();
