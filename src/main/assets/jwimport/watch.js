// Read visible timetable text/declared course attributes only. No input values or network calls.
(function(){
  const seen=new Set(),parts=[];let budget=240000;
  function visible(node){
    for(let at=node;at;at=at.parentElement||at.getRootNode?.().host){
      const style=at.ownerDocument?.defaultView?.getComputedStyle(at);
      if(at.hidden||style?.display==='none'||style?.visibility==='hidden')return false;
    }
    return true;
  }
  function scan(root,depth){
    if(!root||seen.has(root)||depth>4||seen.size>=16||budget<=0)return;seen.add(root);
    const attributes=['data-course-name','data-day','data-sections','data-weeks','data-teacher','data-room'];
    for(const node of [...root.querySelectorAll('[data-course-name]')].slice(0,5001)){
      if(!visible(node))continue;
      const value=JSON.stringify(attributes.map(key=>node.getAttribute(key))).slice(0,Math.min(8000,budget));
      parts.push(value);budget-=value.length;if(budget<=0)break;
    }
    const nodes=[...root.querySelectorAll('table,.datagrid-view,[role="grid"],.el-table,.ant-table,.k-grid,.ui-jqgrid,.dataTables_scroll,.bootstrap-table')].slice(0,24);
    if(!nodes.length&&root.body)nodes.push(root.body);
    const texts=[];
    for(const node of nodes){
      if(!visible(node))continue;
      const text=(node.innerText||node.textContent||'').slice(0,Math.min(80000,budget));
      texts.push(text);budget-=text.length;if(budget<=0)break;
    }
    const combined=texts.join('\n');
    if(/星期[一二三四五六日天]|周[一二三四五六日天]|Monday|Tuesday|Wednesday/i.test(combined)
      &&/节次|周次|\bF[1-9]|\d\s*[-~—]\s*\d+\s*周|第\s*\d+\s*节/.test(combined))parts.push(combined);
    for(const frame of [...root.querySelectorAll('iframe,frame')].slice(0,12)){
      if(!visible(frame))continue;try{scan(frame.contentDocument,depth+1);}catch(_){}
    }
    let checked=0;
    for(const node of root.querySelectorAll('*')){
      if(++checked>2400)break;
      if(node.shadowRoot&&visible(node))scan(node.shadowRoot,depth+1);
    }
  }
  scan(document,0);
  if(!parts.length)return '';
  const text=parts.join('\n');let hash=2166136261;
  for(let i=0;i<text.length;i++)hash=Math.imul(hash^text.charCodeAt(i),16777619);
  return text.length+':'+(hash>>>0);
})();
