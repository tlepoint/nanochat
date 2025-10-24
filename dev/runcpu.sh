#!/bin/bash

# Showing an example run for exercising some of the code paths on the CPU (or MPS on Macbooks)
# Run as:
# bash dev/cpu_demo_run.sh

# NOTE: Training LLMs requires GPU compute and $$$. You will not get far on your Macbook.
# Think of this run as educational/fun demo, not something you should expect to work well.
# This is also why I hide this script away in dev/

# all the setup stuff
export OMP_NUM_THREADS=1
export PYTORCH_MPS_HIGH_WATERMARK_RATIO=0.0
SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
source "$SCRIPT_DIR/setup.sh"
source "$SCRIPT_DIR/tokenizer.sh"

bootstrap_nanochat cpu
ensure_eval_bundle

# wipe the report
python -m nanochat.report reset

# train tokenizer on ~1B characters
ensure_dataset_shards 4
# train/evaluate tokenizer with caching to avoid redundant work
ensure_tokenizer 1000000000 || exit 1

# train a very small 8 layer model on the CPU
# each optimization step processes a single sequence of 1024 tokens
# we only run 400 steps of optimization (bump this to get better results)
python -m scripts.base_train \
    --depth=8 \
    --max_seq_len=1024 \
    --device_batch_size=1 \
    --total_batch_size=1024 \
    --eval_every=50 \
    --checkpoint_every=50 \
    --eval_tokens=4096 \
    --core_metric_every=50 \
    --core_metric_max_per_task=12 \
    --sample_every=50 \
    --num_iterations=400
python -m scripts.base_loss --device_batch_size=1 --split_tokens=4096
python -m scripts.base_eval --max-per-task=16

# midtraining
python -m scripts.mid_train \
    --max_seq_len=1024 \
    --device_batch_size=1 \
    --eval_every=50 \
    --eval_tokens=4096 \
    --total_batch_size=1024 \
    --num_iterations=100
# eval results will be terrible, this is just to execute the code paths.
# note that we lower the execution memory limit to 1MB to avoid warnings on smaller systems
python -m scripts.chat_eval --source=mid --max-new-tokens=128 --max-problems=20

# SFT
python -m scripts.chat_sft \
    --device_batch_size=1 \
    --target_examples_per_step=4 \
    --num_iterations=100 \
    --eval_steps=4 \
    --eval_metrics_max_problems=16

# Chat CLI
# python -m scripts.chat_cli -p "Why is the sky blue?"

# Chat Web
# python -m scripts.chat_web

python -m nanochat.report generate
