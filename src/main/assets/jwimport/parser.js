(function(root,factory){if(typeof module==='object'&&module.exports)module.exports=factory();else root.CourseImport=factory();})(typeof globalThis!=='undefined'?globalThis:this,function(){
  'use strict';
  const DAYS={'一':1,'二':2,'三':3,'四':4,'五':5,'六':6,'日':7,'天':7};
  const incomplete=message=>Object.assign(new Error(message),{code:'INCOMPLETE_TIMETABLE'});
  const text=e=>e?e.textContent.replace(/\s+/g,' ').trim():'';
  const clean=s=>String(s??'').replace(/[０-９]/g,c=>String(c.charCodeAt(0)-65296)).replace(/[，、；;]/g,',').replace(/[～~—–至]/g,'-').replace(/[（]/g,'(').replace(/[）]/g,')').trim();
  function range(s,max,label){
    s=clean(s).replace(/\s/g,'');
    if(!/^\d+(?:-\d+)?(?:,\d+(?:-\d+)?)*$/.test(s))throw new Error(label+'格式无法识别：'+s);
    const result=[];
    for(const p of s.split(',')){
      const [a,b=a]=p.split('-').map(Number);
      if(a<1||b<a||b>max)throw new Error(label+'超出范围：'+p);
      for(let n=a;n<=b;n++)result.push(n);
    }
    return [...new Set(result)].sort((a,b)=>a-b);
  }
  function weeks(value){
    if(Array.isArray(value))return integerList(value,60,'周次');
    let s=clean(value).replace(/第/g,'').replace(/周次[:：]?/g,'').replace(/\s/g,'');
    if(!s)throw new Error('缺少周次');
    // Strip section annotations before parsing the week expression.
    s=s.replace(/\[[^\]]*节[^\]]*\]|\([^)]*节[^)]*\)/g,'');
    const result=[];
    for(let p of s.split(',')){
      const parity=/单/.test(p)?1:/双/.test(p)?0:null;
      p=p.replace(/\(?(?:单|双)(?:周)?\)?/g,'').replace(/[{}\[\]()周]/g,'');
      const list=range(p,60,'周次');
      result.push(...list.filter(n=>parity===null||n%2===parity));
    }
    if(!result.length)throw new Error('没有可用周次');
    return [...new Set(result)].sort((a,b)=>a-b);
  }
  function integerList(v,max,label){
    if(!Array.isArray(v)||!v.length||v.some(x=>!Number.isInteger(x)||x<1||x>max))throw new Error(label+'列表无效');
    return [...new Set(v)].sort((a,b)=>a-b);
  }
  function sections(v){return Array.isArray(v)?integerList(v,30,'节次'):range(clean(v).replace(/第|节|\[|\]|\(|\)/g,''),30,'节次');}
  function day(v){
    const s=clean(v);if(/^[1-7]$/.test(s))return +s;
    const m=s.match(/^(?:星期|周|礼拜)([一二三四五六日天1-7])$/);if(m)return DAYS[m[1]]||+m[1];
    if(DAYS[s])return DAYS[s];throw new Error('星期无法识别：'+s);
  }
  function normalize(c){
    const name=String(c.name??'').trim();if(!name||name.length>200)throw new Error('课程名无效');
    return {name,teacher:String(c.teacher??'').slice(0,200),room:String(c.room??'').slice(0,200),day:day(c.day),
      sections:sections(c.sections),weeks:weeks(c.weeks),note:String(c.note??'').slice(0,1000)};
  }
  function hiddenCell(cell){
    if(cell.hidden)return true;
    if(cell.style.display)return cell.style.display==='none';
    const raw=cell.getAttribute('style');if(!raw)return false;
    // CSP can disable inline style in DOMParser. Ask the native CSS parser on
    // a detached declaration, preserving order/!important without rendering it.
    const declaration=cell.ownerDocument.createElement('span').style;
    declaration.cssText=raw;
    return declaration.display==='none';
  }
  function grid(table){
    const rows=[...table.rows], result=[];
    for(let r=0;r<rows.length;r++){
      result[r]??=[];let col=0;
      for(const cell of rows[r].cells){
        if(hiddenCell(cell))continue;
        while(result[r][col])col++;
        const rs=Math.max(1,Math.min(100,Number(cell.rowSpan)||1)),cs=Math.max(1,Math.min(20,Number(cell.colSpan)||1));
        for(let i=0;i<rs;i++)for(let j=0;j<cs;j++){result[r+i]??=[];result[r+i][col+j]=cell;}
        col+=cs;
      }
    }
    return result;
  }
  function columnDays(rows){
    for(const row of rows.slice(0,256)){
      const map=new Map();
      row.forEach((cell,col)=>{
        const s=clean(text(cell)).replace(/\s+/g,'');
        const m=s.match(/^((?:星期|周|礼拜)[一二三四五六日天1-7])(?:[\[(]?(?:Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)[\])]?)?$/i);
        if(m)map.set(col,day(m[1]));
      });
      if(map.size)return map;
    }
    return new Map();
  }
  function sectionFromRow(row,dayMap){
    const labels=row.slice(0,Math.min(...dayMap.keys())).map(text);
    for(const s of labels){
      const m=clean(s).match(/(?:第)?(\d+(?:[-,]\d+)*)\s*节/);if(m)return sections(m[1]);
      if(/^\d+$/.test(s))return sections(s);
      if(/^[Ff]\d{1,2}$/.test(s))return sections(s.slice(1));
      const period=clean(s).match(/^(?:上午|下午|晚上)\s*(\d{1,2})$/);
      if(period)return sections(period[1]);
    }
    return null;
  }
  // Decode string literals only; never evaluate scripts supplied by a university page.
  function jsString(token){
    const body=token.slice(1,-1);
    return body.replace(/\\(?:u[0-9a-fA-F]{4}|x[0-9a-fA-F]{2}|\r?\n|.)/g,s=>{
      const c=s.slice(1);if(c[0]==='u'||c[0]==='x')return String.fromCharCode(parseInt(c.slice(1),16));
      return ({n:'\n',r:'\r',t:'\t',b:'\b',f:'\f',v:'\v','0':'\0','\n':'','\r\n':''})[c]??c;
    });
  }
  function activityArguments(source,start){
    const args=[];let begin=start,depth=1,quote='',escaped=false;
    for(let i=start;i<Math.min(source.length,start+65536);i++){
      const c=source[i];
      if(quote){if(escaped)escaped=false;else if(c==='\\')escaped=true;else if(c===quote)quote='';continue;}
      if(c==='"'||c==="'"){quote=c;continue;}
      if(c==='('||c==='['||c==='{')depth++;
      else if(c===')'||c===']'||c==='}'){
        if(--depth===0){args.push(source.slice(begin,i).trim());return {args,end:i+1};}
      }else if(c===','&&depth===1){args.push(source.slice(begin,i).trim());begin=i+1;}
    }
    throw new Error('树维课程参数未完整加载');
  }
  const activityLiteral=token=>/^(?:"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')$/.test(token||'')?jsString(token):null;
  function parseSupwisdom(doc,emit,warn){
    let recognized=false;
    for(const script of doc.querySelectorAll('script')){
      const source=script.textContent;if(!/new\s+TaskActivity\s*\(/.test(source))continue;recognized=true;
      const events=/var\s+teachers\s*=\s*(\[[^;]*\])\s*;|new\s+TaskActivity(\s*\()|index\s*=\s*(\d+)\s*\*\s*unitCount\s*\+\s*(\d+)/g;
      let activity=null,teacher='',match;
      const flush=()=>{if(activity)try{emit(activity);}catch(e){warn(activity.name,e.message);}activity=null;};
      while((match=events.exec(source))){
        if(match[1]){try{teacher=JSON.parse(match[1]).map(x=>String(x.name||'')).filter(Boolean).join(', ');}catch(e){teacher=[...match[1].matchAll(/(?:^|[,\s{])(?:name|"name"|'name')\s*:\s*("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')/g)].map(m=>jsString(m[1])).join(', ');}continue;}
        if(match[2]!==undefined){
          flush();let parsed;
          try{parsed=activityArguments(source,events.lastIndex);}catch(e){warn('',e.message);continue;}
          events.lastIndex=parsed.end;
          const fields=parsed.args.map(activityLiteral),offset=fields.length>=7&&/^0[01]{1,60}$/.test(fields[6]||'')?2:0;
          const w=fields[offset+4]||'',name=fields[offset+1];
          if(!name||!/^0[01]{1,60}$/.test(w)){warn(name,'树维位图缺少第零周占位或无效');teacher='';continue;}
          activity={name,teacher:offset===2?(fields[1]||teacher):teacher,room:fields[offset+3]||'',weeks:[...w].flatMap((x,i)=>x==='1'?[i]:[]),sections:[],day:null};teacher='';
        }else if(activity){
          const d=Number(match[3])+1,n=Number(match[4])+1;
          // A single activity can have multiple days; preserve each explicit arrangement.
          if(activity.day!==null&&activity.day!==d){const next={...activity,sections:[],day:d};flush();activity=next;}
          activity.day=d;activity.sections.push(n);
        }
      }
      flush();
    }
    return recognized;
  }
  function nanruanCourses(source,doc,d,slots){
    // These pages draw brackets with CSS pseudo-elements. Preserve the real
    // span boundaries instead of flattening name/weeks/teacher/room together.
    const courses=[],blocks=[...source.querySelectorAll('p')];
    if(blocks.length){
      const remainder=source.cloneNode(true);remainder.querySelectorAll('p').forEach(node=>node.remove());
      if(text(remainder))throw incomplete('课表存在尚未完整识别的课程，请保留当前页面后重试。');
    }
    for(const block of blocks.length?blocks:[source])for(const html of block.innerHTML.split(/<br\s*\/?\s*>/i)){
      const fragment=doc.createElement('div');fragment.innerHTML=html;
      if(!text(fragment))continue;
      const spans=[...fragment.querySelectorAll('span')];
      if(spans.length!==2||!slots.length)throw incomplete('课表部分课程的周次或节次尚未完整加载，请等课表加载完成后再读取。');
      const before=doc.createRange(),between=doc.createRange(),after=doc.createRange();
      before.setStart(fragment,0);before.setEndBefore(spans[0]);
      between.setStartAfter(spans[0]);between.setEndBefore(spans[1]);
      after.setStartAfter(spans[1]);after.setEnd(fragment,fragment.childNodes.length);
      if(text(after.cloneContents()))throw incomplete('课表课程格式尚未完整识别，请保留当前页面后重试。');
      try{courses.push(normalize({name:text(before.cloneContents()),teacher:text(between.cloneContents()),
        room:text(spans[1]),weeks:text(spans[0]),sections:slots,day:d}));}
      catch(e){throw incomplete('课表部分课程的周次或节次无法识别，请保留当前页面后重试。');}
    }
    return courses;
  }
  function parseWeeklyTables(doc,emit,warn,excluded=new Set()){
    let recognized=false;
    for(const table of doc.querySelectorAll('table')){
      if(excluded.has(table))continue;
      const rows=grid(table),days=columnDays(rows),seen=new Set();
      if(!days.size)continue;
      recognized=true;
      rows.forEach((row,r)=>days.forEach((d,col)=>{
        const cell=row[col];if(!cell||seen.has(cell))return;seen.add(cell);
        const content=text(cell);if(!content||/^(星期|周|礼拜)[一二三四五六日天1-7]$/.test(content))return;
        const nodes=[...cell.querySelectorAll('.course-item,.kbcontent,.timetable_con')];
        const sources=nodes.length?nodes.filter(n=>!nodes.some(p=>p!==n&&n.contains(p))):[cell];
        const subjects=[...cell.querySelectorAll('.C_kc_subject,.C_kc_today_subject')];
        const structured=subjects.some(subject=>subject.querySelector('span')&&!/[\[【][^\]】]*周[^\]】]*[\]】]/.test(text(subject)));
        const rowSections=row=>{
          try{return sectionFromRow(row,days);}
          catch(e){if(structured)throw incomplete('课表部分课程的节次无效，请保留当前页面后重试。');throw e;}
        };
        const rowSlots=new Set();
        for(let i=r;i<Math.min(rows.length,r+Math.max(1,cell.rowSpan));i++){
          for(const n of rowSections(rows[i])||[])rowSlots.add(n);
        }
        if(structured){
          const covered=Math.max(1,cell.rowSpan);
          if(r+covered>rows.length||rows.slice(r,r+covered).some(row=>!rowSections(row)))
            throw incomplete('课表部分合并行缺少明确节次，请等完整课表加载后再读取。');
          for(const subject of subjects)for(const course of nanruanCourses(subject,doc,d,[...rowSlots].sort((a,b)=>a-b)))emit(course);
          return;
        }
        if(cell.tagName==='TH'&&!rowSlots.size)return;
        for(const source of sources){
          const clone=source.cloneNode(true);
          clone.querySelectorAll('script,style,input,textarea,select').forEach(n=>n.remove());
          for(const node of clone.querySelectorAll('[title]')){
            const label=node.getAttribute('title')||'';
            if(/^(教师|老师|任课教师|授课教师|教室|地点|上课地点|周次|节次)$/.test(label)&&!/^.*[:：]/.test(node.textContent))node.prepend(label+'：');
          }
          const holder=doc.createElement('div');
          let html=clone.innerHTML.replace(/\r?\n/g,' ').replace(/>\s+</g,'><');
          if(!clone.matches('.course-item,.timetable_con'))html=html.replace(/<br\s*\/?>\s*<br\s*\/?>/ig,'\n---\n');
          holder.innerHTML=html.replace(/<hr\b[^>]*>/ig,'\n---\n').replace(/<br\s*\/?>/ig,'\n').replace(/<\/(?:div|p|li)>/ig,'\n');
          for(const block of holder.textContent.split(/\n\s*[-—]{3,}\s*\n|(?=课程(?:名称|名)?\s*[:：])/)){
            const inline=/([^\[\]【】\n]+?)\s*[\[【]\s*([^\]】]*周[^\]】]*)[\]】]\s*([^\[\]【】\n]*?)\s*[\[【]([^\]】]+)[\]】]/g;
            const records=[...block.matchAll(inline)];
            if(records.length&&block.replace(inline,'').trim()===''){
              for(const record of records)try{emit({name:record[1].trim(),day:d,sections:[...rowSlots].sort((a,b)=>a-b),weeks:record[2],teacher:record[3].trim(),room:record[4].trim()});}catch(e){warn(record[1].trim(),e.message);}
              continue;
            }
            const lines=block.split(/\n/).map(x=>x.trim()).filter(Boolean);if(!lines.length)continue;
            const weekPattern=/(?:第)?\d{1,2}(?:\s*[-~～至—–]\s*\d{1,2})?(?:\s*[,，、]\s*\d{1,2}(?:\s*[-~～至—–]\s*\d{1,2})?)*\s*(?:[（(][单双][）)]\s*)?[（(]?周[）)]?(?:\s*[（(]?[单双]周?[）)]?)?/g;
            const timing=clean(block).match(/(?:第)?(\d+(?:\s*[-,]\s*\d+)*)\s*[\]）)]?节/);
            const name=lines[0].replace(weekPattern,'').replace(/(?:第)?\d+(?:\s*[-,]\s*\d+)*\s*节/g,'').replace(/^课程(?:名称|名)?\s*[:：]/,'').trim();
            if(!name||/^(无课|星期|周次|节次)/.test(name))continue;
            try{
              const ws=block.match(weekPattern);if(!ws)throw new Error('缺少明确周次，请打开完整学期课表');
              const slots=timing?sections(timing[1]):[...rowSlots].sort((a,b)=>a-b);
              const field=re=>lines.find(x=>re.test(x))?.replace(/^.*?[:：]\s*/,'')||'';
              emit({name,day:d,sections:slots,weeks:ws.join(','),teacher:field(/^(?:教师|老师|任课教师|授课教师)\s*[:：]/),room:field(/^(?:教室|地点|上课地点)\s*[:：]/)});
            }catch(e){warn(name,e.message);}
          }
        }
      }));
    }
    return recognized;
  }
  function parseSplitWeeklyTables(doc,emit,warn){
    // Known fixed-header widgets split one logical grid into sibling tables.
    // Pair only inside the same widget, with equal explicit column counts and
    // real section labels. Never stitch unrelated page tables by their order.
    const widgets='.ui-jqgrid,.datagrid-view,.el-table,.ant-table,.k-grid,.bootstrap-table,.dataTables_scroll';
    let recognized=false;
    for(const widget of [...doc.querySelectorAll(widgets)].slice(0,32)){
      const tables=[...widget.querySelectorAll('table')].filter(t=>t.closest(widgets)===widget);
      const headers=tables.filter(t=>columnDays(grid(t)).size);
      if(headers.length!==1)continue;
      const header=headers[0],headerRows=grid(header),days=columnDays(headerRows);
      const width=Math.max(...headerRows.map(row=>row.length));
      const bodies=tables.filter(t=>t!==header).filter(t=>{
        const rows=grid(t);
        return rows.length<=256&&rows.length&&Math.max(...rows.map(row=>row.length))===width
          &&rows.some(row=>sectionFromRow(row,days));
      });
      if(bodies.length!==1)continue;
      const wrapper=widget.closest('.dataTables_wrapper')||widget;
      const pager=wrapper.querySelector('.dataTables_paginate');
      if(pager&&[...pager.querySelectorAll('.paginate_button')].some(button=>
        !button.classList.contains('disabled')&&button.getAttribute('aria-disabled')!=='true'
        &&(/\b(next|previous)\b/.test(button.className)||/^\d+$/.test(text(button))&&Number(text(button))>1))){
        throw incomplete('当前课表是分页数据，请先选择显示全部课程后读取。');
      }
      const temporary=doc.implementation.createHTMLDocument(''),table=temporary.createElement('table');
      for(const source of [header,bodies[0]])for(const row of source.rows)table.append(row.cloneNode(true));
      temporary.body.append(table);
      const courses=[],failures=[];
      if(parseWeeklyTables(temporary,c=>courses.push(normalize(c)),(name,message)=>failures.push(message))){
        if(failures.length)throw incomplete('当前课表未完整读取：'+failures[0]);
        courses.forEach(emit);recognized=true;
      }
    }
    return recognized;
  }
  function parseHtml(doc,mode,emit,warn){
    let used='';const detailTables=new Set();
    if((mode==='auto'||mode==='whu-graduate')&&doc.querySelector('table.mtt_table1 .arrage')){
      const grouped=new Map();
      for(const cell of doc.querySelectorAll('table.mtt_table1 td[jc][xq]')){
        for(const block of cell.querySelectorAll('.arrage')){
          const fields=[...block.children].map(text),name=fields[1]||'';
          try{
            const period=Number(cell.getAttribute('jc')),d=Number(cell.getAttribute('xq')),span=Number(cell.getAttribute('rowspan')||1);
            if(!Number.isInteger(period)||period<1||!Number.isInteger(span)||span<1||period+span-1>24||!Number.isInteger(d)||d<1||d>7)throw new Error('武汉大学课表节次或星期无法识别');
            if(fields.length<4||!name)throw new Error('武汉大学课表课程字段不完整');
            const ws=weeks(fields[0]),key=JSON.stringify([name,d,fields[2],fields[3]]);
            // The table starts with Sunday, but xq remains Monday=1 ... Sunday=7.
            let course=grouped.get(key);
            if(!course){course={name,day:d,teacher:fields[2],room:fields[3],byWeek:new Map()};grouped.set(key,course);}
            for(const w of ws){let slots=course.byWeek.get(w);if(!slots){slots=new Set();course.byWeek.set(w,slots);}for(let n=period;n<period+span;n++)slots.add(n);}
          }catch(e){warn(name,e.message);}
        }
      }
      // Repeated per-period cells are unioned by week, then only equal period sets share a record.
      for(const c of grouped.values()){
        const arrangements=new Map();
        for(const [w,slots] of [...c.byWeek].sort((a,b)=>a[0]-b[0])){
          const ss=[...slots].sort((a,b)=>a-b),key=JSON.stringify(ss);
          let arrangement=arrangements.get(key);if(!arrangement){arrangement={sections:ss,weeks:[]};arrangements.set(key,arrangement);}arrangement.weeks.push(w);
        }
        for(const a of arrangements.values())emit({name:c.name,day:c.day,teacher:c.teacher,room:c.room,...a});
      }
      return '武汉大学研究生 HTML';
    }
    if((mode==='auto'||mode==='supwisdom')&&parseSupwisdom(doc,emit,warn))return '树维 EAMS TaskActivity';
    const jz=doc.querySelector('.wut_table');
    if(jz&&(mode==='auto'||mode==='jz')){
      for(const block of jz.querySelectorAll('.mtt_arrange_item')){
        const name=text(block.querySelector('.mtt_item_kcmc'));
        try{
          const parts=clean(text(block.querySelector('.mtt_item_room'))).split(',').map(x=>x.trim());
          const at=parts.findIndex(x=>/^(星期|周)[一二三四五六日天1-7]$/.test(x));
          if(at<1||at+1>=parts.length)throw new Error('缺少完整星期、节次或周次');
          emit({name,teacher:'',note:text(block.querySelector('.mtt_item_jxbmc')),room:parts.slice(at+2).join(','),day:parts[at],sections:parts[at+1],weeks:parts.slice(0,at).join(',')});
        }catch(e){warn(name,e.message);}
      }
      return '金智 HTML';
    }
    const qz=doc.querySelector('#kbtable');
    if(qz&&(mode==='auto'||mode==='qz')){
      used='强智 HTML';const rows=grid(qz),days=columnDays(rows),seen=new Set();
      if(days.size<5)throw new Error('强智页面缺少完整星期表头');
      rows.forEach(row=>row.forEach((cell,col)=>{
        if(!days.has(col)||seen.has(cell))return;seen.add(cell);
        const blocks=[...cell.querySelectorAll('.kbcontent')];
        for(const el of blocks){
          if(!text(el))continue;
          const parts=el.innerHTML.split(/(?:<br\s*\/?>(?:\s|&nbsp;)*)?-{3,}(?:\s*<br\s*\/?>)?/i);
          for(const html of parts){
            const fragment=doc.createElement('div');fragment.innerHTML=html;
            const wk=fragment.querySelector('[title="周次(节次)"],[title="周次"],[title="周次（节次）"]');
            const w=text(wk);const node=clean(w).match(/\[(\d+(?:[-,]\d+)*)节\]|\((\d+(?:[-,]\d+)*)节\)/);
            const nameHolder=fragment.cloneNode(true);nameHolder.querySelectorAll('font').forEach(e=>e.remove());
            const name=(nameHolder.textContent||'').trim().replace(/^-+|-+$/g,'').trim();
            if(!name)continue;
            try{emit({name,teacher:text(fragment.querySelector('[title="老师"],[title="教师"]')),room:text(fragment.querySelector('[title="教室"]')),
              day:days.get(col),sections:node?(node[1]||node[2]):sectionFromRow(row,days),weeks:w});}catch(e){warn(name,e.message);}
          }
        }
      }));
      return used;
    }
    const zf=doc.querySelector('#table1');
    if(zf&&(mode==='auto'||mode==='zf')){
      used='正方 HTML';const rows=grid(zf),days=columnDays(rows),seen=new Set();
      rows.forEach(row=>row.forEach((cell,col)=>{
        if(seen.has(cell))return;seen.add(cell);
        const explicit=cell.id.match(/^([1-7])[-_]/), d=explicit?+explicit[1]:days.get(col);
        if(!d)return;
        const modern=[...cell.querySelectorAll('.title')];
        if(modern.length){
          for(const title of modern){
            const block=title.parentElement;
            let teacher='',room='',timing='';
            block.querySelectorAll('p').forEach(p=>{
              const key=p.getAttribute('title')||p.querySelector('[title]')?.getAttribute('title')||'';
              if(/教师/.test(key))teacher=text(p);else if(/上课地点|教室/.test(key))room=text(p);else if(/节\/周|周\/节/.test(key))timing=text(p);
            });
            const m=clean(timing).match(/\((\d+(?:[-,]\d+)*)节\)/);
            try{emit({name:text(title),teacher,room,day:d,sections:m?m[1]:sectionFromRow(row,days),weeks:timing});}catch(e){warn(text(title),e.message);}
          }
        }else{
          const parts=cell.innerHTML.split(/<br\s*\/?>\s*<br\s*\/?>/i);
          for(const html of parts){
            const el=doc.createElement('div');el.innerHTML=html.replace(/<br\s*\/?>/ig,'\n');
            const lines=el.textContent.split(/\n/).map(x=>x.trim()).filter(Boolean);
            const times=lines.map((line,index)=>({line,index})).filter(x=>/第.*节.*周|周.*第.*节/.test(x.line));
            for(const {line,index} of times){
              const w=clean(line).match(/\{([^}]*周[^}]*)\}|(\d+(?:[-,]\d+)*周(?:\([单双]\))?)/);
              const n=clean(line).match(/第(\d+(?:[-,]\d+)*)节/);
              try{emit({name:lines[0],teacher:lines[index+1]||'',room:lines[index+2]||'',day:d,sections:n?n[1]:null,weeks:w?(w[1]||w[2]):''});}catch(e){warn(lines[0],e.message);}
            }
          }
        }
      }));return used;
    }
    // URP list pages have explicit course/day/week/session headings and may span rows.
    if(mode==='auto'||mode==='urp')for(const table of doc.querySelectorAll('table')){
      const rows=grid(table);let headers=null,start=-1;
      for(let i=0;i<Math.min(4,rows.length);i++){
        const h=rows[i].map(text);
        if(h.some(x=>/^(课程名|课程名称)$/.test(x))&&h.some(x=>/^(星期|星期几|上课星期)$/.test(x))&&h.some(x=>/^(周次|上课周次)$/.test(x))){headers=h;start=i+1;break;}
      }
      if(!headers)continue;
      detailTables.add(table);
      used='URP 明细表';
      const find=re=>headers.findIndex(x=>re.test(x)),n=find(/^(课程名|课程名称)$/),t=find(/^(教师|任课教师|授课教师)$/),d=find(/^(星期|星期几|上课星期)$/),w=find(/^(周次|上课周次)$/),s=find(/^(节次|上课节次)$/),len=find(/^节数$/),room=find(/^(教室|上课地点|地点)$/),building=find(/^教学楼$/);
      for(const row of rows.slice(start)){
        if(!text(row[d]))continue;
        try{
          let nodes=sections(text(row[s]));
          if(len>=0&&nodes.length===1){const count=Number(text(row[len]));if(!Number.isInteger(count)||count<1||count>30)throw new Error('节数无效');nodes=sections(nodes[0]+'-'+(nodes[0]+count-1));}
          emit({name:text(row[n]),teacher:text(row[t]),room:text(row[building])+text(row[room]),day:text(row[d]),sections:nodes,weeks:text(row[w])});
        }catch(e){warn(text(row[n]),e.message);}
      }
      // A semester may be split into several detail tables. Read all of them.
    }
    const split=(mode==='auto'||mode==='generic')&&parseSplitWeeklyTables(doc,emit,warn);
    const weekly=(mode==='auto'||mode==='generic')&&parseWeeklyTables(doc,emit,warn,detailTables);
    if(used||weekly||split)return [used,(weekly||split)?'通用周课表':''].filter(Boolean).join(' + ');
    throw new Error('未识别到已支持的完整课表。请进入课表查询页，或导出 JSON / HTML / CSV。');
  }
  function parseJson(input,emit,warn){
    if(!input||typeof input!=='object')throw new Error('JSON 应为课表对象或数组');
    if(input.format==='campus-backup'&&Array.isArray(input.tables))throw new Error('BACKUP');
    for(let depth=0;depth<6&&!Array.isArray(input);depth++){
      if(['activities','kbList','dateList','courses'].some(k=>Array.isArray(input[k]))||Array.isArray(input.datas?.arrangedList))break;
      const next=input.rows??input.courseList??input.kcbData??input.data??input.datas;
      if(!next||typeof next!=='object')break;input=next;
    }
    if(Array.isArray(input.activities)){
      for(const c of input.activities)try{
        const start=Number(c.startUnit),end=Number(c.endUnit);
        if(!Number.isInteger(start)||!Number.isInteger(end)||start<1||end<start||end>24)throw new Error('节次无效');
        emit({name:c.courseName,day:c.weekday??c.dayOfWeek,sections:start+'-'+end,weeks:c.weekIndexes,
          teacher:Array.isArray(c.teacherNames)?c.teacherNames.join('、'):'',room:c.roomName||''});
      }catch(e){warn(c.courseName,e.message);}
      return '树维 activities JSON';
    }
    const arranged=input.datas?.arrangedList;
    if(Array.isArray(arranged)){
      for(const c of arranged){
        const teacher=String(c.weeksAndTeachers||'').split('/').slice(1).join('/').replace(/\[主讲\]/g,'').trim();
        const details=Array.isArray(c.titleDetail)?c.titleDetail.filter(x=>typeof x==='string'&&/^\s*\d/.test(x)):[];
        if(!details.length){warn(c.courseName,'金智详情缺少明确周次；未使用汇总字段猜测');continue;}
        for(const detail of details)try{
          const match=clean(detail).match(/^(\d[^\s]*)(?:\s+(.*))?$/);if(!match)throw new Error('无法识别周次详情');
          emit({name:c.courseName,teacher,room:match[2]||'',day:c.dayOfWeek,sections:c.beginSection+'-'+c.endSection,weeks:match[1]});
        }catch(e){warn(c.courseName,e.message);}
      }
      return '金智 homeapp JSON';
    }
    const urp=input.dateList?.flatMap(x=>x.selectCourseList||[]);
    if(urp){
      for(const c of urp)for(const p of c.timeAndPlaceList||[]){
        try{
          if(!/^[01]{1,60}$/.test(p.classWeek||''))throw new Error('URP 周次位图无效');
          const w=[...p.classWeek].flatMap((x,i)=>x==='1'?[i+1]:[]);
          emit({name:c.courseName,teacher:c.attendClassTeacher,room:(p.campusName||'')+(p.teachingBuildingName||'')+(p.classroomName||''),day:p.classDay,
            sections:p.classSessions+'-'+(Number(p.classSessions)+Number(p.continuingSession)-1),weeks:w});
        }catch(e){warn(c.courseName,e.message);}
      }return '新 URP JSON';
    }
    const zf=input.kbList;
    if(Array.isArray(zf)){
      for(const c of zf)try{emit({name:c.kcmc,teacher:c.xm,room:c.cdmc,day:c.xqj,sections:c.jcs,weeks:c.zcd});}catch(e){warn(c.kcmc,e.message);}
      return '新正方 JSON';
    }
    const raw=Array.isArray(input)?input:input.courses;
    if(!Array.isArray(raw))throw new Error('JSON 未包含 courses / kbList / dateList');
    if(raw.length>5000)throw new Error('课程记录过多');
    for(const c of raw)try{
      if(!c||typeof c!=='object')throw new Error('课程必须为对象');
      let nodes=c.sections??c.jcs??c.JC;
      if(nodes==null){
        const start=Number(c.startPeriod??c.startNode??c.startUnit),end=Number(c.endPeriod??c.endUnit??(start+Number(c.step??1)-1));
        if(!Number.isInteger(start)||!Number.isInteger(end))throw new Error('缺少明确节次');
        nodes=start+'-'+end;
      }
      let ws=c.weeks??c.weekIndexes??c.zcd??c.ZC??c.weekText;
      if(ws==null&&c.startWeek!=null&&c.endWeek!=null)ws=c.startWeek+'-'+c.endWeek;
      ws=weeks(ws);
      if(c.weekParity!=null){
        if(c.weekParity!==0&&c.weekParity!==1)throw new Error('单双周值无效');
        ws=ws.filter(w=>w%2===c.weekParity);
      }
      emit({name:c.name??c.courseName??c.kcmc??c.KCM,day:c.day??c.weekday??c.dayOfWeek??c.xqj??c.XQJ,
        sections:nodes,weeks:ws,teacher:c.teacher??c.teacherName??c.xm??c.jsxm??c.JSXM??(Array.isArray(c.teacherNames)?c.teacherNames.join('、'):''),
        room:c.room??c.roomName??c.cdmc??c.jsmc??c.JASMC,note:c.note});
    }catch(e){warn(c?.name??c?.courseName??c?.kcmc,e.message);}
    return '规范化 JSON';
  }
  function csvRows(s){
    const rows=[];let row=[],cell='',quoted=false;
    for(let i=0;i<s.length;i++){
      const c=s[i];
      if(c==='"'){if(quoted&&s[i+1]==='"'){cell+='"';i++;}else quoted=!quoted;}
      else if(c===','&&!quoted){row.push(cell);cell='';}
      else if((c==='\n'||c==='\r')&&!quoted){if(c==='\r'&&s[i+1]==='\n')i++;row.push(cell);rows.push(row);row=[];cell='';}
      else cell+=c;
    }
    if(quoted)throw new Error('CSV 引号未闭合');
    if(cell||row.length){row.push(cell);rows.push(row);}return rows;
  }
  function parseCsv(s,emit,warn){
    const rows=csvRows(s),header=rows.shift()?.map(x=>x.trim())||[];
    const names={name:['name','课程名称','课程名'],teacher:['teacher','教师','老师'],room:['room','教室','地点'],day:['day','星期'],sections:['sections','节次'],weeks:['weeks','周次']};
    const indices=Object.fromEntries(Object.entries(names).map(([k,v])=>[k,header.findIndex(x=>v.includes(x))]));
    if(['name','day','sections','weeks'].some(k=>indices[k]<0))throw new Error('CSV 需要课程名、星期、节次、周次列；可在导入面板下载模板');
    for(const row of rows){if(!row.some(x=>x.trim()))continue;const c={};for(const k of Object.keys(indices))c[k]=indices[k]<0?'':row[indices[k]];try{emit(c);}catch(e){warn(c.name,e.message);}}
    return 'CSV';
  }
  // Trusted, data-only adapters. University HTML is input, never executable code.
  // Add a record/field declaration instead of changing either importer host.
  function adapterDefinitions(pack){
    const invalid=()=>{throw new Error('适配规则配置无效');};
    const object=v=>v&&typeof v==='object'&&!Array.isArray(v)&&Object.getPrototypeOf(v)===Object.prototype;
    const keys=(value,allowed)=>{if(!object(value)||Object.keys(value).some(k=>!allowed.includes(k)))invalid();};
    const path=value=>typeof value==='string'&&value.length<=160&&value.split('.').length<=8&&
      value.split('.').every(k=>/^[A-Za-z_][A-Za-z0-9_]*$/.test(k)&&!['__proto__','prototype','constructor'].includes(k));
    const selector=value=>typeof value==='string'&&value.length>0&&value.length<=200;
    keys(pack,['schemaVersion','revision','adapters']);
    if(pack.schemaVersion!==1||!Number.isSafeInteger(pack.revision)||pack.revision<1||!Array.isArray(pack.adapters)||pack.adapters.length>32)invalid();
    const ids=new Set();
    for(const rule of pack.adapters){
      keys(rule,['id','label','format','records','fields']);
      if(typeof rule.id!=='string'||! /^[a-z][a-z0-9-]{0,63}$/.test(rule.id)||ids.has(rule.id)||
        typeof rule.label!=='string'||!rule.label.trim()||rule.label.length>80||!['json','html'].includes(rule.format))invalid();
      ids.add(rule.id);keys(rule.fields,['name','teacher','room','day','weeks','sections','note']);
      if(['name','day','weeks','sections'].some(k=>!Object.hasOwn(rule.fields,k)))invalid();
      if(rule.format==='json'){
        if(!path(rule.records)||Object.values(rule.fields).some(v=>!path(v)))invalid();
      }else{
        if(!selector(rule.records))invalid();
        for(const field of Object.values(rule.fields)){
          keys(field,['selector','attribute']);
          if(field.selector!==undefined&&!selector(field.selector))invalid();
          if(field.attribute!==undefined&&(typeof field.attribute!=='string'||! /^(?:data-[a-z0-9-]+|title|aria-label)$/.test(field.attribute)))invalid();
        }
      }
    }
    // Capture a detached JSON declaration, never shared mutable configuration.
    return JSON.parse(JSON.stringify(pack)).adapters;
  }
  function atPath(record,path){
    for(const key of path.split('.')){
      if(!record||typeof record!=='object'||!Object.hasOwn(record,key))return undefined;
      record=record[key];
    }
    return record;
  }
  function declaredImport(input,format,rules,emit){
    for(const rule of rules){
      if(rule.format!==format)continue;
      let records;
      try{
        records=format==='json'?atPath(input,rule.records):[...input.querySelectorAll(rule.records)].filter(record=>{
          for(let at=record;at;at=at.parentElement)if(hiddenCell(at))return false;
          return true;
        });
      }
      catch(_){throw new Error('适配规则选择器无效');}
      if(records===undefined||format==='html'&&!records.length)continue;
      if(!Array.isArray(records)&&format==='json'||!records.length||records.length>5000)
        throw incomplete('课表记录尚未完整加载，未导入部分结果。');
      const courses=[];
      for(const record of records){
        const course={};
        try{
          for(const [key,field] of Object.entries(rule.fields)){
            if(format==='json')course[key]=atPath(record,field);
            else{
              const element=field.selector?record.querySelector(field.selector):record;
              course[key]=field.attribute?element?.getAttribute(field.attribute):text(element);
            }
          }
          courses.push(normalize(course));
        }catch(_){throw incomplete('课表部分记录缺少明确的课程、星期、节次或周次，未导入部分结果。');}
      }
      courses.forEach(emit);return rule;
    }
    return null;
  }
  const builtinPack={schemaVersion:1,revision:1,adapters:[{
    id:'course-attributes',label:'结构化课程属性',format:'html',
    records:'[data-course-name]',
    fields:{name:{attribute:'data-course-name'},teacher:{attribute:'data-teacher'},room:{attribute:'data-room'},
      day:{attribute:'data-day'},sections:{attribute:'data-sections'},weeks:{attribute:'data-weeks'}}
  }]};
  const defaultAdapters=adapterDefinitions(builtinPack);
  function createImporter(pack){
    const extra=adapterDefinitions(pack),ids=new Set(extra.map(rule=>rule.id));
    const rules=[...extra,...defaultAdapters.filter(rule=>!ids.has(rule.id))];
    const revision=pack.revision;
    return Object.freeze({
      parseImport:(source,options={})=>({...parseImport(source,options,rules),adapterRevision:revision}),
      parseCapture:(capture,options={})=>({...parseCapture(capture,options,rules),adapterRevision:revision}),
      schemaVersion:pack.schemaVersion,revision:pack.revision
    });
  }
  function mergePeriodTimes(...sources){
    const result={},conflicts=new Set();
    for(const source of sources)for(const [key,value] of Object.entries(source||{})){
      if(result[key]&&(result[key].start!==value.start||result[key].end!==value.end))conflicts.add(key);
      result[key]=value;
    }
    for(const key of conflicts)delete result[key];
    let end='';for(const key of Object.keys(result).map(Number).sort((a,b)=>a-b)){
      if(result[key].start<end)return {};end=result[key].end;
    }
    return result;
  }
  function jsonPeriodTimes(input){
    const maps=[];let visited=0;
    const time=v=>{if(typeof v!=='string')return null;const m=clean(v).replace(/：/g,':').match(/^([01]?\d|2[0-3]):([0-5]\d)$/);return m?m[1].padStart(2,'0')+':'+m[2]:null;};
    const read=(value)=>{
      if(!value||typeof value!=='object')return;
      const result={},conflicts=new Set();
      for(const [key,row] of Object.entries(value).slice(0,96)){
        if(!row||typeof row!=='object')continue;
        const n=Number(Array.isArray(value)?row.index??row.section??row.period: key);
        const start=time(row.start??row.startTime),end=time(row.end??row.endTime);
        if(Number.isInteger(n)&&n>=1&&n<=24&&start&&end&&start<end){
          if(result[n]&&(result[n].start!==start||result[n].end!==end)){conflicts.add(n);continue;}
          result[n]={start,end};
        }
      }
      for(const key of conflicts)delete result[key];
      maps.push(result);
    };
    const walk=(node,depth)=>{
      if(!node||typeof node!=='object'||Array.isArray(node)||depth>4||++visited>16)return;
      for(const key of ['periodTimes','sectionTimes'])read(node[key]);
      for(const key of ['data','datas','result'])walk(node[key],depth+1);
    };
    walk(input,0);return mergePeriodTimes(...maps);
  }
  function periodTimesFrom(doc){
    const result={},conflicts=new Set();
    const visible=node=>{
      for(let at=node;at;at=at.parentElement){
        if(hiddenCell(at))return false;
        const style=at.ownerDocument.createElement('span').style;
        style.cssText=at.getAttribute('style')||'';
        if(['hidden','collapse'].includes(style.visibility))return false;
      }
      return true;
    };
    const add=(key,start,end)=>{
      const valid=v=>typeof v==='string'&&/^(?:[01]\d|2[0-3]):[0-5]\d$/.test(v);
      key=Number(key);if(!Number.isInteger(key)||key<1||key>24||!valid(start)||!valid(end)||start>=end)return;
      if(result[key]&&(result[key].start!==start||result[key].end!==end))conflicts.add(key);
      result[key]={start,end};
    };
    for(const element of doc.querySelectorAll('[data-period-index][data-start-time][data-end-time]'))
      if(visible(element))add(element.getAttribute('data-period-index'),element.getAttribute('data-start-time'),element.getAttribute('data-end-time'));
    const cellWords=cell=>{const clone=cell.cloneNode(true);clone.querySelectorAll('script,style').forEach(node=>node.remove());clone.querySelectorAll('br').forEach(node=>node.replaceWith(doc.createTextNode(' ')));return clean(clone.textContent).replace(/：/g,':');};
    for(const row of [...doc.querySelectorAll('table tr')].slice(0,1000)){
      const cells=[...row.cells];if(cells.length<1||!visible(row))continue;
      const cellText=cellWords(cells[0]);
      const label=cellText.match(/^第\s*(\d{1,2})\s*节(?:\s|$)/)||cellText.match(/^(\d{1,2})(?=\s|$)/);
      if(!label)continue;
      const timeText=v=>v.replace(/[\d\s:：~～—–\-]/g,'')==='';
      if(!/^第/.test(cellText)&&!timeText(cellText))continue;
      if(!visible(cells[0]))continue;
      const timePattern=/(?<!\d)(?:[01]?\d|2[0-3]):[0-5]\d(?!\d)/g;
      let times=cellText.match(timePattern)||[];
      if(times.length<2)for(const cell of cells.slice(1,3)){
        const text=cellWords(cell);
        if(!visible(cell)||!timeText(text))break;
        times.push(...text.match(timePattern)||[]);
        if(times.length>=2)break;
      }
      if(times?.length===2)add(label[1]||label[2],...times.map(value=>value.padStart(5,'0')));
    }
    for(const key of conflicts)delete result[key];
    let end='';for(const key of Object.keys(result).map(Number).sort((a,b)=>a-b)){
      if(result[key].start<end)return {};end=result[key].end;
    }
    return result;
  }
  function parseImport(source,options={},rules=defaultAdapters){
    const courses=[],warnings=[];const emit=c=>courses.push(normalize(c)),warn=(name,message)=>warnings.push({name:name||'未命名',message});
    if(typeof source!=='string'||source.length>4_000_000)throw new Error('输入大小无效');
    const s=source.replace(/^\uFEFF/,'').trim();if(!s)throw new Error('导入内容为空');
    let adapter,declared,periodTimes={};
    if(/^[{[]/.test(s)){
      const input=JSON.parse(s);periodTimes=jsonPeriodTimes(input);declared=declaredImport(input,'json',rules,emit);
      adapter=declared?.label||parseJson(input,emit,warn);
    }
    else if(/<\w|<!doctype/i.test(s)){
      const DOM=options.DOMParser||(typeof DOMParser!=='undefined'?DOMParser:null);
      if(!DOM)throw new Error('HTML 解析环境缺失');
      const doc=new DOM().parseFromString(s,'text/html');
      periodTimes=periodTimesFrom(doc);
      declared=declaredImport(doc,'html',rules,emit);
      adapter=declared?.label||parseHtml(doc,options.mode||'auto',emit,warn);
    }else adapter=parseCsv(s,emit,warn);
    const seen=new Set(),unique=courses.filter(c=>{const k=JSON.stringify(c);if(seen.has(k))return false;seen.add(k);return true;});
    if(!unique.length)throw new Error('未得到有效课程。'+warnings.slice(0,3).map(x=>x.name+'：'+x.message).join('；'));
    return {adapter,courses:unique,warnings,periodTimes,adapterId:declared?.id||'builtin-family',adapterSchemaVersion:1,adapterRevision:1};
  }
  function parseCapture(capture,options={},rules=defaultAdapters){
    if(capture.error)throw new Error(String(capture.error));
    const candidates=[],seen=new Set(),failures=[];
    const add=(value,json)=>{
      if(value==null)return;
      const source=json?JSON.stringify(value):value;
      if(typeof source==='string'&&!seen.has(source)){seen.add(source);candidates.push({source,json});}
    };
    if(capture.jsonSource!=='page')add(capture.json,true);
    add(capture.html,false);
    if(capture.jsonSource==='page')add(capture.json,true);
    for(const value of (Array.isArray(capture.jsonCandidates)?capture.jsonCandidates.slice(0,16):[]))add(value,true);
    let lastError;
    for(const candidate of candidates)try{
      const result=parseImport(candidate.source,options,rules);
      const capturedTimes=jsonPeriodTimes({periodTimes:capture.periodTimes});
      let htmlTimes={};
      if(typeof capture.html==='string'&&capture.html.length<=4_000_000){
        const DOM=options.DOMParser||(typeof DOMParser!=='undefined'?DOMParser:null);
        if(DOM)htmlTimes=periodTimesFrom(new DOM().parseFromString(capture.html,'text/html'));
      }
      result.periodTimes=mergePeriodTimes(result.periodTimes,capturedTimes,htmlTimes);
      result.warnings.push(...[...(Array.isArray(capture.warnings)?capture.warnings:[]),...failures]
        .map(message=>({name:'页面采集',message:String(message)})));
      return result;
    }catch(error){
      if(error.code==='INCOMPLETE_TIMETABLE')throw error;
      lastError=error;failures.push((candidate.json?'JSON 解析失败，尝试其他课表：':'页面解析失败，尝试已加载课表数据：')+error.message);
    }
    throw lastError||new Error('当前页面没有可读取的课表数据');
  }
  function toICS(courses,config){
    const start=new Date(config.startDate+'T00:00:00+08:00');
    if(!Number.isFinite(start.getTime())||start.getUTCDay()!==0)throw new Error('学期起始日必须为周一');
    const esc=s=>String(s||'').replace(/\\/g,'\\\\').replace(/\n/g,'\\n').replace(/,/g,'\\,').replace(/;/g,'\\;');
    const stamp=date=>date.toISOString().replace(/[-:]/g,'').replace(/\.\d{3}/,'');
    const lines=['BEGIN:VCALENDAR','VERSION:2.0','PRODID:-//Campus Schedule//CN','CALSCALE:GREGORIAN'];
    let serial=0;const generated=stamp(new Date());
    for(const c of courses)for(const w of c.weeks){
      const groups=[];for(const n of c.sections){const g=groups[groups.length-1];if(g&&g[g.length-1]+1===n)g.push(n);else groups.push([n]);}
      for(const nodes of groups){
        const first=config.times[nodes[0]-1],last=config.times[nodes[nodes.length-1]-1];if(!first||!last)throw new Error('课程节次缺少作息时间');
        const at=t=>new Date(start.getTime()+((w-1)*7+c.day-1)*86400000+(+t.slice(0,2)*60+(+t.slice(3)))*60000);
        lines.push('BEGIN:VEVENT','UID:'+config.id+'-'+(serial++)+'@campus.local','DTSTAMP:'+generated,'DTSTART:'+stamp(at(first[0])),'DTEND:'+stamp(at(last[1])),
          'SUMMARY:'+esc(c.name),'LOCATION:'+esc(c.room),'DESCRIPTION:'+esc(c.teacher+' '+c.note),'END:VEVENT');
      }
    }
    lines.push('END:VCALENDAR');
    const encoder=new TextEncoder();
    return lines.map(line=>{let result='',size=0;for(const ch of line){const n=encoder.encode(ch).length;if(size+n>75){result+='\r\n ';size=1;}result+=ch;size+=n;}return result;}).join('\r\n')+'\r\n';
  }
  return {parseImport,parseCapture,createImporter,weeks,sections,normalize,toICS};
});
