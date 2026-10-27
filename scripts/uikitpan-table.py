#!/usr/bin/env python3
"""UIKITPAN-s1: turns the `UKP q=...` lines of UIKitPanProbeUITests (one *.ukp file per lane) into per-lane tables with
the pass verdicts of docs/design/UIKIT-pan.md §4. usage: scripts/uikitpan-table.py <dir-with-*.ukp> [--summary] > tables.md"""
import glob
import os
import sys
from collections import defaultdict


def parse(line):
    d = {}
    for kv in line.strip().split(" "):
        if "=" in kv:
            k, v = kv.split("=", 1)
            d[k] = v
    return d


def f(d, k, default=0.0):
    try:
        return float(d.get(k, default))
    except ValueError:
        return default


def rows_by_q(paths):
    out = defaultdict(list)
    for p in sorted(paths):
        lane = os.path.basename(p)[:-4]
        for line in open(p, errors="replace"):
            i = line.find("UKP q=")
            if i < 0:
                continue
            d = parse(line[i + 4:])
            d["lane"] = lane
            out[d["q"]].append(d)
    return out


def table(head, rows):
    if not rows:
        print("(no rows)\n")
        return
    print("| " + " | ".join(head) + " |")
    print("|" + "---|" * len(head))
    for r in rows:
        print("| " + " | ".join(str(c) for c in r) + " |")
    print()


def vertical(q, rows, pager):
    base = {(r["lane"], r["row"]): r for r in rows if r["variant"] == "none"}
    out = []
    for r in rows:
        b = base.get((r["lane"], r["row"]))
        same = b is not None and (r.get("det"), r.get("gone")) == (b.get("det"), b.get("gone"))
        xs = f(r, "offXMax") - f(r, "offXMin") if r.get("offXMax", "-") != "-" else 0.0
        ok = same and (xs <= 0.5 or not pager)
        verdict = "base" if r["variant"] == "none" else ("PASS" if ok else "FAIL")
        top = f"{r.get('topMin')}..{r.get('topMax')}"
        recv = "/".join(r.get(f"uikitpan.pager.receive.{k}", "0") for k in ("desc.yes", "desc.no", "root.yes", "root.no"))
        out.append([r["lane"], r["variant"], r["row"], r.get("det"), r.get("gone"), top, f"{xs:.1f}",
                    r.get("uikitpan.pager.shouldBegin.no", "0"), r.get("uikitpan.began", "0"), recv, verdict])
    table(["lane", "variant", "row", "det after", "dismissed", "top min..max", "pager x span", "pager shouldBegin no", "began",
           "window receive desc y/n, root y/n", "verdict"], out)


def q2(rows):
    out = []
    expect = {"P0": 1, "ZMid": 1, "ZEdge": 2}
    for r in rows:
        if "skipped" in r:
            out.append([r["lane"], r["start"], r["v"], r["pos"], r["vel"], "-", "-", "-", "-", "-", "skipped"])
            continue
        zx = f(r, "zxMax") - f(r, "zxMin")
        page = int(f(r, "page", -1))
        fixed = r.get("topMin") == r.get("topMax")
        moved_ok = page == expect[r["pos"]] and ((zx > 0.5) if r["pos"] == "ZMid" else (zx <= 0.5))
        ok = moved_ok and fixed and r.get("gone") == "0" and r.get("bothX") == "0"
        out.append([r["lane"], r["start"], r["v"], r["pos"], r["vel"], page, f"{zx:.0f}", f"{r.get('topMin')}..{r.get('topMax')}",
                    r.get("gone"), r.get("bothX"), "PASS" if ok else "FAIL"])
    table(["lane", "detent", "V", "position", "speed", "page after", "zoomer x span", "top min..max", "dismissed", "bothX", "verdict"], out)


def q3(rows):
    base_of = {"carousel": "nativeCarousel", "list": "nativeList", "zoomer": "plain"}
    base = {(r["lane"], r["target"], r["deg"], r["speed"]): r["mover"] for r in rows if r["v"] == "-"}
    summary = defaultdict(lambda: [0, 0, []])
    detail = []
    for r in rows:
        key = (r["lane"], r["target"], r["v"])
        if r["v"] == "-":
            summary[key][1] += 1
            summary[key][2].append(f"{r['deg']}°/{r['speed']}:{r['mover']}")
            continue
        b = base.get((r["lane"], base_of[r["target"]], r["deg"], r["speed"]))
        ok = b is not None and r["mover"] == b and r["mover"] in ("P", "T", "-") and r.get("bothPT", "0") == "0"
        if b == "-" and r["mover"] != "-":
            ok = False
        summary[key][0] += 1 if ok else 0
        summary[key][1] += 1
        if not ok:
            summary[key][2].append(f"{r['deg']}°/{r['speed']}:{r['mover']}≠{b}")
        detail.append(r)
    out = []
    for (lane, target, v), (p, n, notes) in sorted(summary.items()):
        verdict = "base" if v == "-" else ("PASS" if p == n else f"FAIL {n - p}/{n}")
        out.append([lane, target, v, f"{p}/{n}" if v != "-" else "-", verdict, " ".join(notes)])
    table(["lane", "target", "V", "rows = native", "verdict", "movers (baseline) / mismatches deg/speed:ours≠native"], out)


def sweep(rows):
    """Q3e: who moves per angle (deg from horizontal), for UIKit's own nested scroll views and the probe with a boundary."""
    groups = defaultdict(dict)
    for r in rows:
        groups[(r["lane"], r["target"], r["v"], r.get("extra", "-"))][(int(r["deg"]), r["speed"])] = r["mover"]
    degs = sorted({k[0] for g in groups.values() for k in g})
    head = ["lane", "target", "V", "extra"] + [f"{d}°" for d in degs]
    out = []
    for (lane, target, v, extra), g in sorted(groups.items()):
        out.append([lane, target, v, extra] + ["/".join(g.get((d, sp), "?") for sp in sorted({k[1] for k in g}, key=int)) for d in degs])
    print("movers per angle, slow/fast (P page, T target, - none)\n")
    table(head, out)


def simple(rows, keys):
    table(["lane"] + keys, [[r["lane"]] + [r.get(k, "-") for k in keys] for r in rows])


def q7(rows):
    """Control values are per launch (cumulative over its rows): a row's effect is its change from the previous row."""
    def ok(r, p):
        xs, ys = f(r, "controls.x.span"), f(r, "controls.y.span")
        still = xs <= 0.5 and ys <= 0.5
        d = lambda k: r.get(k) != p.get(k)
        n = r["row"]
        if n == "buttonTap": return d("ctlB") and still
        if n == "buttonDrag": return not d("ctlB") and xs > 0.5
        if n == "sliderDrag": return d("ctlS") and xs <= 0.5
        if n == "toggleTap": return d("ctlT") and still
        if n == "wheelDrag": return d("ctlW") and ys <= 0.5
        if n == "stepperTap": return d("ctlSt") and still
        if n == "segmentTap": return d("ctlSeg") and still
        if n == "emptyDrag": return xs > 0.5
        if n == "textTapType": return r.get("ctlX") == "a" and still
        return r.get("uikitpan.began", "0") == "0" and still  # bars, header, disabled
    out, prev = [], {}
    for r in rows:
        key = (r["lane"], r["v"])
        p = prev.get(key, {"ctlB": "0", "ctlS": "0.50", "ctlT": "0", "ctlW": "10", "ctlSt": "0", "ctlSeg": "0"})
        if r["row"].startswith("disabled"):
            p = {"ctlB": "0", "ctlS": "0.50", "ctlT": "0", "ctlW": "10", "ctlSt": "0", "ctlSeg": "0"}
        changed = " ".join(k[3:] for k in ("ctlB", "ctlS", "ctlT", "ctlW", "ctlSt", "ctlSeg") if r.get(k) != p.get(k)) or "-"
        out.append([r["lane"], r["v"], r["row"], changed, r.get("ctlX"), r.get("controls.x.span"), r.get("controls.y.span"),
                    r.get("uikitpan.began", "0"), "PASS" if ok(r, p) else "FAIL"])
        prev[key] = r
    table(["lane", "V", "row", "controls changed", "text", "x span", "y span", "pan began", "verdict"], out)


def q9(rows):
    out = []
    for r in rows:
        ok = f(r, "carousel.x.span", 99) == 0 and r.get("uikitpan.carousel.began", "0") == "0"
        out.append([r["lane"], r["cover"], r.get("carousel.x.span"), r.get("uikitpan.carousel.began", "0"),
                    "/".join(r.get(f"uikitpan.carousel.receive.{k}", "0") for k in ("desc.yes", "desc.no", "root.yes", "root.no")),
                    r.get("uikitpan.pager.began", "0"), "PASS" if ok else "FAIL"])
    table(["lane", "cover", "carousel x span", "carousel began", "window receive desc yes/no, root yes/no", "pager began", "verdict"], out)


def lane_os(rows):
    return {r["lane"]: r["os"] for r in rows}


def summary(allrows):
    """One condensed per-lane table per Q (the handoff's); the detailed tables come from the default mode."""
    def g(q):
        return allrows.get(q, [])
    os_of = {}
    for rs in allrows.values():
        os_of.update(lane_os(rs))
    lanes = lambda rs: sorted({r["lane"] for r in rs}, key=lambda l: [int(x) for x in os_of.get(l, "0").split(".")] + [l])

    def vert(q, pager):
        rs = g(q)
        base = {(r["lane"], r["row"]): (r.get("det"), r.get("gone")) for r in rs if r["variant"] == "none"}
        variants = sorted({r["variant"] for r in rs if r["variant"] != "none"})
        out = []
        for l in lanes(rs):
            row = [l, os_of[l]]
            for v in variants:
                vr = [r for r in rs if r["lane"] == l and r["variant"] == v]
                ok = sum(1 for r in vr if base.get((l, r["row"])) == (r.get("det"), r.get("gone"))
                         and (not pager or f(r, "offXMax") - f(r, "offXMin") <= 0.5))
                row.append(f"{ok}/{len(vr)}" + ("" if ok == len(vr) else " FAIL"))
            if pager:
                row.append(max((int(r.get("bothX", "0")) for r in rs if r["lane"] == l and r.get("bothX", "-") != "-"), default=0))
            out.append(row)
        table(["lane", "iOS"] + [f"{v} = P5 outcome" for v in variants] + (["max bothX"] if pager else []), out)

    print("### Q1 (S, vertical drags declined: expand / collapse / dismiss as the no-gesture pane P5, pager x span ≤ 0.5)\n")
    vert("Q1", True)
    print("### Q2 / Q8 (S, horizontal: page +1, zoomer pans mid-content, pages at its edge; top fixed, not dismissed, bothX 0)\n")
    rs, out = g("Q2"), []
    expect = {"P0": 1, "ZMid": 1, "ZEdge": 2}
    for l in lanes(rs):
        row = [l, os_of[l]]
        for v in ("on", "off"):
            vr = [r for r in rs if r["lane"] == l and r["v"] == v and "skipped" not in r]
            ok = [r for r in vr if int(f(r, "page", -1)) == expect[r["pos"]] and ((f(r, "zxMax") - f(r, "zxMin") > 0.5) == (r["pos"] == "ZMid"))
                  and r.get("topMin") == r.get("topMax") and r.get("gone") == "0" and r.get("bothX") == "0"]
            bad = [f"{r['start']}/{r['pos']}/{r['vel']}" for r in vr if r not in ok]
            row.append(f"{len(ok)}/{len(vr)}" + (" FAIL " + " ".join(bad) if bad else ""))
        row.append(max((int(r.get("bothX", "0")) for r in rs if r["lane"] == l), default=0))
        out.append(row)
    table(["lane", "iOS", "V on", "V off", "max bothX"], out)
    print("### Q3 (N, rows matching UIKit's own nested scroll views; 12 rows = 0/40/50/90° × 150/600/2500 pt/s)\n")
    rs = g("Q3")
    base_of = {"carousel": "nativeCarousel", "list": "nativeList", "zoomer": "plain"}
    base = {(r["lane"], r["target"], r["deg"], r["speed"]): r["mover"] for r in rs if r["v"] == "-"}
    out = []
    for l in lanes(rs):
        for t in ("carousel", "list", "zoomer"):
            row = [l, os_of[l], t]
            for v in ("on", "off", "axis"):
                vr = [r for r in rs if r["lane"] == l and r["target"] == t and r["v"] == v]
                ok = [r for r in vr if r["mover"] == base.get((l, base_of[t], r["deg"], r["speed"])) and r.get("bothPT", "0") == "0"]
                both = sum(1 for r in vr if r["mover"] == "PT")
                miss = sorted({f"{r['deg']}°" for r in vr if r not in ok})
                row.append(f"{len(ok)}/{len(vr)}" + (f" (double {both})" if both else "") + (" ≠ " + ",".join(miss) if miss else ""))
            out.append(row)
    table(["lane", "iOS", "target", "V on", "V off", "V axis"], out)
    print("### Q4 (`bounds(of: .scrollView(axis:))` inside a ZTron viewport: S any, V vertical, H horizontal)\n")
    rs = g("Q4")
    parents = []
    for r in rs:
        if r["parent"] not in parents:
            parents.append(r["parent"])
    table(["lane", "iOS"] + parents, [[l, os_of[l]] + [next((r["det"] + ("" if r["det"] == r["detGR"] else "/GR " + r["detGR"]) for r in rs
                                                        if r["lane"] == l and r["parent"] == p), "-") for p in parents] for l in lanes(rs)])
    print("### Q5 (finger travel at the first shouldBegin, its translation and decision source; lift order; second touch; reset)\n")
    rs, out = g("Q5"), []
    for l in lanes(rs):
        lr = [r for r in rs if r["lane"] == l]
        drags = [r for r in lr if r["row"] == "drag"]
        trav = " ".join(f"{r['deg']}°/{r['speed']}:{r.get('fsbD', '-')}→{r.get('fsb', '-')}{r.get('fsbSrc', '')}" for r in drags)
        axes = " ".join(("h" if r.get("uikitpan.axis.h") else "v" if r.get("uikitpan.axis.v") else "?") for r in drags)
        lifts = sorted({r.get("lift", "-") for r in drags})
        pinch = next((r for r in lr if r["row"] == "pinch"), {})
        resets = [r for r in lr if r["row"] == "resetAfter1"]
        rst = " ".join(f"{r['speed']}:b{r.get('uikitpan.began', '0')}/x{r.get('uikitpan.cancelled', '0')}"
                       f"(s{r.get('uikitpan.cancelled.sync', '0')}a{r.get('uikitpan.cancelled.async', '0')})/e{r.get('uikitpan.ended', '0')}" for r in resets)
        out.append([l, os_of[l], trav, axes, ",".join(lifts), f"maxT {pinch.get('maxT', '-')} began {pinch.get('uikitpan.began', '0')} "
                    f"reset {pinch.get('uikitpan.reset', '0')} cancelled {pinch.get('uikitpan.cancelled', '0')} pinch {pinch.get('pinch', '0')}", rst])
    table(["lane", "iOS", "deg/speed: travel→translation (src)", "axis decided", "lift order", "pinch (2 touches)",
           "reset after 1 change: began/cancelled(sync,async)/ended"], out)
    print("### Q6 (the library's MagnifyGesture / SpatialTapGesture(count: 2) alone in a sheet: outcome = P5)\n")
    vert("Q6", False)
    print("### Q7 (controls on the UIKit path; per V: rows passing, failing rows)\n")
    rs = g("Q7")
    import io, contextlib
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        q7(rs)
    verdict = {}
    for line in buf.getvalue().splitlines()[2:]:
        c = [x.strip() for x in line.strip("|").split("|")]
        if len(c) > 8:
            verdict.setdefault((c[0], c[1]), []).append((c[2], c[-1]))
    out = []
    for (l, v), items in sorted(verdict.items(), key=lambda kv: (os_of.get(kv[0][0], ""), kv[0])):
        bad = [n for n, x in items if x != "PASS"]
        out.append([l, os_of.get(l, "?"), v, f"{len(items) - len(bad)}/{len(items)}", " ".join(bad) or "-"])
    table(["lane", "iOS", "V", "rows passing", "failing rows"], out)
    print("### Q9 (a sheet over an N carousel: carousel x span 0 and its pan never begins)\n")
    rs = g("Q9")
    table(["lane", "iOS", "cover", "carousel x span", "carousel began", "verdict"],
          [[r["lane"], r["os"], r["cover"], r.get("carousel.x.span"), r.get("uikitpan.carousel.began", "0"),
            "PASS" if f(r, "carousel.x.span", 99) == 0 and r.get("uikitpan.carousel.began", "0") == "0" else "FAIL"] for r in rs])


def main():
    rows = rows_by_q(glob.glob(os.path.join(sys.argv[1], "*.ukp")))
    if len(sys.argv) > 2 and sys.argv[2] == "--summary":
        summary(rows)
        return
    for q in sorted(rows):
        print(f"### {q}\n")
        r = rows[q]
        if q in ("Q1", "Q6"):
            vertical(q, r, pager=q == "Q1")
        elif q == "Q2":
            q2(r)
        elif q == "Q3":
            q3(r)
        elif q == "Q3e":
            sweep(r)
        elif q == "Q4":
            simple(r, ["parent", "det", "detGR"])
        elif q == "Q5":
            simple(r, ["row", "deg", "speed", "fsb", "fsbD", "fsbV", "fsbSrc", "fsbXY", "bt", "btD", "lift", "maxT", "uikitpan.axis.h", "uikitpan.axis.v",
                       "uikitpan.began", "uikitpan.ended", "uikitpan.cancelled", "uikitpan.cancelled.sync", "uikitpan.cancelled.async",
                       "uikitpan.reset", "uikitpan.reset.state0", "uikitpan.reset.state1", "uikitpan.reset.state2", "uikitpan.secondFinger",
                       "uikitpan.secondFinger.end", "uikitpan.shouldBegin.yes", "uikitpan.shouldBegin.no", "pinch"])
        elif q == "Q7":
            q7(r)
        elif q == "Q9":
            q9(r)


main()
