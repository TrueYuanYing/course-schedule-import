const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');const path=require('node:path');
const {JSDOM}=require('jsdom');
const provider=fs.readFileSync(path.join(__dirname,'../src/main/assets/jwimport/provider.js'),'utf8');
test('隐藏课程行删除不使当前行错位，隐藏作息不进入快照',async()=>{
 const r=await capture('<table><tr hidden data-course-name="Old"><td>旧课</td></tr><tr data-course-name="Current" data-day="2" data-sections="1,2" data-weeks="1,2"><td>当前课</td></tr></table><div style="visibility:hidden"><p data-period-index="1" data-start-time="07:00" data-end-time="07:45"></p></div>','https://example.edu.cn/course',()=>{throw Error('unexpected_fetch');});
 assert.match(r.html,/data-course-name="Current"/);assert.doesNotMatch(r.html,/data-course-name="Old"|data-period-index/);
});
async function capture(html,url,fetch,setup){
 const dom=new JSDOM(html,{url,runScripts:'outside-only'}),w=dom.window;w.fetch=fetch;w.AbortController=AbortController;
 setup?.(w);
 w.eval(provider);for(let i=0;i<100&&!w.__campusCapture.done;i++)await new Promise(r=>setTimeout(r,5));
 const result=w.__campusCapture;assert.equal(result.done,true);w.close();return result;
}
test('采集移除凭据字段、无关脚本，仅保留惰性树维数据脚本',async()=>{
 let requests=0;
 const r=await capture('<input type="password" value="test-only-password"><textarea>test-only-secret</textarea><script>test-only-token</script><script>new TaskActivity("t","数学","r","A101","011");index=0*unitCount+0;</script>','https://example.edu.cn/course',()=>{requests++;throw new Error();});
 assert.doesNotMatch(r.html,/test-only-password|test-only-secret|test-only-token|<input|<textarea/);assert.match(r.html,/type="text\/plain"/);assert.match(r.html,/TaskActivity/);assert.equal(requests,0);
});
test('新正方仅在已知课表路径向同源发送明确学期参数',async()=>{
 const calls=[];const response={kbList:[{kcmc:'数学'}]};
 const r=await capture('<select id="xnm"><option value="2026" selected>2026</option></select><select id="xqm"><option value="3" selected>1</option></select>','https://example.edu.cn/jwglxt/kbcx/xskbcx_cxXsgrkb.html',async(u,o)=>{calls.push({u,o});return {ok:true,json:async()=>response};});
 assert.equal(calls.length,1);assert.equal(calls[0].u,'/jwglxt/kbcx/xskbcx_cxXsgrkb.html');assert.equal(calls[0].o.credentials,'same-origin');assert.equal(calls[0].o.body,'xnm=2026&xqm=3&kzlx=ck');assert.deepEqual(r.json,response);
});
test('接口失败保留 HTML 并提示，不把登录 HTML 当 JSON 成功',async()=>{
 const r=await capture('<p>当前课表页面</p>','https://example.edu.cn/student/courseSelect/thisSemesterCurriculum/index',async()=>({ok:true,json:async()=>{throw new Error('HTML response');}}));
 assert.equal(r.json,null);assert.match(r.html,/当前课表页面/);assert.equal(r.warnings.length,1);
});
test('东北大学金智多校区不会静默选第一个校区',async()=>{
 const calls=[];
 const r=await capture('<p>课表</p>','https://jwxt.neu.edu.cn/jwapp/sys/homeapp/*default/index.do',async u=>{calls.push(u);return {ok:true,json:async()=>u.includes('currentUser')?{datas:{welcomeInfo:{xnxqdm:'2026-2027-1'}}}:{datas:[{id:'a'},{id:'b'}]}};});
 assert.equal(calls.length,2);assert.equal(r.json,null);assert.match(r.warnings.join(''),/不是单校区格式/);
});

test('异步接口等待结束后采集最新课表 DOM，避免保存加载占位页',async()=>{
 const dom=new JSDOM('<main id="page">加载中</main>',{url:'https://example.edu.cn/student/courseSelect/thisSemesterCurriculum/index',runScripts:'outside-only'}),w=dom.window;
 w.AbortController=AbortController;
 w.fetch=async()=>{await new Promise(r=>setTimeout(r,15));w.document.getElementById('page').textContent='矩阵论 17-21周';return {ok:true,json:async()=>({dateList:[]})};};
 w.eval(provider);for(let i=0;i<100&&!w.__campusCapture.done;i++)await new Promise(r=>setTimeout(r,5));
 assert.equal(w.__campusCapture.done,true);assert.match(w.__campusCapture.html,/矩阵论 17-21周/);assert.doesNotMatch(w.__campusCapture.html,/加载中/);w.close();
});

test('开放 shadow DOM 的课表可采集，组件内凭据和脚本仍被移除',async()=>{
 const r=await capture('<div id="portal"></div>','https://example.edu.cn/course',()=>{throw new Error('no request');},w=>{
   w.document.getElementById('portal').attachShadow({mode:'open'}).innerHTML='<table><tr><th>周四</th></tr><tr><td>矩阵论 17-21周</td></tr></table><input value="test-shadow-secret"><script>test-shadow-script</script>';
 });
 assert.match(r.html,/矩阵论 17-21周/);assert.doesNotMatch(r.html,/test-shadow-secret|test-shadow-script/);
});

test('保留多份已加载课表 JSON 候选，不让第一份无效全局数据挡住有效数据',async()=>{
 const r=await capture('<p>课程</p>','https://example.edu.cn/course',()=>{throw new Error('no request');},w=>{
   w.activities=[{unrelated:'not a course'}];
   w.kbList=[{kcmc:'英语',xqj:4,jcs:'3-4',zcd:'17-21周'}];
 });
 assert.equal(r.jsonSource,'page');assert.equal(r.jsonCandidates.length,2);assert.equal(r.jsonCandidates[1].kbList[0].kcmc,'英语');
});

test('某个同源 iframe 接口失败不影响另一个 iframe 的已加载课表',async()=>{
 const r=await capture('<iframe src="/student/courseSelect/thisSemesterCurriculum/index"></iframe><iframe src="/course"></iframe>','https://example.edu.cn/portal',async()=>{throw new Error('first frame failed');},w=>{
   w.document.querySelectorAll('iframe')[1].contentWindow.kbList=[{kcmc:'矩阵论',xqj:4,jcs:'3-4',zcd:'17-21周'}];
 });
 assert.equal(r.jsonCandidates.length,1);assert.equal(r.jsonCandidates[0].kbList[0].kcmc,'矩阵论');assert.equal(r.done,true);
});

test('读取期间切换学期时丢弃旧学期接口响应',async()=>{
 const dom=new JSDOM('<select id="xnm"><option value="2026">2026</option><option value="2025">2025</option></select><select id="xqm"><option value="3">1</option></select>',{url:'https://example.edu.cn/jwglxt/kbcx/xskbcx_cxXsgrkb.html',runScripts:'outside-only'}),w=dom.window;
 w.AbortController=AbortController;w.fetch=async()=>{w.document.getElementById('xnm').value='2025';return {ok:true,json:async()=>({kbList:[{kcmc:'旧学期'}]})};};
 w.eval(provider);for(let i=0;i<100&&!w.__campusCapture.done;i++)await new Promise(r=>setTimeout(r,5));
 assert.equal(w.__campusCapture.json,null);assert.match(w.__campusCapture.warnings.join(''),/学期.*切换/);w.close();
});
test('页面作息只返回节次起止字段，不查询未知接口或带出额外资料',async()=>{
 const r=await capture('<p>课表</p>','https://example.edu.cn/course',()=>{throw Error('unexpected_fetch');},w=>{
  w.sectionTimes=[{section:1,startTime:'8:00',endTime:'8:45',password:'private-value'},{section:2,startTime:'08:55',endTime:'09:40'}];
 });
 assert.deepEqual(JSON.parse(JSON.stringify(r.periodTimes)),{'1':{start:'08:00',end:'08:45'},'2':{start:'08:55',end:'09:40'}});
 assert.doesNotMatch(JSON.stringify(r),/private-value|password/);
});
