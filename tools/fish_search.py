"""Search the Fish Audio voice library (prints id | title | tags | uses | description).

Usage: python tools/fish_search.py [--title X] [--tag X] [--lang ko] [--n 30]
"""
import argparse
import json
import os
import sys
import urllib.parse
import urllib.request

ap = argparse.ArgumentParser()
ap.add_argument("--title", default="")
ap.add_argument("--tag", default="")
ap.add_argument("--lang", default="ko")
ap.add_argument("--n", type=int, default=30)
ap.add_argument("--page", type=int, default=1)
a = ap.parse_args()

key = os.environ.get("FISH_API_KEY")
if not key:
    sys.exit("FISH_API_KEY is not set")
params = {"page_size": a.n, "page_number": a.page, "sort_by": "task_count"}
if a.lang:
    params["language"] = a.lang
if a.title:
    params["title"] = a.title
if a.tag:
    params["tag"] = a.tag
url = "https://api.fish.audio/model?" + urllib.parse.urlencode(params)
req = urllib.request.Request(url, headers={"Authorization": f"Bearer {key}"})
with urllib.request.urlopen(req, timeout=60) as r:
    data = json.loads(r.read().decode("utf-8"))
sys.stdout.reconfigure(encoding="utf-8")
print("total", data.get("total"))
for it in data.get("items", []):
    desc = (it.get("description") or "").replace("\n", " ")[:70]
    print(f"{it['_id']} | {it.get('title')} | {','.join(it.get('tags') or [])[:70]} | {it.get('task_count')} | {desc}")
