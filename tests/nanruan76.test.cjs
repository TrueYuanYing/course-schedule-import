const {test}=require('node:test');
const assert=require('node:assert/strict');
const {JSDOM}=require('jsdom');
const parser=require('../src/main/assets/jwimport/parser.js');
test('graduate bilingual F rows preserve periods and distinct teacher/week records',()=>{
 const html='<table><tr><th>节次</th><th>星期一 [Monday]</th><th>星期二 [Tuesday]</th></tr>'+
 '<tr><td>F1</td><td rowspan="2"><div>数值分析10班 [11-18周] 示例甲 [教学楼101]</div></td><td></td></tr><tr><td>F2</td><td></td></tr>'+
 '<tr><td>F3</td><td rowspan="2"><div>矩阵理论11班 [6-8周] 示例乙 [教学楼101]</div><div>矩阵理论11班 [1-5周] 示例丙 [教学楼101]</div></td><td></td></tr><tr><td>F4</td><td></td></tr></table>';
 const result=parser.parseImport(html,{DOMParser:new JSDOM('').window.DOMParser});
 assert.equal(result.courses.length,3,JSON.stringify(result));
 assert.deepEqual(result.courses.map(c=>c.sections),[[1,2],[3,4],[3,4]]);
 assert.deepEqual(result.courses.map(c=>c.teacher),['示例甲','示例乙','示例丙']);
 assert.deepEqual(result.courses.map(c=>c.day),[1,1,1]);
});
