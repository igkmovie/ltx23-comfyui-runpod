# LTX-2.3 / AnimeGen-I2V ComfyUI on RunPod(その他のGPUホストでも可)

このリポジトリは、LTX-2.3およびAnimeGen-I2Vのワークフローを動かすComfyUIを
クリーンなGPUホスト上に再現するためのセットアップ一式です。ComfyUI本体や
モデルファイルは意図的にGit管理していません — セットアップ時に、選んだ
ワークフローが必要とするものだけをbootstrapスクリプトがダウンロードします。

## 対象ホスト

- GPU: A40 48GB(bf16チェックポイントの場合。48GB以上のVRAMが目安。`fp8`
  チェックポイントならもっと小さいGPUでも収まります)
- RunPodイメージ: `runpod/pytorch:1.0.2-cu1281-torch280-ubuntu2404`、
  `/workspace` に永続ボリュームをマウント
- 普通のGPU VM(例: CUDA対応イメージのGCP Compute Engine)でも動作します —
  詳細は下の「他のホスト」を参照。

## セットアップ

ホストのターミナルから:

```bash
git clone https://github.com/igkmovie/ltx23-comfyui-runpod.git /workspace/ltx23-comfyui-runpod
bash /workspace/ltx23-comfyui-runpod/scripts/bootstrap-runpod.sh AnimeGen-I2V_832x480_5s
```
bash /workspace/ltx23-comfyui-runpod/scripts/bootstrap-runpod.sh <workflow-name>
`<workflow-name>` は `workflows/` 内の任意のファイル名です(`.json` の有無は
どちらでも可)。例:

```bash
bash scripts/bootstrap-runpod.sh LTX-2.3_Distilled_I2V_Simple
bash scripts/bootstrap-runpod.sh LTX-2.3_Distilled_I2V_Simple_FP8
bash scripts/bootstrap-runpod.sh LTX-2.3_Distilled_NoLoRA
bash scripts/bootstrap-runpod.sh AnimeGen-I2V_832x480_5s
```

引数なしで実行すると、使い方と利用可能なワークフロー一覧が表示されます。

このスクリプトは**選択したワークフローが実際に参照しているモデルだけ**を
(`models-manifest.json` で名前引きして)ダウンロードし、その後 `workflows/`
内の全ワークフローをComfyUIにコピーします(モデルさえ揃えば、UI上で他の
ワークフローにも切り替えられます)。ダウンロードは再開可能です — 大きなモデル
の途中でダウンロードが止まっても、もう一度実行すれば `curl -C -` が続きから
再開します。

**カスタムノードも同じ発想で解決されます。** ComfyUI本体のコア組み込み
ノードだけで選択したワークフローの要求を満たせるか確認し、足りない場合だけ
`custom-nodes-manifest.json` を名前引きして必要なリポジトリ(現状
`ComfyUI-LTXVideo`, `RES4LYF`)だけをクローンします。各リポジトリは
マニフェストに記録された特定のコミット(`revision`)にチェックアウトされ、
上流の最新コミットを無条件に追従することはありません。

第2引数に `--no-start` を渡すと、ComfyUIの起動をスキップします(サーバーを
起動せずにホストを事前に温めておきたい場合に便利です)。

### 利用可能なワークフロー

| ワークフロー | 説明 |
|---|---|
| `AnimeGen-I2V_832x480_5s` | AIdeaLab AnimeGen-I2Vによるアニメ向けImage-to-Video。入力画像から832×480・5秒・16fpsを生成し、high/low-noiseモデルを8ステップで切り替える。 |
| `AnimeGen-I2V-NSFW_832x480_5s` | 上記に2D Animation Effects LoRA(high/low)とNSFW向けself-attn LoRA(low-noiseのみ)を追加したバリアント。LoRAファイルはCivitaiの認証が必要なため手動配置が前提(下記参照)。 |
| `LTX-2.3_Distilled_I2V_Simple` | 一本道のImage-to-Video、音声出力なし、bf16チェックポイント(約46GB)。まずはこれがおすすめ。 |
| `LTX-2.3_Distilled_I2V_Simple_FP8` | 上と同じグラフで、fp8量子化チェックポイント(約29.5GB)。ディスクから読むデータ量が少ない分、初回のチェックポイント読み込みが体感でも速くなる。 |
| `LTX-2.3_Distilled_NoLoRA` | 音声+映像のフル2系統ワークフロー(Distilled/Full品質の両ブランチ)。 |
| `LTX-2.3_Distilled_NoLoRA_NoAudio` | 上と同じだが、音声デコード・保存ノードを削除したもの。 |
| `LTX-2.3_Distilled_PublicGemma` | 公開版Gemmaテキストエンコーダーを使う2系統ワークフロー(音声VAEデコードあり)。 |

### AnimeGen-I2V

`AnimeGen-I2V_832x480_5s`はT2Vではなく、`Load Image`で指定した画像を
`WanImageToVideo`の開始画像として使うI2V専用ワークフローです。positive promptには
画像の説明を繰り返すより、`gently blinks`、`turns her head`、
`hair sways in the breeze`のように動作を英語で簡潔に指定してください。

AnimeGenのhigh/low-noiseモデルだけで合計約57.2GBあります。LoRA、T5、
VAE、ComfyUI環境を含め、クリーンなボリュームでも100GB以上の空きを推奨します。
既存のLTX-2.3モデルを同じ永続ボリュームに残す場合は、bootstrap実行前に
`df -h /workspace`で空き容量を確認してください。A40 48GBではComfyUIの
モデルオフロードを利用する前提です。

### AnimeGen-I2V-NSFW

`AnimeGen-I2V-NSFW_832x480_5s`は`AnimeGen-I2V_832x480_5s`と同じベース構成に、
以下3つのLoRAを鎖状に追加したものです。

- `2D_animation_effects_high_noise.safetensors` / `_low_noise.safetensors` —
  high/low-noise両ブランチに強度1.0で適用。
- `lightfix_selfattn_merged_NSFW-22-L-e8.safetensors` — **low-noiseブランチのみ**
  に強度1.0で適用(ファイル名の`L`が示す通りlow-noise専用。self-attention層
  [blocks 0-9]のみのパッチで、high-noiseブランチには繋いでいない)。

これら3ファイルはCivitaiのログイン/APIトークンが必要で直接curlできないため、
専用の小さな公開GCSバケット(`creachat-trial-2026-wan22-loras-public`、
この3ファイルのみ・他の本番アセットとは別バケット)に置いてあります。
`models-manifest.json`のURLは通常のHTTPS直リンクなので、他のワークフロー
同様にbootstrapが自動でダウンロードします。追加の認証設定は不要です。

RunPodを何度も作り直す運用を想定しているため、認証周りの複雑さより
「誰でも読める代わりに何も考えず動く」方を優先した構成です。バケットは
このLoRA配布専用で、機密情報や他のプロジェクト資産とは分離しています。

### 新しいワークフローを追加する

1. ワークフローのJSONを `workflows/` に置く。
2. `python scripts/register-workflow-models.py workflows/<name>.json` を実行し、
   新しく出てきたモデルファイル名を `models-manifest.json` に雛形登録する
   (保存先ディレクトリは推測、URLは `TODO` プレースホルダ)。
3. 新規エントリそれぞれについて、`models-manifest.json` に実際のダウンロード
   URLを記入する。
4. `python scripts/register-workflow-nodes.py --comfy-root <ComfyUIのパス> workflows/<name>.json`
   を実行し、コアで足りないノードクラスを確認する。未分類のクラスがあれば
   `--write` を付けて再実行し、`custom-nodes-manifest.json` にTODOスタブを
   追記する(`--write` を付けない限りファイルは一切変更されない)。
5. 追記されたTODOエントリそれぞれについて、`custom-nodes-manifest.json` に
   実際の `git_url` と(動作確認済みの)`revision` を記入する。
6. これで `bash scripts/bootstrap-runpod.sh <name>` が、そのワークフローに
   必要なモデル・カスタムノードだけを正しく解決するようになる。

ワークフローがどちらかのマニフェストに登録されていないモデル/ノードクラスを
参照している場合や、エントリはあってもURL/リポジトリが `TODO` のままの場合、
`bootstrap-runpod.sh` は対応するregisterスクリプトを指し示す明確なエラーで
実行を拒否します — 必要なダウンロード/インストールを黙ってスキップすること
はありません。

**既知の制限事項:**
- 必要ノード・必要モデルの抽出はワークフローJSON内の全ノードを対象にし、
  `mode`(無効化/ミュート状態)は見ません。
- 複数のカスタムノードリポジトリが異なるバージョンの同じPythonパッケージを
  要求する場合の依存関係解決は行いません(後からインストールした方が勝ちます)。
- `custom-nodes-manifest.json` の `revision` は「動作確認済みの1点」を
  記録しているだけで、上流の継続的な追従(自動更新)はしません。

### 他のホスト(GCPなど)

`COMFY_ROOT` と `PROJECT_ROOT` はデフォルトでRunPodの `/workspace` 規約に
従いますが、別の場所にストレージをマウントするホスト向けに上書きできます:

```bash
COMFY_ROOT=/opt/ComfyUI PROJECT_ROOT=/opt/ltx23-comfyui-runpod \
  bash scripts/bootstrap-runpod.sh LTX-2.3_Distilled_I2V_Simple
```

スクリプトの他の部分にRunPod固有の要素はなく、NVIDIA GPU・git・curl・
Python 3が使えるLinuxホストであれば動作します。

bootstrapは、古い `gemma_3_12B_it_fp8_scaled.safetensors` ファイルを削除
してから、公開版の `gemma_3_12B_it_fp4_mixed.safetensors` エンコーダーを
導入します。また、PyTorchがGPUを認識できるか検証し、ベースイメージが
まだ使えるCUDAを提供していない場合のみCUDA 12.8のwheelを導入します。

セットアップスクリプトは、モデル・依存関係・カスタムノード・選択した
ワークフローの検証が全て通った後、ポート `8188`(`COMFY_PORT` で上書き可)
でComfyUIを自動起動します。GUIを使う間はターミナルを開いたままにしてください。
