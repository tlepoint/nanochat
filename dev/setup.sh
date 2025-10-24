#!/bin/bash

# Shared helpers for bootstrapping nanochat runs.

SETUP_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO_ROOT="$(cd "$SETUP_DIR/.." >/dev/null 2>&1 && pwd)"

source "$REPO_ROOT/dev/logging.sh"

setup_info() {
    log_info "setup" "$@"
}

setup_warn() {
    log_warn "setup" "$@"
}

setup_success() {
    log_success "setup" "$@"
}

setup_error() {
    log_error "setup" "$@"
}

log_step() {
    setup_info "$@"
}

_base_dataset_dir() {
    echo "${NANOCHAT_DATASETS_DIR:-$HOME/.cache/nanochat/datasets}/base_data"
}

_count_missing_shards() {
    local upto="$1"
    local data_dir="$(_base_dataset_dir)"
    local missing=0
    mkdir -p "$data_dir"
    local shard
    for ((i = 0; i < upto; i++)); do
        shard=$(printf "shard_%05d.parquet" "$i")
        if [ ! -f "$data_dir/$shard" ]; then
            missing=$((missing + 1))
        fi
    done
    echo "$missing"
}

ensure_dataset_shards() {
    local upto="$1"
    if [ -z "$upto" ] || [ "$upto" -le 0 ]; then
        echo "ensure_dataset_shards: positive shard count required" >&2
        return 1
    fi
    local missing
    missing=$(_count_missing_shards "$upto")
    if [ "$missing" -eq 0 ]; then
        setup_success "Base dataset shards 0..$((upto-1)) already present."
        return 0
    fi
    log_step "Downloading base dataset shards 0..$((upto-1)) (missing: $missing)."
    python -m nanochat.dataset -n "$upto" --quiet
}

prefetch_dataset_shards() {
    local upto="$1"
    local pid_var="$2"
    if [ -z "$upto" ] || [ "$upto" -le 0 ]; then
        echo "prefetch_dataset_shards: positive shard count required" >&2
        return 1
    fi
    local missing
    missing=$(_count_missing_shards "$upto")
    if [ "$missing" -eq 0 ]; then
        setup_success "Base dataset shards 0..$((upto-1)) already present; skipping prefetch."
        return 1
    fi
    log_step "Prefetching base dataset shards 0..$((upto-1)) in background (missing: $missing)."
    python -m nanochat.dataset -n "$upto" --quiet &
    local pid=$!
    if [ -n "$pid_var" ]; then
        printf -v "$pid_var" "%d" "$pid"
    fi
    return 0
}

bootstrap_nanochat() {
    local uv_extra="${1:-gpu}"
    local quiet_flags=()
    if [ -z "${NANOCHAT_VERBOSE_SETUP:-}" ]; then
        quiet_flags=(-q)
    fi

    export NANOCHAT_BASE_DIR="${NANOCHAT_BASE_DIR:-$HOME/.cache/nanochat}"
    mkdir -p "$NANOCHAT_BASE_DIR"
    export NANOCHAT_DATASETS_DIR="${NANOCHAT_DATASETS_DIR:-$NANOCHAT_BASE_DIR/datasets}"
    mkdir -p "$NANOCHAT_DATASETS_DIR"

    if ! command -v uv &> /dev/null; then
        log_step "Installing uv package manager."
        curl -LsSf https://astral.sh/uv/install.sh | sh
    fi

    if [ ! -d ".venv" ]; then
        log_step "Creating virtual environment (.venv)."
        uv "${quiet_flags[@]}" venv
    else
        log_step "Using existing virtual environment (.venv)."
    fi

    log_step "Syncing Python dependencies (extra: $uv_extra)."
    uv "${quiet_flags[@]}" sync --extra "$uv_extra"
    # shellcheck disable=SC1090
    source .venv/bin/activate

    if [ -z "$WANDB_RUN" ]; then
        export WANDB_RUN=dummy
        setup_warn "WANDB_RUN not set; defaulting to 'dummy'."
    fi

    if ! command -v cargo &> /dev/null; then
        log_step "Installing Rust toolchain (rustup)."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    fi
    if [ -f "$HOME/.cargo/env" ]; then
        # shellcheck disable=SC1090
        source "$HOME/.cargo/env"
    fi

    local rust_stamp="$NANOCHAT_BASE_DIR/.rustbpe_build_stamp"
    local rebuild=1
    if [ -f "$rust_stamp" ]; then
        if ! find "$REPO_ROOT/rustbpe" -type f -newer "$rust_stamp" -print -quit | grep -q .; then
            rebuild=0
        fi
    fi
    if [ "$rebuild" -eq 1 ]; then
        log_step "Building rustbpe tokenizer bindings."
        if uv "${quiet_flags[@]}" run maturin develop --release --manifest-path "$REPO_ROOT/rustbpe/Cargo.toml"; then
            touch "$rust_stamp"
        else
            setup_error "Failed to build rustbpe tokenizer bindings."
            return 1
        fi
    else
        setup_success "Rust tokenizer bindings already up to date."
    fi
}

ensure_eval_bundle() {
    local url="https://karpathy-public.s3.us-west-2.amazonaws.com/eval_bundle.zip"
    local target_dir="${NANOCHAT_DATASETS_DIR:-$HOME/.cache/nanochat/datasets}"

    if [ ! -d "$target_dir/eval_bundle" ]; then
        log_step "Downloading eval bundle."
        curl -sSL -o eval_bundle.zip "$url"
        unzip -q eval_bundle.zip
        rm eval_bundle.zip
        mv eval_bundle "$target_dir"
    else
        setup_success "Eval bundle already present."
    fi
}
