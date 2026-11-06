const {test}=require('node:test');const assert=require('node:assert/strict');const {JSDOM}=require('jsdom');
const {parseImport,parseCapture}=require('../src/main/assets/jwimport/parser.js');const DOMParser=new JSDOM('').window.DOMParser;
const course={name:'示例',day:2,sections:[1,2],weeks:[1,2]};
test('已加载JSON学校作息与同页时间轴合并，冲突不猜',()=>{
 const json={courses:[course],periodTimes:{1:{start:'8:00',end:'8:45'}}};
 const html='<table><tr><td>第2节</td><td>08:55-09:40</td></tr></table>';
 assert.deepEqual(parseCapture({json,html},{DOMParser}).periodTimes,{'1':{start:'08:00',end:'08:45'},'2':{start:'08:55',end:'09:40'}});
 const conflict='<p data-period-index="1" data-start-time="08:10" data-end-time="08:55"></p>';
 assert.deepEqual(parseCapture({json,html:conflict},{DOMParser}).periodTimes,{});
});
test('JSON明确sectionTimes和跨午休支持，不从课程总时长平分节次',()=>{
 assert.deepEqual(parseImport(JSON.stringify({courses:[course],data:{sectionTimes:[{section:1,startTime:'08:00',endTime:'08:45'},{section:5,startTime:'14:00',endTime:'14:45'}]}})).periodTimes,{'1':{start:'08:00',end:'08:45'},'5':{start:'14:00',end:'14:45'}});
 assert.deepEqual(parseImport(JSON.stringify({courses:[{...course,startTime:'08:00',endTime:'09:40'}]})).periodTimes,{});
});
test('已加载作息不把课程单元格两次时间当成节次',()=>{
 const html='<div data-course-name="示例" data-day="2" data-sections="1-2" data-weeks="1-16"></div><table><tr><td>1</td><td>实验08:00-09:40</td></tr></table>';
 assert.deepEqual(parseImport(html,{DOMParser}).periodTimes,{});
});
