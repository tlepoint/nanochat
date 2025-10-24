#!/bin/bash

# Common logging helpers with optional ANSI color support.

if [ -z "${NANOCHAT_LOGGING_INITIALIZED:-}" ]; then
    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
        export NANOCHAT_COLOR_TAG=${NANOCHAT_COLOR_TAG:-$'\033[38;5;244m'}
        export NANOCHAT_COLOR_INFO=${NANOCHAT_COLOR_INFO:-$'\033[1;36m'}
        export NANOCHAT_COLOR_SUCCESS=${NANOCHAT_COLOR_SUCCESS:-$'\033[1;32m'}
        export NANOCHAT_COLOR_WARN=${NANOCHAT_COLOR_WARN:-$'\033[1;33m'}
        export NANOCHAT_COLOR_ERROR=${NANOCHAT_COLOR_ERROR:-$'\033[1;31m'}
        export NANOCHAT_COLOR_RESET=${NANOCHAT_COLOR_RESET:-$'\033[0m'}
    else
        export NANOCHAT_COLOR_TAG=""
        export NANOCHAT_COLOR_INFO=""
        export NANOCHAT_COLOR_SUCCESS=""
        export NANOCHAT_COLOR_WARN=""
        export NANOCHAT_COLOR_ERROR=""
        export NANOCHAT_COLOR_RESET=""
    fi
    export NANOCHAT_LOGGING_INITIALIZED=1
fi

_log_emit() {
    local stream="$1"
    local tag="$2"
    local color="$3"
    shift 3
    local message="$*"
    local reset="$NANOCHAT_COLOR_RESET"
    local prefix
    if [ -n "$NANOCHAT_COLOR_TAG" ] && [ -n "$reset" ]; then
        prefix="${NANOCHAT_COLOR_TAG}[${tag}]${reset} "
    else
        prefix="[${tag}] "
    fi
    if [ -n "$color" ] && [ -n "$reset" ]; then
        message="${color}${message}${reset}"
    fi
    if [ "$stream" = "stderr" ]; then
        printf "%s%s\n" "$prefix" "$message" >&2
    else
        printf "%s%s\n" "$prefix" "$message"
    fi
}

log_info() {
    local tag="$1"
    shift
    _log_emit stdout "$tag" "$NANOCHAT_COLOR_INFO" "$@"
}

log_success() {
    local tag="$1"
    shift
    _log_emit stdout "$tag" "$NANOCHAT_COLOR_SUCCESS" "$@"
}

log_warn() {
    local tag="$1"
    shift
    _log_emit stderr "$tag" "$NANOCHAT_COLOR_WARN" "$@"
}

log_error() {
    local tag="$1"
    shift
    local color="$NANOCHAT_COLOR_ERROR"
    if [ -z "$color" ]; then
        color="$NANOCHAT_COLOR_WARN"
    fi
    _log_emit stderr "$tag" "$color" "$@"
}
