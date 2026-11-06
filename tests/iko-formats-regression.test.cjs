const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {JSDOM}=require('jsdom');
const parser=require('../src/main/assets/jwimport/parser.js');

test('增强导入研究生明细表支持上课周次和地点，不丢元旦后课程',()=>{
 const dom=new JSDOM('');
 const source='<table><tr><th>课程名称</th><th>星期</th><th>节次</th><th>上课周次</th><th>授课教师</th><th>上课地点</th></tr><tr><td>矩阵论</td><td>星期四</td><td>3,5</td><td>17-21周</td><td>示例教师</td><td>A301</td></tr></table>';
 const result=parser.parseImport(source,{DOMParser:dom.window.DOMParser});
 assert.deepEqual(result.courses[0].weeks,[17,18,19,20,21]);
 assert.deepEqual(result.courses[0].sections,[3,5]);assert.equal(result.courses[0].day,4);assert.equal(result.courses[0].room,'A301');
 dom.window.close();
});

test('增强导入现代activities明确映射，不把缺周次数据当完整课表',()=>{
 const row={courseName:'大学英语',weekday:4,startUnit:7,endUnit:8,weekIndexes:[2,4,6],teacherNames:['示例教师'],roomName:'C402'};
 const result=parser.parseImport(JSON.stringify({activities:[row]}));
 assert.deepEqual(result.courses[0].weeks,[2,4,6]);assert.equal(result.courses[0].room,'C402');
 delete row.weekIndexes;assert.throws(()=>parser.parseImport(JSON.stringify({activities:[row]})),/未得到有效课程/);
 assert.throws(()=>parser.normalize({name:'复合安排',day:'星期二、星期四',sections:[1,2],weeks:[1]}),/星期/);
});

test('增强采集读取页面已有activities，无需密码或额外猜测请求',async()=>{
 const dom=new JSDOM('<p>课表</p>',{url:'https://example.edu.cn/course-table',runScripts:'outside-only'});
 dom.window.activities=[{courseName:'大学英语',weekday:4,startUnit:7,endUnit:8,weekIndexes:[2,4]}];
 let calls=0;dom.window.fetch=()=>{calls++;throw new Error('unexpected request')};
 dom.window.eval(fs.readFileSync(path.join(__dirname,'../src/main/assets/jwimport/provider.js'),'utf8'));
 for(let i=0;i<50&&!dom.window.__campusCapture.done;i++)await new Promise(r=>setTimeout(r,5));
 assert.equal(dom.window.__campusCapture.json.activities[0].courseName,'大学英语');assert.equal(calls,0);dom.window.close();
});
