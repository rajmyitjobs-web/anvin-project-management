const CACHE='mpm-mobile-public-v50';
self.addEventListener('install',event=>{event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(['./mobile-offline.html','./mobile-icon-192.png','./mobile-icon-512.png'])));self.skipWaiting();});
self.addEventListener('activate',event=>{event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k.startsWith('mpm-mobile-public-')&&k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim()));});
self.addEventListener('fetch',event=>{let url=new URL(event.request.url);if(event.request.method!=='GET'||url.origin!==self.location.origin)return;if(event.request.mode==='navigate'&&url.pathname.endsWith('/mobile.html'))event.respondWith(fetch(event.request,{cache:'no-store'}).catch(()=>caches.match('./mobile-offline.html')));});
