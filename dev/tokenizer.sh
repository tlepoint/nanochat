#!/bin/bash

# Helper to train the tokenizer once per configuration and reuse cached artifacts.
# Usage: ensure_tokenizer <max_chars> [doc_cap] [vocab_size]

TOKENIZER_HELPER_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
if ! declare -F log_info >/dev/null 2>&1; then
    source "$TOKENIZER_HELPER_DIR/logging.sh"
fi

ensure_tokenizer() {
    local max_chars="$1"
    local doc_cap="${2:-10000}"
    local vocab_size="${3:-65536}"

    if [ -z "$max_chars" ]; then
        echo "ensure_tokenizer: max_chars argument is required." >&2
        return 1
    fi

    local base_dir="${NANOCHAT_BASE_DIR:-$HOME/.cache/nanochat}" # mirrors python helper default
    local tokenizer_dir="$base_dir/tokenizer"
    local cache_root="$base_dir/tokenizer_cache"
    local config_id="max${max_chars}_doc${doc_cap}_vocab${vocab_size}"
    local config_dir="$cache_root/$config_id"
    local metadata_file="$config_dir/config.txt"

    mkdir -p "$tokenizer_dir" "$config_dir" # ensure active and cache dirs exist
    # remove legacy sentinel markers from previous implementation
    find "$tokenizer_dir" -maxdepth 1 -name ".trained_*" -delete 2>/dev/null || true

    local needs_training=0 # track whether current config is missing artifacts
    for artifact in tokenizer.pkl token_bytes.pt; do
        if [ ! -f "$config_dir/$artifact" ]; then
            needs_training=1
            break
        fi
    done
    if [ ! -f "$metadata_file" ]; then
        needs_training=1
    fi

    if [ "$needs_training" -eq 1 ]; then
        log_info "tokenizer" "Training (config: $config_id)..."
        if python -m scripts.tok_train \
            --max_chars="$max_chars" \
            --doc_cap="$doc_cap" \
            --vocab_size="$vocab_size"; then
            # clean out old config dir and persist newly trained artifacts
            rm -rf "$config_dir" # drop stale cache before writing fresh copy
            mkdir -p "$config_dir"
            if ! cp -a "$tokenizer_dir/." "$config_dir/"; then
                log_error "tokenizer" "Failed to cache tokenizer artifacts at $config_dir"
                return 1
            fi
            cat > "$metadata_file" <<EOF
max_chars=$max_chars
doc_cap=$doc_cap
vocab_size=$vocab_size
trained_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
            log_success "tokenizer" "Cached artifacts at $config_dir"
        else
            log_error "tokenizer" "Training failed; please address the issue and re-run."
            return 1
        fi
    else
        log_info "tokenizer" "Cache hit (config: $config_id); reusing cached artifacts."
    fi

    # ensure the active tokenizer directory reflects the desired configuration
    rm -rf "$tokenizer_dir" # replace active dir with chosen cache contents
    mkdir -p "$tokenizer_dir"
    if ! cp -a "$config_dir/." "$tokenizer_dir/"; then
        log_error "tokenizer" "Failed to copy cached artifacts into $tokenizer_dir"
        return 1
    fi

    if ! python -m scripts.tok_eval; then
        log_error "tokenizer" "Evaluation failed; please address the issue and re-run."
        return 1
    fi
}
