-- Offline regressions for the OpenSubtitles integration. No API key/network needed.
package.path = 'share/lua/modules/?.lua;' .. package.path
local service = require('pvlc_opensubtitles')
local json = require('dkjson')
local function eq(a,b) assert(a == b, tostring(a)..' ~= '..tostring(b)) end
eq(service.searchable_name('https://user:password@example.com/video?token=secret'), '')
eq(service.searchable_name('Film (2004).mkv'), 'Film (2004).mkv')
local zeros, ones = string.rep('\0',65536), string.rep('\255',65536)
eq(service.hash_blocks(65536,zeros,zeros),'0000000000010000')
eq(service.hash_blocks(4294967296,zeros,zeros),'0000000100000000')
eq(service.hash_blocks(4294967296,ones,ones),'00000000ffffc000')
eq(service.hash_blocks(100,zeros,zeros),nil)
eq(service.hash_blocks(131072,zeros,'short'),nil)
local m = service.identify('Show.Name.S02E03.1080p.WEB-DL.mkv')
eq(m.query,'show name'); eq(m.season_number,2); eq(m.episode_number,3)
m = service.identify('Les Indestructibles (2004).mkv')
eq(m.query,'indestructibles'); eq(m.year,2004)
eq(service.identify('Dr.No').query, 'dr no')
eq(service.identify('Film.2004.mkv').year, 2004)
eq(service.identify('Show.S01.E02.mkv').episode_number, 2)
m = service.identify('Show.Name.2x03.mkv'); eq(m.season_number,2); eq(m.episode_number,3)
eq(service.query({query='a & b',year=2004}),'query=a+%26+b&year=2004')
eq(table.concat(service.languages('FR,en,fr'),','),'fr,en')
eq(service.languages('en,fr,de,it'),nil); eq(service.languages('en&query=x'),nil)
eq(service.imdb_id('tt0114709'),'114709'); eq(service.imdb_id('bad'),nil)
eq(service.guessable_name('Movie.Name.2024.mkv'),'Movie.Name.2024.mkv')
eq(service.guessable_name('../secret/movie.mkv'),nil)
local fallback=service.language_catalog({{language_code='xk',language_name='Klingon'}})
local found_en,found_xk=false,false
for _,entry in ipairs(fallback)do
 if entry.code=='en' then found_en=true end
 if entry.code=='xk' and entry.name=='Klingon' then found_xk=true end
end
eq(found_en,true);eq(found_xk,true)
local ranked={
 {id=1, feature=10, language='en', hash_match=false, trusted=false, downloads=2,rating=9},
 {id=2, feature=20, language='fr', hash_match=false, trusted=true, downloads=1000,rating=4},
 {id=3, feature=10, language='fr', hash_match=false, trusted=false, downloads=1,rating=8}}
service.sort(ranked,{'fr','en'})
eq(ranked[1].id,3);eq(ranked[2].id,1);eq(ranked[3].id,2)
service.sort(ranked,{'fr','en'},'downloads');eq(ranked[1].id,2)
service.sort(ranked,{'fr','en'},'rating');eq(ranked[1].id,1)
local offset
vlc = { stream = function() return {
 getsize=function() return 8 * 1024 * 1024 * 1024 end,
 read=function() return zeros end,
 seek=function(_,n) offset=n; return true end,
} end }
eq(service.hash('file:///large.mkv'),'0000000200000000')
eq(offset,8589869056)
eq(service.hash('https://example.com/live'),nil)
vlc.stream=function() return { getsize=function() return 131072 end,
 read=function() return zeros end,seek=function() return false end} end
eq(service.hash('file:///bad.mkv'),nil)

local srt='1\n00:00:01,000 --> 00:00:02,000\nTest\n'
local queue, calls = {}, {}
local function respond(status,obj,raw)
 queue[#queue+1]={status,type(obj)=='table' and json.encode(obj) or obj,raw}
end
local function transport(method,url,body,headers)
 calls[#calls+1]={method=method,url=url,body=body,headers=headers}
 assert(#queue>0,'unexpected HTTP call: '..url)
 return unpack(table.remove(queue,1))
end
vlc.http={get=function(url,h,no_redirect) return transport('GET',url,nil,h) end,
 post=function(url,b,ct,auth,h)
   if auth then h.Authorization=auth end
   return transport('POST',url,b,h)
 end}
local client=service.new('test-key','test')
respond(200,{token='test-token',base_url='vip-api.opensubtitles.com'})
assert(client:login('user','password'))
eq(calls[1].headers['Api-Key'],'test-key'); eq(calls[1].headers['User-Agent'],'PowerVLC vtest')
respond(200,{data={{language_code='fr',language_name='French'},{language_code='eo',language_name='Esperanto'}}})
local languages=assert(client:language_catalog());assert(#languages>2)
eq(calls[#calls].headers.Authorization,'Bearer test-token')
respond(200,{title='Movie',year=2024,season=2,episode=3})
local guessed=assert(client:guess('Movie.S02E03.mkv'))
eq(guessed.query,'Movie');eq(guessed.year,2024);eq(guessed.season_number,2)
respond(200,{token='account-token',base_url='vip-api.opensubtitles.com'})
respond(200,{data={username='user',level='VIP',downloads_count=2,allowed_downloads=20,reset_time_utc='tomorrow'}})
local account=assert(client:account('user','password'))
eq(account.remaining,18);eq(account.level,'VIP');eq(account.reset_time,'tomorrow')
respond(200,{data={{attributes={language='fr',moviehash_match=true,from_trusted=true,
 hd=true,ai_translated=true,machine_translated=false,ratings=8.5,votes=12,fps=23.976,
 download_count=321,upload_date='2026-09-01',uploader={name='Alice',rank='trusted'},
 files={{file_id=42,file_name='test.srt'}}}}},page=1,total_pages=2})
local rows,err,page=client:search({languages='fr'})
eq(#rows,1); eq(rows[1].id,42); eq(rows[1].hash_match,true); eq(page.pages,2)
eq(rows[1].rating,8.5);eq(rows[1].downloads,321);eq(rows[1].hd,true)
eq(rows[1].ai_translated,true);eq(rows[1].uploader,'Alice')
assert(calls[#calls].url:match('^https://vip%-api.opensubtitles.com/api/v1/subtitles'))
respond(200,{link='https://dl.opensubtitles.com/download/test.srt',remaining=4})
respond(200,srt)
local body,_,quota=client:download(42,'user','password')
eq(body,srt); eq(quota.remaining,4)
eq(calls[#calls].headers,nil)
eq(calls[#calls-1].headers.Authorization,'Bearer account-token')
eq(json.decode(calls[#calls-1].body).sub_format,'srt')
respond(406,{remaining=0}); local _,e=client:download(42,'user','password'); eq(e,'quota')
respond(429,{}); _,e=client:search({}); eq(e,'rate_limit')
respond(401,{}); respond(200,{token='new-token'});
respond(200,{link='https://dl.opensubtitles.com/test.srt'}); respond(200,srt)
assert(client:download(42,'user','password'))
eq(calls[#calls-1].headers.Authorization,'Bearer new-token')
respond(200,{link='https://evil.example/test.srt'}); _,e=client:download(42,'',''); eq(e,'invalid_response')
respond(302,'','HTTP/1.1 302\r\nLocation: http://api.opensubtitles.com/test\r\n')
_,e=client:search({}); eq(e,'invalid_response')
respond(200,{link='https://dl.opensubtitles.com/test.srt'}); respond(200,'<html>Login</html>')
_,e=client:download(42,'',''); eq(e,'invalid_subtitle')
respond(200,{token='bad',base_url='evil.example'}); _,e=client:login('u','p');eq(e,'invalid_response')
respond(200,{data=false}); _,e=client:search({}); eq(e,'invalid_response')
eq(#queue,0)

local written,existing={}, {['/movie/Film.fr.srt']=true}
vlc.io={open_exclusive=function(path)
 if existing[path] then return nil,17 end
 if path:match('^/readonly/') then return nil,13 end
 existing[path]=true
 return {write=function(_,data) written[path]=data;return true end,close=function() return true end}
end,unlink=function(path) existing[path]=nil;written[path]=nil end}
local row={language='fr',id=42}
local path=service.save(srt,{'/movie'},'Film',row)
eq(path,'/movie/Film.fr.42.2.srt');eq(written['/movie/Film.fr.srt'],nil)
path=service.save(srt,{'/readonly','/cache'},'../Film',row)
eq(path,'/cache/.._Film.fr.srt');eq(written[path],srt)
vlc.io.open_exclusive=function()return {write=function()return false end,close=function()return true end} end
_,e=service.save(srt,{'/cache'},'Disk-full',row);eq(e,'save_failed')

-- Exercise the extension callbacks with native-widget stand-ins.
local widgets, timer, input_id, loaded, saved_paths={},nil,1,nil,{}
local function widget(kind,text)
 local w={kind=kind,text=text,values={},selection={}}
 function w:set_text(t)self.text=t end
 function w:get_text()return self.text end
 function w:set_value(v)self.value=v end
 function w:get_value()return self.value end
 function w:set_checked(v)self.checked=v end
 function w:get_checked()return self.checked end
 function w:add_value(t,id)self.values[id]=t end
 function w:clear()self.values={};self.selection={} end
 function w:get_selection()return self.selection end
 widgets[#widgets+1]=w;return w
end
local item={uri=function()return 'file:///movie/Film.2004.mkv' end,name=function()return 'Film.2004.mkv' end}
vlc.config={language=function()return 'fr_FR' end,userdatadir=function()return '/data' end,
 cachedir=function()return '/cache' end,datadir=function()return 'share' end}
vlc.input={item=function()return item end,add_subtitle=function(path,select,id)
 eq(select,true);eq(id,1);loaded=path;return true end}
vlc.playlist={current=function()return input_id end}
vlc.strings={make_path=function()return '/movie/Film.2004.mkv' end}
vlc.misc={product_version=function()return 'test' end}
vlc.timer=function(_,name)timer=name end
local memory_files={}
vlc.io={open=function(path,mode)
 if mode=='wb'then return {write=function(_,body)memory_files[path]=body;return true end,close=function()return true end}end
 if memory_files[path]then return {read=function()return memory_files[path]end,close=function()return true end}end
 return nil
 end,mkdir=function()return 0 end,
 open_exclusive=function(path)saved_paths[#saved_paths+1]=path;memory_files[path]=srt
  return {write=function(_,body)memory_files[path]=body;return true end,close=function()return true end}end,
 unlink=function()end}
vlc.dialog=function()
 widgets={}
 local d={show=function()end,delete=function()end,update=function()end}
 d.add_text_input=function(_,text)return widget('text',text)end
 d.add_password=function(_,text)return widget('password',text)end
 d.add_label=function(_,text)return widget('label',text)end
 d.add_button=function(_,text,fn)local w=widget('button',text);w.click=fn;return w end
 d.add_dropdown=function()return widget('dropdown')end
 d.add_list=function()return widget('list')end
 d.add_check_box=function(_,text,checked)local w=widget('check',text);w.checked=checked;return w end
 return d
end
service.hash=function()return '0000000100000000' end
package.loaded.pvlc_folder_picker={new=function(_,callbacks)return {
 busy=function()return false end,
 open=function(_,prompt,current)callbacks.done('/chosen',nil);return true end,
 poll=function()return false end,close=function()end}end}
assert(loadfile('share/lua/extensions/PowerVLSub.lua'))()
activate();eq(timer,'search')
respond(200,{data={},page=1,total_pages=0})
respond(200,{data={{attributes={language='fr',files={{file_id=42,file_name='Film.srt'}}}}},page=1,total_pages=1})
search()
eq(calls[#calls-1].url:find('moviehash=',1,true)~=nil,true)
eq(calls[#calls].url:find('query=film',1,true)~=nil,true)
local list
for _,w in ipairs(widgets)do if w.kind=='list'then list=w end end
assert(list.values[1]);list.selection[1]=true
respond(200,{link='https://dl.opensubtitles.com/test.srt',remaining=4});respond(200,srt)
download();eq(loaded,'/movie/Film.2004.fr.srt')
loaded=nil;input_id=2;local count=#calls
download();eq(loaded,nil);eq(#calls,count)
input_id=1
toggle_advanced_search()
local text_inputs={}
for _,w in ipairs(widgets)do if w.kind=='text'then text_inputs[#text_inputs+1]=w end end
eq(#text_inputs,5);text_inputs[5]:set_text('tt0114709')
respond(200,{data={{attributes={language='fr',ratings=9.1,download_count=900,
 files={{file_id=43,file_name='Film.IMDb.srt'}}}}},page=1,total_pages=1})
search()
assert(calls[#calls].url:find('imdb_id=114709',1,true));assert(not calls[#calls].url:find('query=',1,true))
respond(200,{data={{language_code='fr',language_name='French'}}})
show_settings()
local setting_texts,passwords,dropdowns,buttons={},{},{},{}
for _,w in ipairs(widgets)do
 if w.kind=='text'then setting_texts[#setting_texts+1]=w
 elseif w.kind=='password'then passwords[#passwords+1]=w
 elseif w.kind=='dropdown'then dropdowns[#dropdowns+1]=w
 elseif w.kind=='button'then buttons[#buttons+1]=w end
end
setting_texts[2]:set_text('user');passwords[1]:set_text('password')
respond(200,{token='ui-account-token'})
respond(200,{data={username='user',level='VIP',remaining_downloads=17,reset_time='tomorrow'}})
for _,button in ipairs(buttons)do if button.text=='Tester le compte'then button.click()end end
dropdowns[4]:set_value(2)
respond(200,{data={{attributes={language='fr',files={{file_id=44,file_name='Temporary.srt'}}}}},page=1,total_pages=1})
save_settings()
local temporary_list
for _,w in ipairs(widgets)do if w.kind=='list'then temporary_list=w end end
temporary_list.selection[1]=true
respond(200,{token='download-token'})
respond(200,{link='https://dl.opensubtitles.com/temporary.srt',remaining=16});respond(200,srt)
download();assert(loaded:find('^/cache/subtitles/'))
local before_save_as=#saved_paths
save_as();eq(#saved_paths,before_save_as+1);assert(saved_paths[#saved_paths]:find('^/chosen/'))
for _,w in ipairs(widgets)do assert(w.text==nil or type(w.text)=='string') end
input_changed();deactivate()
eq(#queue,0)
print('OpenSubtitles: hash, search, auth, quotas, safe saving and UI callbacks passed')
