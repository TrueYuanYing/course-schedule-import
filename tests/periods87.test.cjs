const {test}=require('node:test');const assert=require('node:assert/strict');const {JSDOM}=require('jsdom');
const {parseImport}=require('../src/main/assets/jwimport/parser.js');const DOMParser=new JSDOM('').window.DOMParser;
const {parseCapture}=require('../src/main/assets/jwimport/parser.js');
const course='<div data-course-name="示例" data-day="2" data-sections="1-2" data-weeks="1-16"></div>';
test('只读取明确节次起止时间，缺失作息不猜测',()=>{
 const page=course+'<table><tr><td>第1节</td><td>8:00 - 8:45</td></tr><tr><td>第2节</td><td>08:55</td><td>09:40</td></tr></table>';
 assert.deepEqual(parseImport(page,{DOMParser}).periodTimes,{'1':{start:'08:00',end:'08:45'},'2':{start:'08:55',end:'09:40'}});
 assert.deepEqual(parseImport(course,{DOMParser}).periodTimes,{});
});
test('JSON优先仍保留同页明确作息，不把下午相对节次当绝对序号',()=>{
 const html=course+'<table><tr><td>第1节</td><td>08:00-08:45</td></tr><tr><td>下午1</td><td>14:00-14:45</td></tr></table>';
 const json={courses:[{name:'示例',day:2,sections:[1,2],weeks:[1,2]}]};
 assert.deepEqual(parseCapture({json,html},{DOMParser}).periodTimes,{'1':{start:'08:00',end:'08:45'}});
 const hidden='<div hidden><p data-period-index="1" data-start-time="06:00" data-end-time="06:45"></p></div>';
 assert.deepEqual(parseImport(course+hidden,{DOMParser}).periodTimes,{});
 assert.deepEqual(parseImport(course+hidden.replace(' hidden',' style="visibility:hidden"'),{DOMParser}).periodTimes,{});
});
test('明确属性作息可读，冲突时间和非时间不冒充学校作息',()=>{
 const attributes='<p data-period-index="3" data-start-time="10:00" data-end-time="10:45"></p>';
 assert.deepEqual(parseImport(course+attributes,{DOMParser}).periodTimes,{'3':{start:'10:00',end:'10:45'}});
 assert.deepEqual(parseImport(course+attributes+attributes.replace('10:00','10:15'),{DOMParser}).periodTimes,{});
 assert.deepEqual(parseImport(course+'<table><tr><td>第1节</td><td>25:00 - 26:00</td></tr></table>',{DOMParser}).periodTimes,{});
});
