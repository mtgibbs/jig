#!/usr/bin/env python3
"""runboard.py — render the tracked run history as a single self-contained HTML board.

Reads .evidence/index-*.jsonl (one JSON record per TASK, not per run) and emits a board
showing every spec, its task pipeline, and what each task cost in attempts.

Why this reads git-tracked files and not a live feed: .evidence/index-*.jsonl is committed,
so the "which stage is everything at" half of the picture already leaves the worker on every
push, with no coordinator and no inbound connection. A live feed upgrades this later; it was
never a prerequisite for looking at the work.

Usage: python3 scripts/runboard.py [-o out.html]
"""
import argparse, glob, html, json, os, sys, time
from collections import OrderedDict


def load(root):
    specs = OrderedDict()
    for path in sorted(glob.glob(os.path.join(root, ".evidence", "index-*.jsonl"))):
        name = os.path.basename(path).split("index-", 1)[1].rsplit(".", 1)[0]
        rows = []
        for ln in open(path, encoding="utf-8"):
            ln = ln.strip()
            if not ln:
                continue
            try:
                rows.append(json.loads(ln))
            except json.JSONDecodeError:
                continue
        if rows:
            specs[name] = rows
    return specs


def tasknum(t):
    """Sort T1, T2, T10 numerically — lexical order puts T10 before T2."""
    s = str(t or "")
    d = "".join(c for c in s if c.isdigit())
    return int(d) if d else 0


def summarize(name, rows):
    rows = sorted(rows, key=lambda r: tasknum(r.get("task")))
    tasks = []
    for r in rows:
        runs = r.get("runs") or []
        diff = r.get("diff") or {}
        # attempts_observed counts what the evidence tree actually holds; attempts_metrics is
        # what the loop recorded. They disagree when a run was reaped, so prefer the larger:
        # under-reporting an attempt is the direction that flatters the model.
        att = max(r.get("attempts_observed") or 0, r.get("attempts_metrics") or 0)
        stamps = [x for x in (rn.get("updated") for rn in runs) if x]
        # Two INDEPENDENT dimensions, and collapsing them is the bug this board must not have.
        # `landed` means the commit is reachable from main — a MERGE fact. Whether the work
        # passed its gate is a separate question answered by the run's own verify_pass. A task
        # that passed on a branch nobody has merged yet is green work in an unmerged state, not
        # a failure, and showing it red would report five passing tasks as one.
        # The reliable verdict is whether the task PRODUCED A COMMIT: run-loop.sh commits only
        # after the gate goes green, so a commit is a gate pass that already happened. The
        # runs[].verify_pass field looks like the obvious signal and is not — it is the last
        # heartbeat value, `None` on almost every record here, so reading it reports seven
        # merged tasks as zero passes.
        passed = bool(r.get("commit"))
        if passed:
            outcome = "pass"
        elif att:
            outcome = "fail"
        else:
            outcome = "none"
        tasks.append({
            "task": r.get("task") or "?",
            "landed": bool(r.get("landed")),
            "outcome": outcome,
            "attempts": att,
            "pass": r.get("gate_pass") or 0,
            "fail": r.get("gate_fail") or 0,
            "pend": r.get("gate_pend") or 0,
            "commit": (r.get("commit") or "")[:7],
            "at": r.get("committed_at") or "",
            "files": diff.get("files") or 0,
            "ins": diff.get("insertions") or 0,
            "dels": diff.get("deletions") or 0,
            "phases": [rn.get("phase") or "?" for rn in runs],
            "agents": sorted({rn.get("agent") or "?" for rn in runs}),
            "updated": max(stamps) if stamps else 0,
            "subjects": [c.get("subject", "")[:150] for c in (r.get("commits") or [])],
        })
    landed = sum(1 for t in tasks if t["landed"])
    passed = sum(1 for t in tasks if t["outcome"] == "pass")
    failed = sum(1 for t in tasks if t["outcome"] == "fail")
    # Evidence retention prunes old run directories, so attempts_observed is None for many
    # older tasks. Counting only tasks with a recorded attempt keeps the ratio meaningful; the
    # footer says plainly that attempt counts are a floor.
    tried = sum(1 for t in tasks if t["attempts"])
    att = sum(t["attempts"] for t in tasks)
    return {
        "name": name,
        "tasks": tasks,
        "total": len(tasks),
        "landed": landed,
        "passed": passed,
        "failed": failed,
        "tried": tried,
        "attempts": att,
        # Attempts per task the executor actually ATTEMPTED. The denominator is deliberately not
        # `landed`: merge state is a human's decision and would make this number swing when a PR
        # is merged without a single line of work changing. Tasks skipped by resume have zero
        # attempts and are excluded, which is what makes this comparable across runs.
        "cost": round(att / tried, 2) if tried else None,
        "pend": sum(t["pend"] for t in tasks),
        "fail": sum(t["fail"] for t in tasks),
        "updated": max([t["updated"] for t in tasks] or [0]),
        # Deliberately weak words. Each index-*.jsonl is a SNAPSHOT committed alongside the run
        # that produced it, not a live status feed — a task that landed through a later PR is not
        # reflected here. "blocked" would assert something about the present that this file
        # cannot support; "partial" only describes the record, which is all it is.
        "state": ("complete" if tasks and landed == len(tasks) else
                  "no work recorded" if not passed else
                  "partial"),
    }


CSS = """
:root{
  --ground:#f6f7f9; --panel:#ffffff; --sunk:#eceff4; --line:#d8dee7; --line-soft:#e6eaf0;
  --ink:#161b22; --ink-2:#4a5568; --ink-3:#79839a;
  --accent:#2f4b8f; --accent-soft:#e5eaf6;
  --ok:#1f7a4d; --ok-bg:#e2f2e9; --bad:#b3261e; --bad-bg:#fbe6e4;
  --wait:#8a6100; --wait-bg:#faeed2;
  --shadow:0 1px 2px rgba(20,28,45,.06),0 8px 24px -18px rgba(20,28,45,.5);
}
@media (prefers-color-scheme:dark){
  :root:not([data-theme="light"]){
    --ground:#0f1319; --panel:#161b23; --sunk:#1b212b; --line:#2b3440; --line-soft:#232b36;
    --ink:#e8edf4; --ink-2:#a8b3c4; --ink-3:#75819a;
    --accent:#8fa9e8; --accent-soft:#1e2942;
    --ok:#5cc98d; --ok-bg:#14301f; --bad:#f08a80; --bad-bg:#361a18;
    --wait:#e0b357; --wait-bg:#32270f;
    --shadow:0 1px 2px rgba(0,0,0,.4),0 8px 24px -18px #000;
  }
}
:root[data-theme="dark"]{
  --ground:#0f1319; --panel:#161b23; --sunk:#1b212b; --line:#2b3440; --line-soft:#232b36;
  --ink:#e8edf4; --ink-2:#a8b3c4; --ink-3:#75819a;
  --accent:#8fa9e8; --accent-soft:#1e2942;
  --ok:#5cc98d; --ok-bg:#14301f; --bad:#f08a80; --bad-bg:#361a18;
  --wait:#e0b357; --wait-bg:#32270f;
  --shadow:0 1px 2px rgba(0,0,0,.4),0 8px 24px -18px #000;
}
*{box-sizing:border-box}
body{margin:0;background:var(--ground);color:var(--ink);
  font-family:"IBM Plex Sans",ui-sans-serif,system-ui,sans-serif;font-size:15px;line-height:1.5}
.mono{font-family:"IBM Plex Mono",ui-monospace,SFMono-Regular,Menlo,monospace}
.tnum{font-variant-numeric:tabular-nums}
header{border-bottom:1px solid var(--line);background:var(--panel);padding:22px 26px}
.wrap{max-width:1240px;margin:0 auto}
h1{margin:0;font-size:19px;font-weight:600;letter-spacing:-.01em}
.sub{margin:4px 0 0;color:var(--ink-2);font-size:13.5px;max-width:74ch}
.stats{display:flex;flex-wrap:wrap;gap:26px;margin-top:16px}
.stat b{display:block;font-size:25px;font-weight:600;letter-spacing:-.02em;
  font-family:"IBM Plex Mono",ui-monospace,monospace;font-variant-numeric:tabular-nums}
.stat span{font-size:10.5px;text-transform:uppercase;letter-spacing:.09em;color:var(--ink-3)}
main{max-width:1240px;margin:0 auto;padding:22px 26px 60px;
  display:grid;grid-template-columns:290px minmax(0,1fr);gap:22px;align-items:start}
@media(max-width:880px){main{grid-template-columns:1fr}}
.rail{display:flex;flex-direction:column;gap:6px;position:sticky;top:18px}
@media(max-width:880px){.rail{position:static;max-height:none}}
.rail h2,.pane h2{font-size:10.5px;text-transform:uppercase;letter-spacing:.09em;
  color:var(--ink-3);margin:0 0 8px;font-weight:600}
.sitem{display:block;width:100%;text-align:left;border:1px solid var(--line);
  background:var(--panel);border-radius:9px;padding:9px 11px;cursor:pointer;
  color:inherit;font:inherit;transition:border-color .12s,background .12s}
.sitem:hover{border-color:var(--accent)}
.sitem[aria-current="true"]{border-color:var(--accent);background:var(--accent-soft)}
.sitem .nm{font-size:12.5px;font-family:"IBM Plex Mono",monospace;
  overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.sitem .meta{display:flex;justify-content:space-between;align-items:center;
  margin-top:6px;font-size:11px;color:var(--ink-3)}
.strip{display:flex;gap:2px;margin-top:7px}
.strip i{height:4px;flex:1;border-radius:2px;background:var(--line)}
.strip i.ok{background:var(--ok)} .strip i.no{background:var(--bad)}
.strip i.merged{box-shadow:0 3px 0 -1px var(--accent)}
.merged-tick{color:var(--accent);font-size:8px;vertical-align:middle}
.pane{background:var(--panel);border:1px solid var(--line);border-radius:12px;
  padding:18px 20px;box-shadow:var(--shadow)}
.ptitle{font-family:"IBM Plex Mono",monospace;font-size:15.5px;margin:0 0 3px;font-weight:600}
.pmeta{color:var(--ink-2);font-size:13px;margin:0 0 16px}
.pipe{display:flex;gap:0;overflow-x:auto;padding-bottom:10px;margin-bottom:4px}
.node{flex:0 0 auto;display:flex;align-items:center}
.node .link{width:20px;height:2px;background:var(--line);flex:0 0 auto}
.tcard{border:1px solid var(--line);background:var(--panel);border-radius:9px;
  padding:8px 11px;min-width:132px;cursor:pointer;color:inherit;font:inherit;text-align:left;
  transition:border-color .12s,background .12s}
.tcard:hover{border-color:var(--accent)}
.tcard[aria-current="true"]{border-color:var(--accent);background:var(--accent-soft)}
.tcard .id{font-family:"IBM Plex Mono",monospace;font-weight:600;font-size:13px}
.tcard .st{font-size:11px;margin-top:3px;display:flex;align-items:center;gap:5px}
.dot{width:7px;height:7px;border-radius:50%;flex:0 0 auto}
.dot.ok{background:var(--ok)} .dot.no{background:var(--bad)} .dot.pend{background:var(--wait)}
.pill{display:inline-flex;align-items:center;gap:5px;border-radius:20px;padding:1px 9px;
  font-size:11px;font-weight:500;border:1px solid transparent}
.pill.ok{background:var(--ok-bg);color:var(--ok);border-color:var(--ok)}
.pill.no{background:var(--bad-bg);color:var(--bad);border-color:var(--bad)}
.pill.pend{background:var(--wait-bg);color:var(--wait);border-color:var(--wait)}
.detail{border-top:1px solid var(--line-soft);margin-top:14px;padding-top:16px}
.dgrid{display:grid;grid-template-columns:repeat(auto-fit,minmax(96px,1fr));gap:14px;margin:14px 0}
.dgrid div b{display:block;font-family:"IBM Plex Mono",monospace;font-size:17px;font-weight:600;
  font-variant-numeric:tabular-nums}
.dgrid div span{font-size:10px;text-transform:uppercase;letter-spacing:.08em;color:var(--ink-3)}
.subj{background:var(--sunk);border-radius:8px;padding:10px 12px;font-size:12.5px;
  font-family:"IBM Plex Mono",monospace;color:var(--ink-2);
  max-height:150px;overflow:auto;white-space:pre-wrap;word-break:break-word}
.hint{color:var(--ink-3);font-size:12.5px;margin:10px 0 0}
footer{max-width:1240px;margin:0 auto;padding:0 26px 44px;color:var(--ink-3);font-size:12px}
footer code{font-family:"IBM Plex Mono",monospace;background:var(--sunk);
  padding:1px 5px;border-radius:4px}
"""

JS = """
const $=s=>document.querySelector(s);
let curSpec=DATA[0]?DATA[0].name:null, curTask=null;
function fmt(ts){ if(!ts) return '—';
  return new Date(ts*1000).toLocaleString(undefined,{month:'short',day:'numeric',
    hour:'2-digit',minute:'2-digit'}); }
function rail(){
  $('#rail').innerHTML = DATA.map(s=>{
    const bars = s.tasks.map(t=>`<i class="${t.outcome==='pass'?'ok':t.outcome==='fail'?'no':''}${t.landed?' merged':''}"></i>`).join('');
    return `<button class="sitem" data-spec="${s.name}" aria-current="${s.name===curSpec}">
      <div class="nm">${s.name}</div>
      <div class="strip">${bars}</div>
      <div class="meta"><span class="tnum">${s.passed}/${s.total} passed</span>
        <span class="tnum">${s.cost===null?'—':s.cost+'× cost'}</span></div></button>`;
  }).join('');
  document.querySelectorAll('.sitem').forEach(b=>b.onclick=()=>{
    curSpec=b.dataset.spec; curTask=null; render();});
}
function render(){
  rail();
  const s=DATA.find(x=>x.name===curSpec); if(!s) return;
  const pipe = s.tasks.map((t,i)=>{
    const cls = t.outcome==='pass'?'ok':t.outcome==='fail'?'no':'pend';
    const label = t.outcome==='pass'
        ? (t.attempts? `${t.attempts} attempt${t.attempts===1?'':'s'}` : 'skipped, gate green')
        : t.outcome==='fail' ? `gave up after ${t.attempts}` : 'not run';
    return `<div class="node">${i?'<div class="link"></div>':''}
      <button class="tcard" data-task="${t.task}" aria-current="${t.task===curTask}">
        <div class="id">${t.task}${t.landed?' <span class="merged-tick" title="merged to main">\u25CF</span>':''}</div>
        <div class="st"><span class="dot ${cls}"></span>${label}</div>
      </button></div>`;
  }).join('');
  const st = s.state==='complete'?'ok':(s.state==='stalled'?'no':'pend');
  $('#pane').innerHTML = `
    <h2>Pipeline</h2>
    <p class="ptitle">${s.name}</p>
    <p class="pmeta"><span class="pill ${st}">${s.state}</span>
      &nbsp;${s.passed} of ${s.total} passed their gate · ${s.landed} merged to main ·
      ${s.attempts} attempts recorded across ${s.tried} task${s.tried===1?'':'s'}
      ${s.cost===null?'':'· <b class="tnum">'+s.cost+'</b> attempts per recorded task'}
      · last activity ${fmt(s.updated)}</p>
    <div class="pipe">${pipe}</div>
    <div id="detail"></div>`;
  document.querySelectorAll('.tcard').forEach(b=>b.onclick=()=>{
    curTask = curTask===b.dataset.task?null:b.dataset.task; render();});
  detail(s);
}
function detail(s){
  const d=$('#detail'); if(!d) return;
  const t=s.tasks.find(x=>x.task===curTask);
  if(!t){ d.innerHTML=`<p class="hint">Select a task to see its gate verdicts, its diff and the
    commit it produced. Rail bars are one per task — green passed its gate, red gave up, hollow
    never ran; an underline marks a task already merged to <span class="mono">main</span>.
    Passing and merged are separate facts, because work waits in a branch.</p>`;
    return; }
  const gates = [
    t.pass?`<span class="pill ok">${t.pass} pass</span>`:'',
    t.fail?`<span class="pill no">${t.fail} fail</span>`:'',
    t.pend?`<span class="pill pend">${t.pend} deferred</span>`:''].filter(Boolean).join(' ');
  d.innerHTML=`<div class="detail">
    <h2>${t.task} · ${t.outcome==='pass'?'gate passed':t.outcome==='fail'?'gate never passed':'not attempted'}${t.landed?' · merged to main':''}</h2>
    <p class="pmeta">${gates||'<span class="pill pend">no gate record</span>'}
      ${t.agents.length?' · agent '+t.agents.join(', '):''}
      ${t.phases.length?' · run phases: '+t.phases.join(' → '):''}</p>
    <div class="dgrid">
      <div><b class="tnum">${t.attempts}</b><span>attempts recorded</span></div>
      <div><b class="tnum">${t.files}</b><span>files</span></div>
      <div><b class="tnum">+${t.ins}</b><span>added</span></div>
      <div><b class="tnum">−${t.dels}</b><span>removed</span></div>
      <div><b class="mono">${t.commit||'—'}</b><span>commit</span></div>
    </div>
    ${t.subjects.length?`<div class="subj">${t.subjects.map(x=>x).join('\\n\\n')}</div>`:''}
  </div>`;
}
render();
"""


def build(specs, root):
    data = [summarize(n, r) for n, r in specs.items()]
    data.sort(key=lambda s: s["name"])
    tot_t = sum(s["total"] for s in data)
    tot_l = sum(s["landed"] for s in data)
    tot_p = sum(s["passed"] for s in data)
    tot_r = sum(s["tried"] for s in data)
    tot_a = sum(s["attempts"] for s in data)
    cost = round(tot_a / tot_r, 2) if tot_r else 0
    payload = json.dumps(data, separators=(",", ":"))
    gen = time.strftime("%Y-%m-%d %H:%M UTC", time.gmtime())
    return f"""<title>Jig Run Board</title>
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;600&family=IBM+Plex+Sans:wght@400;500;600&display=swap">
<style>{CSS}</style>
<header><div class="wrap">
  <h1>Jig Run Board</h1>
  <p class="sub">Every spec the ralph loop has built, task by task, with what each task cost in
  attempts. Read straight from <span class="mono">.evidence/index-*.jsonl</span> — the run
  records the loop commits to git, so this needs no coordinator and no connection into a worker.
  Each index is a snapshot written by the run that produced it, so a task later merged through a
  PR still reads as unmerged until that spec next runs.</p>
  <div class="stats">
    <div class="stat"><b>{len(data)}</b><span>specs</span></div>
    <div class="stat"><b>{tot_t}</b><span>tasks</span></div>
    <div class="stat"><b>{tot_p}</b><span>gates passed</span></div>
    <div class="stat"><b>{tot_l}</b><span>merged</span></div>
    <div class="stat"><b>{tot_a}</b><span>attempts</span></div>
    <div class="stat"><b>{cost}</b><span>attempts / recorded task</span></div>
  </div>
</div></header>
<main>
  <div class="rail"><h2>Specs</h2><div id="rail"></div></div>
  <div class="pane" id="pane"></div>
</main>
<footer>Generated {gen} by <code>scripts/runboard.py</code> from
{tot_t} task records across {len(data)} spec indexes. A task counts as passed when it produced a commit \u2014 the loop commits only on a green gate. Attempt counts are a FLOOR: evidence retention prunes old run directories, so a pruned attempt is invisible here. Regenerate after any run:
<code>python3 scripts/runboard.py -o board.html</code></footer>
<script>const DATA={payload};{JS}</script>
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-o", "--out", default="board.html")
    ap.add_argument("-C", "--root", default=".")
    a = ap.parse_args()
    specs = load(a.root)
    if not specs:
        print("no .evidence/index-*.jsonl found under " + a.root, file=sys.stderr)
        return 1
    with open(a.out, "w", encoding="utf-8") as fh:
        fh.write(build(specs, a.root))
    print(f"wrote {a.out}: {len(specs)} specs, "
          f"{sum(len(v) for v in specs.values())} tasks")
    return 0


if __name__ == "__main__":
    sys.exit(main())
