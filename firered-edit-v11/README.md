# FireRed-Image-Edit-1.1 for SaladCloud (lantern-wan22-salad:firered-edit-v11-q6k-lightning-v1)

Container image for [SaladCloud](https://salad.com): SaladTechnologies' ComfyUI image with the open-weights **FireRed-Image-Edit-1.1** image-editing model baked in (GGUF Q6_K, with its text encoder, VAE and Lightning speed LoRA), so a new node pulls the weights with the image instead of downloading them at start. Only open-weight models and open-source code are included; there is no safety checker or content filter in the image.

Image: `ghcr.io/<owner>/lantern-wan22-salad:firered-edit-v11-q6k-lightning-v1`. Pin it by digest. Built by `.github/workflows/build-firered-edit-v11.yml`
from `firered-edit-v11/Dockerfile` (self-contained: the downloader and the layout manifest are embedded in it).
Every file is downloaded from the pinned URL below inside the build and must match its SHA-256.

## What is inside

| Model | Source (revision) | File | Bytes | SHA-256 | Licence | In the image |
|---|---|---|---|---|---|---|
| FireRed-Image-Edit-1.1 (20B Qwen-Image MMDiT), GGUF Q6_K (vantagewithai conversion of FireRedTeam/FireRed-Image-Edit-1.1) | [`vantagewithai/FireRed-Image-Edit-1.1-GGUF`](https://huggingface.co/vantagewithai/FireRed-Image-Edit-1.1-GGUF) @ `6882be7fafd5` | `FireRed-Image-Edit-1.1-Q6_K.gguf` | 16,824,990,272 | `00fa3171c44b0d526c0d1450a4e39235216eb7905dc27b8fe8b853036b849cd1` | apache-2.0 | `/opt/lantern/parts/FireRed-Image-Edit-1.1-Q6_K.gguf.part00` .. `.part07` (8 layers) |
| Qwen2.5-VL-7B-Instruct text encoder, fp8 scaled (Comfy-Org repackage) | [`Comfy-Org/Qwen-Image`](https://huggingface.co/Comfy-Org/Qwen-Image) @ `1f12b17be14c` | `split_files/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors` | 9,384,670,680 | `cb5636d852a0ea6a9075ab1bef496c0db7aef13c02350571e388aea959c5c0b4` | apache-2.0 | `/opt/lantern/parts/qwen_2.5_vl_7b_fp8_scaled.safetensors.part00` .. `.part04` (5 layers) |
| Qwen-Image VAE (Comfy-Org repackage) | [`Comfy-Org/Qwen-Image`](https://huggingface.co/Comfy-Org/Qwen-Image) @ `1f12b17be14c` | `split_files/vae/qwen_image_vae.safetensors` | 253,806,246 | `a70580f0213e67967ee9c95f05bb400e8fb08307e017a924bf3441223e023d1f` | apache-2.0 | `/opt/ComfyUI/models/vae/qwen_image_vae.safetensors` |
| FireRed-Image-Edit-1.1 Lightning 8-step LoRA v1.2 (FireRedTeam), bf16 | [`FireRedTeam/FireRed-Image-Edit-1.1-ComfyUI`](https://huggingface.co/FireRedTeam/FireRed-Image-Edit-1.1-ComfyUI) @ `8625b60ec52d` | `FireRed-Image-Edit-1.1-Lightning-8steps-v1.2.safetensors` | 849,542,776 | `e8089300fd0b76c0bb3441ff64509258e95b483cc7c5a6f955add907d6c8177d` | apache-2.0 | `/opt/ComfyUI/models/loras/FireRed-Image-Edit-1.1-Lightning-8steps-v1.2.safetensors` |

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

Compressed: about 30.5 GB, at most 32.3 GB if the new layers do not compress at all
(base 4.97 GB + 27.31 GB of weights). Salad's limit is 35 GB.

## Licences of the weights

- **FireRed-Image-Edit-1.1** ([`FireRedTeam/FireRed-Image-Edit-1.1`](https://huggingface.co/FireRedTeam/FireRed-Image-Edit-1.1)): Apache-2.0 (model card); code [`FireRedTeam/FireRed-Image-Edit`](https://github.com/FireRedTeam/FireRed-Image-Edit): Apache-2.0. The GGUF conversion ([`vantagewithai/FireRed-Image-Edit-1.1-GGUF`](https://huggingface.co/vantagewithai/FireRed-Image-Edit-1.1-GGUF)) keeps the original weights' licence.
- **FireRed-Image-Edit-1.1 Lightning LoRA** ([`FireRedTeam/FireRed-Image-Edit-1.1-ComfyUI`](https://huggingface.co/FireRedTeam/FireRed-Image-Edit-1.1-ComfyUI)): Apache-2.0.
- **Qwen2.5-VL-7B-Instruct** (text encoder, [`Comfy-Org/Qwen-Image`](https://huggingface.co/Comfy-Org/Qwen-Image) repackage of [`Qwen/Qwen2.5-VL-7B-Instruct`](https://huggingface.co/Qwen/Qwen2.5-VL-7B-Instruct)): Apache-2.0. **Qwen-Image VAE**: Apache-2.0.
- **ComfyUI-GGUF** ([city96](https://github.com/city96/ComfyUI-GGUF)): Apache-2.0. **gguf** (PyPI): MIT.
- No safety checker or content filter is part of this image or its workflows.

Each licence is the one published on the source page linked above. This summary is not legal advice; the licence
texts and model cards govern.
