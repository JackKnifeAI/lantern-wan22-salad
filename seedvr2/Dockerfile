# syntax=docker/dockerfile:1.28.0@sha256:bb22d9815c728170f72750f4e5b0d672e06176142e1d602c7e66c050100b7e5b
# Generated file: the build layout tool and fetch.py live with the build tooling; fetch.py is embedded below.
#
# SeedVR2 (ByteDance-Seed, Apache-2.0) 3B + 7B fp16 and its VAE, with the ComfyUI-SeedVR2_VideoUpscaler node, baked into SaladTechnologies' comfyui-api image (ComfyUI 0.12.3, CUDA 12.8) for SaladCloud.
# Baked: SeedVR2 7B fp16 + 3B fp16 DiTs and the SeedVR2 VAE (numz/SeedVR2_comfyUI repackage of ByteDance-Seed SeedVR2,
# Apache-2.0) and the node's Python dependencies as wheels. NOT baked: the ComfyUI-SeedVR2_VideoUpscaler node itself; the
# container clones it from its upstream repo at a pinned, verified commit (it carries one helper file of unclear licence,
# so this image does not redistribute it).
# Every byte comes from its pinned upstream URL inside the build and is SHA-256-verified there (fetch.py below).
# GHCR caps a layer at 10 GB, so each large file is split into 2147483648-byte parts, one part per layer;
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

# seedvr2_7b_fp16: stream the whole file once (nothing stored): size, SHA-256, head/tail; record each part's SHA-256
FROM fetcher AS verify-seedvr2-7b-fp16-run
RUN python3 -I /fetch.py verify --id seedvr2_7b_fp16 --url "https://huggingface.co/numz/SeedVR2_comfyUI/resolve/09ced71023636e9bc8cdf9cdecfb2625d1e691e8/seedvr2_ema_7b_fp16.safetensors" --bytes 16479334424 --sha256 7b8241aa957606ab6cfb66edabc96d43234f9819c5392b44d2492d9f0b0bbe4a --probe-bytes 67108864 --head-sha256 11b0a5c97cbfb6b83372a08ebeb8c9452dd0ead22aa7e2b6139834e602ceaa0f --tail-sha256 1e94e7c0916dbf354d64aec6c8e2441f442fc3fb8e0f4e779cdb4c7577861361 \
      --part-bytes 2147483648 --out /verify/seedvr2_7b_fp16.json
FROM scratch AS verify-seedvr2-7b-fp16
COPY --from=verify-seedvr2-7b-fp16-run /verify/ /

FROM fetcher AS part-seedvr2-7b-fp16-00
RUN --mount=type=bind,from=verify-seedvr2-7b-fp16,target=/verify \
    python3 -I /fetch.py part --plan /verify/seedvr2_7b_fp16.json --index 0 --url "https://huggingface.co/numz/SeedVR2_comfyUI/resolve/09ced71023636e9bc8cdf9cdecfb2625d1e691e8/seedvr2_ema_7b_fp16.safetensors" \
      --dest opt/lantern/parts/seedvr2_ema_7b_fp16.safetensors.part00 --out /out --mtime 1793318400
FROM fetcher AS part-seedvr2-7b-fp16-01
RUN --mount=type=bind,from=verify-seedvr2-7b-fp16,target=/verify \
    python3 -I /fetch.py part --plan /verify/seedvr2_7b_fp16.json --index 1 --url "https://huggingface.co/numz/SeedVR2_comfyUI/resolve/09ced71023636e9bc8cdf9cdecfb2625d1e691e8/seedvr2_ema_7b_fp16.safetensors" \
      --dest opt/lantern/parts/seedvr2_ema_7b_fp16.safetensors.part01 --out /out --mtime 1793318400
FROM fetcher AS part-seedvr2-7b-fp16-02
RUN --mount=type=bind,from=verify-seedvr2-7b-fp16,target=/verify \
    python3 -I /fetch.py part --plan /verify/seedvr2_7b_fp16.json --index 2 --url "https://huggingface.co/numz/SeedVR2_comfyUI/resolve/09ced71023636e9bc8cdf9cdecfb2625d1e691e8/seedvr2_ema_7b_fp16.safetensors" \
      --dest opt/lantern/parts/seedvr2_ema_7b_fp16.safetensors.part02 --out /out --mtime 1793318400
FROM fetcher AS part-seedvr2-7b-fp16-03
RUN --mount=type=bind,from=verify-seedvr2-7b-fp16,target=/verify \
    python3 -I /fetch.py part --plan /verify/seedvr2_7b_fp16.json --index 3 --url "https://huggingface.co/numz/SeedVR2_comfyUI/resolve/09ced71023636e9bc8cdf9cdecfb2625d1e691e8/seedvr2_ema_7b_fp16.safetensors" \
      --dest opt/lantern/parts/seedvr2_ema_7b_fp16.safetensors.part03 --out /out --mtime 1793318400
FROM fetcher AS part-seedvr2-7b-fp16-04
RUN --mount=type=bind,from=verify-seedvr2-7b-fp16,target=/verify \
    python3 -I /fetch.py part --plan /verify/seedvr2_7b_fp16.json --index 4 --url "https://huggingface.co/numz/SeedVR2_comfyUI/resolve/09ced71023636e9bc8cdf9cdecfb2625d1e691e8/seedvr2_ema_7b_fp16.safetensors" \
      --dest opt/lantern/parts/seedvr2_ema_7b_fp16.safetensors.part04 --out /out --mtime 1793318400
FROM fetcher AS part-seedvr2-7b-fp16-05
RUN --mount=type=bind,from=verify-seedvr2-7b-fp16,target=/verify \
    python3 -I /fetch.py part --plan /verify/seedvr2_7b_fp16.json --index 5 --url "https://huggingface.co/numz/SeedVR2_comfyUI/resolve/09ced71023636e9bc8cdf9cdecfb2625d1e691e8/seedvr2_ema_7b_fp16.safetensors" \
      --dest opt/lantern/parts/seedvr2_ema_7b_fp16.safetensors.part05 --out /out --mtime 1793318400
FROM fetcher AS part-seedvr2-7b-fp16-06
RUN --mount=type=bind,from=verify-seedvr2-7b-fp16,target=/verify \
    python3 -I /fetch.py part --plan /verify/seedvr2_7b_fp16.json --index 6 --url "https://huggingface.co/numz/SeedVR2_comfyUI/resolve/09ced71023636e9bc8cdf9cdecfb2625d1e691e8/seedvr2_ema_7b_fp16.safetensors" \
      --dest opt/lantern/parts/seedvr2_ema_7b_fp16.safetensors.part06 --out /out --mtime 1793318400
FROM fetcher AS part-seedvr2-7b-fp16-07
RUN --mount=type=bind,from=verify-seedvr2-7b-fp16,target=/verify \
    python3 -I /fetch.py part --plan /verify/seedvr2_7b_fp16.json --index 7 --url "https://huggingface.co/numz/SeedVR2_comfyUI/resolve/09ced71023636e9bc8cdf9cdecfb2625d1e691e8/seedvr2_ema_7b_fp16.safetensors" \
      --dest opt/lantern/parts/seedvr2_ema_7b_fp16.safetensors.part07 --out /out --mtime 1793318400

# seedvr2_3b_fp16: stream the whole file once (nothing stored): size, SHA-256, head/tail; record each part's SHA-256
FROM fetcher AS verify-seedvr2-3b-fp16-run
RUN python3 -I /fetch.py verify --id seedvr2_3b_fp16 --url "https://huggingface.co/numz/SeedVR2_comfyUI/resolve/09ced71023636e9bc8cdf9cdecfb2625d1e691e8/seedvr2_ema_3b_fp16.safetensors" --bytes 6783018808 --sha256 2fd0e03a3dad24e07086750360727ca437de4ecd456f769856e960ae93e2b304 --probe-bytes 67108864 --head-sha256 3afa80738f39a28908064452a9126c45ef6985bdb4f99f25226d67e76c50c3af --tail-sha256 a94c174dd333b90d9800677bd3ee43258136249027347ff74ebd83f57930d2f0 \
      --part-bytes 2147483648 --out /verify/seedvr2_3b_fp16.json
FROM scratch AS verify-seedvr2-3b-fp16
COPY --from=verify-seedvr2-3b-fp16-run /verify/ /

FROM fetcher AS part-seedvr2-3b-fp16-00
RUN --mount=type=bind,from=verify-seedvr2-3b-fp16,target=/verify \
    python3 -I /fetch.py part --plan /verify/seedvr2_3b_fp16.json --index 0 --url "https://huggingface.co/numz/SeedVR2_comfyUI/resolve/09ced71023636e9bc8cdf9cdecfb2625d1e691e8/seedvr2_ema_3b_fp16.safetensors" \
      --dest opt/lantern/parts/seedvr2_ema_3b_fp16.safetensors.part00 --out /out --mtime 1793318400
FROM fetcher AS part-seedvr2-3b-fp16-01
RUN --mount=type=bind,from=verify-seedvr2-3b-fp16,target=/verify \
    python3 -I /fetch.py part --plan /verify/seedvr2_3b_fp16.json --index 1 --url "https://huggingface.co/numz/SeedVR2_comfyUI/resolve/09ced71023636e9bc8cdf9cdecfb2625d1e691e8/seedvr2_ema_3b_fp16.safetensors" \
      --dest opt/lantern/parts/seedvr2_ema_3b_fp16.safetensors.part01 --out /out --mtime 1793318400
FROM fetcher AS part-seedvr2-3b-fp16-02
RUN --mount=type=bind,from=verify-seedvr2-3b-fp16,target=/verify \
    python3 -I /fetch.py part --plan /verify/seedvr2_3b_fp16.json --index 2 --url "https://huggingface.co/numz/SeedVR2_comfyUI/resolve/09ced71023636e9bc8cdf9cdecfb2625d1e691e8/seedvr2_ema_3b_fp16.safetensors" \
      --dest opt/lantern/parts/seedvr2_ema_3b_fp16.safetensors.part02 --out /out --mtime 1793318400
FROM fetcher AS part-seedvr2-3b-fp16-03
RUN --mount=type=bind,from=verify-seedvr2-3b-fp16,target=/verify \
    python3 -I /fetch.py part --plan /verify/seedvr2_3b_fp16.json --index 3 --url "https://huggingface.co/numz/SeedVR2_comfyUI/resolve/09ced71023636e9bc8cdf9cdecfb2625d1e691e8/seedvr2_ema_3b_fp16.safetensors" \
      --dest opt/lantern/parts/seedvr2_ema_3b_fp16.safetensors.part03 --out /out --mtime 1793318400

FROM fetcher AS file-seedvr2-vae-fp16
RUN python3 -I /fetch.py whole --id seedvr2_vae_fp16 --url "https://huggingface.co/numz/SeedVR2_comfyUI/resolve/09ced71023636e9bc8cdf9cdecfb2625d1e691e8/ema_vae_fp16.safetensors" --bytes 501324814 --sha256 20678548f420d98d26f11442d3528f8b8c94e57ee046ef93dbb7633da8612ca1 --probe-bytes 67108864 --head-sha256 6032b064578c5a34843372a7becdcd51897a8cc8a13ce0438983442adf9c6503 --tail-sha256 359db03fba26c5a3b2b4a866598be6fa5b024bdc445db195b0aeacbc12d570fe \
      --dest opt/ComfyUI/models/SEEDVR2/ema_vae_fp16.safetensors --out /out --mtime 1793318400

FROM fetcher AS wheel-diffusers
RUN python3 -I /fetch.py whole --id diffusers-0.37.1-py3-none-any.whl --url "https://files.pythonhosted.org/packages/9c/dd/51c38785ce5e1c287b5ad17ba550edaaaffce0deb0da4857019c6700fbaf/diffusers-0.37.1-py3-none-any.whl" --bytes 5001536 --sha256 0537c0b28cb53cf39d6195489bcf8f833986df556c10f5e28ab7427b86fc8b90 \
      --dest opt/lantern/wheels/diffusers-0.37.1-py3-none-any.whl --out /out --mtime 1793318400

FROM fetcher AS wheel-omegaconf
RUN python3 -I /fetch.py whole --id omegaconf-2.4.0-py3-none-any.whl --url "https://files.pythonhosted.org/packages/4f/bd/0d9f8247b0819385213d09564eda5c52d3673313c2414d51f72883ec24cd/omegaconf-2.4.0-py3-none-any.whl" --bytes 254152 --sha256 f141a664c777582405e3cc6e0545ecc79429e79f844995b1a6e71c35946a025c \
      --dest opt/lantern/wheels/omegaconf-2.4.0-py3-none-any.whl --out /out --mtime 1793318400

FROM fetcher AS wheel-rotary-embedding-torch
RUN python3 -I /fetch.py whole --id rotary_embedding_torch-0.8.9-py3-none-any.whl --url "https://files.pythonhosted.org/packages/94/21/05e319ebef4a8194f9c4cc09f9c3213ab846da200fa6e88699cdb7e9679a/rotary_embedding_torch-0.8.9-py3-none-any.whl" --bytes 5872 --sha256 700e8de9dfbefba5f9117a66652a2520648dcc60136895f0068b6a85347cab02 \
      --dest opt/lantern/wheels/rotary_embedding_torch-0.8.9-py3-none-any.whl --out /out --mtime 1793318400

FROM fetcher AS wheel-opencv-python-headless
RUN python3 -I /fetch.py whole --id opencv_python_headless-4.11.0.86-cp37-abi3-manylinux_2_17_x86_64.manylinux2014_x86_64.whl --url "https://files.pythonhosted.org/packages/dd/5c/c139a7876099916879609372bfa513b7f1257f7f1a908b0bdc1c2328241b/opencv_python_headless-4.11.0.86-cp37-abi3-manylinux_2_17_x86_64.manylinux2014_x86_64.whl" --bytes 49969856 --sha256 0e0a27c19dd1f40ddff94976cfe43066fbbe9dfbb2ec1907d66c19caef42a57b \
      --dest opt/lantern/wheels/opencv_python_headless-4.11.0.86-cp37-abi3-manylinux_2_17_x86_64.manylinux2014_x86_64.whl --out /out --mtime 1793318400

# the layout manifest the container agent checks before trusting any baked byte
FROM fetcher AS file-manifest
COPY <<"MANIFEST_JSON_EOF" /out/opt/lantern/manifest.json
{
 "base_image": "ghcr.io/saladtechnologies/comfyui-api@sha256:597aa2699776bbc4c24da5b1319fed9908b21a8aa0c1b807d9e1f8a0f6ce0064",
 "custom_node": null,
 "files": {
  "seedvr2_3b_fp16": {
   "bytes": 6783018808,
   "comfy_dir": "SEEDVR2",
   "filename": "seedvr2_ema_3b_fp16.safetensors",
   "head_sha256": "3afa80738f39a28908064452a9126c45ef6985bdb4f99f25226d67e76c50c3af",
   "layout": "parts",
   "parts": [
    {
     "bytes": 2147483648,
     "offset": 0,
     "path": "opt/lantern/parts/seedvr2_ema_3b_fp16.safetensors.part00"
    },
    {
     "bytes": 2147483648,
     "offset": 2147483648,
     "path": "opt/lantern/parts/seedvr2_ema_3b_fp16.safetensors.part01"
    },
    {
     "bytes": 2147483648,
     "offset": 4294967296,
     "path": "opt/lantern/parts/seedvr2_ema_3b_fp16.safetensors.part02"
    },
    {
     "bytes": 340567864,
     "offset": 6442450944,
     "path": "opt/lantern/parts/seedvr2_ema_3b_fp16.safetensors.part03"
    }
   ],
   "sha256": "2fd0e03a3dad24e07086750360727ca437de4ecd456f769856e960ae93e2b304",
   "source": {
    "license": "apache-2.0",
    "repo": "numz/SeedVR2_comfyUI",
    "revision": "09ced71023636e9bc8cdf9cdecfb2625d1e691e8",
    "url": "https://huggingface.co/numz/SeedVR2_comfyUI/resolve/09ced71023636e9bc8cdf9cdecfb2625d1e691e8/seedvr2_ema_3b_fp16.safetensors"
   },
   "tail_sha256": "a94c174dd333b90d9800677bd3ee43258136249027347ff74ebd83f57930d2f0"
  },
  "seedvr2_7b_fp16": {
   "bytes": 16479334424,
   "comfy_dir": "SEEDVR2",
   "filename": "seedvr2_ema_7b_fp16.safetensors",
   "head_sha256": "11b0a5c97cbfb6b83372a08ebeb8c9452dd0ead22aa7e2b6139834e602ceaa0f",
   "layout": "parts",
   "parts": [
    {
     "bytes": 2147483648,
     "offset": 0,
     "path": "opt/lantern/parts/seedvr2_ema_7b_fp16.safetensors.part00"
    },
    {
     "bytes": 2147483648,
     "offset": 2147483648,
     "path": "opt/lantern/parts/seedvr2_ema_7b_fp16.safetensors.part01"
    },
    {
     "bytes": 2147483648,
     "offset": 4294967296,
     "path": "opt/lantern/parts/seedvr2_ema_7b_fp16.safetensors.part02"
    },
    {
     "bytes": 2147483648,
     "offset": 6442450944,
     "path": "opt/lantern/parts/seedvr2_ema_7b_fp16.safetensors.part03"
    },
    {
     "bytes": 2147483648,
     "offset": 8589934592,
     "path": "opt/lantern/parts/seedvr2_ema_7b_fp16.safetensors.part04"
    },
    {
     "bytes": 2147483648,
     "offset": 10737418240,
     "path": "opt/lantern/parts/seedvr2_ema_7b_fp16.safetensors.part05"
    },
    {
     "bytes": 2147483648,
     "offset": 12884901888,
     "path": "opt/lantern/parts/seedvr2_ema_7b_fp16.safetensors.part06"
    },
    {
     "bytes": 1446948888,
     "offset": 15032385536,
     "path": "opt/lantern/parts/seedvr2_ema_7b_fp16.safetensors.part07"
    }
   ],
   "sha256": "7b8241aa957606ab6cfb66edabc96d43234f9819c5392b44d2492d9f0b0bbe4a",
   "source": {
    "license": "apache-2.0",
    "repo": "numz/SeedVR2_comfyUI",
    "revision": "09ced71023636e9bc8cdf9cdecfb2625d1e691e8",
    "url": "https://huggingface.co/numz/SeedVR2_comfyUI/resolve/09ced71023636e9bc8cdf9cdecfb2625d1e691e8/seedvr2_ema_7b_fp16.safetensors"
   },
   "tail_sha256": "1e94e7c0916dbf354d64aec6c8e2441f442fc3fb8e0f4e779cdb4c7577861361"
  },
  "seedvr2_vae_fp16": {
   "bytes": 501324814,
   "comfy_dir": "SEEDVR2",
   "filename": "ema_vae_fp16.safetensors",
   "head_sha256": "6032b064578c5a34843372a7becdcd51897a8cc8a13ce0438983442adf9c6503",
   "layout": "whole",
   "path": "opt/ComfyUI/models/SEEDVR2/ema_vae_fp16.safetensors",
   "sha256": "20678548f420d98d26f11442d3528f8b8c94e57ee046ef93dbb7633da8612ca1",
   "source": {
    "license": "apache-2.0",
    "repo": "numz/SeedVR2_comfyUI",
    "revision": "09ced71023636e9bc8cdf9cdecfb2625d1e691e8",
    "url": "https://huggingface.co/numz/SeedVR2_comfyUI/resolve/09ced71023636e9bc8cdf9cdecfb2625d1e691e8/ema_vae_fp16.safetensors"
   },
   "tail_sha256": "359db03fba26c5a3b2b4a866598be6fa5b024bdc445db195b0aeacbc12d570fe"
  }
 },
 "image_tag": "seedvr2-node2.5.24-3b7b-fp16-v1",
 "part_bytes": 2147483648,
 "probe_bytes": 67108864,
 "probe_rule": "head_sha256 = SHA-256 of the first min(probe_bytes, size) bytes; tail_sha256 = SHA-256 of the last min(probe_bytes, size) bytes",
 "runtime_download": [],
 "schema": "lantern.baked-image.v1",
 "wheels": [
  {
   "bytes": 5001536,
   "file": "diffusers-0.37.1-py3-none-any.whl",
   "license": "Apache-2.0",
   "path": "opt/lantern/wheels/diffusers-0.37.1-py3-none-any.whl",
   "requirement": "diffusers==0.37.1",
   "sha256": "0537c0b28cb53cf39d6195489bcf8f833986df556c10f5e28ab7427b86fc8b90",
   "url": "https://files.pythonhosted.org/packages/9c/dd/51c38785ce5e1c287b5ad17ba550edaaaffce0deb0da4857019c6700fbaf/diffusers-0.37.1-py3-none-any.whl",
   "why": "the node's DiT/VAE layers import diffusers classes at module level (0.38+ needs a newer safetensors than the base)"
  },
  {
   "bytes": 254152,
   "file": "omegaconf-2.4.0-py3-none-any.whl",
   "license": "BSD-3-Clause",
   "path": "opt/lantern/wheels/omegaconf-2.4.0-py3-none-any.whl",
   "requirement": "omegaconf==2.4.0",
   "sha256": "f141a664c777582405e3cc6e0545ecc79429e79f844995b1a6e71c35946a025c",
   "url": "https://files.pythonhosted.org/packages/4f/bd/0d9f8247b0819385213d09564eda5c52d3673313c2414d51f72883ec24cd/omegaconf-2.4.0-py3-none-any.whl",
   "why": "model configs (module-level import); 2.4.0 vendors antlr4, so no extra wheel"
  },
  {
   "bytes": 5872,
   "file": "rotary_embedding_torch-0.8.9-py3-none-any.whl",
   "license": "MIT",
   "path": "opt/lantern/wheels/rotary_embedding_torch-0.8.9-py3-none-any.whl",
   "requirement": "rotary-embedding-torch==0.8.9",
   "sha256": "700e8de9dfbefba5f9117a66652a2520648dcc60136895f0068b6a85347cab02",
   "url": "https://files.pythonhosted.org/packages/94/21/05e319ebef4a8194f9c4cc09f9c3213ab846da200fa6e88699cdb7e9679a/rotary_embedding_torch-0.8.9-py3-none-any.whl",
   "why": "RoPE in the 3B/7B DiTs"
  },
  {
   "bytes": 49969856,
   "file": "opencv_python_headless-4.11.0.86-cp37-abi3-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
   "license": "Apache-2.0",
   "path": "opt/lantern/wheels/opencv_python_headless-4.11.0.86-cp37-abi3-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
   "requirement": "opencv-python-headless==4.11.0.86",
   "sha256": "0e0a27c19dd1f40ddff94976cfe43066fbbe9dfbb2ec1907d66c19caef42a57b",
   "url": "https://files.pythonhosted.org/packages/dd/5c/c139a7876099916879609372bfa513b7f1257f7f1a908b0bdc1c2328241b/opencv_python_headless-4.11.0.86-cp37-abi3-manylinux_2_17_x86_64.manylinux2014_x86_64.whl",
   "why": "imported at module level (alpha upscaling); headless = no libGL needed; works with numpy 1.x or 2.x"
  }
 ]
}
MANIFEST_JSON_EOF

# ------------------------------------------------------------------ image chain: one stage = one layer
FROM ${BASE_IMAGE} AS s00
ARG SOURCE_URL=https://github.com/OWNER/REPO
LABEL org.opencontainers.image.source="${SOURCE_URL}" \
      org.opencontainers.image.title="lantern-wan22-salad" \
      org.opencontainers.image.version="seedvr2-node2.5.24-3b7b-fp16-v1" \
      org.opencontainers.image.description="ComfyUI 0.12.3 + SeedVR2 3B/7B fp16 + VAE + ComfyUI-SeedVR2_VideoUpscaler (open Apache-2.0 weights and code)" \
      org.opencontainers.image.base.name="ghcr.io/saladtechnologies/comfyui-api@sha256:597aa2699776bbc4c24da5b1319fed9908b21a8aa0c1b807d9e1f8a0f6ce0064"

FROM s00 AS s01
# seedvr2_ema_7b_fp16.safetensors part 00
COPY --link --from=part-seedvr2-7b-fp16-00 /out/ /

FROM s01 AS s02
# seedvr2_ema_7b_fp16.safetensors part 01
COPY --link --from=part-seedvr2-7b-fp16-01 /out/ /

FROM s02 AS s03
# seedvr2_ema_7b_fp16.safetensors part 02
COPY --link --from=part-seedvr2-7b-fp16-02 /out/ /

FROM s03 AS s04
# seedvr2_ema_7b_fp16.safetensors part 03
COPY --link --from=part-seedvr2-7b-fp16-03 /out/ /

FROM s04 AS s05
# seedvr2_ema_7b_fp16.safetensors part 04
COPY --link --from=part-seedvr2-7b-fp16-04 /out/ /

FROM s05 AS s06
# seedvr2_ema_7b_fp16.safetensors part 05
COPY --link --from=part-seedvr2-7b-fp16-05 /out/ /

FROM s06 AS s07
# seedvr2_ema_7b_fp16.safetensors part 06
COPY --link --from=part-seedvr2-7b-fp16-06 /out/ /

FROM s07 AS s08
# seedvr2_ema_7b_fp16.safetensors part 07
COPY --link --from=part-seedvr2-7b-fp16-07 /out/ /

FROM s08 AS s09
# seedvr2_ema_3b_fp16.safetensors part 00
COPY --link --from=part-seedvr2-3b-fp16-00 /out/ /

FROM s09 AS s10
# seedvr2_ema_3b_fp16.safetensors part 01
COPY --link --from=part-seedvr2-3b-fp16-01 /out/ /

FROM s10 AS s11
# seedvr2_ema_3b_fp16.safetensors part 02
COPY --link --from=part-seedvr2-3b-fp16-02 /out/ /

FROM s11 AS s12
# seedvr2_ema_3b_fp16.safetensors part 03
COPY --link --from=part-seedvr2-3b-fp16-03 /out/ /

FROM s12 AS s13
# ema_vae_fp16.safetensors
COPY --link --from=file-seedvr2-vae-fp16 /out/ /

FROM s13 AS s14
# diffusers-0.37.1-py3-none-any.whl (installed offline, hash-locked, at container start)
COPY --link --from=wheel-diffusers /out/ /

FROM s14 AS s15
# omegaconf-2.4.0-py3-none-any.whl (installed offline, hash-locked, at container start)
COPY --link --from=wheel-omegaconf /out/ /

FROM s15 AS s16
# rotary_embedding_torch-0.8.9-py3-none-any.whl (installed offline, hash-locked, at container start)
COPY --link --from=wheel-rotary-embedding-torch /out/ /

FROM s16 AS s17
# opencv_python_headless-4.11.0.86-cp37-abi3-manylinux_2_17_x86_64.manylinux2014_x86_64.whl (installed offline, hash-locked, at container start)
COPY --link --from=wheel-opencv-python-headless /out/ /

FROM s17 AS s18
COPY --link --from=file-manifest /out/ /
