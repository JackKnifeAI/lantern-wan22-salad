# Qwen-Image-Edit-2511 for SaladCloud (lantern-wan22-salad:qwen-edit-2511-q6k-lightning-v1)

Container image for [SaladCloud](https://salad.com): SaladTechnologies' ComfyUI image with the open-weights **Qwen-Image-Edit-2511** image-editing model baked in (GGUF Q6_K, with its text encoder, VAE and Lightning speed LoRA), so a new node pulls the weights with the image instead of downloading them at start. Only open-weight models and open-source code are included; there is no safety checker or content filter in the image.

Image: `ghcr.io/<owner>/lantern-wan22-salad:qwen-edit-2511-q6k-lightning-v1`. Pin it by digest. Built by `.github/workflows/build-qwen-edit-2511.yml`
from `qwen-edit-2511/Dockerfile` (self-contained: the downloader and the layout manifest are embedded in it).
Every file is downloaded from the pinned URL below inside the build and must match its SHA-256.

## What is inside

| Model | Source (revision) | File | Bytes | SHA-256 | Licence | In the image |
|---|---|---|---|---|---|---|
| Qwen-Image-Edit-2511 (20B MMDiT), GGUF Q6_K (Unsloth dynamic quant of Qwen/Qwen-Image-Edit-2511) | [`unsloth/Qwen-Image-Edit-2511-GGUF`](https://huggingface.co/unsloth/Qwen-Image-Edit-2511-GGUF) @ `52838251db24` | `qwen-image-edit-2511-Q6_K.gguf` | 17,947,757,152 | `5107c54a85d8e3ac76615612dee244268b53270d2091b525e325fc05cc84d8fd` | apache-2.0 | `/opt/lantern/parts/qwen-image-edit-2511-Q6_K.gguf.part00` .. `.part08` (9 layers) |
| Qwen2.5-VL-7B-Instruct text encoder, fp8 scaled (Comfy-Org repackage) | [`Comfy-Org/Qwen-Image`](https://huggingface.co/Comfy-Org/Qwen-Image) @ `1f12b17be14c` | `split_files/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors` | 9,384,670,680 | `cb5636d852a0ea6a9075ab1bef496c0db7aef13c02350571e388aea959c5c0b4` | apache-2.0 | `/opt/lantern/parts/qwen_2.5_vl_7b_fp8_scaled.safetensors.part00` .. `.part04` (5 layers) |
| Qwen-Image VAE (Comfy-Org repackage) | [`Comfy-Org/Qwen-Image`](https://huggingface.co/Comfy-Org/Qwen-Image) @ `1f12b17be14c` | `split_files/vae/qwen_image_vae.safetensors` | 253,806,246 | `a70580f0213e67967ee9c95f05bb400e8fb08307e017a924bf3441223e023d1f` | apache-2.0 | `/opt/ComfyUI/models/vae/qwen_image_vae.safetensors` |
| Qwen-Image-Edit-2511-Lightning 8-step distill LoRA (lightx2v), bf16 | [`lightx2v/Qwen-Image-Edit-2511-Lightning`](https://huggingface.co/lightx2v/Qwen-Image-Edit-2511-Lightning) @ `107d238d68b8` | `Qwen-Image-Edit-2511-Lightning-8steps-V1.0-bf16.safetensors` | 849,608,296 | `a9e81a58a78f260f67b337a6f615e8fa4cd3bc79847c77b7d61a581b789b1ba8` | apache-2.0 | `/opt/ComfyUI/models/loras/Qwen-Image-Edit-2511-Lightning-8steps-V1.0-bf16.safetensors` |
| Qwen-Image-Edit-2511-Lightning 4-step distill LoRA (lightx2v), bf16 | [`lightx2v/Qwen-Image-Edit-2511-Lightning`](https://huggingface.co/lightx2v/Qwen-Image-Edit-2511-Lightning) @ `107d238d68b8` | `Qwen-Image-Edit-2511-Lightning-4steps-V1.0-bf16.safetensors` | 849,608,296 | `22226e8d05d354bb356627d428809f5afd7819399b077238a2b70a82883a904f` | apache-2.0 | `/opt/ComfyUI/models/loras/Qwen-Image-Edit-2511-Lightning-4steps-V1.0-bf16.safetensors` |

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

Compressed: about 32.3 GB, at most 34.3 GB if the new layers do not compress at all
(base 4.97 GB + 29.29 GB of weights). Salad's limit is 35 GB.

## Licences of the weights

- **Qwen-Image-Edit-2511** ([`Qwen/Qwen-Image-Edit-2511`](https://huggingface.co/Qwen/Qwen-Image-Edit-2511)): Apache-2.0 (model card header and "Qwen-Image is licensed under Apache 2.0"); code [`QwenLM/Qwen-Image`](https://github.com/QwenLM/Qwen-Image): Apache-2.0. The GGUF quantisation ([`unsloth/Qwen-Image-Edit-2511-GGUF`](https://huggingface.co/unsloth/Qwen-Image-Edit-2511-GGUF)) is published under Apache-2.0.
- **Qwen-Image-Edit-2511-Lightning** ([`lightx2v/Qwen-Image-Edit-2511-Lightning`](https://huggingface.co/lightx2v/Qwen-Image-Edit-2511-Lightning)): Apache-2.0.
- **Qwen2.5-VL-7B-Instruct** (text encoder, [`Comfy-Org/Qwen-Image`](https://huggingface.co/Comfy-Org/Qwen-Image) repackage of [`Qwen/Qwen2.5-VL-7B-Instruct`](https://huggingface.co/Qwen/Qwen2.5-VL-7B-Instruct)): Apache-2.0. **Qwen-Image VAE**: Apache-2.0.
- **ComfyUI-GGUF** ([city96](https://github.com/city96/ComfyUI-GGUF)): Apache-2.0. **gguf** (PyPI): MIT.
- No safety checker or content filter is part of this image or its workflows.

Each licence is the one published on the source page linked above. This summary is not legal advice; the licence
texts and model cards govern.
