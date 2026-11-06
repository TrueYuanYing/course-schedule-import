const {JSDOM}=require('jsdom');
const {parseImport}=require('../src/main/assets/jwimport/parser.js');
const DOMParser=new JSDOM('').window.DOMParser;
const html='<div data-course-name="合成数学" data-day="2" data-sections="1-2" data-weeks="1-16"></div><table><tr><td>1</td><td>08:00-08:45</td></tr></table>';
const result=parseImport(html,{DOMParser});
console.log(JSON.stringify(result,null,2));
if(!result.courses?.length) throw new Error('synthetic_course_not_parsed');
