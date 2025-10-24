#!/bin/bash

# The $1000 tier of nanochat
# Designed to run end-to-end for $1000/24 ~= 41.6 hours on an 8XH100 node
# A bit sparser on comments, see speedrun.sh for more detail

# all the setup stuff
export OMP_NUM_THREADS=1

REPO_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
source "$REPO_ROOT/dev/setup.sh"
source "$REPO_ROOT/dev/tokenizer.sh"

bootstrap_nanochat gpu
python -m nanochat.report reset
ensure_eval_bundle
if [ ! -f "$NANOCHAT_DATASETS_DIR/identity_conversations.jsonl" ]; then
    log_step "Downloading identity conversations dataset."
    curl -sSL -o $NANOCHAT_DATASETS_DIR/identity_conversations.jsonl https://karpathy-public.s3.us-west-2.amazonaws.com/identity_conversations.jsonl
else
    setup_success "Identity conversations dataset already present."
fi

# train tokenizer on ~4B characters and kick off download of the rest for pretraining
ensure_dataset_shards 16
# start downloading the rest of the shards for a total of 800 (see below why 800)
prefetch_dataset_shards 800 DATASET_DOWNLOAD_PID || DATASET_DOWNLOAD_PID=""
# todo: download the rest of it
# train/evaluate tokenizer with caching to avoid redundant work
ensure_tokenizer 4000000000 || exit 1

if [ -n "${DATASET_DOWNLOAD_PID:-}" ]; then
    log_step "Waiting for dataset download to complete..."
    wait "$DATASET_DOWNLOAD_PID"
fi

# Documenting my process for determining the hyperparameters for this run1000.sh script:
# We want a budget of approx. $1000 ~= 41.6 hours of 8XH100 compute
# 1) I guessed the model size for this to be about depth=32
# 2) Determine the device_batch_size that fits:
# Running the base_train.py script with --depth=32, I saw that --device_batch_size=16
# runs out of memory, but --device_batch_size=8 fits. Inspecting `nvidia-smi` during training,
# I saw all GPUs were at about 78/80GB VRAM, so it just barely fits and we have good MFU at ~50%.
# So the training script was running ok and showed:
# Vocab size: 65,536
# num_layers: 32
# model_dim: 2048
# num_heads: 16
# num_kv_heads: 16
# Tokens / micro-batch / rank: 8 x 2048 = 16,384
# Tokens / micro-batch: 131,072
# Total batch size 524,288 => gradient accumulation steps: 4
# Number of parameters: 1,879,048,192
# Estimated FLOPs per token: 1.207960e+10
# Calculated number of iterations from target data:param ratio: 71,680
# Total number of training tokens: 37,580,963,840
# Tokens : Params ratio: 20.00
# Total training FLOPs estimate: 4.539628e+20
# step 00004/71680 (0.01%) | loss: 8.813754 | lrm: 1.00 | dt: 1571.88ms | tok/sec: 83,385 | mfu: 50.92 | total time: 0.00m
# step 00005/71680 (0.01%) | loss: 8.488074 | lrm: 1.00 | dt: 1572.76ms | tok/sec: 83,338 | mfu: 50.89 | total time: 0.00m
# ...
# 3) validate that the runtime fits our budget:
# The training script uses the Chinchilla scaling law to compute-optimally set #tokens = 20 * #params. In particular:
# The script shows that we will be training for 71,680 steps, and each step takes 1.574s so:
# estimated time to train: 71,680 * 1.574s / 60 / 60 = 31.3 hours.
# This is OK, fits our budget, and leaves ~10 hours for midtraining and SFT and evals and maybe RL.
# It's possible that we might even fit depth=33 or depth=34, but for now let's go along with this.
# 4) The last thing to pay attention to is the amount of training data required for the run.
# The script above calculated that "Total number of training tokens: 37,580,963,840"
# The tok_eval.py script reports about ~4.8 chars/token on average for the default tokenizer settings.
# So ~38B tokens # ~4.8 chars/token = ~185B chars.
# Each data shard is ~250M chars, so we need ~185B / 250M ~= 740 shards.
# For safety, I bumped that up to 800 shards, and that's why up above I used -n 800 when pre-downloading dataset shards.
# If we didn't have enough data, the training script would loop around and do multiple epochs over the same data,
# which would decrease model performance. Possibly 2, 3 or so epochs is ~ok, but certainly not ideal and at 10+ epochs we'd
# start to overfit hard.
# 5) That's it, everything else (e.g. the learning rates) is adjusted automatically by the training script.
torchrun --standalone --nproc_per_node=8 -m scripts.base_train -- --depth=32 --device_batch_size=8
torchrun --standalone --nproc_per_node=8 -m scripts.base_loss
torchrun --standalone --nproc_per_node=8 -m scripts.base_eval

# midtrain
# NOTE: ensure that we use the same device_batch_size here as the base training script.
torchrun --standalone --nproc_per_node=8 -m scripts.mid_train -- --device_batch_size=8 --run=$WANDB_RUN
torchrun --standalone --nproc_per_node=8 -m scripts.chat_eval -- -i mid

# sft
torchrun --standalone --nproc_per_node=8 -m scripts.chat_sft -- --run=$WANDB_RUN
torchrun --standalone --nproc_per_node=8 -m scripts.chat_eval -- -i sft

# generate final report
python -m nanochat.report generate

# talk to it
python -m scripts.chat_web
