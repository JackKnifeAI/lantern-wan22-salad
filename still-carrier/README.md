# Carrier image: ComfyUI + ComfyUI-GGUF, no weights (lantern-wan22-salad:still-carrier-gguf-v1)

Container image for [SaladCloud](https://salad.com): SaladTechnologies' ComfyUI image plus the ComfyUI-GGUF node, its pinned `gguf` wheel and an (empty) layout manifest, so it adds only a few MB to a base image most Salad nodes already hold. It carries no model weights: the job controller downloads the open weights an engine needs at container start, from their pinned Hugging Face URLs, and checks every file's SHA-256. No safety checker or content filter is included.

Image: `ghcr.io/<owner>/lantern-wan22-salad:still-carrier-gguf-v1`. Pin it by digest. Built by `.github/workflows/build-still-carrier.yml`
from `still-carrier/Dockerfile` (self-contained: the downloader and the layout manifest are embedded in it).
Every file is downloaded from the pinned URL below inside the build and must match its SHA-256.

## What is inside

| Model | Source (revision) | File | Bytes | SHA-256 | Licence | In the image |
|---|---|---|---|---|---|---|


Also baked: [`city96/ComfyUI-GGUF`](https://github.com/city96/ComfyUI-GGUF) at commit `6ea2651e7df66d7585f6ffee804b20e92fb38b8a` (licence Apache-2.0, at `/opt/ComfyUI/custom_nodes/ComfyUI-GGUF`, `.git` kept) and [`gguf-0.17.1-py3-none-any.whl`](https://files.pythonhosted.org/packages/fc/31/6a93a887617ee7deeaa602ca3d02d1c12a6cb8a742a695de5d128f5fa46a/gguf-0.17.1-py3-none-any.whl) (SHA-256 `7bc5aa7eeb1931f7d39b48fdc5b38fda6b294b9dca75cf607ac69557840a3943`, licence MIT, at `/opt/lantern/wheels/`).

**Base image (unchanged):** `ghcr.io/saladtechnologies/comfyui-api@sha256:597aa2699776bbc4c24da5b1319fed9908b21a8aa0c1b807d9e1f8a0f6ce0064`
(SaladTechnologies comfyui-api: ComfyUI (GPL-3.0, source in the image at `/opt/ComfyUI`), comfyui-api (MIT),
PyTorch and the CUDA runtime under their own licences).

## Split files

GitHub's container registry accepts at most 10 GB per layer, so every file larger than 2,147,483,648 bytes is stored
as parts of that size, one part per layer. Rebuild a file by concatenating its parts in order
(`cat /opt/lantern/parts/<file>.part?? > <file>`) and check the SHA-256 in the table. `/opt/lantern/manifest.json` lists every
file, its parts, sizes, SHA-256 and the SHA-256 of its first and last 64 MiB (a fast integrity check).

## Size

Compressed: about 5.0 GB, at most 5.0 GB if the new layers do not compress at all
(base 4.97 GB + 0.00 GB of weights). Salad's limit is 35 GB.

## Licences of the weights

- **ComfyUI-GGUF** ([city96](https://github.com/city96/ComfyUI-GGUF)): Apache-2.0. **gguf** (PyPI): MIT.

Each licence is the one published on the source page linked above. This summary is not legal advice; the licence
texts and model cards govern.
