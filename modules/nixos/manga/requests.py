"""Manga requests for jellyfin-client: search Suwayomi's sources, add a title.

The client's Requests tab reaches this at /suwayomi on its own origin, behind
Caddy's check for a Seerr session. Suwayomi's own API can also delete manga,
install extensions and change settings, so it stays on loopback and only these
routes are passed through:

  GET  /search?q=       titles matching q in each of SOURCES, closest match first;
                        a title on several is listed once, from the earliest in SOURCES
  GET  /manga/<id>      one title's details and chapter count
  GET  /requests        the library, newest first, with chapter counts
  POST /request/<id>    add a title to the library and download one version of every
                        chapter, from the group in the JSON body ({"group": name};
                        the most complete one when absent)
  GET  /thumbnail/<id>  cover art

Komga only looks for new files on its own schedule, so whenever Suwayomi has
downloaded more chapters (requests and library updates alike) this asks Komga
to scan its libraries, signed in as KOMGA_USER.
"""

import json
import os
import re
import sys
import threading
import time
from base64 import b64encode
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit
from urllib.request import Request, urlopen

SUWAYOMI_URL = os.environ["SUWAYOMI_URL"]
SOURCES = json.loads(os.environ["SOURCES"])
PORT = int(os.environ["PORT"])
KOMGA_URL = os.environ["KOMGA_URL"]
KOMGA_PASSWORD = (Path(os.environ["CREDENTIALS_DIRECTORY"]) / "komga-password").read_text().strip()
KOMGA_AUTH = "Basic " + b64encode(f"{os.environ['KOMGA_USER']}:{KOMGA_PASSWORD}".encode()).decode()
RESULTS = 8

MANGA = "id title inLibrary source { name }"
CHAPTER = "id chapterNumber scanlator"


def graphql(query, **variables):
    body = json.dumps({"query": query, "variables": variables}).encode()
    req = Request(f"{SUWAYOMI_URL}/api/graphql", body, {"Content-Type": "application/json"})
    with urlopen(req, timeout=60) as res:
        data = json.load(res)
    if data.get("errors"):
        raise RuntimeError(data["errors"][0]["message"])
    return data["data"]


def title(m):
    return {"id": m["id"], "title": m["title"], "source": m["source"]["name"], "inLibrary": m["inLibrary"]}


def search_source(source, q):
    try:
        data = graphql(
            "mutation($source: LongString!, $q: String) {"
            f" fetchSourceManga(input: {{source: $source, type: SEARCH, page: 1, query: $q}}) {{ mangas {{ {MANGA} }} }} }}",
            source=source,
            q=q,
        )
    except Exception as e:
        # One source being down shouldn't hide the other's results.
        print(f"search {source}: {e}", file=sys.stderr)
        return []
    return [title(m) for m in data["fetchSourceManga"]["mangas"]]


def search(q):
    with ThreadPoolExecutor(len(SOURCES)) as pool:
        results = [t for ts in pool.map(lambda s: search_source(s, q), SOURCES) for t in ts]
    seen = {}
    for t in sorted(results, key=lambda t: rank(t["title"], q)):
        seen.setdefault(normalize(t["title"]), t)
    return list(seen.values())[:RESULTS]


def normalize(title):
    return re.sub(r"\W", "", title.casefold())


def rank(title, q):
    """Exact matches, then titles starting with the query, then the rest; fan works last."""
    fan = re.search(r"doujinshi|anthology|\bdj\b", title, re.I) is not None
    t, q = normalize(title), normalize(q)
    return (fan, 0 if t == q else 1 if t.startswith(q) else 2)


def fetch_chapters(manga_id):
    """The source's chapter list; empty when it has none (MangaDex lists licensed titles bare)."""
    try:
        return graphql(
            f"mutation($id: Int!) {{ fetchChapters(input: {{mangaId: $id}}) {{ chapters {{ {CHAPTER} }} }} }}",
            id=manga_id,
        )["fetchChapters"]["chapters"]
    except RuntimeError as e:
        if "No chapters found" not in str(e):
            raise
        return []


def details(manga_id):
    m = graphql(
        f"mutation($id: Int!) {{ fetchManga(input: {{id: $id}}) {{ manga {{ {MANGA} author artist description genre status }} }} }}",
        id=manga_id,
    )["fetchManga"]["manga"]
    chapters = fetch_chapters(manga_id)
    groups = Counter(c["scanlator"] or m["source"]["name"] for c in chapters)
    people = f"{m['author'] or ''},{m['artist'] or ''}".split(",")
    return {
        **title(m),
        "authors": list(dict.fromkeys(p.strip() for p in people if p.strip())),
        # Sources append alternative names and tracker links after the summary.
        "description": re.split(r"\n\s*(?:Associated Name|Alternative Name|Tracker)", m["description"] or "")[0].strip(),
        "genres": m["genre"],
        "status": m["status"],
        "chapters": len({c["chapterNumber"] for c in chapters}),
        "groups": [{"name": g, "chapters": n} for g, n in groups.most_common()],
    }


def library():
    data = graphql(
        "{ mangas(condition: {inLibrary: true}, order: [{by: IN_LIBRARY_AT, byType: DESC}]) {"
        f" nodes {{ {MANGA} downloadCount chapters {{ totalCount }} }} }}"
        " downloadStatus { queue { chapter { mangaId } } } }"
    )
    queued = [d["chapter"]["mangaId"] for d in data["downloadStatus"]["queue"]]
    return [
        {
            **title(m),
            "chapters": m["chapters"]["totalCount"],
            "downloaded": m["downloadCount"],
            "queued": queued.count(m["id"]),
        }
        for m in data["mangas"]["nodes"]
    ]


def request(manga_id, group=None):
    """Add the title and download one version of each chapter: the chosen group's (the most
    complete one by default), with the other groups filling chapters it lacks."""
    # Chapters first: a source that fails here leaves nothing half-added.
    chapters = fetch_chapters(manga_id)
    if not chapters:
        raise ValueError("no chapters")
    group = group or Counter(c["scanlator"] for c in chapters).most_common(1)[0][0]
    chosen = {}
    for c in sorted(chapters, key=lambda c: c["scanlator"] != group):
        chosen.setdefault(c["chapterNumber"], c["id"])
    graphql("mutation($id: Int!) { updateManga(input: {id: $id, patch: {inLibrary: true}}) { manga { id } } }", id=manga_id)
    graphql(
        "mutation($ids: [Int!]!) { enqueueChapterDownloads(input: {ids: $ids}) { clientMutationId } }",
        ids=list(chosen.values()),
    )


def komga(path, method="GET"):
    req = Request(f"{KOMGA_URL}/api/v1{path}", method=method, headers={"Authorization": KOMGA_AUTH})
    with urlopen(req, timeout=60) as res:
        return json.load(res) if res.status == 200 else None


def scan_on_download():
    downloaded = None
    while True:
        try:
            nodes = graphql("{ mangas(condition: {inLibrary: true}) { nodes { downloadCount } } }")["mangas"]["nodes"]
            count = sum(m["downloadCount"] for m in nodes)
            if downloaded is not None and count > downloaded:
                for library in komga("/libraries"):
                    komga(f"/libraries/{library['id']}/scan", "POST")
            downloaded = count
        except Exception as e:
            print(f"scan: {e}", file=sys.stderr)
        time.sleep(60)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        url = urlsplit(self.path)
        if url.path == "/search":
            q = parse_qs(url.query).get("q", [""])[0].strip()
            self.respond(lambda: self.json(search(q) if q else []))
        elif m := re.fullmatch(r"/manga/(\d+)", url.path):
            self.respond(lambda: self.json(details(int(m[1]))))
        elif url.path == "/requests":
            self.respond(lambda: self.json(library()))
        elif m := re.fullmatch(r"/thumbnail/(\d+)", url.path):
            self.respond(lambda: self.thumbnail(int(m[1])))
        else:
            self.send_error(404)

    def do_POST(self):
        if m := re.fullmatch(r"/request/(\d+)", self.path):
            body = json.loads(self.rfile.read(int(self.headers.get("Content-Length") or 0)) or b"{}")
            self.respond(lambda: (request(int(m[1]), body.get("group")), self.send_response(204), self.end_headers()))
        else:
            self.send_error(404)

    def respond(self, handle):
        try:
            handle()
        except Exception as e:
            print(f"{self.command} {self.path}: {e}", file=sys.stderr)
            self.send_error(502)

    def json(self, value):
        body = json.dumps(value).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def thumbnail(self, manga_id):
        with urlopen(f"{SUWAYOMI_URL}/api/v1/manga/{manga_id}/thumbnail", timeout=60) as res:
            body = res.read()
            self.send_response(200)
            self.send_header("Content-Type", res.headers["Content-Type"])
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "max-age=86400")
            self.end_headers()
            self.wfile.write(body)


threading.Thread(target=scan_on_download, daemon=True).start()
ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
