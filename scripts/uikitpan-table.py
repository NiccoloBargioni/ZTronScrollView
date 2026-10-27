#!/usr/bin/env python3
"""UIKITPAN-s1: turns the `UKP q=...` lines of UIKitPanProbeUITests (one *.ukp file per lane) into per-lane tables with
the pass verdicts of docs/design/UIKIT-pan.md §4. usage: scripts/uikitpan-table.py <dir-with-*.ukp> > tables.md"""
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


def main():
    rows = rows_by_q(glob.glob(os.path.join(sys.argv[1], "*.ukp")))
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
