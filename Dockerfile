# syntax=docker/dockerfile:1.28.0@sha256:bb22d9815c728170f72750f4e5b0d672e06176142e1d602c7e66c050100b7e5b
# Generated file: the build layout tool and fetch.py live with the build tooling; fetch.py is embedded below.
#
# Wan 2.2 I2V-A14B weights baked into SaladTechnologies' comfyui-api image (ComfyUI 0.12.3, CUDA 12.8) for SaladCloud.
# Baked: Wan2.2 I2V-A14B HighNoise + LowNoise GGUF Q6_K, Wan 2.1 VAE, lightx2v 4-step 1022 LoRAs (high + low),
# ComfyUI-GGUF @ 6ea2651e7df6 and its gguf wheel. NOT baked: the umt5 text encoder (downloaded at container start).
# Every byte comes from its pinned upstream URL inside the build and is SHA-256-verified there (fetch.py below).
# GHCR caps a layer at 10 GB, so each 12.0 GB GGUF is split into 2147483648-byte parts, one part per layer;
# the container reassembles them at start and re-checks the full-file SHA-256 (see /opt/lantern/manifest.json).
# The image stages are COPY --link / ADD --link only, so BuildKit never pulls the base image's layers; it pushes
# the new layers on top of them. CI builds one stage per step (see .github/workflows/build.yml); a plain
# `docker buildx build --target s18 --push` builds the same image in one go on a machine with ~90 GB free.

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

# unet_high_q6k: stream the whole file once (nothing stored): size, SHA-256, head/tail; record each part's SHA-256
FROM fetcher AS verify-unet-high-q6k-run
RUN python3 -I /fetch.py verify --id unet_high_q6k --url "https://huggingface.co/QuantStack/Wan2.2-I2V-A14B-GGUF/resolve/6c6717459277b9cd1f72579d78a0fd62a79e57dc/HighNoise/Wan2.2-I2V-A14B-HighNoise-Q6_K.gguf" --bytes 12003652096 --sha256 33ab8d99b5be745d2c939055f541d09108befe3467802fdbbf22ba8e4e62383c --probe-bytes 67108864 --head-sha256 fb21f6be82c032a58f824462310fccea01e27a404688668608b2e01d5a71c568 --tail-sha256 acf60bb5ab8dea4e693b12940ae6d3354de0b42229e923b31efc7c36f8c44775 \
      --part-bytes 2147483648 --out /verify/unet_high_q6k.json
FROM scratch AS verify-unet-high-q6k
COPY --from=verify-unet-high-q6k-run /verify/ /

FROM fetcher AS part-unet-high-q6k-00
RUN --mount=type=bind,from=verify-unet-high-q6k,target=/verify \
    python3 -I /fetch.py part --plan /verify/unet_high_q6k.json --index 0 --url "https://huggingface.co/QuantStack/Wan2.2-I2V-A14B-GGUF/resolve/6c6717459277b9cd1f72579d78a0fd62a79e57dc/HighNoise/Wan2.2-I2V-A14B-HighNoise-Q6_K.gguf" \
      --dest opt/lantern/parts/Wan2.2-I2V-A14B-HighNoise-Q6_K.gguf.part00 --out /out --mtime 1793318400
FROM fetcher AS part-unet-high-q6k-01
RUN --mount=type=bind,from=verify-unet-high-q6k,target=/verify \
    python3 -I /fetch.py part --plan /verify/unet_high_q6k.json --index 1 --url "https://huggingface.co/QuantStack/Wan2.2-I2V-A14B-GGUF/resolve/6c6717459277b9cd1f72579d78a0fd62a79e57dc/HighNoise/Wan2.2-I2V-A14B-HighNoise-Q6_K.gguf" \
      --dest opt/lantern/parts/Wan2.2-I2V-A14B-HighNoise-Q6_K.gguf.part01 --out /out --mtime 1793318400
FROM fetcher AS part-unet-high-q6k-02
RUN --mount=type=bind,from=verify-unet-high-q6k,target=/verify \
    python3 -I /fetch.py part --plan /verify/unet_high_q6k.json --index 2 --url "https://huggingface.co/QuantStack/Wan2.2-I2V-A14B-GGUF/resolve/6c6717459277b9cd1f72579d78a0fd62a79e57dc/HighNoise/Wan2.2-I2V-A14B-HighNoise-Q6_K.gguf" \
      --dest opt/lantern/parts/Wan2.2-I2V-A14B-HighNoise-Q6_K.gguf.part02 --out /out --mtime 1793318400
FROM fetcher AS part-unet-high-q6k-03
RUN --mount=type=bind,from=verify-unet-high-q6k,target=/verify \
    python3 -I /fetch.py part --plan /verify/unet_high_q6k.json --index 3 --url "https://huggingface.co/QuantStack/Wan2.2-I2V-A14B-GGUF/resolve/6c6717459277b9cd1f72579d78a0fd62a79e57dc/HighNoise/Wan2.2-I2V-A14B-HighNoise-Q6_K.gguf" \
      --dest opt/lantern/parts/Wan2.2-I2V-A14B-HighNoise-Q6_K.gguf.part03 --out /out --mtime 1793318400
FROM fetcher AS part-unet-high-q6k-04
RUN --mount=type=bind,from=verify-unet-high-q6k,target=/verify \
    python3 -I /fetch.py part --plan /verify/unet_high_q6k.json --index 4 --url "https://huggingface.co/QuantStack/Wan2.2-I2V-A14B-GGUF/resolve/6c6717459277b9cd1f72579d78a0fd62a79e57dc/HighNoise/Wan2.2-I2V-A14B-HighNoise-Q6_K.gguf" \
      --dest opt/lantern/parts/Wan2.2-I2V-A14B-HighNoise-Q6_K.gguf.part04 --out /out --mtime 1793318400
FROM fetcher AS part-unet-high-q6k-05
RUN --mount=type=bind,from=verify-unet-high-q6k,target=/verify \
    python3 -I /fetch.py part --plan /verify/unet_high_q6k.json --index 5 --url "https://huggingface.co/QuantStack/Wan2.2-I2V-A14B-GGUF/resolve/6c6717459277b9cd1f72579d78a0fd62a79e57dc/HighNoise/Wan2.2-I2V-A14B-HighNoise-Q6_K.gguf" \
      --dest opt/lantern/parts/Wan2.2-I2V-A14B-HighNoise-Q6_K.gguf.part05 --out /out --mtime 1793318400

# unet_low_q6k: stream the whole file once (nothing stored): size, SHA-256, head/tail; record each part's SHA-256
FROM fetcher AS verify-unet-low-q6k-run
RUN python3 -I /fetch.py verify --id unet_low_q6k --url "https://huggingface.co/QuantStack/Wan2.2-I2V-A14B-GGUF/resolve/6c6717459277b9cd1f72579d78a0fd62a79e57dc/LowNoise/Wan2.2-I2V-A14B-LowNoise-Q6_K.gguf" --bytes 12003652096 --sha256 962d9c937a6e882562cd234ba87c5cfc19d6e99efbf0fc31b4dd9e43eb493ae6 --probe-bytes 67108864 --head-sha256 20375c3dcc542637ea1cbd168fca57572be473fb58ac04ef93e6735732974ae7 --tail-sha256 7dc6b6469ca131bd87f9d3ba2bb9222859116dd85ddd69e9c47391fb815469da \
      --part-bytes 2147483648 --out /verify/unet_low_q6k.json
FROM scratch AS verify-unet-low-q6k
COPY --from=verify-unet-low-q6k-run /verify/ /

FROM fetcher AS part-unet-low-q6k-00
RUN --mount=type=bind,from=verify-unet-low-q6k,target=/verify \
    python3 -I /fetch.py part --plan /verify/unet_low_q6k.json --index 0 --url "https://huggingface.co/QuantStack/Wan2.2-I2V-A14B-GGUF/resolve/6c6717459277b9cd1f72579d78a0fd62a79e57dc/LowNoise/Wan2.2-I2V-A14B-LowNoise-Q6_K.gguf" \
      --dest opt/lantern/parts/Wan2.2-I2V-A14B-LowNoise-Q6_K.gguf.part00 --out /out --mtime 1793318400
FROM fetcher AS part-unet-low-q6k-01
RUN --mount=type=bind,from=verify-unet-low-q6k,target=/verify \
    python3 -I /fetch.py part --plan /verify/unet_low_q6k.json --index 1 --url "https://huggingface.co/QuantStack/Wan2.2-I2V-A14B-GGUF/resolve/6c6717459277b9cd1f72579d78a0fd62a79e57dc/LowNoise/Wan2.2-I2V-A14B-LowNoise-Q6_K.gguf" \
      --dest opt/lantern/parts/Wan2.2-I2V-A14B-LowNoise-Q6_K.gguf.part01 --out /out --mtime 1793318400
FROM fetcher AS part-unet-low-q6k-02
RUN --mount=type=bind,from=verify-unet-low-q6k,target=/verify \
    python3 -I /fetch.py part --plan /verify/unet_low_q6k.json --index 2 --url "https://huggingface.co/QuantStack/Wan2.2-I2V-A14B-GGUF/resolve/6c6717459277b9cd1f72579d78a0fd62a79e57dc/LowNoise/Wan2.2-I2V-A14B-LowNoise-Q6_K.gguf" \
      --dest opt/lantern/parts/Wan2.2-I2V-A14B-LowNoise-Q6_K.gguf.part02 --out /out --mtime 1793318400
FROM fetcher AS part-unet-low-q6k-03
RUN --mount=type=bind,from=verify-unet-low-q6k,target=/verify \
    python3 -I /fetch.py part --plan /verify/unet_low_q6k.json --index 3 --url "https://huggingface.co/QuantStack/Wan2.2-I2V-A14B-GGUF/resolve/6c6717459277b9cd1f72579d78a0fd62a79e57dc/LowNoise/Wan2.2-I2V-A14B-LowNoise-Q6_K.gguf" \
      --dest opt/lantern/parts/Wan2.2-I2V-A14B-LowNoise-Q6_K.gguf.part03 --out /out --mtime 1793318400
FROM fetcher AS part-unet-low-q6k-04
RUN --mount=type=bind,from=verify-unet-low-q6k,target=/verify \
    python3 -I /fetch.py part --plan /verify/unet_low_q6k.json --index 4 --url "https://huggingface.co/QuantStack/Wan2.2-I2V-A14B-GGUF/resolve/6c6717459277b9cd1f72579d78a0fd62a79e57dc/LowNoise/Wan2.2-I2V-A14B-LowNoise-Q6_K.gguf" \
      --dest opt/lantern/parts/Wan2.2-I2V-A14B-LowNoise-Q6_K.gguf.part04 --out /out --mtime 1793318400
FROM fetcher AS part-unet-low-q6k-05
RUN --mount=type=bind,from=verify-unet-low-q6k,target=/verify \
    python3 -I /fetch.py part --plan /verify/unet_low_q6k.json --index 5 --url "https://huggingface.co/QuantStack/Wan2.2-I2V-A14B-GGUF/resolve/6c6717459277b9cd1f72579d78a0fd62a79e57dc/LowNoise/Wan2.2-I2V-A14B-LowNoise-Q6_K.gguf" \
      --dest opt/lantern/parts/Wan2.2-I2V-A14B-LowNoise-Q6_K.gguf.part05 --out /out --mtime 1793318400

FROM fetcher AS file-lora-low-lightx2v-4step-1022
RUN python3 -I /fetch.py whole --id lora_low_lightx2v_4step_1022 --url "https://huggingface.co/lightx2v/Wan2.2-Distill-Loras/resolve/57adea585d1d21085e2dfc91ce3c7b646cdd9345/wan2.2_i2v_A14b_low_noise_lora_rank64_lightx2v_4step_1022.safetensors" --bytes 739472104 --sha256 8833bd4fd7c8eabebf0bc8ee5cfaf47f4f310ce116928a02c1adf8941dd4b0f1 --probe-bytes 67108864 --head-sha256 76cf996503d12bde0abc8b87bbc7661a8219bcc559a3b596502ca4e0800bd015 --tail-sha256 5621986442dafb79087690483115725e3d113d74eee28aa3c7a549ef46ee5c95 \
      --dest opt/ComfyUI/models/loras/wan2.2_i2v_A14b_low_noise_lora_rank64_lightx2v_4step_1022.safetensors --out /out --mtime 1793318400

FROM fetcher AS file-lora-high-lightx2v-4step-1022
RUN python3 -I /fetch.py whole --id lora_high_lightx2v_4step_1022 --url "https://huggingface.co/lightx2v/Wan2.2-Distill-Loras/resolve/57adea585d1d21085e2dfc91ce3c7b646cdd9345/wan2.2_i2v_A14b_high_noise_lora_rank64_lightx2v_4step_1022.safetensors" --bytes 634645944 --sha256 887c3bdeb74e83859c920438e16ca31f39ab18ce189abc5f0e36f8348c5bbb19 --probe-bytes 67108864 --head-sha256 93d3efc05f650d1e1ef0d12f009ac75d862dcbc17f62ed36db7d718c850c0a57 --tail-sha256 03b93782c089c5673324c6b5ae5ec72669d0d205ce99bcf3580d4d88e4243170 \
      --dest opt/ComfyUI/models/loras/wan2.2_i2v_A14b_high_noise_lora_rank64_lightx2v_4step_1022.safetensors --out /out --mtime 1793318400

FROM fetcher AS file-vae-wan21
RUN python3 -I /fetch.py whole --id vae_wan21 --url "https://huggingface.co/Comfy-Org/Wan-2.2/resolve/ee6f4a40737a995bf5818954cfce6d59443b0f04/split_files/vae/wan_2.1_vae.safetensors" --bytes 253815318 --sha256 2fc39d31359a4b0a64f55876d8ff7fa8d780956ae2cb13463b0223e15148976b --probe-bytes 67108864 --head-sha256 1ca25bb2e10622584217cbcfd4204e0a40396bd386bb8079d7c00e7469049ec4 --tail-sha256 a114c0994cb9b4e0115e806ab443ed08433b97f87966ee2492fde50b81026e2f \
      --dest opt/ComfyUI/models/vae/wan_2.1_vae.safetensors --out /out --mtime 1793318400

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
 "files": {
  "lora_high_lightx2v_4step_1022": {
   "bytes": 634645944,
   "comfy_dir": "loras",
   "filename": "wan2.2_i2v_A14b_high_noise_lora_rank64_lightx2v_4step_1022.safetensors",
   "head_sha256": "93d3efc05f650d1e1ef0d12f009ac75d862dcbc17f62ed36db7d718c850c0a57",
   "layout": "whole",
   "path": "opt/ComfyUI/models/loras/wan2.2_i2v_A14b_high_noise_lora_rank64_lightx2v_4step_1022.safetensors",
   "sha256": "887c3bdeb74e83859c920438e16ca31f39ab18ce189abc5f0e36f8348c5bbb19",
   "source": {
    "license": "apache-2.0",
    "repo": "lightx2v/Wan2.2-Distill-Loras",
    "revision": "57adea585d1d21085e2dfc91ce3c7b646cdd9345",
    "url": "https://huggingface.co/lightx2v/Wan2.2-Distill-Loras/resolve/57adea585d1d21085e2dfc91ce3c7b646cdd9345/wan2.2_i2v_A14b_high_noise_lora_rank64_lightx2v_4step_1022.safetensors"
   },
   "tail_sha256": "03b93782c089c5673324c6b5ae5ec72669d0d205ce99bcf3580d4d88e4243170"
  },
  "lora_low_lightx2v_4step_1022": {
   "bytes": 739472104,
   "comfy_dir": "loras",
   "filename": "wan2.2_i2v_A14b_low_noise_lora_rank64_lightx2v_4step_1022.safetensors",
   "head_sha256": "76cf996503d12bde0abc8b87bbc7661a8219bcc559a3b596502ca4e0800bd015",
   "layout": "whole",
   "path": "opt/ComfyUI/models/loras/wan2.2_i2v_A14b_low_noise_lora_rank64_lightx2v_4step_1022.safetensors",
   "sha256": "8833bd4fd7c8eabebf0bc8ee5cfaf47f4f310ce116928a02c1adf8941dd4b0f1",
   "source": {
    "license": "apache-2.0",
    "repo": "lightx2v/Wan2.2-Distill-Loras",
    "revision": "57adea585d1d21085e2dfc91ce3c7b646cdd9345",
    "url": "https://huggingface.co/lightx2v/Wan2.2-Distill-Loras/resolve/57adea585d1d21085e2dfc91ce3c7b646cdd9345/wan2.2_i2v_A14b_low_noise_lora_rank64_lightx2v_4step_1022.safetensors"
   },
   "tail_sha256": "5621986442dafb79087690483115725e3d113d74eee28aa3c7a549ef46ee5c95"
  },
  "unet_high_q6k": {
   "bytes": 12003652096,
   "comfy_dir": "diffusion_models",
   "filename": "Wan2.2-I2V-A14B-HighNoise-Q6_K.gguf",
   "head_sha256": "fb21f6be82c032a58f824462310fccea01e27a404688668608b2e01d5a71c568",
   "layout": "parts",
   "parts": [
    {
     "bytes": 2147483648,
     "offset": 0,
     "path": "opt/lantern/parts/Wan2.2-I2V-A14B-HighNoise-Q6_K.gguf.part00"
    },
    {
     "bytes": 2147483648,
     "offset": 2147483648,
     "path": "opt/lantern/parts/Wan2.2-I2V-A14B-HighNoise-Q6_K.gguf.part01"
    },
    {
     "bytes": 2147483648,
     "offset": 4294967296,
     "path": "opt/lantern/parts/Wan2.2-I2V-A14B-HighNoise-Q6_K.gguf.part02"
    },
    {
     "bytes": 2147483648,
     "offset": 6442450944,
     "path": "opt/lantern/parts/Wan2.2-I2V-A14B-HighNoise-Q6_K.gguf.part03"
    },
    {
     "bytes": 2147483648,
     "offset": 8589934592,
     "path": "opt/lantern/parts/Wan2.2-I2V-A14B-HighNoise-Q6_K.gguf.part04"
    },
    {
     "bytes": 1266233856,
     "offset": 10737418240,
     "path": "opt/lantern/parts/Wan2.2-I2V-A14B-HighNoise-Q6_K.gguf.part05"
    }
   ],
   "sha256": "33ab8d99b5be745d2c939055f541d09108befe3467802fdbbf22ba8e4e62383c",
   "source": {
    "license": "apache-2.0",
    "repo": "QuantStack/Wan2.2-I2V-A14B-GGUF",
    "revision": "6c6717459277b9cd1f72579d78a0fd62a79e57dc",
    "url": "https://huggingface.co/QuantStack/Wan2.2-I2V-A14B-GGUF/resolve/6c6717459277b9cd1f72579d78a0fd62a79e57dc/HighNoise/Wan2.2-I2V-A14B-HighNoise-Q6_K.gguf"
   },
   "tail_sha256": "acf60bb5ab8dea4e693b12940ae6d3354de0b42229e923b31efc7c36f8c44775"
  },
  "unet_low_q6k": {
   "bytes": 12003652096,
   "comfy_dir": "diffusion_models",
   "filename": "Wan2.2-I2V-A14B-LowNoise-Q6_K.gguf",
   "head_sha256": "20375c3dcc542637ea1cbd168fca57572be473fb58ac04ef93e6735732974ae7",
   "layout": "parts",
   "parts": [
    {
     "bytes": 2147483648,
     "offset": 0,
     "path": "opt/lantern/parts/Wan2.2-I2V-A14B-LowNoise-Q6_K.gguf.part00"
    },
    {
     "bytes": 2147483648,
     "offset": 2147483648,
     "path": "opt/lantern/parts/Wan2.2-I2V-A14B-LowNoise-Q6_K.gguf.part01"
    },
    {
     "bytes": 2147483648,
     "offset": 4294967296,
     "path": "opt/lantern/parts/Wan2.2-I2V-A14B-LowNoise-Q6_K.gguf.part02"
    },
    {
     "bytes": 2147483648,
     "offset": 6442450944,
     "path": "opt/lantern/parts/Wan2.2-I2V-A14B-LowNoise-Q6_K.gguf.part03"
    },
    {
     "bytes": 2147483648,
     "offset": 8589934592,
     "path": "opt/lantern/parts/Wan2.2-I2V-A14B-LowNoise-Q6_K.gguf.part04"
    },
    {
     "bytes": 1266233856,
     "offset": 10737418240,
     "path": "opt/lantern/parts/Wan2.2-I2V-A14B-LowNoise-Q6_K.gguf.part05"
    }
   ],
   "sha256": "962d9c937a6e882562cd234ba87c5cfc19d6e99efbf0fc31b4dd9e43eb493ae6",
   "source": {
    "license": "apache-2.0",
    "repo": "QuantStack/Wan2.2-I2V-A14B-GGUF",
    "revision": "6c6717459277b9cd1f72579d78a0fd62a79e57dc",
    "url": "https://huggingface.co/QuantStack/Wan2.2-I2V-A14B-GGUF/resolve/6c6717459277b9cd1f72579d78a0fd62a79e57dc/LowNoise/Wan2.2-I2V-A14B-LowNoise-Q6_K.gguf"
   },
   "tail_sha256": "7dc6b6469ca131bd87f9d3ba2bb9222859116dd85ddd69e9c47391fb815469da"
  },
  "vae_wan21": {
   "bytes": 253815318,
   "comfy_dir": "vae",
   "filename": "wan_2.1_vae.safetensors",
   "head_sha256": "1ca25bb2e10622584217cbcfd4204e0a40396bd386bb8079d7c00e7469049ec4",
   "layout": "whole",
   "path": "opt/ComfyUI/models/vae/wan_2.1_vae.safetensors",
   "sha256": "2fc39d31359a4b0a64f55876d8ff7fa8d780956ae2cb13463b0223e15148976b",
   "source": {
    "license": "apache-2.0",
    "repo": "Comfy-Org/Wan-2.2",
    "revision": "ee6f4a40737a995bf5818954cfce6d59443b0f04",
    "url": "https://huggingface.co/Comfy-Org/Wan-2.2/resolve/ee6f4a40737a995bf5818954cfce6d59443b0f04/split_files/vae/wan_2.1_vae.safetensors"
   },
   "tail_sha256": "a114c0994cb9b4e0115e806ab443ed08433b97f87966ee2492fde50b81026e2f"
  }
 },
 "image_tag": "comfy0.12.3-q6k-lightx2v1022-v1",
 "part_bytes": 2147483648,
 "probe_bytes": 67108864,
 "probe_rule": "head_sha256 = SHA-256 of the first min(probe_bytes, size) bytes; tail_sha256 = SHA-256 of the last min(probe_bytes, size) bytes",
 "runtime_download": [
  {
   "bytes": 6735906897,
   "id": "text_encoder_umt5_fp8",
   "reason": "kept out of the image by design: baking it (+6.74 GB) would put the image over Salad's 35 GB limit; the agent downloads it at start (parallel ranged streams, full SHA-256)"
  }
 ],
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
      org.opencontainers.image.version="comfy0.12.3-q6k-lightx2v1022-v1" \
      org.opencontainers.image.description="ComfyUI 0.12.3 + Wan2.2 I2V-A14B GGUF Q6_K experts, Wan 2.1 VAE, lightx2v 4-step LoRAs, ComfyUI-GGUF (open Apache-2.0 weights; text encoder not included)" \
      org.opencontainers.image.base.name="ghcr.io/saladtechnologies/comfyui-api@sha256:597aa2699776bbc4c24da5b1319fed9908b21a8aa0c1b807d9e1f8a0f6ce0064"

FROM s00 AS s01
# Wan2.2-I2V-A14B-HighNoise-Q6_K.gguf part 00
COPY --link --from=part-unet-high-q6k-00 /out/ /

FROM s01 AS s02
# Wan2.2-I2V-A14B-HighNoise-Q6_K.gguf part 01
COPY --link --from=part-unet-high-q6k-01 /out/ /

FROM s02 AS s03
# Wan2.2-I2V-A14B-HighNoise-Q6_K.gguf part 02
COPY --link --from=part-unet-high-q6k-02 /out/ /

FROM s03 AS s04
# Wan2.2-I2V-A14B-HighNoise-Q6_K.gguf part 03
COPY --link --from=part-unet-high-q6k-03 /out/ /

FROM s04 AS s05
# Wan2.2-I2V-A14B-HighNoise-Q6_K.gguf part 04
COPY --link --from=part-unet-high-q6k-04 /out/ /

FROM s05 AS s06
# Wan2.2-I2V-A14B-HighNoise-Q6_K.gguf part 05
COPY --link --from=part-unet-high-q6k-05 /out/ /

FROM s06 AS s07
# Wan2.2-I2V-A14B-LowNoise-Q6_K.gguf part 00
COPY --link --from=part-unet-low-q6k-00 /out/ /

FROM s07 AS s08
# Wan2.2-I2V-A14B-LowNoise-Q6_K.gguf part 01
COPY --link --from=part-unet-low-q6k-01 /out/ /

FROM s08 AS s09
# Wan2.2-I2V-A14B-LowNoise-Q6_K.gguf part 02
COPY --link --from=part-unet-low-q6k-02 /out/ /

FROM s09 AS s10
# Wan2.2-I2V-A14B-LowNoise-Q6_K.gguf part 03
COPY --link --from=part-unet-low-q6k-03 /out/ /

FROM s10 AS s11
# Wan2.2-I2V-A14B-LowNoise-Q6_K.gguf part 04
COPY --link --from=part-unet-low-q6k-04 /out/ /

FROM s11 AS s12
# Wan2.2-I2V-A14B-LowNoise-Q6_K.gguf part 05
COPY --link --from=part-unet-low-q6k-05 /out/ /

FROM s12 AS s13
# wan2.2_i2v_A14b_low_noise_lora_rank64_lightx2v_4step_1022.safetensors
COPY --link --from=file-lora-low-lightx2v-4step-1022 /out/ /

FROM s13 AS s14
# wan2.2_i2v_A14b_high_noise_lora_rank64_lightx2v_4step_1022.safetensors
COPY --link --from=file-lora-high-lightx2v-4step-1022 /out/ /

FROM s14 AS s15
# wan_2.1_vae.safetensors
COPY --link --from=file-vae-wan21 /out/ /

FROM s15 AS s16
# ComfyUI-GGUF at its pinned commit, .git kept so the container can verify HEAD
ADD --link --keep-git-dir=true --checksum=6ea2651e7df66d7585f6ffee804b20e92fb38b8a https://github.com/city96/ComfyUI-GGUF.git#6ea2651e7df66d7585f6ffee804b20e92fb38b8a /opt/ComfyUI/custom_nodes/ComfyUI-GGUF

FROM s16 AS s17
# gguf-0.17.1-py3-none-any.whl (installed offline, hash-locked, at container start)
COPY --link --from=wheel-gguf /out/ /

FROM s17 AS s18
COPY --link --from=file-manifest /out/ /
