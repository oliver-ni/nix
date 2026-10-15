"""Manga requests for jellyfin-client: search Suwayomi's sources, add a title.

The client's Requests tab reaches this at /suwayomi on its own origin, behind
Caddy's check for a Seerr session. Suwayomi's own API can also delete manga,
install extensions and change settings, so it stays on loopback and only these
routes are passed through:

  GET  /search?q=       titles matching q in each of SOURCES
  GET  /requests        the library, newest first, with chapter counts
  POST /request/<id>    add a title to the library and download every chapter
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
PER_SOURCE = 5

MANGA = "id title inLibrary source { name }"


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
    return [title(m) for m in data["fetchSourceManga"]["mangas"][:PER_SOURCE]]


def search(q):
    with ThreadPoolExecutor(len(SOURCES)) as pool:
        return [t for ts in pool.map(lambda s: search_source(s, q), SOURCES) for t in ts]


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


def request(manga_id):
    # Chapters first: a source that fails here leaves nothing half-added.
    data = graphql(
        "mutation($id: Int!) { fetchMangaAndChapters(input: {id: $id, fetchManga: true, fetchChapters: true}) { chapters { id } } }",
        id=manga_id,
    )
    graphql("mutation($id: Int!) { updateManga(input: {id: $id, patch: {inLibrary: true}}) { manga { id } } }", id=manga_id)
    graphql(
        "mutation($ids: [Int!]!) { enqueueChapterDownloads(input: {ids: $ids}) { clientMutationId } }",
        ids=[c["id"] for c in data["fetchMangaAndChapters"]["chapters"]],
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
        elif url.path == "/requests":
            self.respond(lambda: self.json(library()))
        elif m := re.fullmatch(r"/thumbnail/(\d+)", url.path):
            self.respond(lambda: self.thumbnail(int(m[1])))
        else:
            self.send_error(404)

    def do_POST(self):
        if m := re.fullmatch(r"/request/(\d+)", self.path):
            self.respond(lambda: (request(int(m[1])), self.send_response(204), self.end_headers()))
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
