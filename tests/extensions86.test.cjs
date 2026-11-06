const {test}=require('node:test');
const assert=require('node:assert/strict');
const {JSDOM}=require('jsdom');
const engine=require('../src/main/assets/jwimport/parser.js');
const DOMParser=new JSDOM('').window.DOMParser;
const watch=require('node:fs').readFileSync(require('node:path').join(__dirname,'../src/main/assets/jwimport/watch.js'),'utf8');
const provider=require('node:fs').readFileSync(require('node:path').join(__dirname,'../src/main/assets/jwimport/provider.js'),'utf8');
const course={name:'矩阵基础',teacher:'教师甲',room:'教室一',day:4,sections:[3,4],weeks:[1,3,5],note:''};
const definition={id:'sample-json',label:'公开样例',format:'json',records:'payload.lessons',fields:{name:'title',teacher:'lecturer',room:'place',day:'weekday',sections:'periods',weeks:'weekNumbers'}};
const row={title:course.name,lecturer:course.teacher,place:course.room,weekday:4,periods:[3,4],weekNumbers:[1,3,5]};
const pack=adapters=>({schemaVersion:1,revision:1,adapters});

test('声明式JSON适配不改宿主，规则实例相互隔离',()=>{
 const importer=engine.createImporter(pack([definition]));
 assert.deepEqual(importer.parseCapture({json:{payload:{lessons:[row]}}}).courses,[course]);
 assert.throws(()=>engine.parseImport(JSON.stringify({payload:{lessons:[row]}})));
 assert.equal(importer.parseImport(JSON.stringify({payload:{lessons:[row]}})).adapterId,'sample-json');
});
test('内置字段属性规则在正式自动解析入口生效',()=>{
 const html='<div data-course-name="矩阵基础" data-day="4" data-sections="3-4" data-weeks="1,3,5" data-teacher="教师甲" data-room="教室一"></div>';
 assert.deepEqual(engine.parseCapture({html},{DOMParser}).courses,[course]);
});
test('内置属性记录缺属性也必须识别为不完整，不能跳过或用旧缓存',()=>{
 const complete='<div data-course-name="课程甲" data-day="2" data-sections="1-2" data-weeks="1-4"></div>';
 const partial='<div data-course-name="课程乙" data-day="3" data-sections="3-4"></div>';
 for(const html of [complete+partial,partial])
  assert.throws(()=>engine.parseCapture({html,jsonSource:'page',json:[course]},{DOMParser}),e=>e.code==='INCOMPLETE_TIMETABLE');
});
test('属性课表自动发现且属性变更刷新指纹，不读取输入框',()=>{
 const dom=new JSDOM('<div data-course-name="课程甲" data-day="2" data-sections="1-2" data-weeks="1-4"></div><input type="password" value="never-export">',{runScripts:'outside-only'});
 const before=dom.window.eval(watch);assert.match(before,/^\d+:\d+$/);
 dom.window.document.querySelector('input').value='changed-private';assert.equal(dom.window.eval(watch),before);
 dom.window.document.querySelector('div').setAttribute('data-sections','3-4');assert.notEqual(dom.window.eval(watch),before);
 dom.window.document.querySelector('div').hidden=true;assert.equal(dom.window.eval(watch),'');dom.window.close();
});
test('正式采集到解析排除样式及祖先隐藏的旧课，不依赖DOMParser样式',async()=>{
 const current='<div data-course-name="当前课程" data-day="2" data-sections="1-2" data-weeks="1-4"></div>';
 const old=current.replace('当前课程','旧课程');
 const dom=new JSDOM('<style>.old{display:none}</style>'+current+'<div class="old">'+old+'</div><div style="display:none">'+old+'</div>',{url:'https://example.edu.cn/timetable',runScripts:'outside-only'});
 dom.window.eval(provider);
 for(let i=0;i<100&&!dom.window.__campusCapture.done;i++)await new Promise(r=>setTimeout(r,10));
 const result=engine.parseCapture(dom.window.__campusCapture,{DOMParser});
 assert.deepEqual(result.courses.map(c=>c.name),['当前课程']);dom.window.close();
 assert.deepEqual(engine.parseImport(current+'<div style="display:none">'+old+'</div>',{DOMParser}).courses.map(c=>c.name),['当前课程']);
});
test('自定义HTML规则可读子元素及属性，命中不完整不得降级',()=>{
 const importer=engine.createImporter(pack([{id:'sample-html',label:'结构化课表',format:'html',records:'.lesson',fields:{name:{selector:'.title'},day:{attribute:'data-day'},weeks:{attribute:'data-weeks'},sections:{attribute:'data-periods'}}}]));
 const html='<div class="lesson" data-day="2" data-weeks="1-4" data-periods="1-2"><b class="title">示例课程</b></div>';
 const result=importer.parseImport(html,{DOMParser});
 assert.equal(result.courses[0].day,2);assert.equal(result.courses[0].name,'示例课程');
 assert.throws(()=>importer.parseCapture({html:html.replace('1-4',''),jsonSource:'page',json:[course]},{DOMParser}),e=>e.code==='INCOMPLETE_TIMETABLE');
});
test('声明不完整或越界拒绝，不执行函数/脚本/原型路径',()=>{
 for(const bad of [
  {...pack([definition]),schemaVersion:2},pack([definition,definition]),
  pack([{...definition,records:'__proto__.lessons'}]),
  pack([{...definition,fields:{...definition.fields,name:'constructor.name'}}]),
  pack([{...definition,script:'alert(1)'}]),
  pack([{...definition,fields:{...definition.fields,name:()=>{throw new Error('executed');}}}]),
  pack([{...definition,fields:{name:'title'}}]),pack(Array(33).fill(definition))
 ]) assert.throws(()=>engine.createImporter(bad));
 const importer=engine.createImporter(pack([definition]));
 for(const lessons of [null,[],{}])
  assert.throws(()=>importer.parseImport(JSON.stringify({payload:{lessons},courses:[course]})),e=>e.code==='INCOMPLETE_TIMETABLE');
 assert.throws(()=>importer.parseImport(JSON.stringify({payload:{lessons:[row,{...row,periods:[]}]}})),e=>e.code==='INCOMPLETE_TIMETABLE');
 assert.throws(()=>importer.parseImport(JSON.stringify({payload:{lessons:Array(5001).fill(row)}})));
});
test('复制规则后外部修改不能改变解析行为',()=>{
 const copy=JSON.parse(JSON.stringify(definition));
 const importer=engine.createImporter(pack([copy]));copy.fields.day='title';
 assert.deepEqual(importer.parseImport(JSON.stringify({payload:{lessons:[row]}})).courses,[course]);
});
