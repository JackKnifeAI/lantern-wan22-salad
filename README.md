# lantern-wan22-salad

Container image for [SaladCloud](https://salad.com): SaladTechnologies' ComfyUI image with the **Wan 2.2
I2V-A14B** video weights baked in, so a new or pre-empted node pulls them with the image (free, cached per node)
instead of downloading ~25 GB at start. Only open-weight models are included.

Image: `ghcr.io/<owner>/lantern-wan22-salad:comfy0.12.3-q6k-lightx2v1022-v1`. Pin it by digest. Built by `.github/workflows/build.yml` from this
`Dockerfile`. Every file is downloaded from the pinned URL below inside the build and must match its SHA-256.

## What is inside

| Model | Source (revision) | File | Bytes | SHA-256 | Licence | In the image |
|---|---|---|---|---|---|---|
| Wan2.2 I2V-A14B high-noise expert, GGUF Q6_K (QuantStack conversion of Wan-AI/Wan2.2-I2V-A14B) | [`QuantStack/Wan2.2-I2V-A14B-GGUF`](https://huggingface.co/QuantStack/Wan2.2-I2V-A14B-GGUF) @ `6c6717459277` | `HighNoise/Wan2.2-I2V-A14B-HighNoise-Q6_K.gguf` | 12,003,652,096 | `33ab8d99b5be745d2c939055f541d09108befe3467802fdbbf22ba8e4e62383c` | apache-2.0 | `/opt/lantern/parts/Wan2.2-I2V-A14B-HighNoise-Q6_K.gguf.part00` .. `.part05` (6 layers) |
| Wan2.2 I2V-A14B low-noise expert, GGUF Q6_K (QuantStack conversion of Wan-AI/Wan2.2-I2V-A14B) | [`QuantStack/Wan2.2-I2V-A14B-GGUF`](https://huggingface.co/QuantStack/Wan2.2-I2V-A14B-GGUF) @ `6c6717459277` | `LowNoise/Wan2.2-I2V-A14B-LowNoise-Q6_K.gguf` | 12,003,652,096 | `962d9c937a6e882562cd234ba87c5cfc19d6e99efbf0fc31b4dd9e43eb493ae6` | apache-2.0 | `/opt/lantern/parts/Wan2.2-I2V-A14B-LowNoise-Q6_K.gguf.part00` .. `.part05` (6 layers) |
| lightx2v 4-step distill LoRA, low-noise expert (rank 64, release 1022) | [`lightx2v/Wan2.2-Distill-Loras`](https://huggingface.co/lightx2v/Wan2.2-Distill-Loras) @ `57adea585d1d` | `wan2.2_i2v_A14b_low_noise_lora_rank64_lightx2v_4step_1022.safetensors` | 739,472,104 | `8833bd4fd7c8eabebf0bc8ee5cfaf47f4f310ce116928a02c1adf8941dd4b0f1` | apache-2.0 | `/opt/ComfyUI/models/loras/wan2.2_i2v_A14b_low_noise_lora_rank64_lightx2v_4step_1022.safetensors` |
| lightx2v 4-step distill LoRA, high-noise expert (rank 64, release 1022) | [`lightx2v/Wan2.2-Distill-Loras`](https://huggingface.co/lightx2v/Wan2.2-Distill-Loras) @ `57adea585d1d` | `wan2.2_i2v_A14b_high_noise_lora_rank64_lightx2v_4step_1022.safetensors` | 634,645,944 | `887c3bdeb74e83859c920438e16ca31f39ab18ce189abc5f0e36f8348c5bbb19` | apache-2.0 | `/opt/ComfyUI/models/loras/wan2.2_i2v_A14b_high_noise_lora_rank64_lightx2v_4step_1022.safetensors` |
| Wan 2.1 VAE (used by Wan 2.2 A14B), Comfy-Org repackage | [`Comfy-Org/Wan-2.2`](https://huggingface.co/Comfy-Org/Wan-2.2) @ `ee6f4a40737a` | `split_files/vae/wan_2.1_vae.safetensors` | 253,815,318 | `2fc39d31359a4b0a64f55876d8ff7fa8d780956ae2cb13463b0223e15148976b` | apache-2.0 | `/opt/ComfyUI/models/vae/wan_2.1_vae.safetensors` |

Also baked: [`city96/ComfyUI-GGUF`](https://github.com/city96/ComfyUI-GGUF) at commit `6ea2651e7df66d7585f6ffee804b20e92fb38b8a` (licence Apache-2.0, at
`/opt/ComfyUI/custom_nodes/ComfyUI-GGUF`, `.git` kept) and its dependency [`gguf-0.17.1-py3-none-any.whl`](https://pypi.org/project/gguf/0.17.1/)
(SHA-256 `7bc5aa7eeb1931f7d39b48fdc5b38fda6b294b9dca75cf607ac69557840a3943`, licence MIT, at `/opt/lantern/wheels/`).

**Not included:** the umt5-xxl text encoder (`umt5_xxl_fp8_e4m3fn_scaled.safetensors`, 6,735,906,897 B, Apache-2.0,
[`Comfy-Org/Wan-2.1`](https://huggingface.co/Comfy-Org/Wan-2.1)). With it the image would exceed Salad's 35 GB
image limit, so containers download it at start.

**Base image (unchanged):** `ghcr.io/saladtechnologies/comfyui-api@sha256:597aa2699776bbc4c24da5b1319fed9908b21a8aa0c1b807d9e1f8a0f6ce0064`
(tag `comfy0.12.3-api1.17.1-torch2.8.0-cuda12.8-runtime`): ComfyUI v0.12.3 (GPL-3.0, its source is in the image at
`/opt/ComfyUI`), comfyui-api 1.17.1 (MIT), PyTorch 2.8.0 and the CUDA 12.8 runtime under their own licences.

## Split files

GitHub's container registry accepts at most 10 GB per layer, so each 12.0 GB GGUF expert is stored as
2,147,483,648-byte parts, one part per layer. Rebuild a file by concatenating its parts in order, then check the
SHA-256 in the table:

```sh
cat /opt/lantern/parts/Wan2.2-I2V-A14B-HighNoise-Q6_K.gguf.part0? > Wan2.2-I2V-A14B-HighNoise-Q6_K.gguf
sha256sum Wan2.2-I2V-A14B-HighNoise-Q6_K.gguf   # 33ab8d99...2383c
```

`/opt/lantern/manifest.json` lists every file, its parts, sizes, SHA-256, and the SHA-256 of its first and last 64 MiB
(a fast integrity check).

## Size

Compressed: about 30.3 GB, at most 30.6 GB if the new layers do not compress at all
(base 4.97 GB + 25.64 GB of weights). Salad's limit is 35 GB.

## Licences of the weights

- **Wan2.2-I2V-A14B** ([`Wan-AI/Wan2.2-I2V-A14B`](https://huggingface.co/Wan-AI/Wan2.2-I2V-A14B)): Apache-2.0.
  The model card says the authors claim no rights over generated content, and lists uses the licence does not allow
  (breaking laws, harming people, spreading harmful misinformation, and so on). The GGUF quantisations
  ([`QuantStack/Wan2.2-I2V-A14B-GGUF`](https://huggingface.co/QuantStack/Wan2.2-I2V-A14B-GGUF)) keep the original
  licence terms.
- **lightx2v Wan2.2-Distill-Loras** ([`lightx2v/Wan2.2-Distill-Loras`](https://huggingface.co/lightx2v/Wan2.2-Distill-Loras)): Apache-2.0.
- **Wan 2.1 VAE** ([`Comfy-Org/Wan-2.2`](https://huggingface.co/Comfy-Org/Wan-2.2) repackage): Apache-2.0.
- **ComfyUI-GGUF** ([city96](https://github.com/city96/ComfyUI-GGUF)): Apache-2.0. **gguf** (PyPI): MIT.

Each licence is the one published on the source page linked above. This summary is not legal advice; the licence
texts and model cards govern.
