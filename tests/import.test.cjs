const {test}=require('node:test');
const assert=require('node:assert/strict');

const path=require('node:path');
const {JSDOM}=require('jsdom');
const C=require('../src/main/assets/jwimport/parser.js');
const DOMParser=new JSDOM('').window.DOMParser;
const parse=s=>C.parseImport(s,{DOMParser});
const qz=(headers='<th>节次</th>'+['一','二','三','四','五','六','日'].map(x=>'<th>星期'+x+'</th>').join(''),content='高等数学<br><font title="老师">王老师</font><br><font title="周次(节次)">1-16(单)(周)[01-02节]</font><br><font title="教室">A101</font>')=>'<table id="kbtable"><tr>'+headers+'</tr><tr><td>1-2节</td><td><div class="kbcontent">'+content+'</div></td>'+('<td></td>'.repeat(6))+'</tr></table>';
test('解析强智课表保留单周、教师、教室、节次',()=>{
 const r=parse(qz());assert.deepEqual(r.courses,[{name:'高等数学',teacher:'王老师',room:'A101',day:1,sections:[1,2],weeks:[1,3,5,7,9,11,13,15],note:''}]);
});
test('星期日位于首列时不能误认为星期一',()=>{
 const r=parse(qz('<th>节次</th>'+['日','一','二','三','四','五','六'].map(x=>'<th>星期'+x+'</th>').join('')));assert.equal(r.courses[0].day,7);
});
test('同格多课分别解析且不丢失课程',()=>{
 const content='线性代数<br><font title="周次(节次)">1-4(周)[03-04节]</font><br>----------------<br>概率论<br><font title="周次(节次)">5-8(周)[03-04节]</font>';
 const r=parse(qz(undefined,content));assert.equal(r.courses.length,2);assert.equal(r.courses[1].name,'概率论');assert.deepEqual(r.courses[1].weeks,[5,6,7,8]);
});
test('拒绝缺失周次而不是默认生成整个学期',()=>{
 assert.throws(()=>parse(qz(undefined,'高等数学<br><font title="教室">A101</font>')),/未得到有效课程/);
});
test('逗号分段周次保留各自单双周限制',()=>{
 assert.deepEqual(C.weeks('1-6周(单),8-12周(双),15周'),[1,3,5,8,10,12,15]);
});
test('非法周次不能默默截断',()=>{
 assert.throws(()=>C.weeks('5-2'),/超出范围/);assert.throws(()=>C.weeks('待定'),/无法识别/);assert.throws(()=>C.weeks('0,61'),/超出范围/);
});
test('新正方 JSON 对离散节次和周次不填补缺课',()=>{
 const r=parse(JSON.stringify({kbList:[{kcmc:'体育',xm:'李老师',cdmc:'操场',xqj:'5',jcs:'1-2,5-6',zcd:'2,4,8-10'}]}));
 assert.deepEqual(r.courses[0].sections,[1,2,5,6]);assert.deepEqual(r.courses[0].weeks,[2,4,8,9,10]);
});
test('新正方 HTML 从节周文本提取正确安排',()=>{
 const r=parse('<table id="table1"><tr><th>节次</th><th>星期一</th></tr><tr><td class="festival">3</td><td id="1-3"><div><span class="title">数据结构</span><p><span title="教师">赵老师</span></p><p><span title="上课地点">C301</span></p><p><span title="节/周">(3-4节)1-8周(双)</span></p></div></td></tr></table>');
 assert.equal(r.courses[0].name,'数据结构');assert.deepEqual(r.courses[0].weeks,[2,4,6,8]);assert.deepEqual(r.courses[0].sections,[3,4]);
});
test('新 URP 位图第一位是第一周',()=>{
 const r=parse(JSON.stringify({dateList:[{selectCourseList:[{courseName:'大学物理',attendClassTeacher:'刘老师',timeAndPlaceList:[{classWeek:'101001',classDay:2,classSessions:5,continuingSession:2,campusName:'主校区',classroomName:'D201'}]}]}]}));
 assert.deepEqual(r.courses[0].weeks,[1,3,6]);assert.deepEqual(r.courses[0].sections,[5,6]);
});
test('URP 明细表 rowspan 后续安排继承课名教师',()=>{
 const r=parse('<table><thead><tr>'+['课程名','教师','周次','星期','节次','节数','教室'].map(x=>'<th>'+x+'</th>').join('')+'</tr></thead><tbody><tr><td rowspan="2">数据库</td><td rowspan="2">陈老师</td><td>1-4</td><td>一</td><td>1</td><td>2</td><td>A102</td></tr><tr><td>5-8</td><td>三</td><td>3</td><td>2</td><td>B202</td></tr></tbody></table>');
 assert.equal(r.courses.length,2);assert.equal(r.courses[1].name,'数据库');assert.equal(r.courses[1].day,3);assert.deepEqual(r.courses[1].sections,[3,4]);
});
test('CSV 引号允许逗号周次和课程名',()=>{
 const r=parse('课程名称,教师,教室,星期,节次,周次\r\n"英语,口语",张老师,A101,周四,3-4,"1,3,5-6"');
 assert.equal(r.courses[0].name,'英语,口语');assert.deepEqual(r.courses[0].weeks,[1,3,5,6]);
});
test('重复导入来源记录去重，但同名异时课程保留',()=>{
 const c={name:'数学',day:1,sections:[1,2],weeks:[1,2]};const r=parse(JSON.stringify({courses:[c,c,{...c,day:3}]}));assert.equal(r.courses.length,2);
});
test('部分错误安排给出警告而不掩盖遗漏',()=>{
 const r=parse(JSON.stringify({courses:[{name:'有效',day:1,sections:[1],weeks:[1]},{name:'不完整',day:2,sections:[2]}]}));assert.equal(r.warnings.length,1);assert.equal(r.warnings[0].name,'不完整');
});
test('登录页与空 JSON 不应误报导入成功',()=>{
 assert.throws(()=>parse('<html><form><input type="password"></form></html>'),/未识别/);assert.throws(()=>parse('{"kbList":[]}'),/未得到有效课程/);
});
test('ICS 使用 UTC 表达北京时间，并拆分不连续节次',()=>{
 const c=C.normalize({name:'数学',day:1,sections:[1,3],weeks:[1]});
 const ics=C.toICS([c],{id:'test',startDate:'2026-09-07',times:[['08:00','08:45'],['08:55','09:40'],['10:00','10:45']]});
 assert.match(ics,/DTSTART:20260907T000000Z/);assert.match(ics,/DTSTART:20260907T020000Z/);assert.equal((ics.match(/BEGIN:VEVENT/g)||[]).length,2);
});
test('ICS 转义与 UTF-8 行折叠符合日历文件要求',()=>{
 const c=C.normalize({name:'课程;'+('数'.repeat(50)),room:'A,101',day:1,sections:[1],weeks:[1]});
 const ics=C.toICS([c],{id:'test',startDate:'2026-09-07',times:[['08:00','08:45']]});
 assert.match(ics,/LOCATION:A\\,101/);assert.ok(ics.split('\r\n').every(line=>Buffer.byteLength(line,'utf8')<=75));
});
test('金智 HTML 保留分段单双周而不猜测缺失星期',()=>{
 const r=parse('<div class="wut_table"><div class="mtt_arrange_item"><div class="mtt_item_kcmc">数据库原理</div><div class="mtt_item_jxbmc">教学班 01</div><div class="mtt_item_room">1-6周(单),8-12周(双),星期三,3-4节,A101</div></div></div>');
 assert.equal(r.courses[0].name,'数据库原理');assert.equal(r.courses[0].day,3);assert.deepEqual(r.courses[0].weeks,[1,3,5,8,10,12]);assert.equal(r.courses[0].room,'A101');
 assert.throws(()=>parse('<div class="wut_table"><div class="mtt_arrange_item"><div class="mtt_item_kcmc">缺信息</div><div class="mtt_item_room">1-6周,A101</div></div></div>'),/未得到有效课程/);
});
test('树维 TaskActivity 周次位图有第零周占位，节次星期从零开始',()=>{
 const r=parse('<html><script>var teachers=[{"name":"张老师"}]; activity = new TaskActivity("t","数学(实验)","r","A101","0101010"); index = 0*unitCount+0; index = 0*unitCount+1; activity = new TaskActivity("t","英语","r","B202","0010001"); index = 6*unitCount+4;</script></html>');
 assert.equal(r.courses.length,2);assert.deepEqual(r.courses[0].weeks,[1,3,5]);assert.deepEqual(r.courses[0].sections,[1,2]);assert.equal(r.courses[0].teacher,'张老师');assert.equal(r.courses[0].name,'数学(实验)');assert.equal(r.courses[1].day,7);assert.deepEqual(r.courses[1].weeks,[2,6]);assert.equal(r.courses[1].teacher,'');
});
test('树维解析单引号字符串但不执行远程脚本',()=>{
 global.__campusUnsafe=false;
 const r=parse('<script>global.__campusUnsafe=true; activity = new TaskActivity(\'t\',\'程序设计\',\'r\',\'C\\u0033\\x30\\x31\',\'011\'); index=2*unitCount+2;</script>');
 assert.equal(global.__campusUnsafe,false);assert.equal(r.courses[0].room,'C301');assert.equal(r.courses[0].day,3);
 assert.throws(()=>parse('<script>activity = new TaskActivity("t","错误位图","r","教室","100"); index=0*unitCount+0;</script>'),/未得到有效课程/);
});
test('东北大学金智 JSON 展开每条周次地点详情',()=>{
 const r=parse(JSON.stringify({datas:{arrangedList:[{courseName:'大学英语',dayOfWeek:4,beginSection:3,endSection:4,weeksAndTeachers:'1-16周/张老师[主讲]',titleDetail:['摘要','1-6周(单) 南湖校区 A101','8-12周(双) 浑南校区 B202']} ]}}));
 assert.equal(r.courses.length,2);assert.deepEqual(r.courses[0].weeks,[1,3,5]);assert.equal(r.courses[0].room,'南湖校区 A101');assert.equal(r.courses[1].room,'浑南校区 B202');assert.equal(r.courses[0].teacher,'张老师');
});

test('普通周课表不依赖表格 ID，保留跨行课节和同格分段课程',()=>{
 const headers='<tr><th>节次</th>'+['日','一','二','三','四','五','六'].map(x=>'<th>星期'+x+'</th>').join('')+'</tr>';
 const html='<table>'+headers+'<tr><td>1-2节</td><td></td><td rowspan="2"><div class="course-item">课程名称：矩阵论<br>教师：张老师<br>教室：A301<br>1-6周(单)</div><div class="course-item">课程名称：矩阵论<br>教师：张老师<br>教室：B302<br>8-12周(双)</div></td><td></td><td></td><td></td><td></td><td></td></tr><tr><td>3-4节</td><td></td><td></td><td></td><td></td><td></td><td></td></tr></table>';
 const r=parse(html);assert.equal(r.courses.length,2);
 assert.deepEqual(r.courses[0],{name:'矩阵论',teacher:'张老师',room:'A301',day:1,sections:[1,2,3,4],weeks:[1,3,5],note:''});
 assert.deepEqual(r.courses[1].weeks,[8,10,12]);assert.equal(r.courses[1].room,'B302');
 assert.deepEqual(r.warnings,[]);
});

test('完整学期拆成多张明细表时全部读取，不止返回第一张',()=>{
 const table=(name,day,week)=>'<table><tr><th>课程名称</th><th>星期</th><th>节次</th><th>周次</th></tr><tr><td>'+name+'</td><td>'+day+'</td><td>3,5</td><td>'+week+'</td></tr></table>';
 const r=parse(table('思政课','星期二','1-16周')+table('矩阵论','星期四','17-21周'));
 assert.equal(r.courses.length,2);assert.equal(r.courses[1].name,'矩阵论');assert.deepEqual(r.courses[1].sections,[3,5]);assert.deepEqual(r.courses[1].weeks,[17,18,19,20,21]);
});

test('普通周课表缺少明确周次不得补成整学期',()=>{
 assert.throws(()=>parse('<table><tr><th>节次</th><th>星期四</th></tr><tr><td>3-4节</td><td>矩阵论<br>教师：示例教师</td></tr></table>'),/缺少明确周次/);
});

test('常见教务 JSON 包装与明确字段别名可以读取，不推测未知周次',()=>{
 const row={kcmc:'数据库',xqj:2,jcs:'3,5',zcd:'17-21周',jsxm:'示例教师',jsmc:'A301'};
 const r=parse(JSON.stringify({data:{rows:[row]}}));
 assert.deepEqual(r.courses[0],{name:'数据库',day:2,sections:[3,5],weeks:[17,18,19,20,21],teacher:'示例教师',room:'A301',note:''});
 delete row.zcd;assert.throws(()=>parse(JSON.stringify({data:{rows:[row]}})),/周次/);
});

test('嵌套课表容器保留各课程叶节点，不将两门课并成一门',()=>{
 const r=parse('<table><tr><th>节次</th><th>星期一</th></tr><tr><td>1-2节</td><td><div class="kbcontent"><div class="course-item">数学<br>1-4周</div><div class="course-item">英语<br>5-8周</div></div></td></tr></table>');
 assert.deepEqual(r.courses.map(c=>[c.name,c.weeks]),[['数学',[1,2,3,4]],['英语',[5,6,7,8]]]);
});

test('课程内部标签排版换行不是两门课程的边界',()=>{
 const r=parse('<table><tr><th>节次</th><th>星期一</th></tr><tr><td>1-2节</td><td><div class="course-item"><div>数学</div>\n<div>教师：王老师</div>\n<div>1-16周</div></div></td></tr></table>');
 assert.equal(r.courses.length,1);assert.equal(r.courses[0].teacher,'王老师');assert.equal(r.courses[0].weeks.length,16);assert.deepEqual(r.warnings,[]);
});

test('课程节点内部段落加 br 或文本换行都不能拆散同一门课',()=>{
 for(const body of ['<p>数学<br></p><p>1-16周<br></p>','数学\n<br>1-16周','数学<br><br>1-16周']){
   const r=parse('<table><tr><th>节次</th><th>星期一</th></tr><tr><td>1-2节</td><td><div class="course-item">'+body+'</div></td></tr></table>');
   assert.equal(r.courses.length,1);assert.equal(r.courses[0].name,'数学');assert.equal(r.courses[0].weeks.length,16);
 }
});

test('同一抓取包含普通周表和明细表时汇总两种布局，不丢另一张课表',()=>{
 const weekly='<table><tr><th>节次</th><th>星期一</th></tr><tr><td>1-2节</td><td>数学<br>1-4周</td></tr></table>';
 const list='<table><tr><th>课程名称</th><th>星期</th><th>节次</th><th>周次</th></tr><tr><td>英语</td><td>星期四</td><td>3-4</td><td>17-21周</td></tr></table>';
 const r=parse(weekly+list);assert.equal(r.courses.length,2);assert.deepEqual(new Set(r.courses.map(c=>c.name)),new Set(['数学','英语']));
});
