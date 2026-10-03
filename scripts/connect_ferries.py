"""Add connector ways between nearby ferry routes.

Ferry lines in OSM rarely share nodes, even when they call at the same port.
OSRM snaps each waypoint to the single nearest ferry way, so a waypoint at a
port often lands on a local ferry that is not connected to the line the user
actually took, and the route fails with NoRoute.

This script links every port to the nearest node of each other ferry way
within RADIUS metres, using a slow connector way tagged
route=ferry + trainlog:connector=yes (see profiles/ferry.lua).

A port is a ferry way endpoint that is either a dead end or tagged as a ferry
terminal. Untagged endpoints shared by several ways are skipped: they are
usually just where a line is split at sea, and linking them would let routes
jump between lines that merely pass close to each other.

Links are made per way rather than per connected network: two lines that
only meet far out at sea count as one network, but a port must still get a
link to each of their quays.

Usage: connect_ferries.py <input.opl> <output.opl> [radius_m]
Only uses the standard library so it can run in python:*-slim.
"""
import math
import re
import sys
from collections import defaultdict

CONNECTOR_ID_BASE = 10**15
PORT_TAGS = ("amenity=ferry_terminal", "public_transport=", "ferry=yes")


def parse(path):
    nodes, ways, port_tagged = {}, {}, set()
    way_re = re.compile(r" N(\S*)")
    for line in open(path, encoding="utf-8"):
        kind = line[0]
        if kind == "n":
            parts = line.split()
            nid = int(parts[0][1:])
            x = next((p[1:] for p in parts if p.startswith("x")), "")
            y = next((p[1:] for p in parts if p.startswith("y")), "")
            if x and y:
                nodes[nid] = (float(x), float(y))
            tags = next((p[1:] for p in parts if p.startswith("T")), "")
            if any(t in tags for t in PORT_TAGS):
                port_tagged.add(nid)
        elif kind == "w":
            m = way_re.search(line)
            refs = [int(n[1:]) for n in m.group(1).split(",") if n] if m else []
            ways[int(line.split()[0][1:])] = refs
    return nodes, ways, port_tagged


def dist(a, b):
    lat1, lat2 = math.radians(a[1]), math.radians(b[1])
    dx = math.radians(b[0] - a[0]) * math.cos((lat1 + lat2) / 2)
    return 6371000 * math.hypot(dx, lat2 - lat1)


def main():
    src, dst = sys.argv[1], sys.argv[2]
    radius = float(sys.argv[3]) if len(sys.argv) > 3 else 1000
    nodes, ways, port_tagged = parse(src)

    # Grid index of every ferry node, cell size ~radius in latitude degrees
    cell = radius / 111000
    grid = defaultdict(list)
    node_ways = defaultdict(set)
    for wid, refs in ways.items():
        for n in refs:
            node_ways[n].add(wid)
            if n in nodes:
                x, y = nodes[n]
                grid[(int(x // cell), int(y // cell))].append((n, wid))

    ports = {
        r
        for refs in ways.values() if refs
        for r in (refs[0], refs[-1])
        if r in nodes and (len(node_ways[r]) == 1 or r in port_tagged)
    }
    pairs = set()
    for a in ports:
        pa = nodes[a]
        # Widen the longitude search at high latitudes
        span = int(math.ceil(1 / max(math.cos(math.radians(pa[1])), 0.01)))
        gx, gy = int(pa[0] // cell), int(pa[1] // cell)
        best = {}
        for ix in range(gx - span, gx + span + 1):
            for iy in range(gy - 1, gy + 2):
                for b, wb in grid.get((ix, iy), ()):
                    if wb in node_ways[a]:
                        continue
                    d = dist(pa, nodes[b])
                    if d <= radius and (wb not in best or d < best[wb][0]):
                        best[wb] = (d, b)
        for _, b in best.values():
            pairs.add((min(a, b), max(a, b)))

    with open(dst, "w", encoding="utf-8") as out:
        for i, (a, b) in enumerate(sorted(pairs)):
            out.write(
                f"w{CONNECTOR_ID_BASE + i} v1 dV c0 t2000-01-01T00:00:00Z i0 u "
                f"Troute=ferry,trainlog:connector=yes Nn{a},n{b}\n"
            )
    print(f"connect_ferries: {len(ways)} ways, {len(ports)} ports, {len(pairs)} connectors within {radius:g} m")


if __name__ == "__main__":
    main()
