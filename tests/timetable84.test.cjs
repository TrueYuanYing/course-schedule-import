const {test}=require('node:test');
const assert=require('node:assert/strict');
const {JSDOM}=require('jsdom');
const fs=require('node:fs');
const provider=fs.readFileSync(__dirname+'/../src/main/assets/jwimport/provider.js','utf8');
const parser=require('../src/main/assets/jwimport/parser.js');

// Public synthetic reconstruction of the component boundary, not an authenticated school export.
async function weeklyCapture(total=4){
  const dom=new JSDOM(`<div class="datagrid"><div class="datagrid-view">
    <table class="datagrid-f" style="display:none"></table>
    <table class="datagrid-htable"><tr><td field="jc">节次</td><td field="xq1">星期一 [Monday]</td><td field="xq2">星期二 [Tuesday]</td></tr></table>
    <table class="datagrid-btable"><tr datagrid-row-index="0"><td field="jc">F1</td><td field="xq1" rowspan="2">示例课程甲 [3-12周] 示例教师 [示例楼101]</td><td field="xq2"></td></tr>
      <tr datagrid-row-index="1"><td field="jc">F2</td><td field="xq2"></td></tr>
      <tr datagrid-row-index="2"><td field="jc">F3</td><td field="xq1"></td><td field="xq2" rowspan="2">示例课程乙 [2-10周] 示例教师 [示例楼202]</td></tr>
      <tr datagrid-row-index="3"><td field="jc">F4</td><td field="xq1"></td></tr></table>
    </div></div>`,{url:'https://graduate.example.edu.cn/gmis5/student/timetable',runScripts:'outside-only'});
  const w=dom.window;
  const columns=[[{field:'jc',title:'节次'},{field:'xq1',title:'星期一 [Monday]'},{field:'xq2',title:'星期二 [Tuesday]'}]];
  const rows=[{jc:'F1',xq1:'示例课程甲 [3-12周] 示例教师 [示例楼101]',xq2:''},
    {jc:'F2',xq1:'',xq2:''},{jc:'F3',xq1:'',xq2:'示例课程乙 [2-10周] 示例教师 [示例楼202]'},{jc:'F4',xq1:'',xq2:''}];
  w.jQuery=()=>({datagrid:m=>m==='options'?{columns}:{total,rows}});
  w.jQuery.fn={datagrid(){}};
  w.fetch=()=>{throw Error('must use current loaded page only');};
  w.eval(provider);
  for(let n=0;n<50&&!w.__campusCapture.done;n++)await new Promise(r=>setTimeout(r,5));
  const captured=JSON.parse(JSON.stringify(w.__campusCapture));
  w.close();return captured;
}

test('分离表头表体的研究生周课表保留F节次与真实rowspan',async()=>{
  const capture=await weeklyCapture();
  const parsed=parser.parseImport(capture.html,{DOMParser:new JSDOM('').window.DOMParser});
  assert.deepEqual(parsed.courses.map(c=>[c.name,c.day,c.sections,c.weeks[0],c.weeks.at(-1)]),
    [['示例课程甲',1,[1,2],3,12],['示例课程乙',2,[3,4],2,10]]);
});

test('周视图分页未完整时拒绝把4条当8条完整学期',async()=>{
  const capture=await weeklyCapture(8);
  assert.match(capture.error||'',/分页.*4.*8/);
});

test('Native和兼容路径共用当前页解析优先级与错误',()=>{
  const html='<table><tr><th>节次</th><th>星期二</th></tr><tr><td>3-4节</td><td>当前学期<br>17-21周</td></tr></table>';
  const result=parser.parseCapture({html,jsonSource:'page',json:{courses:[{name:'旧学期',day:1,sections:[1],weeks:[1]}]}},
    {DOMParser:new JSDOM('').window.DOMParser});
  assert.equal(result.courses[0].name,'当前学期');
  assert.throws(()=>parser.parseCapture({error:'分页尚未完整',html},{}),/分页尚未完整/);
});

test('没有组件API时，成对的固定表头和滚动表体按明确列与节次组合',()=>{
  const html='<div class="ui-jqgrid"><table class="ui-jqgrid-htable"><tr><th>节次</th><th>星期一 [Monday]</th><th>星期四 [Thursday]</th></tr></table>'+
    '<table class="ui-jqgrid-btable"><tr><td>F1</td><td></td><td rowspan="2">矩阵论 [17-21周] 示例教师 [示例楼101]</td></tr>'+
    '<tr><td>F2</td><td></td></tr></table></div>';
  const result=parser.parseImport(html,{DOMParser:new JSDOM('').window.DOMParser});
  assert.deepEqual(result.courses.map(c=>[c.name,c.day,c.sections,c.weeks.at(-1)]),[['矩阵论',4,[1,2],21]]);
});

test('两个不相关的表格不能按位置拼成猜测课表',()=>{
  const html='<table><tr><th>节次</th><th>星期一</th></tr></table>'+
    '<table><tr><td>F1</td><td>矩阵论 [1-16周] 示例教师 [示例楼101]</td></tr></table>';
  assert.throws(()=>parser.parseImport(html,{DOMParser:new JSDOM('').window.DOMParser}),/未得到有效课程/);
});

test('固定表头组件不能把DataTables当前分页当成完整学期',()=>{
  const html='<div class="dataTables_wrapper"><div class="dataTables_scroll">'+
    '<table><tr><th>节次</th><th>星期一</th></tr></table>'+
    '<table><tr><td>F1</td><td>示例课程 [1-16周] 示例教师 [示例楼101]</td></tr></table></div>'+
    '<div class="dataTables_info">Showing 1 to 1 of 8 entries</div><div class="dataTables_paginate">'+
    '<a class="paginate_button previous disabled">Previous</a><a class="paginate_button current">1</a><a class="paginate_button">2</a><a class="paginate_button next">Next</a></div></div>';
  assert.throws(()=>parser.parseImport(html,{DOMParser:new JSDOM('').window.DOMParser}),/分页.*全部/);
});

test('固定表头不能静默丢弃缺少明确节次的非空课程行',()=>{
  const html='<div class="ui-jqgrid"><table><tr><th>节次</th><th>星期一</th></tr></table>'+
    '<table><tr><td>F1</td><td>示例课程甲 [1-16周] 示例教师 [示例楼101]</td></tr>'+
    '<tr><td>未知节次</td><td>示例课程乙 [1-16周] 示例教师 [示例楼102]</td></tr></table></div>';
  assert.throws(()=>parser.parseImport(html,{DOMParser:new JSDOM('').window.DOMParser}),/未完整读取/);
});

test('隐藏旧课表不阻止当前首页继续发现课表菜单',async()=>{
  const dom=new JSDOM('<a href="/student/kcb">课表菜单</a><div hidden><table><tr><th>星期一</th></tr></table></div>',
    {url:'https://graduate.example.edu.cn/home',runScripts:'outside-only'});
  dom.window.eval(provider);
  for(let i=0;i<50&&!dom.window.__campusCapture.done;i++)await new Promise(r=>setTimeout(r,5));
  assert.equal(dom.window.__campusCapture.hasTimetable,false);
  dom.window.close();
});

test('不完整分页的拒绝不能被缓存页面JSON回退绕过',()=>{
  const html='<div class="dataTables_wrapper"><div class="dataTables_scroll">'+
    '<table><tr><th>节次</th><th>星期一</th></tr></table>'+
    '<table><tr><td>F1</td><td>示例课程 [1-16周] 示例教师 [示例楼101]</td></tr></table></div>'+
    '<div class="dataTables_paginate"><a class="paginate_button next">Next</a></div></div>';
  const capture={html,jsonSource:'page',json:{courses:[{name:'缓存的单门课',day:1,sections:[1],weeks:[1]}]}};
  assert.throws(()=>parser.parseCapture(capture,{DOMParser:new JSDOM('').window.DOMParser}),/分页/);
});
