const {test}=require('node:test');
const assert=require('node:assert/strict');
const {JSDOM}=require('jsdom');
const fs=require('node:fs');
const parser=require('../src/main/assets/jwimport/parser.js');
const provider=fs.readFileSync(__dirname+'/../src/main/assets/jwimport/provider.js','utf8');

test('真实EAMS参数形态：教师join调用不能截断TaskActivity参数',()=>{
  const html=`<script>var teachers=[{id:7,name:"示例教师",lab:false}];
    activity=new TaskActivity(actTeacherId.join(','),actTeacherName.join(','),
      "9000","示例课程","100","教学楼101","0000001111111","",null,assistantName,"","");
    index=3*unitCount+2;index=3*unitCount+3;</script>`;
  const result=parser.parseImport(html,{DOMParser:new JSDOM('').window.DOMParser});
  assert.deepEqual(result.courses,[{name:'示例课程',teacher:'示例教师',room:'教学楼101',
    day:4,sections:[3,4],weeks:[6,7,8,9,10,11,12],note:''}]);
});

test('学期说明超过五行且星期含空格和英文括号仍读取正确星期节次',()=>{
  const preamble='<tr><td colspan="3">学期说明</td></tr>'.repeat(7);
  const html='<table>'+preamble+'<tr><th>节次</th><th>星期 一（Monday）</th><th>星期 四（Thursday）</th></tr>'+
    '<tr><td>1-2节</td><td>数值分析<br>1-16周</td><td>矩阵论<br>17-21周</td></tr></table>';
  const result=parser.parseImport(html,{DOMParser:new JSDOM('').window.DOMParser});
  assert.deepEqual(result.courses.map(c=>[c.name,c.day,c.sections,c.weeks.at(-1)]),
    [['数值分析',1,[1,2],16],['矩阵论',4,[1,2],21]]);
});

const columns=[[{field:'title',title:'课程名称'},{field:'weekday',title:'星期'},
  {field:'periods',title:'节次'},{field:'weeks',title:'周次'},
  {field:'teacher',title:'任课教师'},{field:'place',title:'上课地点'}]];
async function gridCapture(total=1,prepare){
  const dom=new JSDOM('<div class="datagrid"><table class="datagrid-f"></table></div>',
    {url:'https://example.edu.cn/gmis5/student/course',runScripts:'outside-only'});
  const w=dom.window;
  const rows=[{title:'矩阵论',weekday:'星期四',periods:'3-4',weeks:'17-21周',teacher:'示例教师',place:'教学楼101',password:'must-not-export'}];
  w.jQuery=node=>({datagrid:method=>{
    assert.equal(node.tagName,'TABLE');
    if(method==='options')return {columns};
    if(method==='getData')return {total,rows};
    throw new Error('must not request or mutate data');
  }});
  w.jQuery.fn={datagrid(){}};
  if(prepare)prepare(w);
  w.fetch=()=>{throw new Error('must not request hidden API');};
  w.eval(provider);
  for(let i=0;i<100&&!w.__campusCapture.done;i++)await new Promise(r=>setTimeout(r,5));
  const capture=JSON.parse(JSON.stringify(w.__campusCapture));w.close();return capture;
}
test('EasyUI已加载课程按列标题归一化，未渲染行可读且不导出无关字段',async()=>{
  const capture=await gridCapture();
  assert.equal(capture.done,true);
  assert.equal(capture.jsonSource,'grid');
  assert.doesNotMatch(JSON.stringify(capture),/must-not-export/);
  const result=parser.parseImport(JSON.stringify(capture.json));
  assert.deepEqual(result.courses,[{name:'矩阵论',teacher:'示例教师',room:'教学楼101',day:4,
    sections:[3,4],weeks:[17,18,19,20,21],note:''}]);
});
test('已加载分页数据不足完整学期时明确拒绝，不将部分页伪装为导入成功',async()=>{
  const capture=await gridCapture(8);
  assert.match(capture.error||'',/分页.*1.*8/);
  assert.equal(capture.json,null);
});
test('隐藏旧学期的表格不成为当前课表数据',async()=>{
  const capture=await gridCapture(1,w=>w.document.querySelector('.datagrid').hidden=true);
  assert.equal(capture.json,null);
});
test('shadow root 内的表格组件也可读取',async()=>{
  const capture=await gridCapture(1,w=>{
    const grid=w.document.querySelector('.datagrid');
    const portal=w.document.createElement('div');w.document.body.append(portal);
    portal.attachShadow({mode:'open'}).append(grid);
  });
  assert.equal(capture.jsonSource,'grid');
  assert.equal(capture.json.courses[0].name,'矩阵论');
});
test('隐藏组件的 shadow root 不导入旧课表',async()=>{
  const capture=await gridCapture(1,w=>{
    const grid=w.document.querySelector('.datagrid');
    const portal=w.document.createElement('div');w.document.body.append(portal);
    portal.hidden=true;portal.attachShadow({mode:'open'}).append(grid);
  });
  assert.equal(capture.json,null);
});
test('非课表业务组件不被收集或触发读取',async()=>{
  const capture=await gridCapture(1,w=>{
    w.jQuery=node=>({datagrid:method=>{
      assert.equal(method,'options');return {columns:[[{field:'email',title:'邮箱'}]]};
    }});w.jQuery.fn={datagrid(){}};
  });
  assert.equal(capture.json,null);
});
test('HTML回退也剔除隐藏旧课表，不能只过滤JSON',async()=>{
  const capture=await gridCapture(1,w=>{
    delete w.jQuery;
    const old=w.document.createElement('div');old.hidden=true;
    old.innerHTML='<table><tr><th>课程名称</th><th>星期</th><th>周次</th><th>节次</th></tr>'+
      '<tr><td>旧学期课程</td><td>星期一</td><td>1-16周</td><td>1-2节</td></tr></table>';
    w.document.body.append(old);
  });
  assert.doesNotMatch(capture.html,/旧学期课程/);
  assert.throws(()=>parser.parseImport(capture.html,{DOMParser:new JSDOM('').window.DOMParser}));
});
test('隐藏iframe中旧课表不混入当前完整课程数据',async()=>{
  const capture=await gridCapture(1,w=>{
    const frame=w.document.createElement('iframe');frame.hidden=true;w.document.body.append(frame);
    frame.contentDocument.body.innerHTML='<table class="datagrid-f"></table>';
    frame.contentWindow.jQuery=w.jQuery;
  });
  assert.equal(capture.json.courses.length,1);
});
test('空分页组件total非零时也不能被当成空课表跳过',async()=>{
  const capture=await gridCapture(1,w=>{
    const second=w.document.createElement('table');second.className='datagrid-f';w.document.body.append(second);
    const original=w.jQuery;
    w.jQuery=node=>node!==second?original(node):{datagrid:method=>method==='options'?{columns}:{total:8,rows:[]}};
    w.jQuery.fn=original.fn;
  });
  assert.match(capture.error||'',/分页.*0.*8/);
  assert.equal(capture.json,null);
});
test('EAMS在head里的课程脚本保留为惰性文本，不因head默认隐藏而丢失',async()=>{
  const capture=await gridCapture(1,w=>{
    delete w.jQuery;
    const script=w.document.createElement('script');
    script.textContent='var activity = new TaskActivity("0", "矩阵论", "0", "教学楼101", "01111");';
    w.document.head.append(script);
  });
  assert.match(capture.html,/new TaskActivity/);
  assert.match(capture.html,/type="text\/plain"/);
});
