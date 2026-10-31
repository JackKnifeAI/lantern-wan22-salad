# syntax=docker/dockerfile:1.28.0@sha256:bb22d9815c728170f72750f4e5b0d672e06176142e1d602c7e66c050100b7e5b
# Generated file: the build layout tool and fetch.py live with the build tooling; fetch.py is embedded below.
#
# SaladTechnologies' comfyui-api image (ComfyUI 0.12.3, CUDA 12.8) + ComfyUI-GGUF and its gguf wheel + a layout manifest; no model weights (engines download them at start).
# Carrier image: the Salad comfyui-api base + ComfyUI-GGUF @ 6ea2651e7df6, its gguf wheel and an empty layout manifest.
# No model weights: engines that use it download theirs at container start (SHA-256-checked).
# Every byte comes from its pinned upstream URL inside the build and is SHA-256-verified there (fetch.py below).
# GHCR caps a layer at 10 GB, so each large file is split into 2147483648-byte parts, one part per layer;
# the container reassembles them at start and re-checks the full-file SHA-256 (see /opt/lantern/manifest.json).
# The image stages are COPY --link / ADD --link only, so BuildKit never pulls the base image's layers; it pushes
# the new layers on top of them. CI builds one stage per step (see .github/workflows/build.yml); a plain
# `docker buildx build --target s03 --push` builds the same image in one go on a machine with ~90 GB free.

ARG BASE_IMAGE=ghcr.io/saladtechnologies/comfyui-api@sha256:597aa2699776bbc4c24da5b1319fed9908b21a8aa0c1b807d9e1f8a0f6ce0064
ARG FETCHER_IMAGE=python:3.13-alpine@sha256:7984cf56ceaddebe4fefeb75d64000b9f45d8b77b11a09b24524da6cdc3af0c8
ARG SOURCE_DATE_EPOCH=1793318400

# ------------------------------------------------------------------ fetch stages (not part of the image)
FROM ${FETCHER_IMAGE} AS fetcher
COPY <<"FETCH_PY_EOF" /fetch.py
#!/usr/bin/env python3
"""Build-time downloader for the weights-baked image. Runs inside `docker buildx build` (fetcher stage,
stdlib only, Python >= 3.8). Every byte that enters the image passes through here and is SHA-256-checked.

  verify  stream a whole file (nothing written); check size, SHA-256 and the head/tail probe hashes;
          write a plan with each fixed-size part's SHA-256
  part    download one part with an HTTP Range request; check it against the plan; write it under --out
  whole   download a whole file; check size, SHA-256 (and head/tail if given); write it under --out

Transient errors resume with a Range request from the last good byte (up to --retries attempts). A server
that ignores Range makes the download restart from zero with fresh hashes. Exit status 0 only when every
check passed; anything else fails the build step.
"""
import argparse
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

UA = "jackknife-baked-image-fetch/1.0 (+https://github.com)"
CHUNK = 8 * 1024 * 1024


class RangeIgnored(Exception):
    pass


def log(msg):
    sys.stdout.write("[fetch +%6.1fs] %s\n" % (time.monotonic() - T0, msg))
    sys.stdout.flush()


T0 = time.monotonic()


def open_range(url, start, end, timeout, whole=False):
    """GET bytes [start, end). A whole-file request from byte 0 is a plain GET; anything else is a Range
    request that must come back 206 with the right start, otherwise RangeIgnored."""
    headers = {"User-Agent": UA}
    if not (whole and start == 0):
        headers["Range"] = "bytes=%d-%d" % (start, end - 1)
    resp = urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=timeout)
    if "Range" in headers:
        cr = resp.headers.get("Content-Range") or ""
        if resp.status != 206 or not cr.startswith("bytes %d-" % start):
            resp.close()
            raise RangeIgnored("asked for bytes=%d-, got HTTP %s %r" % (start, resp.status, cr))
    return resp


def stream(url, start, end, sink, retries=8, timeout=60, label="", whole=False):
    """Feed bytes [start, end) of url to sink(chunk) in order, resuming after transient errors.
    sink.reset() is called if the server ignores Range so the caller can restart its hashes from `start`."""
    pos, attempt, last_log = start, 0, 0
    while pos < end:
        attempt += 1
        try:
            with open_range(url, pos, end, timeout, whole) as resp:
                while pos < end:
                    b = resp.read(min(CHUNK, end - pos))
                    if not b:
                        break
                    sink.feed(b)
                    pos += len(b)
                    if pos - last_log >= 1 << 30:
                        last_log = pos
                        log("%s %.2f / %.2f GB" % (label, (pos - start) / 1e9, (end - start) / 1e9))
            if pos < end:
                raise IOError("connection closed at byte %d of %d" % (pos, end))
        except RangeIgnored as exc:
            if pos == start:
                raise RuntimeError("%s: server does not honour Range: %s" % (label, exc))
            log("%s: %s; restarting from byte %d" % (label, exc, start))
            sink.reset()
            pos = start
        except (urllib.error.URLError, IOError, OSError, ValueError) as exc:
            if isinstance(exc, urllib.error.HTTPError) and exc.code in (401, 403, 404, 410):
                raise RuntimeError("%s: HTTP %s for %s" % (label, exc.code, url))
            if attempt >= retries:
                raise RuntimeError("%s: giving up after %d attempts at byte %d: %s" % (label, attempt, pos, exc))
            wait = min(30, 2 ** attempt)
            log("%s: %s; retry %d in %ds from byte %d" % (label, str(exc)[:200], attempt, wait, pos))
            time.sleep(wait)
    return attempt


class FileSink:
    """Hashes [start, end) of a file as it streams: full SHA-256, per-part SHA-256, head and tail probes.
    Optionally writes the bytes to a path."""

    def __init__(self, start, total, probe=0, part_bytes=0, out_path=None):
        self.start, self.total, self.probe, self.part_bytes, self.out_path = start, total, probe, part_bytes, out_path
        self.fh = None
        self.reset()

    def reset(self):
        self.pos = self.start
        self.full = hashlib.sha256()
        self.head = hashlib.sha256()
        self.tail = hashlib.sha256()
        self.parts = []
        self.part = hashlib.sha256() if self.part_bytes else None
        if self.out_path:
            if self.fh:
                self.fh.close()
            Path(self.out_path).parent.mkdir(parents=True, exist_ok=True)
            self.fh = open(self.out_path, "wb")

    def feed(self, b):
        p0 = self.pos
        self.full.update(b)
        if self.fh:
            self.fh.write(b)
        if self.probe:
            hp = min(self.probe, self.total)
            if p0 < hp:
                self.head.update(b[: hp - p0])
            tail0 = self.total - min(self.probe, self.total)
            if p0 + len(b) > tail0:
                self.tail.update(b[max(0, tail0 - p0):])
        if self.part_bytes:
            off = 0
            while off < len(b):
                in_part = (p0 + off) % self.part_bytes
                take = min(len(b) - off, self.part_bytes - in_part)
                self.part.update(b[off: off + take])
                off += take
                if (p0 + off) % self.part_bytes == 0 or p0 + off == self.total:
                    self.parts.append(self.part.hexdigest())
                    self.part = hashlib.sha256()
        self.pos += len(b)

    def close(self):
        if self.fh:
            self.fh.flush()
            os.fsync(self.fh.fileno())
            self.fh.close()
            self.fh = None


def check(cond, msg):
    if not cond:
        raise RuntimeError(msg)


def cmd_verify(a):
    sink = FileSink(0, a.bytes, probe=a.probe_bytes, part_bytes=a.part_bytes)
    attempts = stream(a.url, 0, a.bytes, sink, a.retries, a.timeout, a.id, whole=True)
    check(sink.pos == a.bytes, "%s: got %d bytes, expected %d" % (a.id, sink.pos, a.bytes))
    got = sink.full.hexdigest()
    check(got == a.sha256, "%s: SHA-256 %s != pinned %s" % (a.id, got, a.sha256))
    if a.head_sha256:
        check(sink.head.hexdigest() == a.head_sha256, "%s: head probe hash differs from baked.json" % a.id)
        check(sink.tail.hexdigest() == a.tail_sha256, "%s: tail probe hash differs from baked.json" % a.id)
    parts, off = [], 0
    for i, h in enumerate(sink.parts):
        n = min(a.part_bytes, a.bytes - off)
        parts.append({"index": i, "offset": off, "bytes": n, "sha256": h})
        off += n
    check(off == a.bytes, "%s: part bookkeeping is off (%d != %d)" % (a.id, off, a.bytes))
    plan = {"schema": "lantern.baked-parts.v1", "id": a.id, "url": a.url, "bytes": a.bytes, "sha256": got,
            "part_bytes": a.part_bytes, "probe_bytes": a.probe_bytes, "head_sha256": sink.head.hexdigest(),
            "tail_sha256": sink.tail.hexdigest(), "parts": parts}
    Path(a.out).parent.mkdir(parents=True, exist_ok=True)
    Path(a.out).write_text(json.dumps(plan, indent=1, sort_keys=True) + "\n")
    log("%s verified: %d B, sha256 %s, %d parts, %d attempt(s)" % (a.id, a.bytes, got, len(parts), attempts))


def safe_dest(out, dest):
    rel = Path(dest)
    check(not rel.is_absolute() and ".." not in rel.parts, "dest must be a relative path inside --out: %r" % dest)
    return Path(out) / rel


def finish_file(tmp, final, out=None, mtime=None):
    os.chmod(tmp, 0o644)
    os.replace(tmp, final)
    if mtime is not None:               # same bytes + same metadata -> same layer digest on every rebuild
        node = Path(final)
        while True:
            os.utime(node, (mtime, mtime))
            if out is None or node == Path(out) or Path(out) not in node.parents:
                break
            node = node.parent


def cmd_part(a):
    plan = json.loads(Path(a.plan).read_text())
    check(plan.get("schema") == "lantern.baked-parts.v1", "not a parts plan: %s" % a.plan)
    check(plan["url"] == a.url, "plan was made for a different URL")
    p = plan["parts"][a.index]
    check(p["index"] == a.index, "plan part index mismatch")
    final = safe_dest(a.out, a.dest)
    tmp = final.with_name(final.name + ".tmp")
    sink = FileSink(p["offset"], plan["bytes"], out_path=tmp)
    label = "%s part %02d" % (plan["id"], a.index)
    attempts = stream(a.url, p["offset"], p["offset"] + p["bytes"], sink, a.retries, a.timeout, label)
    sink.close()
    got = sink.full.hexdigest()
    check(sink.pos - p["offset"] == p["bytes"], "%s: short part" % label)
    check(os.path.getsize(tmp) == p["bytes"], "%s: file size differs from plan" % label)
    check(got == p["sha256"], "%s: SHA-256 %s != plan %s (the full file was verified in the verify stage)" % (label, got, p["sha256"]))
    finish_file(tmp, final, a.out, a.mtime)
    log("%s ok: %d B at offset %d, sha256 %s, %d attempt(s) -> %s" % (label, p["bytes"], p["offset"], got, attempts, a.dest))


def cmd_whole(a):
    final = safe_dest(a.out, a.dest)
    tmp = final.with_name(final.name + ".tmp")
    sink = FileSink(0, a.bytes, probe=a.probe_bytes, out_path=tmp)
    attempts = stream(a.url, 0, a.bytes, sink, a.retries, a.timeout, a.id, whole=True)
    sink.close()
    got = sink.full.hexdigest()
    check(sink.pos == a.bytes and os.path.getsize(tmp) == a.bytes, "%s: size %d != %d" % (a.id, sink.pos, a.bytes))
    check(got == a.sha256, "%s: SHA-256 %s != pinned %s" % (a.id, got, a.sha256))
    if a.head_sha256:
        check(sink.head.hexdigest() == a.head_sha256, "%s: head probe hash differs from baked.json" % a.id)
        check(sink.tail.hexdigest() == a.tail_sha256, "%s: tail probe hash differs from baked.json" % a.id)
    finish_file(tmp, final, a.out, a.mtime)
    log("%s ok: %d B, sha256 %s, %d attempt(s) -> %s" % (a.id, a.bytes, got, attempts, a.dest))


def parse(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("verify", "part", "whole"):
        p = sub.add_parser(name)
        p.add_argument("--url", required=True)
        p.add_argument("--retries", type=int, default=8)
        p.add_argument("--timeout", type=float, default=60)
        if name in ("verify", "whole"):
            p.add_argument("--id", required=True)
            p.add_argument("--bytes", type=int, required=True)
            p.add_argument("--sha256", required=True)
            p.add_argument("--probe-bytes", type=int, default=0)
            p.add_argument("--head-sha256")
            p.add_argument("--tail-sha256")
        if name == "verify":
            p.add_argument("--part-bytes", type=int, required=True)
            p.add_argument("--out", required=True, help="plan JSON path")
        else:
            p.add_argument("--dest", required=True, help="path inside the image, relative to /")
            p.add_argument("--out", required=True, help="stage output root")
            p.add_argument("--mtime", type=int, help="set this mtime on the file and its parents under --out")
        if name == "part":
            p.add_argument("--plan", required=True)
            p.add_argument("--index", type=int, required=True)
    a = ap.parse_args(argv)
    if getattr(a, "head_sha256", None) and not (a.probe_bytes and a.tail_sha256):
        ap.error("--head-sha256 needs --tail-sha256 and --probe-bytes")
    return a


def main(argv=None):
    a = parse(argv)
    try:
        {"verify": cmd_verify, "part": cmd_part, "whole": cmd_whole}[a.cmd](a)
    except RuntimeError as exc:
        log("FAILED: %s" % exc)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
FETCH_PY_EOF

FROM fetcher AS wheel-gguf
RUN python3 -I /fetch.py whole --id gguf-0.17.1-py3-none-any.whl --url "https://files.pythonhosted.org/packages/fc/31/6a93a887617ee7deeaa602ca3d02d1c12a6cb8a742a695de5d128f5fa46a/gguf-0.17.1-py3-none-any.whl" --bytes 96224 --sha256 7bc5aa7eeb1931f7d39b48fdc5b38fda6b294b9dca75cf607ac69557840a3943 \
      --dest opt/lantern/wheels/gguf-0.17.1-py3-none-any.whl --out /out --mtime 1793318400

# the layout manifest the container agent checks before trusting any baked byte
FROM fetcher AS file-manifest
COPY <<"MANIFEST_JSON_EOF" /out/opt/lantern/manifest.json
{
 "base_image": "ghcr.io/saladtechnologies/comfyui-api@sha256:597aa2699776bbc4c24da5b1319fed9908b21a8aa0c1b807d9e1f8a0f6ce0064",
 "custom_node": {
  "commit": "6ea2651e7df66d7585f6ffee804b20e92fb38b8a",
  "license": "Apache-2.0",
  "name": "ComfyUI-GGUF",
  "path": "opt/ComfyUI/custom_nodes/ComfyUI-GGUF",
  "repo": "https://github.com/city96/ComfyUI-GGUF"
 },
 "files": {},
 "image_tag": "still-carrier-gguf-v1",
 "part_bytes": 2147483648,
 "probe_bytes": 67108864,
 "probe_rule": "head_sha256 = SHA-256 of the first min(probe_bytes, size) bytes; tail_sha256 = SHA-256 of the last min(probe_bytes, size) bytes",
 "runtime_download": [],
 "schema": "lantern.baked-image.v1",
 "wheels": [
  {
   "bytes": 96224,
   "file": "gguf-0.17.1-py3-none-any.whl",
   "license": "MIT",
   "path": "opt/lantern/wheels/gguf-0.17.1-py3-none-any.whl",
   "requirement": "gguf==0.17.1",
   "sha256": "7bc5aa7eeb1931f7d39b48fdc5b38fda6b294b9dca75cf607ac69557840a3943",
   "url": "https://files.pythonhosted.org/packages/fc/31/6a93a887617ee7deeaa602ca3d02d1c12a6cb8a742a695de5d128f5fa46a/gguf-0.17.1-py3-none-any.whl"
  }
 ]
}
MANIFEST_JSON_EOF

# ------------------------------------------------------------------ image chain: one stage = one layer
FROM ${BASE_IMAGE} AS s00
ARG SOURCE_URL=https://github.com/OWNER/REPO
LABEL org.opencontainers.image.source="${SOURCE_URL}" \
      org.opencontainers.image.title="lantern-wan22-salad" \
      org.opencontainers.image.version="still-carrier-gguf-v1" \
      org.opencontainers.image.description="ComfyUI 0.12.3 + ComfyUI-GGUF (no weights; a few MB on top of the Salad base image)" \
      org.opencontainers.image.base.name="ghcr.io/saladtechnologies/comfyui-api@sha256:597aa2699776bbc4c24da5b1319fed9908b21a8aa0c1b807d9e1f8a0f6ce0064"

FROM s00 AS s01
# ComfyUI-GGUF at its pinned commit, .git kept so the container can verify HEAD
ADD --link --keep-git-dir=true --checksum=6ea2651e7df66d7585f6ffee804b20e92fb38b8a https://github.com/city96/ComfyUI-GGUF.git#6ea2651e7df66d7585f6ffee804b20e92fb38b8a /opt/ComfyUI/custom_nodes/ComfyUI-GGUF

FROM s01 AS s02
# gguf-0.17.1-py3-none-any.whl (installed offline, hash-locked, at container start)
COPY --link --from=wheel-gguf /out/ /

FROM s02 AS s03
COPY --link --from=file-manifest /out/ /
