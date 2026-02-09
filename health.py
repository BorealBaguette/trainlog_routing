import http.server
import json
import os
import glob
import socket
import threading
import time
from datetime import datetime, timezone

PORT = 5010
BASE = "/opt/host"
STATS_DIR = os.path.join(BASE, "output/stats")
KML_DIR = os.path.join(BASE, "kml")

SERVICES = {
    "train":     {"container": "train_routing",     "port": 5000, "output": "output/filtered_train.osrm"},
    "ferry":     {"container": "ferry_routing",     "port": 5001, "output": "output/filtered_ferry.osrm"},
    "bus":       {"container": "bus_routing",       "port": 5002, "output": "output/filtered_bus.osrm"},
    "aerialway": {"container": "aerialway_routing", "port": 5003, "output": "output/filtered_aerialway.osrm"},
}

# ---------------------------------------------------------------------------
# Docker via raw unix socket – zero pip dependencies
# ---------------------------------------------------------------------------
def _docker_get(path):
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(4)
        s.connect("/var/run/docker.sock")
        s.sendall(f"GET {path} HTTP/1.0\r\nHost: localhost\r\n\r\n".encode())
        buf = b""
        while True:
            chunk = s.recv(8192)
            if not chunk:
                break
            buf += chunk
        s.close()
        idx = buf.find(b"\r\n\r\n")
        if idx < 0:
            return None
        return json.loads(buf[idx + 4:])
    except Exception:
        return None

def get_all_containers():
    raw = _docker_get("/containers/json?all=1")
    if not raw:
        return []
    out = []
    for c in raw:
        names = [n.lstrip("/") for n in c.get("Names", [])]
        port_strs = []
        for p in c.get("Ports", []):
            pub, priv = p.get("PublicPort"), p.get("PrivatePort")
            if pub and priv:
                port_strs.append(f"{pub}->{priv}")
            elif priv:
                port_strs.append(str(priv))
        out.append({
            "name": names[0] if names else "?",
            "state": c.get("State", "unknown"),
            "status": c.get("Status", ""),
            "ports": ", ".join(port_strs),
        })
    return out

def get_container_state(name):
    r = _docker_get(f"/containers/{name}/json")
    if not r:
        return "not found"
    return r.get("State", {}).get("Status", "unknown")

# ---------------------------------------------------------------------------
# OSRM data age
# ---------------------------------------------------------------------------
def get_osrm_mtime(path):
    full = os.path.join(BASE, path)
    newest = None
    for f in glob.glob(full + "*"):
        mt = os.path.getmtime(f)
        if newest is None or mt > newest:
            newest = mt
    return newest

# ---------------------------------------------------------------------------
# Build phase (lock files written by Makefile)
# ---------------------------------------------------------------------------
def get_build_phase(rtype):
    lock = os.path.join(BASE, f"output/.{rtype}_building.lock")
    if not os.path.exists(lock):
        return None
    try:
        with open(lock) as f:
            t = f.read().strip()
            return t if t else "building"
    except Exception:
        return "building"

# ---------------------------------------------------------------------------
# Build stats
# ---------------------------------------------------------------------------
def get_stats(rtype):
    res = {"downloads": [], "filters": [], "merge": None, "osrm_build": None}
    for f in sorted(glob.glob(os.path.join(STATS_DIR, f"filter_{rtype}_*.json"))):
        try:
            with open(f) as fh:
                res["filters"].append(json.load(fh))
        except Exception:
            pass
    used = {d.get("file") for d in res["filters"]}
    for f in sorted(glob.glob(os.path.join(STATS_DIR, "download_*.json"))):
        try:
            with open(f) as fh:
                d = json.load(fh)
                if d.get("file") in used:
                    res["downloads"].append(d)
        except Exception:
            pass
    for step, pat in [("merge", f"merge_{rtype}.json"), ("osrm_build", f"osrm_{rtype}.json")]:
        p = os.path.join(STATS_DIR, pat)
        if os.path.exists(p):
            try:
                with open(p) as fh:
                    res[step] = json.load(fh)
            except Exception:
                pass
    total = sum(i.get("duration_s", 0) for i in res["downloads"] + res["filters"])
    for k in ("merge", "osrm_build"):
        if res[k]:
            total += res[k].get("duration_s", 0)
    res["total_duration_s"] = total
    return res

# ---------------------------------------------------------------------------
# Country lists
# ---------------------------------------------------------------------------
def _read_wanted(path):
    out = []
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#"):
                    out.append(line)
    except Exception:
        pass
    return out

def get_wanted_countries():
    common = _read_wanted(os.path.join(BASE, "countries.wanted"))
    bus = _read_wanted(os.path.join(BASE, "bus_countries.wanted"))
    return {"train": common, "ferry": common, "aerialway": common, "bus": bus}

# ---------------------------------------------------------------------------
# Assemble
# ---------------------------------------------------------------------------
def get_all_data():
    now = datetime.now(tz=timezone.utc)
    svcs = {}
    for name, svc in SERVICES.items():
        phase = get_build_phase(name)
        mtime = get_osrm_mtime(svc["output"])
        if mtime:
            mt = datetime.fromtimestamp(mtime, tz=timezone.utc)
            age = now - mt
            data = {"built": mt.isoformat(), "age_days": age.days, "age_hours": age.seconds // 3600}
        else:
            data = {"built": None, "age_days": None, "age_hours": None}
        svcs[name] = {
            "container": get_container_state(svc["container"]),
            "port": svc["port"],
            "data": data,
            "build_stats": get_stats(name),
            "build_phase": phase,
        }
    return {
        "checked_at": now.isoformat(),
        "services": svcs,
        "containers": get_all_containers(),
        "countries": get_wanted_countries(),
    }

# ---------------------------------------------------------------------------
# SSE
# ---------------------------------------------------------------------------
clients = []
clients_lock = threading.Lock()

def sse_loop():
    while True:
        time.sleep(5)
        try:
            msg = f"data: {json.dumps(get_all_data())}\n\n".encode()
            with clients_lock:
                dead = []
                for c in clients:
                    try:
                        c.wfile.write(msg)
                        c.wfile.flush()
                    except Exception:
                        dead.append(c)
                for d in dead:
                    clients.remove(d)
        except Exception as e:
            print(f"[sse] {e}")

# ---------------------------------------------------------------------------
# HTML
# ---------------------------------------------------------------------------
_html_cache = None

def get_html():
    global _html_cache
    if _html_cache is None:
        p = os.path.join(BASE, "health_ui.html")
        if os.path.exists(p):
            with open(p) as f:
                _html_cache = f.read()
        else:
            _html_cache = "<html><body><h1>health_ui.html not found</h1><p><a href='/api'>/api</a></p></body></html>"
    return _html_cache

# ---------------------------------------------------------------------------
# HTTP handler
# ---------------------------------------------------------------------------
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/api":
            body = json.dumps(get_all_data(), indent=2).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(body)

        elif self.path == "/stream":
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "keep-alive")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(f"data: {json.dumps(get_all_data())}\n\n".encode())
            self.wfile.flush()
            with clients_lock:
                clients.append(self)
            try:
                while True:
                    time.sleep(1)
            except Exception:
                pass
            finally:
                with clients_lock:
                    if self in clients:
                        clients.remove(self)

        elif self.path.startswith("/kml/") and self.path.endswith(".kml"):
            # Serve KML files: /kml/europe/france.kml -> kml/europe/france.kml
            rel = self.path[5:]  # strip /kml/
            fp = os.path.join(KML_DIR, rel)
            fp = os.path.realpath(fp)
            if fp.startswith(os.path.realpath(KML_DIR)) and os.path.isfile(fp):
                self.send_response(200)
                self.send_header("Content-Type", "application/vnd.google-earth.kml+xml")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.send_header("Cache-Control", "public, max-age=86400")
                self.end_headers()
                with open(fp, "rb") as f:
                    self.wfile.write(f.read())
            else:
                self.send_response(404)
                self.end_headers()
                self.wfile.write(b"KML not found")

        elif self.path == "/reload":
            global _html_cache
            _html_cache = None
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"OK - cache cleared")

        else:
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.end_headers()
            self.wfile.write(get_html().encode())

    def log_message(self, *a):
        pass

if __name__ == "__main__":
    threading.Thread(target=sse_loop, daemon=True).start()
    srv = http.server.HTTPServer(("0.0.0.0", PORT), Handler)
    print(f"Health monitor on :{PORT}")
    srv.serve_forever()
