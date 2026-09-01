# MUTANT: ac12
# TARGET: scripts/dispatch/board.html
# WHY: orders the rank map the way the summary counts are printed — killed, then survivor. The
# WHY: sort still runs, the constant is still there, and the one row somebody opened the board to
# WHY: find sits under every mutant that behaved.
<title>Jig Fleet</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;600&family=IBM+Plex+Sans:wght@400;500;600&display=swap">
<style>
:root{
  --ground:#f6f7f9;--panel:#fff;--sunk:#eceff4;--line:#d8dee7;--line-soft:#e6eaf0;
  --ink:#161b22;--ink-2:#4a5568;--ink-3:#79839a;--accent:#2f4b8f;--accent-soft:#e5eaf6;
  --ok:#1f7a4d;--ok-bg:#e2f2e9;--bad:#b3261e;--bad-bg:#fbe6e4;--wait:#8a6100;--wait-bg:#faeed2;
  --live:#1f7a4d;
}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){
  --ground:#0f1319;--panel:#161b23;--sunk:#1b212b;--line:#2b3440;--line-soft:#232b36;
  --ink:#e8edf4;--ink-2:#a8b3c4;--ink-3:#75819a;--accent:#8fa9e8;--accent-soft:#1e2942;
  --ok:#5cc98d;--ok-bg:#14301f;--bad:#f08a80;--bad-bg:#361a18;--wait:#e0b357;--wait-bg:#32270f;
  --live:#5cc98d;
}}
:root[data-theme="dark"]{
  --ground:#0f1319;--panel:#161b23;--sunk:#1b212b;--line:#2b3440;--line-soft:#232b36;
  --ink:#e8edf4;--ink-2:#a8b3c4;--ink-3:#75819a;--accent:#8fa9e8;--accent-soft:#1e2942;
  --ok:#5cc98d;--ok-bg:#14301f;--bad:#f08a80;--bad-bg:#361a18;--wait:#e0b357;--wait-bg:#32270f;
  --live:#5cc98d;
}
*{box-sizing:border-box}
body{margin:0;background:var(--ground);color:var(--ink);
  font-family:"IBM Plex Sans",ui-sans-serif,system-ui,sans-serif;font-size:15px;line-height:1.5}
.mono{font-family:"IBM Plex Mono",ui-monospace,SFMono-Regular,Menlo,monospace}
.tnum{font-variant-numeric:tabular-nums}
header{border-bottom:1px solid var(--line);background:var(--panel);padding:16px 24px}
.bar{max-width:1300px;margin:0 auto;display:flex;align-items:baseline;gap:16px;flex-wrap:wrap}
h1{margin:0;font-size:17px;font-weight:600;letter-spacing:-.01em}
.pulse{display:inline-flex;align-items:center;gap:7px;font-size:12px;color:var(--ink-3)}
.pulse i{width:8px;height:8px;border-radius:50%;background:var(--live);
  animation:b 2s ease-in-out infinite}
@keyframes b{0%,100%{opacity:1}50%{opacity:.25}}
@media (prefers-reduced-motion:reduce){.pulse i{animation:none}}
main{max-width:1300px;margin:0 auto;padding:20px 24px 60px;
  display:grid;grid-template-columns:320px minmax(0,1fr);gap:20px;align-items:start}
@media(max-width:900px){main{grid-template-columns:1fr}}
h2{font-size:10.5px;text-transform:uppercase;letter-spacing:.09em;color:var(--ink-3);
  margin:0 0 8px;font-weight:600}
.rail{display:flex;flex-direction:column;gap:6px}
.run{display:block;width:100%;text-align:left;border:1px solid var(--line);background:var(--panel);
  border-radius:9px;padding:10px 12px;cursor:pointer;color:inherit;font:inherit}
.run:hover{border-color:var(--accent)}
.run[aria-current="true"]{border-color:var(--accent);background:var(--accent-soft)}
.run .sp{font-family:"IBM Plex Mono",monospace;font-size:12.5px;
  overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.run .ln{display:flex;justify-content:space-between;margin-top:5px;font-size:11px;color:var(--ink-3)}
.pane{background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:18px 20px}
.pill{display:inline-flex;align-items:center;gap:5px;border-radius:20px;padding:1px 9px;
  font-size:11px;font-weight:500;border:1px solid transparent}
.pill.ok{background:var(--ok-bg);color:var(--ok);border-color:var(--ok)}
.pill.no{background:var(--bad-bg);color:var(--bad);border-color:var(--bad)}
.pill.run{background:var(--wait-bg);color:var(--wait);border-color:var(--wait)}
.pipe{display:flex;overflow-x:auto;padding-bottom:10px;gap:0}
.node{flex:0 0 auto;display:flex;align-items:center}
.link{width:18px;height:2px;background:var(--line)}
.tcard{border:1px solid var(--line);background:var(--panel);border-radius:9px;padding:8px 11px;
  min-width:118px;cursor:pointer;color:inherit;font:inherit;text-align:left}
.tcard:hover{border-color:var(--accent)}
.tcard[aria-current="true"]{border-color:var(--accent);background:var(--accent-soft)}
.tcard .id{font-family:"IBM Plex Mono",monospace;font-weight:600;font-size:13px}
.tcard .st{font-size:11px;margin-top:3px;display:flex;align-items:center;gap:5px}
.dot{width:7px;height:7px;border-radius:50%}
.dot.ok{background:var(--ok)}.dot.no{background:var(--bad)}.dot.run{background:var(--wait)}
.dot.idle{background:var(--line)}
.task{background:var(--sunk);border-radius:8px;padding:10px 12px;font-size:12.5px;
  color:var(--ink-2);margin:12px 0;max-height:120px;overflow:auto}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(92px,1fr));gap:14px;margin:14px 0}
.grid div b{display:block;font-family:"IBM Plex Mono",monospace;font-size:16px;font-weight:600;
  font-variant-numeric:tabular-nums}
.grid div span{font-size:10px;text-transform:uppercase;letter-spacing:.08em;color:var(--ink-3)}
.ctl{display:flex;gap:8px;margin:14px 0 0}
button.act{border:1px solid var(--line);background:var(--panel);color:inherit;font:inherit;
  font-size:12.5px;border-radius:7px;padding:5px 12px;cursor:pointer}
button.act:hover{border-color:var(--accent);color:var(--accent)}
button.act[disabled]{opacity:.45;cursor:default}
.arts{display:flex;flex-wrap:wrap;gap:6px;margin-top:10px}
.art{font-family:"IBM Plex Mono",monospace;font-size:11px;border:1px solid var(--line);
  border-radius:6px;padding:2px 8px;color:var(--ink-2);background:var(--panel);cursor:pointer}
.art:hover{border-color:var(--accent);color:var(--accent)}
.art[aria-current="true"]{border-color:var(--accent);background:var(--accent-soft);color:var(--accent)}
.mrow{border:1px solid var(--line);border-radius:9px;padding:10px 12px;margin-top:8px;
  background:var(--panel)}
.mrow.survivor{border-color:var(--bad)}
.mrow .mh{display:flex;align-items:center;gap:8px;flex-wrap:wrap}
.mrow .mid{font-family:"IBM Plex Mono",monospace;font-size:12.5px;font-weight:600}
.mrow .mmeta{font-family:"IBM Plex Mono",monospace;font-size:11px;color:var(--ink-3)}
.mrow .mwhy{font-size:12.5px;color:var(--ink-2);margin-top:6px}
.mdiff{background:var(--sunk);border-radius:8px;padding:9px 11px;margin-top:8px;overflow-x:auto;
  font-family:"IBM Plex Mono",monospace;font-size:11.5px;line-height:1.45;white-space:pre;
  max-height:340px;overflow-y:auto;color:var(--ink-2)}
.empty{color:var(--ink-3);font-size:13px;margin:8px 0}
footer{max-width:1300px;margin:0 auto;padding:0 24px 40px;color:var(--ink-3);font-size:12px}
</style>
<header><div class="bar">
  <h1>Jig Fleet</h1>
  <span class="pulse"><i></i><span id="pulse">connecting…</span></span>
</div></header>
<main>
  <div><h2>Runs</h2><div class="rail" id="rail"></div></div>
  <div class="pane" id="pane"><p class="empty">Waiting for a worker to report…</p></div>
</main>
<footer>Workers push; nothing connects in. Controls are parked here and collected by the worker on
its next poll — the same way a CI runner discovers cancellation.</footer>
<script>
let DATA=[], cur=null, curTask=null, curArt=null, ARTIDX=[];
const $=s=>document.querySelector(s);
const ago=t=>{if(!t)return'—';const d=Math.max(0,Math.floor(Date.now()/1000)-t);
  return d<60?d+'s':d<3600?Math.floor(d/60)+'m':Math.floor(d/3600)+'h';};
const live=r=>(Math.floor(Date.now()/1000)-(r.updated||0))<90 &&
  !['passed','failed','stopped','done'].includes(r.phase);

async function poll(){
  try{
    const res=await fetch('/api/runs',{cache:'no-store'});
    if(!res.ok) throw new Error(res.status);
    DATA=(await res.json()).runs||[];
    $('#pulse').textContent=DATA.length+' run'+(DATA.length===1?'':'s')+' · updated '+
      new Date().toLocaleTimeString();
    if(!cur&&DATA.length) cur=DATA[0].key;
    render();
  }catch(e){ $('#pulse').textContent='coordinator unreachable'; }
}
function render(){
  $('#rail').innerHTML=DATA.map(r=>`<button class="run" data-k="${r.key}" aria-current="${r.key===cur}">
    <div class="sp">${r.spec||r.key}</div>
    <div class="ln"><span>${live(r)?'●&nbsp;':''}${r.phase} · T${r.task_index}/${r.total_tasks}</span>
      <span class="tnum">${ago(r.updated)} ago</span></div></button>`).join('')
    || '<p class="empty">No runs yet.</p>';
  document.querySelectorAll('.run').forEach(b=>b.onclick=()=>{cur=b.dataset.k;curTask=null;render();});
  const r=DATA.find(x=>x.key===cur);
  if(!r){ $('#pane').innerHTML='<p class="empty">Waiting for a worker to report…</p>'; return; }

  // One node per task. Everything before the current index has been passed; the current one is
  // in flight; the rest have not started. Attempt records fill in what each cost.
  const byTask={}; (r.attempts||[]).forEach(a=>{
    const k=(a.task||'').split(':')[0]||'T?'; (byTask[k]=byTask[k]||[]).push(a); });
  let pipe='';
  for(let i=1;i<=(r.total_tasks||0);i++){
    const id='T'+i, at=byTask[id]||[];
    const cls = i<r.task_index?'ok' : i===r.task_index?(live(r)?'run':'no') : 'idle';
    const lbl = i<r.task_index? (at.length? at.length+' attempt'+(at.length===1?'':'s') : 'passed')
              : i===r.task_index? 'attempt '+r.attempt+'/'+r.max_attempts : 'queued';
    pipe+=`${i>1?'<div class="link"></div>':''}<div class="node">
      <button class="tcard" data-t="${id}" aria-current="${id===curTask}">
        <div class="id">${id}</div><div class="st"><span class="dot ${cls}"></span>${lbl}</div>
      </button></div>`;
  }
  const ph=r.phase==='passed'?'ok':r.phase==='failed'?'no':'run';
  $('#pane').innerHTML=`
    <h2>Run</h2>
    <p style="margin:0 0 4px"><span class="mono" style="font-size:15px;font-weight:600">${r.spec||r.key}</span>
      &nbsp;<span class="pill ${ph}">${r.phase}</span></p>
    <p style="margin:0;color:var(--ink-2);font-size:13px" class="mono">${r.key} · ${r.branch||''} ·
      agent ${r.agent||'?'} · started ${ago(r.started)} ago</p>
    <div class="task">${r.task||'—'}</div>
    <div class="pipe">${pipe||'<p class="empty">No tasks reported yet.</p>'}</div>
    <div class="ctl">
      <button class="act" data-a="cancel">Stop</button>
      <button class="act" data-a="pause">Pause</button>
      <button class="act" data-a="none">Resume</button>
      <span style="align-self:center;font-size:12px;color:var(--ink-3)">
        ${r.control&&r.control!=='none'?'intent parked: <b>'+r.control+'</b> — the worker collects it on its next poll':''}
      </span>
    </div>
    <div id="det"></div>`;
  document.querySelectorAll('.tcard').forEach(b=>b.onclick=()=>{
    curTask=curTask===b.dataset.t?null:b.dataset.t; render();});
  document.querySelectorAll('.act').forEach(b=>b.onclick=async()=>{
    b.disabled=true;
    try{ await fetch('/runs/'+r.key+'/control',{method:'POST',
      headers:{'Content-Type':'application/json'},body:JSON.stringify({action:b.dataset.a})});
    }catch(e){}
    b.disabled=false; poll();});
  detail(r,byTask);
}
function detail(r,byTask){
  const d=$('#det'); if(!d) return;
  // Artifact keys are held in an array and referenced by INDEX from the markup, never
  // interpolated into it: a key carries a task label that came off a spec, and a quote in one
  // would break out of the attribute it was written into.
  ARTIDX=[];
  if(!curTask){ d.innerHTML=`<p class="empty">Select a task for its attempts — what each one cost,
    how it ended, and which artifacts it shipped.</p>`; return; }
  const at=byTask[curTask]||[];
  if(!at.length){ d.innerHTML=`<p class="empty">${curTask} has reported no attempt records yet.</p>`;
    return; }
  d.innerHTML=at.map(a=>{
    const cls=a.outcome==='passed'?'ok':a.outcome==='failed'?'no':'run';
    const arts=(r.artifacts||[]).filter(k=>k.startsWith(curTask+'/'+a.attempt+'/'))
      .map(k=>{ const i=ARTIDX.push(k)-1;
        return `<button class="art" data-i="${i}">${k.split('/').pop()}</button>`; }).join('');
    return `<div style="border-top:1px solid var(--line-soft);margin-top:14px;padding-top:14px">
      <p style="margin:0"><b class="mono">attempt ${a.attempt}</b>
        &nbsp;<span class="pill ${cls}">${a.outcome||'?'}</span></p>
      <div class="grid">
        <div><b class="tnum">${a.duration_s??'—'}s</b><span>duration</span></div>
        <div><b class="tnum">${a.exec_rc??'—'}</b><span>exec rc</span></div>
        <div><b class="tnum">${a.verify_rc??'—'}</b><span>verify rc</span></div>
        <div><b class="tnum">${a.bytes_transcript??'—'}</b><span>transcript</span></div>
        <div><b class="tnum">${a.bytes_patch??a.bytes_diff??'—'}</b><span>changes</span></div>
      </div>
      <div class="arts">${arts||'<span class="empty">no artifacts shipped — evidence egress not built yet</span>'}</div>
    </div>`;
  }).join('') + '<div id="viewer"></div>';
  d.querySelectorAll('.art').forEach(b=>b.onclick=()=>{
    const k=ARTIDX[+b.dataset.i];
    curArt = (curArt===k) ? null : k;
    d.querySelectorAll('.art').forEach(x=>x.setAttribute('aria-current',
      String(ARTIDX[+x.dataset.i]===curArt)));
    showArtifact(r.key, curArt);
  });
  // The selftest artifact opens on its own. It is the reason a person clicked into a task at
  // all when a gate refused, and making them hunt for it is one click of friction in the exact
  // moment they are debugging.
  const auto=ARTIDX.find(k=>k.endsWith('/selftest'));
  if(auto && !curArt){ curArt=auto;
    d.querySelectorAll('.art').forEach(x=>x.setAttribute('aria-current',
      String(ARTIDX[+x.dataset.i]===auto)));
    showArtifact(r.key, auto); }
  else showArtifact(r.key, curArt);
}

// ── MUTANT PANEL BEGIN ────────────────────────────────────────────────────────────────────
//
// What a gate's mutants did, for the attempt in front of you. 20260831u runs each task's
// corpus the moment that task's gate first goes green; 20260831s ships those verdicts over
// the artifact channel as kind `selftest`. This reads them back.
//
// Two rules hold this section together:
//
//   SURVIVORS FIRST, and the order is a literal rank rather than a comparator expression, so
//   the gate that guards this file can read both numbers and compare them. A survivor is the
//   one row someone opened the board to find; ranking it under the mutants that behaved is
//   the failure mode worth spending a constant on.
//
//   EVERY FIELD BELOW IS WORKER-SUPPLIED, so every field below is set with textContent and the
//   DOM is built node by node. `why` is prose an author wrote in a corpus file and `diff` is a
//   file's contents; either can contain markup, and this page is same-origin with the control
//   route that stops a run.
const VRANK = {KILLED:0, SURVIVOR:1, 'WRONG-REASON':2, HUNG:3};
const VCLS  = {SURVIVOR:'no', 'WRONG-REASON':'run', HUNG:'run', KILLED:'ok'};

function artUrl(key,name){
  return '/api/artifact?key='+encodeURIComponent(key)+'&name='+encodeURIComponent(name);
}
function el(tag,cls,text){
  const n=document.createElement(tag);
  if(cls) n.className=cls;
  if(text!==undefined && text!==null) n.textContent=String(text);
  return n;
}

// parseSelftest — JSONL in, ordered rows + counts out.
//
// A line that does not parse is SKIPPED and counted, never thrown. The artifact is clipped at
// a byte cap by design, which cuts the last line in half; one truncated line must not blank a
// panel whose whole job is to be readable when something has gone wrong.
function parseSelftest(txt){
  const rows=[]; let summary=null, bad=0;
  (txt||'').split('\n').forEach(ln=>{
    ln=ln.trim(); if(!ln) return;
    let o;
    try{ o=JSON.parse(ln); }
    catch(e){ bad++; return; }
    if(o && o.run_complete) summary=o;
    else if(o && o.verdict) rows.push(o);
  });
  rows.sort((a,b)=>(VRANK[a.verdict]===undefined?9:VRANK[a.verdict])
                  -(VRANK[b.verdict]===undefined?9:VRANK[b.verdict]));
  if(!summary){
    // No run_complete line survived. Count what did, rather than showing nothing.
    summary={killed:0,survivor:0,wrong_reason:0,hung:0};
    const K={KILLED:'killed',SURVIVOR:'survivor','WRONG-REASON':'wrong_reason',HUNG:'hung'};
    rows.forEach(r=>{ const k=K[r.verdict]; if(k) summary[k]++; });
  }
  return {rows,summary,bad};
}

function mutantPanel(host,txt){
  const {rows,summary,bad}=parseSelftest(txt);
  host.appendChild(el('h2',null,'Gate selftest'));
  const g=el('div','grid');
  [['killed','killed'],['survivor','SURVIVOR'],['wrong_reason','WRONG-REASON'],['hung','HUNG']]
    .forEach(pair=>{
      const d=el('div');
      d.appendChild(el('b','tnum',summary[pair[0]]===undefined?0:summary[pair[0]]));
      d.appendChild(el('span',null,pair[1]));
      g.appendChild(d);
    });
  host.appendChild(g);
  if(bad) host.appendChild(el('p','empty',
    bad+' line(s) could not be read and were skipped — the artifact is clipped at a byte cap'));
  if(!rows.length){
    host.appendChild(el('p','empty','No mutant rows in this artifact.'));
    return;
  }
  rows.forEach(r=>{
    const card=el('div','mrow'+(r.verdict==='SURVIVOR'?' survivor':''));
    const h=el('div','mh');
    h.appendChild(el('span','pill '+(VCLS[r.verdict]||'run'), r.verdict));
    h.appendChild(el('span','mid', r.mutant||'(unnamed mutant)'));
    h.appendChild(el('span','mmeta','assertion '+(r.assertion||'?')+' · target '+(r.target||'?')));
    card.appendChild(h);
    card.appendChild(el('div','mwhy', r.why||''));
    // The diff is HOW THE MUTANT WAS FORMED — the one thing that exists nowhere else once the
    // worker is gone. It rides only on rows that were not killed; a killed mutant's diff is
    // reconstructible from the corpus file committed beside the gate.
    if(r.diff) card.appendChild(el('pre','mdiff', r.diff));
    host.appendChild(card);
  });
}

async function showArtifact(key,name){
  const v=$('#viewer'); if(!v) return;
  v.textContent='';
  if(!name){
    v.appendChild(el('p','empty','Select an artifact to read it — a selftest opens on its own.'));
    return;
  }
  let txt;
  try{
    const res=await fetch(artUrl(key,name),{cache:'no-store'});
    if(!res.ok) throw new Error('HTTP '+res.status);
    txt=await res.text();
  }catch(e){
    v.appendChild(el('p','empty','could not read '+name+' — '+e.message));
    return;
  }
  if(name.endsWith('/selftest')) mutantPanel(v,txt);
  else { v.appendChild(el('h2',null,name.split('/').pop())); v.appendChild(el('pre','mdiff',txt)); }
}
// ── MUTANT PANEL END ──────────────────────────────────────────────────────────────────────

poll(); setInterval(poll,4000);
</script>
