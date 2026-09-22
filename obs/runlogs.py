#!/usr/bin/env python3
"""Read-only browser for training text logs. Serves only files under given roots."""
from __future__ import annotations

import argparse
import html
import mimetypes
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, quote, unquote, urlparse


TEXT_SUFFIXES = {
    ".log",
    ".txt",
    ".out",
    ".err",
    ".json",
    ".jsonl",
    ".yaml",
    ".yml",
    ".md",
    ".csv",
}
MAX_BYTES = 2 * 1024 * 1024


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8081)
    parser.add_argument("--bind", default="0.0.0.0")
    parser.add_argument(
        "--roots",
        default="/logs",
        help="Colon-separated directories to walk. Only these trees are served.",
    )
    return parser.parse_args()


def discover_roots(raw: str) -> list[Path]:
    roots: list[Path] = []
    for item in raw.split(":"):
        item = item.strip()
        if not item:
            continue
        path = Path(item)
        if path.is_dir():
            roots.append(path.resolve())
            continue
        parent = path
        if parent.exists():
            roots.append(parent.resolve())
    return roots


def is_within(path: Path, roots: list[Path]) -> bool:
    resolved = path.resolve()
    for root in roots:
        try:
            resolved.relative_to(root)
            return True
        except ValueError:
            continue
    return False


def looks_like_log(path: Path) -> bool:
    name = path.name.lower()
    if name.endswith(tuple(TEXT_SUFFIXES)):
        return True
    return "log" in name


def collect_files(roots: list[Path]) -> list[Path]:
    files: list[Path] = []
    for root in roots:
        if not root.exists():
            continue
        for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
            dirnames[:] = [d for d in dirnames if not d.startswith(".")]
            current = Path(dirpath)
            # Prefer directories named logs, but still list text files anywhere under the root.
            for filename in filenames:
                path = current / filename
                if not path.is_file():
                    continue
                if looks_like_log(path) or current.name in {"logs", "output"}:
                    files.append(path)
    files.sort(key=lambda p: p.stat().st_mtime if p.exists() else 0, reverse=True)
    return files


def page(title: str, body: str) -> bytes:
    doc = f"""<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{html.escape(title)}</title>
  <style>
    body {{ font-family: ui-sans-serif, system-ui, sans-serif; margin: 24px; background: #111; color: #eee; }}
    a {{ color: #8ec8ff; }}
    table {{ border-collapse: collapse; width: 100%; }}
    th, td {{ text-align: left; padding: 6px 10px; border-bottom: 1px solid #333; }}
    pre {{ background: #1b1b1b; padding: 16px; overflow: auto; white-space: pre-wrap; }}
    .muted {{ color: #999; }}
  </style>
</head>
<body>
{body}
</body>
</html>
"""
    return doc.encode("utf-8")


class Handler(BaseHTTPRequestHandler):
    roots: list[Path] = []

    def log_message(self, fmt: str, *args) -> None:
        print(f"runlogs: {self.address_string()} {fmt % args}", flush=True)

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        if parsed.path in {"/", "/index.html"}:
            self._index()
            return
        if parsed.path == "/view":
            self._view(parse_qs(parsed.query))
            return
        self.send_error(404, "not found")

    def _index(self) -> None:
        files = collect_files(self.roots)
        rows = []
        if not files:
            rows.append('<tr><td class="muted" colspan="3">还没有日志。训练脚本把 train.log 写到 $PERSON_HOME/logs 或项目下 logs/。</td></tr>')
        for path in files[:500]:
            rel = self._display(path)
            try:
                size = path.stat().st_size
                mtime = __import__("datetime").datetime.fromtimestamp(path.stat().st_mtime).isoformat(sep=" ", timespec="seconds")
            except OSError:
                size = 0
                mtime = ""
            href = "/view?path=" + quote(str(path), safe="")
            rows.append(
                f'<tr><td><a href="{href}">{html.escape(rel)}</a></td>'
                f'<td class="muted">{size}</td><td class="muted">{html.escape(mtime)}</td></tr>'
            )
        body = (
            "<h1>Run logs</h1>"
            '<p class="muted">只读。路径限制在挂进来的 logs/ 目录。</p>'
            "<table><thead><tr><th>文件</th><th>字节</th><th>修改时间</th></tr></thead>"
            f"<tbody>{''.join(rows)}</tbody></table>"
        )
        data = page("Run logs", body)
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _view(self, query: dict[str, list[str]]) -> None:
        raw = unquote((query.get("path") or [""])[0])
        if not raw:
            self.send_error(400, "missing path")
            return
        path = Path(raw)
        if not is_within(path, self.roots) or not path.is_file() or not looks_like_log(path):
            self.send_error(403, "path not allowed")
            return
        try:
            data = path.read_bytes()
        except OSError as exc:
            self.send_error(500, str(exc))
            return
        truncated = ""
        if len(data) > MAX_BYTES:
            data = data[-MAX_BYTES:]
            truncated = f"<p class='muted'>只显示末尾 {MAX_BYTES} 字节。</p>"
        text = data.decode("utf-8", errors="replace")
        mime, _ = mimetypes.guess_type(path.name)
        if mime and not mime.startswith("text") and path.suffix.lower() not in TEXT_SUFFIXES:
            self.send_error(403, "not a text log")
            return
        body = (
            f"<p><a href='/'>返回列表</a></p><h1>{html.escape(self._display(path))}</h1>"
            f"{truncated}<pre>{html.escape(text)}</pre>"
        )
        payload = page(path.name, body)
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def _display(self, path: Path) -> str:
        for root in self.roots:
            try:
                return str(path.resolve().relative_to(root))
            except ValueError:
                continue
        return str(path)


def main() -> int:
    args = parse_args()
    roots = discover_roots(args.roots)
    if not roots:
        # Still serve an empty index so Homer has a live target.
        Path("/logs/home").mkdir(parents=True, exist_ok=True)
        roots = [Path("/logs/home")]
    Handler.roots = roots
    server = ThreadingHTTPServer((args.bind, args.port), Handler)
    print(f"runlogs listening on {args.bind}:{args.port} roots={roots}", flush=True)
    server.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
