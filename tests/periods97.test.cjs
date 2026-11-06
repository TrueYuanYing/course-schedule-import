const {test}=require('node:test');
const assert=require('node:assert/strict');
const {JSDOM}=require('jsdom');
const {parseImport,parseCapture}=require('../src/main/assets/jwimport/parser.js');
const DOMParser=new JSDOM('').window.DOMParser;
const course='<div data-course-name="数学" data-day="2" data-sections="1-2" data-weeks="1-16"></div>';

test('数字节次、多行和中文冒号的明确时间随课程导入',()=>{
 const html=course+'<table><tr><td>节次</td><td>时间</td></tr><tr><td>1<br>８：００<br>８：４５</td></tr><tr><td>2</td><td>08:55～09:40</td></tr></table>';
 assert.deepEqual(parseImport(html,{DOMParser}).periodTimes,{'1':{start:'08:00',end:'08:45'},'2':{start:'08:55',end:'09:40'}});
});

test('时间轴同行有课程名称时仍保存已明确的学校作息',()=>{
 for(const row of ['<td>第1节<br>08:00-08:45</td><td>数学</td>','<td>第1节</td><td>08:00-08:45</td><td>数学</td>'])
  assert.deepEqual(parseImport(course+'<table><tr>'+row+'</tr></table>',{DOMParser}).periodTimes,{'1':{start:'08:00',end:'08:45'}});
});

test('无编号纯时间行不应中断导入或冒充节次',()=>{assert.deepEqual(parseImport(course+'<table><tr><td>08:00-08:45</td><td>示例</td></tr></table>',{DOMParser}).periodTimes,{});});

test('分列换行和HTML空格实体仍完整读取两个时间',()=>{
 for(const row of ['<td>1</td><td>08:00<br>08:45</td><td>数学</td>','<td>第1节&nbsp;08:00-08:45</td><td>数学</td>'])
  assert.deepEqual(parseImport(course+'<table><tr>'+row+'</tr></table>',{DOMParser}).periodTimes,{'1':{start:'08:00',end:'08:45'}});
});
