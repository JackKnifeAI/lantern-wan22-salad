# SeedVR2 video upscaler image (seedvr2/)

Container image for [SaladCloud](https://salad.com): SaladTechnologies' ComfyUI image with
[ByteDance-Seed SeedVR2](https://github.com/ByteDance-Seed/SeedVR) (one-step diffusion video restoration) and the
[`numz/ComfyUI-SeedVR2_VideoUpscaler`](https://github.com/numz/ComfyUI-SeedVR2_VideoUpscaler) ComfyUI node baked in. Open weights and code only.

Image: `ghcr.io/<owner>/lantern-wan22-salad:seedvr2-node2.5.24-3b7b-fp16-v1` (same package as the Wan image in this repo, its own tag). Pin it by
digest. Built by `.github/workflows/build-seedvr2.yml` from `seedvr2/Dockerfile`; every file is downloaded from the
pinned URL inside the build and must match its SHA-256.

## What is inside

| Model | Source (revision) | File | Bytes | SHA-256 | Licence | In the image |
|---|---|---|---|---|---|---|
| SeedVR2 7B DiT, EMA, fp16 (numz repackage of ByteDance-Seed/SeedVR2-7B) | [`numz/SeedVR2_comfyUI`](https://huggingface.co/numz/SeedVR2_comfyUI) @ `09ced7102363` | `seedvr2_ema_7b_fp16.safetensors` | 16,479,334,424 | `7b8241aa957606ab6cfb66edabc96d43234f9819c5392b44d2492d9f0b0bbe4a` | apache-2.0 | `/opt/lantern/parts/seedvr2_ema_7b_fp16.safetensors.part00` .. `.part07` (8 layers) |
| SeedVR2 3B DiT, EMA, fp16 (numz repackage of ByteDance-Seed/SeedVR2-3B) | [`numz/SeedVR2_comfyUI`](https://huggingface.co/numz/SeedVR2_comfyUI) @ `09ced7102363` | `seedvr2_ema_3b_fp16.safetensors` | 6,783,018,808 | `2fd0e03a3dad24e07086750360727ca437de4ecd456f769856e960ae93e2b304` | apache-2.0 | `/opt/lantern/parts/seedvr2_ema_3b_fp16.safetensors.part00` .. `.part03` (4 layers) |
| SeedVR2 video VAE, EMA, fp16 | [`numz/SeedVR2_comfyUI`](https://huggingface.co/numz/SeedVR2_comfyUI) @ `09ced7102363` | `ema_vae_fp16.safetensors` | 501,324,814 | `20678548f420d98d26f11442d3528f8b8c94e57ee046ef93dbb7633da8612ca1` | apache-2.0 | `/opt/ComfyUI/models/SEEDVR2/ema_vae_fp16.safetensors` |

**Not in the image:** the [`numz/ComfyUI-SeedVR2_VideoUpscaler`](https://github.com/numz/ComfyUI-SeedVR2_VideoUpscaler) node (licence Apache-2.0). The container clones it
from that repository at commit `4490bd1f482e026674543386bb2a4d176da245b9` when it starts and checks the commit. One of its helper files,
`src/utils/color_fix.py`, matches code published under a non-commercial licence (S-Lab License 1.0), so this image
does not redistribute the node. The colour-correction modes that run those functions (`lab`, `wavelet`,
`wavelet_adaptive`, `adain`) are not used by our engine; it uses `hsv`.

Python dependencies the base image lacks, as wheels at `/opt/lantern/wheels/` (installed offline, hash-locked, at
container start):

| Wheel | SHA-256 | Licence | Why |
|---|---|---|---|
| `diffusers-0.37.1-py3-none-any.whl` | `0537c0b28cb53cf39d6195489bcf8f833986df556c10f5e28ab7427b86fc8b90` | Apache-2.0 | the node's DiT/VAE layers import diffusers classes at module level (0.38+ needs a newer safetensors than the base) |
| `omegaconf-2.4.0-py3-none-any.whl` | `f141a664c777582405e3cc6e0545ecc79429e79f844995b1a6e71c35946a025c` | BSD-3-Clause | model configs (module-level import); 2.4.0 vendors antlr4, so no extra wheel |
| `rotary_embedding_torch-0.8.9-py3-none-any.whl` | `700e8de9dfbefba5f9117a66652a2520648dcc60136895f0068b6a85347cab02` | MIT | RoPE in the 3B/7B DiTs |
| `opencv_python_headless-4.11.0.86-cp37-abi3-manylinux_2_17_x86_64.manylinux2014_x86_64.whl` | `0e0a27c19dd1f40ddff94976cfe43066fbbe9dfbb2ec1907d66c19caef42a57b` | Apache-2.0 | imported at module level (alpha upscaling); headless = no libGL needed; works with numpy 1.x or 2.x |

**Base image (unchanged):** `ghcr.io/saladtechnologies/comfyui-api@sha256:597aa2699776bbc4c24da5b1319fed9908b21a8aa0c1b807d9e1f8a0f6ce0064` (ComfyUI v0.12.3, GPL-3.0, source in the image at `/opt/ComfyUI`;
comfyui-api 1.17.1, MIT; PyTorch 2.8.0 and the CUDA 12.8 runtime under their own licences).

Files over 2,147,483,648 bytes are stored as parts (one layer each; GHCR limits a layer to 10 GB); concatenate the parts
in order and check the SHA-256. `/opt/lantern/manifest.json` lists every file, its parts and hashes.

## Size

Compressed: about 27.0 GB, at most 28.7 GB (base 4.97 GB + 23.76 GB of weights).
Salad's limit is 35 GB.

## Licences

- **SeedVR2 weights** ([`ByteDance-Seed/SeedVR2-3B`](https://huggingface.co/ByteDance-Seed/SeedVR2-3B), [`-7B`](https://huggingface.co/ByteDance-Seed/SeedVR2-7B)): Apache-2.0 (model cards: "SeedVR and SeedVR2 are licensed under the Apache 2.0"). The fp16 files used here are the [`numz/SeedVR2_comfyUI`](https://huggingface.co/numz/SeedVR2_comfyUI) repackage (card licence: apache-2.0).
- **SeedVR code** ([`ByteDance-Seed/SeedVR`](https://github.com/ByteDance-Seed/SeedVR)): Apache-2.0.
- **ComfyUI-SeedVR2_VideoUpscaler** ([numz](https://github.com/numz/ComfyUI-SeedVR2_VideoUpscaler)): Apache-2.0 at the pinned commit (earlier releases were MIT).
- **Wheels**: diffusers Apache-2.0; omegaconf BSD-3-Clause (vendors the antlr4 runtime, BSD); rotary-embedding-torch MIT; opencv-python-headless Apache-2.0.

This summary is not legal advice; the licence texts and model cards govern.
