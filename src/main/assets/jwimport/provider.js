(function(){
  'use strict';
  // Runs in the explicitly opened school importer, on request or a visible-table change.
  // No credential inputs are read.
  const capture={done:false,html:'',json:null,jsonSource:null,jsonCandidates:[],warnings:[],frameUrls:[],hasTimetable:false,url:location.href};
  window.__campusCapture=capture;
  const roots=[],seen=new Set(),weeklyTables=[];
  function hidden(element){
    // Follow both shadow hosts and same-origin embedding frames. A hidden old
    // semester must not reappear through the HTML fallback or a page global.
    for(let node=element;node;){
      const win=node.ownerDocument?.defaultView;
      const style=win?.getComputedStyle(node);
      if(node.hidden||style?.display==='none'||['hidden','collapse'].includes(style?.visibility))return true;
      const parent=node.parentElement||node.getRootNode().host;
      if(parent){node=parent;continue;}
      try{node=win?.frameElement;}catch(_){node=null;}
    }
    return false;
  }
  function collect(doc,depth){
    if(depth>5||seen.has(doc)||seen.size>=32)return;seen.add(doc);roots.push(doc);
    for(const node of doc.querySelectorAll('*'))if(node.shadowRoot&&!hidden(node))collect(node.shadowRoot,depth+1);
    for(const frame of doc.querySelectorAll('iframe,frame'))try{
      if(hidden(frame))continue;
      if(frame.contentDocument)collect(frame.contentDocument,depth+1);
      else blocked(frame);
    }catch(e){blocked(frame);}
  }
  function blocked(frame){
    capture.warnings.push('存在无法读取的跨域 frame，请直接打开该课表页。');
    try{
      const url=new URL(frame.src,location.href);
      if(/^https?:$/.test(url.protocol)&&!url.username&&!url.password&&!capture.frameUrls.includes(url.href)&&capture.frameUrls.length<16)capture.frameUrls.push(url.href);
    }catch(_){}
  }
  collect(document,0);
  const deadline=Date.now()+8000;
  const context=doc=>JSON.stringify([doc.location.href,doc.querySelector('#xnm,[name="xnm"]')?.value,doc.querySelector('#xqm,[name="xqm"]')?.value]);
  let queriedDocument=null,queriedContext=null;
  function accept(doc,data,before){
    if(context(doc)!==before){capture.json=null;capture.error='读取期间学期或页面已切换，请等待新课表加载完成后重新抓取。';capture.warnings.push(capture.error);return;}
    queriedDocument=doc;queriedContext=before;capture.json=data;
  }
  // Serialize a clone with form controls and unrelated scripts removed. Do not export passwords.
  function snapshot(){return roots.map(doc=>{
    const owner=doc.ownerDocument||doc;
    const clone=doc.documentElement?doc.documentElement.cloneNode(true):owner.createElement('div');
    if(!doc.documentElement)clone.innerHTML=doc.innerHTML;
    // Pair all originals with clones before any removal can shift later indexes.
    const selector='[data-course-name],[data-period-index],tr,table';
    const originals=[...doc.querySelectorAll(selector)],copies=[...clone.querySelectorAll(selector)];
    originals.forEach((node,i)=>{if(hidden(node))copies[i]?.remove();});
    clone.querySelectorAll('[hidden]').forEach(e=>e.remove());
    clone.querySelectorAll('input,textarea,select,script,style').forEach(e=>e.remove());
    // Classic EAMS embeds course records in TaskActivity constructors. Preserve only those
    // data-bearing script texts as inert elements for the parser; never run them locally.
    for(const source of doc.querySelectorAll('script'))if(/new\s+TaskActivity\s*\(/.test(source.textContent)&&(source.parentElement?.tagName==='HEAD'||!hidden(source.parentElement))){
      const data=owner.createElement('script');data.type='text/plain';data.textContent=source.textContent;clone.appendChild(data);
    }
    return clone.outerHTML;
  }).join('\n')+'\n'+weeklyTables.join('\n');}
  function weeklyColumns(columns,plain){
    const days=columns.filter(c=>typeof c?.field==='string'&&/^(?:星期|周|礼拜)\s*[一二三四五六日天1-7](?:\s*[\[(（][A-Za-z]+[\])）])?$/.test(plain(c.title)));
    const period=columns.find(c=>typeof c?.field==='string'&&(/^(节次|上课节次|课节)$/.test(plain(c.title))||/^(jc|jcmc|period|section|unit)$/i.test(c.field)));
    return days.length&&period?{days,period}:null;
  }
  function weeklyTable(doc,grid,rows,layout){
    const table=doc.createElement('table'),heading=table.insertRow();
    for(const title of ['节次',...layout.days.map(c=>c.title)]){
      const cell=doc.createElement('th');cell.textContent=String(title).replace(/<[^>]*>/g,'');heading.append(cell);
    }
    const rendered=new Map(),view=grid.closest('.datagrid-view')||grid.parentElement;
    for(const row of view.querySelectorAll('[datagrid-row-index]')){
      const index=Number(row.getAttribute('datagrid-row-index'));
      if(!Number.isInteger(index)||index<0||index>=rows.length)continue;
      if(!rendered.has(index))rendered.set(index,new Map());
      for(const cell of row.querySelectorAll('td[field]'))rendered.get(index).set(cell.getAttribute('field'),cell);
    }
    const occupied=new Map();
    rows.forEach((data,index)=>{
      const row=table.insertRow();row.insertCell().textContent=String(data[layout.period.field]??'');
      for(const column of layout.days){
        if((occupied.get(column.field)||0)>index)continue;
        const cell=row.insertCell(),live=rendered.get(index)?.get(column.field);
        const span=Math.min(rows.length-index,Math.max(1,Number(live?.rowSpan)||1));
        if(span>1){cell.rowSpan=span;occupied.set(column.field,index+span);}
        cell.innerHTML=String(data[column.field]??'');
        cell.querySelectorAll('input,textarea,select,script,style').forEach(node=>node.remove());
      }
    });
    return table.outerHTML;
  }
  (async()=>{
    // Each frame is independent: a failed request must not hide another frame's timetable.
    for(const doc of roots){
      try{
        const loc=doc.location;
        if(!loc||loc.origin!==location.origin)continue;
        if(Date.now()>=deadline){capture.warnings.push('接口读取达到时间上限，继续读取当前课表页面。');break;}
        const before=context(doc);
        if(/\/kbcx\/xskbcx_/.test(loc.pathname)){
          const year=doc.querySelector('#xnm,[name="xnm"]')?.value;
          const term=doc.querySelector('#xqm,[name="xqm"]')?.value;
          if(year&&term){
            const base=loc.pathname.slice(0,loc.pathname.indexOf('/kbcx/'));
            const controller=new AbortController();const timer=setTimeout(()=>controller.abort(),Math.max(1,deadline-Date.now()));
            try{
              const response=await fetch(base+'/kbcx/xskbcx_cxXsgrkb.html',{method:'POST',credentials:'same-origin',
                headers:{'Content-Type':'application/x-www-form-urlencoded;charset=UTF-8'},body:new URLSearchParams({xnm:year,xqm:term,kzlx:'ck'}).toString(),signal:controller.signal});
              if(response.ok){const data=await response.json();if(Array.isArray(data.kbList))accept(doc,data,before);}
            }finally{clearTimeout(timer);}
          }
        }
        if(/\/student\/courseSelect\/thisSemesterCurriculum/.test(loc.pathname)){
          const base=loc.pathname.slice(0,loc.pathname.indexOf('/student/'));
          const controller=new AbortController();const timer=setTimeout(()=>controller.abort(),Math.max(1,deadline-Date.now()));
          try{
            const r=await fetch(base+'/student/courseSelect/thisSemesterCurriculum/data',{credentials:'same-origin',signal:controller.signal});
            if(r.ok){const data=await r.json();if(Array.isArray(data.dateList))accept(doc,data,before);}
          }finally{clearTimeout(timer);}
        }
        if(loc.hostname==='jwxt.neu.edu.cn'&&(/^\/jwapp\//.test(loc.pathname)||loc.pathname==='/')){
          const controller=new AbortController();const timer=setTimeout(()=>controller.abort(),Math.max(1,deadline-Date.now()));
          const get=async(url,options={})=>{
            const response=await fetch(url,{credentials:'same-origin',signal:controller.signal,...options});
            if(!response.ok)throw new Error('金智接口 HTTP '+response.status);return response.json();
          };
          try{
            const info=await get('/jwapp/sys/homeapp/api/home/currentUser.do');
            const term=info.datas?.welcomeInfo?.xnxqdm;
            if(!term)throw new Error('没有取得当前学期，请先登录并打开本学期课表');
            const campuses=await get('/jwapp/sys/homeapp/api/home/student/getMyScheduledCampus.do?termCode='+encodeURIComponent(term));
            if(!Array.isArray(campuses.datas)||campuses.datas.length!==1)throw new Error('该接口不是单校区格式，需选择校区后针对当前课表页适配');
            const campus=campuses.datas[0].id;if(!campus)throw new Error('校区代码缺失');
            const data=await get('/jwapp/sys/homeapp/api/home/student/getMyScheduleDetail.do',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded;charset=UTF-8'},body:new URLSearchParams({termCode:term,campusCode:campus,type:'term'}).toString()});
            if(!Array.isArray(data.datas?.arrangedList))throw new Error('金智接口格式已变化');
            accept(doc,{datas:{arrangedList:data.datas.arrangedList}},before);
          }catch(e){capture.warnings.push(e.message);}finally{clearTimeout(timer);}
        }
      }catch(e){capture.warnings.push('同源课表接口未返回可解析 JSON，保留当前页面 HTML。');}
    }
    try{
      if(queriedDocument&&context(queriedDocument)!==queriedContext){capture.json=null;capture.error='读取期间学期或页面已切换，请等待新课表加载完成后重新抓取。';capture.warnings.push(capture.error);}
      if(capture.json)capture.jsonSource='api';
      // SPA requests can populate or replace the DOM while the known query is in flight.
      roots.length=0;seen.clear();collect(document,0);
      capture.hasTimetable=roots.some(root=>[...root.querySelectorAll('table,.datagrid-view')]
        .some(table=>!hidden(table)&&/(?:星期|周|礼拜)\s*[一二三四五六日天1-7]/.test(table.textContent)));
      // EasyUI virtualises/freeze-splits visible rows. Read its documented,
      // already-loaded data only; do not enumerate arbitrary globals or fetch APIs.
      const gridCourses=[];
      for(const root of roots){
        const doc=root.ownerDocument||root,win=doc.defaultView,$=win?.jQuery;
        if(!$?.fn?.datagrid||capture.error)continue;
        for(const grid of [...root.querySelectorAll('.datagrid-f')].slice(0,16))try{
          // EasyUI deliberately hides the source table itself; its parent view
          // and embedding frame determine which semester is currently visible.
          if(hidden(grid.parentElement||grid.getRootNode().host))continue;
          const options=$(grid).datagrid('options');
          const columns=[...(options?.frozenColumns||[]),...(options?.columns||[])].flat();
          const plain=value=>{const node=doc.createElement('div');node.innerHTML=String(value??'');return node.textContent.replace(/\s+/g,' ').trim();};
          const field=pattern=>columns.find(c=>typeof c?.field==='string'&&pattern.test(plain(c.title)))?.field;
          const fields={name:field(/^(课程名称|课程名)$/),day:field(/^(星期|星期几|上课星期)$/),
            sections:field(/^(节次|上课节次)$/),weeks:field(/^(周次|上课周次)$/),
            teacher:field(/^(教师|任课教师|授课教师)$/),room:field(/^(教室|地点|上课地点)$/)};
          const weekly=weeklyColumns(columns,plain);
          const isList=fields.name&&fields.day&&fields.sections&&fields.weeks;
          if(!isList&&!weekly)continue;
          const data=$(grid).datagrid('getData');
          const rows=Array.isArray(data)?data:data?.rows;
          if(!Array.isArray(rows))continue;
          if(rows.length>2000||gridCourses.length+rows.length>2000){capture.error='课表记录超过 2000 条，请先选择一个完整学期再读取。';break;}
          const total=Number(data.total??rows.length);
          if(!Number.isInteger(total)||total!==rows.length){
            capture.error='课表分页数据尚未完整加载：当前 '+rows.length+' / '+total+' 条。请在学校课表页选择完整学期或每页全部后重新读取。';
            break;
          }
          if(!rows.length)continue;
          if(weekly&&!isList){weeklyTables.push(weeklyTable(doc,grid,rows,weekly));continue;}
          const courses=rows.map(row=>Object.fromEntries(Object.entries(fields).map(([key,value])=>[key,value?plain(row[value]):''])));
          gridCourses.push(...courses);
        }catch(e){capture.warnings.push('表格组件读取失败，继续使用课表页面：'+e.message);}
      }
      if(gridCourses.length&&!capture.json&&!capture.error){capture.json={courses:gridCourses};capture.jsonSource='grid';}
      if(capture.error){capture.json=null;capture.jsonCandidates=[];}
      // Only explicit, already-loaded period settings; never serialize a window or credentials.
      const periods={},periodConflicts=new Set();
      for(const root of roots)for(const key of ['periodTimes','sectionTimes'])try{
        const raw=(root.defaultView||root.ownerDocument?.defaultView)?.[key];
        if(!raw||typeof raw!=='object'||capture.error)continue;
        for(const [index,row] of Object.entries(raw).slice(0,96)){
          if(!row||typeof row!=='object')continue;
          const n=Number(Array.isArray(raw)?row.index??row.section??row.period:index);
          const normalize=v=>typeof v==='string'&&/^(?:[01]?\d|2[0-3])[:：][0-5]\d$/.test(v)?v.replace('：',':').padStart(5,'0'):null;
          const start=normalize(row.start??row.startTime),end=normalize(row.end??row.endTime);
          if(!Number.isInteger(n)||n<1||n>24||!start||!end||start>=end)continue;
          if(periods[n]&&(periods[n].start!==start||periods[n].end!==end))periodConflicts.add(n);
          periods[n]={start,end};
        }
      }catch(_){/* A page may expose accessors that are unavailable. */}
      for(const n of periodConflicts)delete periods[n];
      capture.periodTimes=periods;
      const fingerprints=new Set();let total=0;
      for(const doc of roots){
        const win=doc.defaultView;if(!win||capture.error)continue;
        for(const key of ['activities','kbList','dateList','courses','courseList','kcbData'])try{
          const rows=win[key];if(!Array.isArray(rows)||!rows.length||rows.length>2000)continue;
          const payload={[(key==='courseList'||key==='kcbData')?'courses':key]:rows};
          const value=JSON.stringify(payload);
          if(fingerprints.has(value)||value.length>1000000||total+value.length>2000000||capture.jsonCandidates.length>=16)continue;
          fingerprints.add(value);total+=value.length;capture.jsonCandidates.push(JSON.parse(value));
        }catch(e){capture.warnings.push('有一份页面课表数据无法读取，继续尝试其他课表。');}
      }
      if(!capture.json&&capture.jsonCandidates.length){capture.json=capture.jsonCandidates[0];capture.jsonSource='page';}
      capture.html=snapshot();
    }catch(e){capture.warnings.push('部分页面内容读取失败，请等待课表加载完成后重试。');}
    finally{capture.done=true;}
  })();
  return 'capture-started';
})();
