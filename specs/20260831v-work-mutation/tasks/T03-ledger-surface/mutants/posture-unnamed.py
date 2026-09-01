# MUTANT: ac3
# TARGET: scripts/mutant-ledger.py
# WHY: the section renders but nothing says telemetry — the first reader to skim the
# WHY: counts will file UNNOTICED as a gate failure, which is the misread the wording
# WHY: contract exists to prevent.
#!/usr/bin/env python3
"""mutant-ledger.py — render the gate-selftest evidence store into the Mutant Ledger.

Reads `.evidence/selftest-<slug>.jsonl` (written by scripts/gate-selftest.sh when
SELFTEST_EVID is set), takes the LATEST COMPLETE run per corpus — rows without a
run_complete marker are a partial record and never preferred — and writes two renders
of the same data:

  mutant-ledger.md     GitHub-renderable: verdict counts, corpus table, per-mutant
                       collapsible diffs. Relative links, so it works from the repo page.
  mutant-ledger.html   the visual board: verdict tiles, filter, survivor-first cards,
                       colored diffs. Absolute repo links, so it works published anywhere.

Survivors sort first — the day one exists it is the headline, not a needle in the kills.

Re-runnable; derives everything from the store and holds no state of its own (the
loop-index.py contract). Deterministic on purpose: identical store, identical bytes —
specs/20260830f-mutant-observability's ac7 regenerates and compares, so a `now()` in
here is a gate failure, not a nicety.

  usage: mutant-ledger.py [--evid DIR] [--out DIR] [--repo-url URL]
"""
import argparse, glob, html, json, os, sys

RANK = {"SURVIVOR": 0, "WRONG-REASON": 1, "HUNG": 2, "KILLED": 3}
GLYPH = {"SURVIVOR": "✗", "WRONG-REASON": "↯", "HUNG": "⏱", "KILLED": "✓"}
MEAN = {
    "KILLED": "gate failed naming the declared assertion",
    "SURVIVOR": "gate accepted the mutant — the defect walks",
    "WRONG-REASON": "gate failed, but not where the mutant aimed",
    "HUNG": "gate never returned inside the bound",
}
CSS_CLASS = {"SURVIVOR": "crit", "WRONG-REASON": "warn", "HUNG": "hung", "KILLED": "good"}


def load(evid):
    runs = {}
    for f in sorted(glob.glob(os.path.join(evid, "selftest-*.jsonl"))):
        with open(f, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                r = json.loads(line)
                key = (r["spec"], r["task"])
                slot = runs.setdefault(key, {}).setdefault(r["run_id"], {"rows": [], "marker": None})
                if r.get("run_complete"):
                    slot["marker"] = r
                else:
                    slot["rows"].append(r)
    corpora = []
    for key in sorted(runs):
        complete = {rid: s for rid, s in runs[key].items() if s["marker"]}
        if not complete:
            continue
        rid = sorted(complete)[-1]  # run ids lead with a UTC stamp, so max() is latest
        rows = sorted(complete[rid]["rows"], key=lambda r: (RANK.get(r["verdict"], 9), r["mutant"]))
        corpora.append(dict(spec=key[0], task=key[1], run_id=rid,
                            marker=complete[rid]["marker"], rows=rows))
    return corpora


WS_RANK = {"UNNOTICED": 0, "HUNG": 1, "NOTICED": 2}
WS_GLYPH = {"UNNOTICED": "?", "HUNG": "⏱", "NOTICED": "✓"}


def load_worksens(evid):
    """The work-sensitivity telemetry store (specs/20260831v-work-mutation): probes derived
    from a committed diff, TELEMETRY not enforcement — an UNNOTICED probe is a lead, not a
    conviction. Same latest-complete-run discipline as the corpus store."""
    runs = {}
    for f in sorted(glob.glob(os.path.join(evid, "worksens-*.jsonl"))):
        with open(f, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                r = json.loads(line)
                key = (r["spec"], r["task"])
                slot = runs.setdefault(key, {}).setdefault(r["run_id"], {"rows": [], "marker": None})
                if r.get("run_complete"):
                    slot["marker"] = r
                else:
                    slot["rows"].append(r)
    out = []
    for (spec, task), by_run in sorted(runs.items()):
        complete = {rid: v for rid, v in by_run.items() if v["marker"]}
        if not complete:
            continue
        rid = sorted(complete)[-1]
        rows = sorted(complete[rid]["rows"], key=lambda r: (WS_RANK.get(r["verdict"], 9), r.get("target", ""), r.get("site", "")))
        out.append(dict(spec=spec, task=task, run_id=rid, rows=rows, marker=complete[rid]["marker"]))
    return out


def render_worksens_md(ws):
    out = []
    a = out.append
    a("\n## Work sensitivity\n")
    a("> Probes derived from each task's own committed diff.\n")
    if not ws:
        a("No sensitivity rows recorded yet — the loop writes `worksens-<slug>.jsonl` at "
          "every task commit whenever `SELFTEST_EVID` is set.\n")
        return "\n".join(out)
    a("| task commit | probes | noticed | unnoticed | hung |")
    a("|---|---:|---:|---:|---:|")
    for w in ws:
        m = w["marker"]
        a("| `%s · %s` @ `%s` | %d | %d | %d | %d |" % (
            w["spec"], w["task"], str(m.get("commit", ""))[:9], len(w["rows"]),
            m.get("noticed", 0), m.get("unnoticed", 0), m.get("hung", 0)))
    a("")
    for w in ws:
        for r in w["rows"]:
            v = r["verdict"]
            a("### %s `%s` @ `%s` [%s] — %s" % (
                WS_GLYPH.get(v, "?"), r.get("operator", "?"), r.get("target", "?"),
                r.get("site", "?"), v))
            a("`%s · %s` · commit `%s` · gate rc %s\n" % (
                r["spec"], r["task"], str(r.get("commit", ""))[:9], r.get("gate_rc", "?")))
            if r.get("diff"):
                a("<details><summary>probe diff</summary>\n")
                a("````diff")
                a(str(r["diff"]).rstrip("\n"))
                a("````")
                a("</details>\n")
    return "\n".join(out)


def render_worksens_html(ws):
    frag = ['<hr><section id="worksens"><h2>Work sensitivity — telemetry, not enforcement</h2>']
    frag.append("<p>Probes from each task's own committed diff; an UNNOTICED probe is a lead, "
                "not a conviction — these rows never fail a run.</p>")
    if not ws:
        frag.append("<p>No sensitivity rows recorded yet.</p>")
    else:
        frag.append("<ul>")
        for w in ws:
            for r in w["rows"]:
                frag.append("<li><b>%s</b> — %s @ %s [%s] (%s · %s)</li>" % (
                    html.escape(r["verdict"]), html.escape(str(r.get("operator", ""))),
                    html.escape(str(r.get("target", ""))), html.escape(str(r.get("site", ""))),
                    html.escape(r["spec"]), html.escape(r["task"])))
        frag.append("</ul>")
    frag.append("</section>")
    return "".join(frag)


def counts(corpora):
    c = {"KILLED": 0, "SURVIVOR": 0, "WRONG-REASON": 0, "HUNG": 0}
    for corp in corpora:
        for r in corp["rows"]:
            c[r["verdict"]] = c.get(r["verdict"], 0) + 1
    return c


def corpus_path(corp):
    if corp["spec"] == corp["task"]:  # non-standard layout fallback (fixtures)
        return None
    return "specs/%s/tasks/%s" % (corp["spec"], corp["task"])


def provenance(corpora):
    dates = sorted({c["run_id"][:8] for c in corpora})
    dates = ["%s-%s-%s" % (d[:4], d[4:6], d[6:8]) for d in dates]
    n = sum(len(c["rows"]) for c in corpora)
    return dates, len(corpora), n


def render_md(corpora, repo_url):
    c = counts(corpora)
    dates, ncorp, nmut = provenance(corpora)
    out = []
    a = out.append
    a("# Mutant Ledger\n")
    a("> Generated by `scripts/mutant-ledger.py` from `.evidence/selftest-*.jsonl` — do not "
      "edit; regenerate. Latest complete run per corpus. Convention: "
      "[`specs/20260828k-gate-selftest`](../specs/20260828k-gate-selftest/spec.md); "
      "observability spec: `specs/20260830f-mutant-observability`.\n")
    a("Sweep dates: %s · **%d corpora · %d mutants**\n" % (", ".join(dates), ncorp, nmut))
    a("| verdict | count | meaning |")
    a("|---|---:|---|")
    for v in ("SURVIVOR", "WRONG-REASON", "HUNG", "KILLED"):
        a("| %s %s | %d | %s |" % (GLYPH[v], v, c[v], MEAN[v]))
    a("")
    a("| corpus | run | mutants | killed | survived | wrong-reason | hung |")
    a("|---|---|---:|---:|---:|---:|---:|")
    for corp in corpora:
        m = corp["marker"]
        base = corpus_path(corp)
        name = "%s · %s" % (corp["spec"], corp["task"])
        link = "[`%s`](../%s/mutants)" % (name, base) if base else "`%s`" % name
        a("| %s | `%s` | %d | %d | %d | %d | %d |" % (
            link, corp["run_id"], len(corp["rows"]),
            m["killed"], m["survivor"], m["wrong_reason"], m["hung"]))
    a("")
    for corp in corpora:
        base = corpus_path(corp)
        a("## %s · %s" % (corp["spec"], corp["task"]))
        if base:
            a("[mutants/](../%s/mutants) · [gate](../%s/verify.sh) · run `%s`\n" % (base, base, corp["run_id"]))
        for r in corp["rows"]:
            v = r["verdict"]
            a("### %s `%s` — %s" % (GLYPH[v], r["mutant"], v))
            bits = ["breaks `%s`" % r["assertion"], "±%d lines" % r.get("diff_lines", 0)]
            if base:
                bits.append("[mutant](../%s/mutants/%s)" % (base, r["mutant"]))
            bits.append("target [`%s`](../%s)" % (r["target"], r["target"]))
            if r.get("instead"):
                bits.append("fired instead: `%s`" % "`, `".join(r["instead"]))
            a(" · ".join(bits) + "\n")
            if r.get("why"):
                a("> %s\n" % r["why"])
            a("<details><summary>diff</summary>\n")
            a("````diff")
            a(r["diff"].rstrip("\n"))
            a("````")
            a("</details>\n")
    return "\n".join(out) + "\n"


HTML_TEMPLATE = r"""<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Jig Mutant Ledger</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500;600&family=IBM+Plex+Sans:wght@400;500;600&display=swap">
<style>
:root{
  --bg:#F6F7F9; --surface:#FFFFFF; --surface2:#EEF0F4; --ink:#1C222B; --muted:#5A6472;
  --line:#DDE2E9; --accent:#4F5BD5; --accent-ink:#3D48B8;
  --good:#1A7F4B; --good-bg:#E3F2E9; --crit:#C63A3A; --crit-bg:#FAE8E8;
  --warn:#B0790F; --warn-bg:#F8EFD9; --hung:#7A5FB8; --hung-bg:#EFEAF8;
  --add-bg:#E4F3EA; --add-ink:#14663C; --del-bg:#FBEAEA; --del-ink:#A32E2E;
  --hunk:#5F6ACB; --chip-bg:#E9EBF7;
}
@media (prefers-color-scheme: dark){
  :root:not([data-theme="light"]){
    --bg:#14171C; --surface:#1C2129; --surface2:#232935; --ink:#E8EBF0; --muted:#97A1AE;
    --line:#2A313B; --accent:#8A93E8; --accent-ink:#A5ACEF;
    --good:#4CC58A; --good-bg:#1B3226; --crit:#E06A6A; --crit-bg:#3A2223;
    --warn:#D9A73E; --warn-bg:#37301C; --hung:#A18BE0; --hung-bg:#2A2440;
    --add-bg:#1D3A2A; --add-ink:#7BD8A6; --del-bg:#422626; --del-ink:#E89090;
    --hunk:#8A93E8; --chip-bg:#262D45;
  }
}
:root[data-theme="dark"]{
  --bg:#14171C; --surface:#1C2129; --surface2:#232935; --ink:#E8EBF0; --muted:#97A1AE;
  --line:#2A313B; --accent:#8A93E8; --accent-ink:#A5ACEF;
  --good:#4CC58A; --good-bg:#1B3226; --crit:#E06A6A; --crit-bg:#3A2223;
  --warn:#D9A73E; --warn-bg:#37301C; --hung:#A18BE0; --hung-bg:#2A2440;
  --add-bg:#1D3A2A; --add-ink:#7BD8A6; --del-bg:#422626; --del-ink:#E89090;
  --hunk:#8A93E8; --chip-bg:#262D45;
}
*{box-sizing:border-box}
body{background:var(--bg); color:var(--ink); font:15px/1.55 "IBM Plex Sans",-apple-system,"Segoe UI",sans-serif; margin:0; padding:0 20px 80px;}
.wrap{max-width:1020px; margin:0 auto;}
a{color:var(--accent-ink); text-decoration:none;}
a:hover{text-decoration:underline;}
a:focus-visible,button:focus-visible,input:focus-visible,summary:focus-visible{outline:2px solid var(--accent); outline-offset:2px; border-radius:2px;}
code,.mono{font-family:"IBM Plex Mono",ui-monospace,SFMono-Regular,Menlo,monospace;}
header{padding:44px 0 8px;}
.kicker{font-family:"IBM Plex Mono",monospace; font-size:12px; letter-spacing:.14em; text-transform:uppercase; color:var(--muted);}
h1{font-family:"IBM Plex Mono",monospace; font-weight:600; font-size:clamp(26px,4vw,36px); margin:6px 0 10px; text-wrap:balance;}
.prov{color:var(--muted); font-size:13.5px; max-width:68ch;}
.prov code{font-size:12.5px; background:var(--surface2); padding:1px 5px; border-radius:3px;}
.thesis{border-left:3px solid var(--accent); padding:2px 0 2px 14px; margin:20px 0 0; max-width:68ch; font-size:15px;}
.tiles{display:grid; grid-template-columns:repeat(auto-fit,minmax(170px,1fr)); gap:12px; margin:28px 0 12px;}
.tile{background:var(--surface); border:1px solid var(--line); border-radius:6px; padding:14px 16px 12px;}
.tile .n{font-family:"IBM Plex Mono",monospace; font-size:34px; font-weight:600; line-height:1; font-variant-numeric:tabular-nums;}
.tile .lbl{display:flex; align-items:center; gap:7px; margin-top:8px; font-size:13px; font-weight:600;}
.tile .sub{font-size:12px; color:var(--muted); margin-top:3px; line-height:1.4;}
.dot{width:9px; height:9px; border-radius:50%; flex:none;}
.t-good .n,.t-good .lbl{color:var(--good);} .t-good .dot{background:var(--good);}
.t-crit .n,.t-crit .lbl{color:var(--crit);} .t-crit .dot{background:var(--crit);}
.t-warn .n,.t-warn .lbl{color:var(--warn);} .t-warn .dot{background:var(--warn);}
.t-hung .n,.t-hung .lbl{color:var(--hung);} .t-hung .dot{background:var(--hung);}
.tile.zero .n{color:var(--muted); opacity:.55;}
.corpus{width:100%; border-collapse:collapse; background:var(--surface); border:1px solid var(--line); border-radius:6px; overflow:hidden; font-size:13.5px; margin:10px 0 0;}
.corpus th{font-family:"IBM Plex Mono",monospace; font-size:11px; letter-spacing:.1em; text-transform:uppercase; color:var(--muted); text-align:left; font-weight:500; padding:9px 14px; border-bottom:1px solid var(--line); background:var(--surface2);}
.corpus td{padding:8px 14px; border-bottom:1px solid var(--line); font-variant-numeric:tabular-nums;}
.corpus tr:last-child td{border-bottom:none;}
.corpus .num{text-align:right; font-family:"IBM Plex Mono",monospace;}
.tblwrap{overflow-x:auto;}
.controls{display:flex; gap:10px; align-items:center; flex-wrap:wrap; margin:34px 0 6px; position:sticky; top:0; background:var(--bg); padding:12px 0; z-index:5; border-bottom:1px solid var(--line);}
.controls input[type=search]{flex:1 1 220px; max-width:340px; background:var(--surface); color:var(--ink); border:1px solid var(--line); border-radius:5px; padding:7px 11px; font:13.5px "IBM Plex Mono",monospace;}
.controls button{background:var(--surface); color:var(--ink); border:1px solid var(--line); border-radius:5px; padding:7px 12px; font:13px "IBM Plex Sans",sans-serif; font-weight:500; cursor:pointer;}
.controls button:hover{border-color:var(--accent);}
.count{font-size:12.5px; color:var(--muted); margin-left:auto; font-variant-numeric:tabular-nums;}
h2{font-family:"IBM Plex Mono",monospace; font-size:17px; font-weight:600; margin:38px 0 4px; text-wrap:balance;}
h2 a{color:inherit;}
.taskline{font-size:13px; color:var(--muted); margin:0 0 14px;}
h3.task{font-family:"IBM Plex Mono",monospace; font-size:13px; font-weight:500; letter-spacing:.06em; color:var(--muted); text-transform:uppercase; margin:26px 0 10px;}
h3.task a{color:inherit;}
.card{background:var(--surface); border:1px solid var(--line); border-radius:6px; margin:0 0 10px; overflow:hidden;}
.card summary{list-style:none; cursor:pointer; padding:12px 16px; display:flex; flex-wrap:wrap; gap:8px 12px; align-items:center;}
.card summary::-webkit-details-marker{display:none;}
.card summary:hover{background:var(--surface2);}
.twist{font-family:"IBM Plex Mono",monospace; color:var(--muted); font-size:12px; transition:transform .15s; flex:none;}
@media (prefers-reduced-motion: reduce){ .twist{transition:none;} }
details[open] .twist{transform:rotate(90deg);}
.mname{font-family:"IBM Plex Mono",monospace; font-size:14px; font-weight:600; word-break:break-all;}
.pill{font-family:"IBM Plex Mono",monospace; font-size:11px; font-weight:600; letter-spacing:.08em; padding:2px 9px; border-radius:20px; flex:none;}
.p-good{color:var(--good); background:var(--good-bg);}
.p-crit{color:var(--crit); background:var(--crit-bg);}
.p-warn{color:var(--warn); background:var(--warn-bg);}
.p-hung{color:var(--hung); background:var(--hung-bg);}
.chip{font-family:"IBM Plex Mono",monospace; font-size:11.5px; color:var(--accent-ink); background:var(--chip-bg); padding:2px 8px; border-radius:4px; flex:none;}
.drift{font-family:"IBM Plex Mono",monospace; font-size:11.5px; color:var(--muted); flex:none; margin-left:auto;}
.drift b{font-weight:600;}
.drift .hot{color:var(--warn);}
.meta{padding:2px 16px 14px; border-top:1px dashed var(--line);}
.meta .row{display:flex; gap:8px; font-size:13px; margin-top:10px; align-items:baseline; flex-wrap:wrap;}
.meta .k{font-family:"IBM Plex Mono",monospace; font-size:11px; letter-spacing:.1em; text-transform:uppercase; color:var(--muted); flex:none; width:74px;}
.meta .why{max-width:72ch;}
.meta code{font-size:12.5px;}
.diff{margin:14px 0 2px; background:var(--surface2); border:1px solid var(--line); border-radius:5px; overflow-x:auto; max-height:440px; overflow-y:auto;}
.diff pre{margin:0; padding:10px 0; font:12px/1.5 "IBM Plex Mono",ui-monospace,monospace; min-width:max-content;}
.dl{display:block; padding:0 14px; white-space:pre;}
.dl.add{background:var(--add-bg); color:var(--add-ink);}
.dl.del{background:var(--del-bg); color:var(--del-ink);}
.dl.hunk{color:var(--hunk); font-weight:500;}
.dl.filehdr{color:var(--muted); font-weight:600;}
.driftnote{font-size:12.5px; color:var(--muted); margin:10px 0 0; max-width:72ch;}
.lore{margin-top:52px; border-top:1px solid var(--line); padding-top:8px;}
.lore .intro{color:var(--muted); font-size:13.5px; max-width:70ch; margin:2px 0 18px;}
.story{background:var(--surface); border:1px solid var(--line); border-left:3px solid var(--crit); border-radius:6px; padding:14px 18px; margin-bottom:12px;}
.story h4{margin:0 0 6px; font-size:14.5px; font-family:"IBM Plex Mono",monospace;}
.story p{margin:0 0 6px; font-size:13.5px; max-width:74ch;}
.story .rule{font-weight:600;}
.story .src{font-size:12.5px; color:var(--muted);}
footer{margin-top:48px; font-size:12.5px; color:var(--muted); border-top:1px solid var(--line); padding-top:14px; max-width:74ch;}
.hidden-card{display:none;}
</style></head><body>
<div class="wrap">
<header>
  <div class="kicker">jig · gate-selftest · .evidence/selftest-*.jsonl</div>
  <h1>Mutant Ledger</h1>
  <p class="prov">__PROV__ Generated by <a href="__GH__blob/main/scripts/mutant-ledger.py"><code>scripts/mutant-ledger.py</code></a>
    from the committed store — latest complete run per corpus, one hermetic temp copy per mutant, metadata stripped on install.</p>
  <p class="thesis">Each diff below is <b>exactly what the gate was asked to catch</b>: the wrong implementation a
    competent person would plausibly write, installed over the real target. A kill proves the assertion tells that
    wrongness apart from health. A survivor is the defect that walks through — which is why survivors sort first.</p>
</header>
<div class="tiles" id="tiles"></div>
<div class="tblwrap"><table class="corpus" id="corpus">
  <thead><tr><th>corpus</th><th>run</th><th>gate</th><th class="num">mutants</th><th class="num">killed</th><th class="num">survived</th><th class="num">wrong-reason</th><th class="num">hung</th></tr></thead>
  <tbody></tbody>
</table></div>
<div class="controls">
  <input type="search" id="q" placeholder="filter: name, target, assertion, why…" aria-label="Filter mutants">
  <button id="expand">Expand all diffs</button>
  <button id="collapse">Collapse all</button>
  <span class="count" id="count"></span>
</div>
<div id="list"></div>
<section class="lore">
  <h2>How survivors have actually happened</h2>
  <p class="intro">When the board is clean, the survivor lesson lives in the record. Three real incidents, each of
    which first read as "weak assertion" when the assertion was fine — the diff was the thing that told the truth.</p>
  <div class="story">
    <h4>The harness planted the needle — two doc mutants "survived"</h4>
    <p>2026-08-29, first real corpus: the tool installed mutants <em>with</em> their <code>WHY:</code> metadata lines
       intact. A WHY line describes what the mutant removed — so a gate grepping the target for that very token matched
       the <em>description of its absence</em> and passed. Trap A, needle planted by the harness itself.</p>
    <p class="rule">Rule: strip the metadata on install — it is the tool's data, never part of the artifact.</p>
    <p class="src">Fixed in <a href="__GH__blob/main/scripts/gate-selftest.sh"><code>gate-selftest.sh</code></a>.</p>
  </div>
  <div class="story">
    <h4>A mutant that deletes one of two redundant guards changes nothing</h4>
    <p>2026-08-28, <code>20260828l-run-control</code>: the mutant deleted an explicit guard while a second code path
       enforced the same property. Behaviour never changed, the assertion had nothing to detect, and the false survivor
       invited "strengthening" a check that was already correct.</p>
    <p class="rule">Rule: don't mutate by deletion — write the mistake a competent person would make. Before writing a
       mutant, look for a second implementation of the behaviour.</p>
    <p class="src"><a href="__GH__blob/main/specs/20260828l-run-control/evidence/2026-08-28-mutants-that-miss.md">evidence: mutants-that-miss.md</a></p>
  </div>
  <div class="story">
    <h4>"Disable the behaviour, not delete one of the places that implement it"</h4>
    <p>The original form of the rule, from the corpus convention's own write-up — the same defect arrived one spec
       later anyway, which is what upgraded it from good intentions to procedure.</p>
    <p class="src"><a href="__GH__tree/main/specs/20260828k-gate-selftest">spec: 20260828k-gate-selftest</a></p>
  </div>
</section>
<footer>
  Diffs are mutant-vs-target as captured at each run — the target keeps moving, so a large diff usually means
  <b>corpus drift</b> (the mutant was written against an older target), not a bigger mutation. Store and schema:
  <a href="__GH__blob/main/specs/20260830f-mutant-observability/spec.md">specs/20260830f-mutant-observability</a>.
</footer>
</div>
<script type="application/json" id="data">__DATA__</script>
<script>
const GH = "__GH__blob/main/";
const GHT = "__GH__tree/main/";
const payload = JSON.parse(document.getElementById("data").textContent);
const V = {
  KILLED:        {cls:"good", glyph:"✓", label:"KILLED",       sub:"gate failed naming the declared assertion"},
  SURVIVOR:      {cls:"crit", glyph:"✗", label:"SURVIVOR",     sub:"gate accepted the mutant — the defect walks"},
  "WRONG-REASON":{cls:"warn", glyph:"↯", label:"WRONG-REASON", sub:"gate failed, but not where the mutant aimed"},
  HUNG:          {cls:"hung", glyph:"⏱", label:"HUNG",         sub:"gate never returned inside the bound"},
};
const esc = s => String(s).replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;");
const counts = {KILLED:0, SURVIVOR:0, "WRONG-REASON":0, HUNG:0};
payload.forEach(c => c.rows.forEach(r => counts[r.verdict] = (counts[r.verdict]||0)+1));
const total = payload.reduce((n,c) => n + c.rows.length, 0);
document.getElementById("tiles").innerHTML = Object.entries(V).map(([k,v]) =>
  `<div class="tile t-${v.cls}${counts[k] ? "" : " zero"}">
     <div class="n">${counts[k]}</div>
     <div class="lbl"><span class="dot"></span>${v.glyph} ${v.label}</div>
     <div class="sub">${v.sub}</div></div>`).join("");
document.querySelector("#corpus tbody").innerHTML = payload.map(c => {
  const m = c.marker, base = c.base;
  const name = `${c.spec} · ${c.task}`;
  return `<tr><td class="mono">${base ? `<a href="${GHT}${base}/mutants">${esc(name)}</a>` : esc(name)}</td>
    <td class="mono">${esc(c.run_id)}</td>
    <td class="mono">${base ? `<a href="${GH}${base}/verify.sh">verify.sh</a>` : "—"}</td>
    <td class="num">${c.rows.length}</td><td class="num">${m.killed}</td>
    <td class="num">${m.survivor || "—"}</td><td class="num">${m.wrong_reason || "—"}</td><td class="num">${m.hung || "—"}</td></tr>`;
}).join("");
function renderDiff(d){
  return d.split("\n").map(l => {
    let c = "";
    if (/^\+\+\+ |^--- /.test(l)) c = "filehdr";
    else if (l.startsWith("@@")) c = "hunk";
    else if (l.startsWith("+")) c = "add";
    else if (l.startsWith("-")) c = "del";
    return `<span class="dl ${c}">${esc(l) || " "}</span>`;
  }).join("");
}
function driftBadge(n){
  if (n <= 25)  return `<b>${n}</b> ±lines · surgical`;
  if (n <= 100) return `<b>${n}</b> ±lines`;
  return `<b class="hot">${n}</b> ±lines · <span class="hot">drifted</span>`;
}
const bySpec = {};
payload.forEach(c => (bySpec[c.spec] = bySpec[c.spec] || []).push(c));
document.getElementById("list").innerHTML = Object.entries(bySpec).map(([spec, cs]) => {
  const specDir = "specs/" + spec, hasDir = cs.some(c => c.base);
  return `<h2>${hasDir ? `<a href="${GHT}${specDir}">${esc(spec)}</a>` : esc(spec)}</h2>
  <p class="taskline">${cs.length} corpus${cs.length>1?"es":""}${hasDir ? ` · <a href="${GH}${specDir}/spec.md">spec.md</a>` : ""}</p>` +
  cs.map(c => {
    const base = c.base;
    return (base ? `<h3 class="task"><a href="${GHT}${base}/mutants">${c.task}/mutants</a> · <a href="${GH}${base}/verify.sh">gate</a></h3>` : `<h3 class="task">${esc(c.task)}</h3>`) +
    c.rows.map(r => {
      const v = V[r.verdict], mpath = base ? `${base}/mutants/${r.mutant}` : null;
      const hay = (r.mutant+" "+r.target+" "+r.assertion+" "+r.why).toLowerCase();
      return `<details class="card" data-hay="${esc(hay)}"${r.verdict === "SURVIVOR" ? " open" : ""}>
        <summary><span class="twist">▸</span><span class="mname">${esc(r.mutant)}</span>
          <span class="pill p-${v.cls}">${v.glyph} ${v.label}</span>
          <span class="chip">breaks ${esc(r.assertion)}</span>
          <span class="drift">${driftBadge(r.diff_lines)}</span></summary>
        <div class="meta">
          <div class="row"><span class="k">target</span><code><a href="${GH}${esc(r.target)}">${esc(r.target)}</a></code></div>
          ${mpath ? `<div class="row"><span class="k">mutant</span><code><a href="${GH}${esc(mpath)}">${esc(mpath)}</a></code></div>` : ""}
          ${r.instead && r.instead.length ? `<div class="row"><span class="k">instead</span><code>${r.instead.map(esc).join(", ")}</code></div>` : ""}
          <div class="row"><span class="k">why</span><span class="why">${esc(r.why)}</span></div>
          <div class="diff"><pre>${renderDiff(r.diff)}</pre></div>
          ${r.diff_lines > 100 ? `<p class="driftnote">Large diff — the mutant predates changes to its target, so this shows drift <em>plus</em> the mutation. The verdict stands (it ran against today's gate); a drifted mutant trends toward WRONG-REASON and is corpus maintenance.</p>` : ""}
        </div></details>`;
    }).join("");
  }).join("");
}).join("");
const cards = [...document.querySelectorAll(".card")];
const countEl = document.getElementById("count");
function updateCount(){
  const vis = cards.filter(c => !c.classList.contains("hidden-card")).length;
  countEl.textContent = vis === total ? `${total} mutants` : `${vis} of ${total} mutants`;
}
document.getElementById("q").addEventListener("input", e => {
  const q = e.target.value.trim().toLowerCase();
  cards.forEach(c => c.classList.toggle("hidden-card", q && !c.dataset.hay.includes(q)));
  updateCount();
});
document.getElementById("expand").onclick  = () => cards.forEach(c => { if (!c.classList.contains("hidden-card")) c.open = true; });
document.getElementById("collapse").onclick = () => cards.forEach(c => c.open = false);
updateCount();
</script>
</body></html>
"""


def render_html(corpora, repo_url):
    dates, ncorp, nmut = provenance(corpora)
    payload = []
    for corp in corpora:
        payload.append(dict(spec=corp["spec"], task=corp["task"], run_id=corp["run_id"],
                            base=corpus_path(corp), marker=corp["marker"], rows=corp["rows"]))
    prov = "Sweep%s of <b>%s</b> — %d corpora, %d mutants." % (
        "s" if len(dates) > 1 else "", html.escape(", ".join(dates)), ncorp, nmut)
    data = json.dumps(payload, ensure_ascii=False, sort_keys=True).replace("</", "<\\/")
    page = HTML_TEMPLATE.replace("__GH__", repo_url.rstrip("/") + "/")
    page = page.replace("__PROV__", prov).replace("__DATA__", data)
    return page


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--evid", default=".evidence")
    ap.add_argument("--out", default=None, help="output dir (default: same as --evid)")
    ap.add_argument("--repo-url", default="https://github.com/mtgibbs/jig")
    args = ap.parse_args()
    out = args.out or args.evid
    corpora = load(args.evid)
    if not corpora:
        print("mutant-ledger: no complete runs in %s (selftest-*.jsonl)" % args.evid, file=sys.stderr)
        return 1
    worksens = load_worksens(args.evid)
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, "mutant-ledger.md"), "w", encoding="utf-8") as f:
        f.write(render_md(corpora, args.repo_url) + render_worksens_md(worksens))
    page = render_html(corpora, args.repo_url)
    page = page.replace("</body></html>", render_worksens_html(worksens) + "</body></html>")
    with open(os.path.join(out, "mutant-ledger.html"), "w", encoding="utf-8") as f:
        f.write(page)
    n = sum(len(c["rows"]) for c in corpora)
    s = sum(c["marker"]["survivor"] for c in corpora)
    print("mutant-ledger: %d corpora, %d mutants, %d survivors -> %s" % (len(corpora), n, s, out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
