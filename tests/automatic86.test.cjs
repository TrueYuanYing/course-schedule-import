const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const {JSDOM}=require('jsdom');
const watch=fs.readFileSync(__dirname+'/../src/main/assets/jwimport/watch.js','utf8');
const table='<table><tr><th>节次</th><th>星期一</th></tr><tr><td>1-2节</td><td>示例课 [1-16周]</td></tr></table>';
test('登录表单不触发采集，课程变化才改变指纹，输入值不被读取',()=>{
 const dom=new JSDOM('<input value="fixture-secret"><div>登录系统(学生)</div>',{runScripts:'outside-only'}),w=dom.window;
 assert.equal(w.eval(watch),'');w.document.body.insertAdjacentHTML('beforeend',table);
 const first=w.eval(watch);assert.match(first,/^\d+:\d+$/);assert.equal(w.eval(watch),first);
 w.document.querySelector('input').value='changed-secret';assert.equal(w.eval(watch),first);
 w.document.querySelector('tr:last-child td:last-child').textContent='另一门课 [17-21周]';assert.notEqual(w.eval(watch),first);w.close();
});
test('隐藏旧课表不触发，分离表头组件更新表体可触发',()=>{
 const dom=new JSDOM('<div hidden>'+table+'</div><div class="ui-jqgrid"><table><tr><th>节次</th><th>星期一</th></tr></table><table id="body"></table></div>',{runScripts:'outside-only'}),w=dom.window;
 const first=w.eval(watch);w.document.querySelector('#body').innerHTML='<tr><td>F1</td><td>示例课 [1-16周]</td></tr>';
 assert.notEqual(w.eval(watch),first);w.document.querySelector('.ui-jqgrid').remove();assert.equal(w.eval(watch),'');w.close();
});
test('同源课表iframe可自动发现，不执行表单或网络请求',()=>{
 const dom=new JSDOM('<iframe></iframe>',{runScripts:'outside-only'}),w=dom.window;
 w.document.querySelector('iframe').contentDocument.body.innerHTML=table;
 assert.match(w.eval(watch),/^\d+:\d+$/);w.close();
});
test('没有特定组件类名的分离表头/表体也会随课程变化重新读取',()=>{
 const dom=new JSDOM('<table><tr><th>节次</th><th>星期一</th></tr></table><div><table id="courses"></table></div>',{runScripts:'outside-only'}),w=dom.window;
 const first=w.eval(watch);w.document.querySelector('#courses').innerHTML='<tr><td>F1</td><td>矩阵论 [1-16周]</td></tr>';
 assert.notEqual(w.eval(watch),first);w.close();
});
