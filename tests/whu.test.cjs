const {test}=require('node:test');
const assert=require('node:assert/strict');
const {JSDOM}=require('jsdom');
const C=require('../src/main/assets/jwimport/parser.js');
const DOMParser=new JSDOM('').window.DOMParser;
const parse=html=>C.parseImport(html,{DOMParser});
const cell=(period,day,w,name='课程甲',span=1)=>`<td jc="${period}" xq="${day}" rowspan="${span}"><div class="arrage"><div>${w}</div><div>${name}</div><div>教师</div><div>A101</div></div></td>`;

test('武大研究生按 xq 原值确定星期，逐节重复不会丢失周次或课节',()=>{
  const html='<table class="mtt_table1"><tr><th>星期日</th><th>星期一</th><th>星期二</th></tr><tr>'+cell(3,2,'1-3周')+cell(4,2,'1-3周')+cell(5,2,'1-2周')+cell(7,4,'1-16周','课程乙',3)+'</tr></table>';
  const r=parse(html);
  assert.equal(r.adapter,'武汉大学研究生 HTML');
  assert.deepEqual(r.courses.map(c=>[c.name,c.day,c.sections,c.weeks]),[
    ['课程甲',2,[3,4,5],[1,2]],['课程甲',2,[3,4],[3]],
    ['课程乙',4,[7,8,9],Array.from({length:16},(_,i)=>i+1)]
  ]);
  assert.deepEqual(r.warnings,[]);
});

test('武大研究生缺失周次、非法星期和超出节次不能被当成成功课程',()=>{
  for(const html of [cell(3,2,'待定'),cell(3,0,'1-8周'),cell(24,2,'1-8周','课程甲',2)]){
    assert.throws(()=>parse('<table class="mtt_table1"><tr>'+html+'</tr></table>'),/未得到有效课程/);
  }
});

test('武大研究生离散周次和节次保留空档，重复 frame 不重复导入',()=>{
  const html='<table class="mtt_table1"><tr>'+cell(3,2,'1,3,5周')+cell(5,2,'1,3,5周')+'</tr></table>';
  const r=parse(html+html);
  assert.equal(r.courses.length,1);
  assert.deepEqual(r.courses[0].sections,[3,5]);
  assert.deepEqual(r.courses[0].weeks,[1,3,5]);
});

test('武大研究生同格多课分别保留',()=>{
  const block=w=>`<div class="arrage"><div>${w}</div><div>课程甲</div><div>教师</div><div>A101</div></div>`;
  const r=parse('<table class="mtt_table1"><tr><td jc="3" xq="2">'+block('1周')+block('3周')+'</td></tr></table>');
  assert.deepEqual(r.courses[0].weeks,[1,3]);
});
