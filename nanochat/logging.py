"""
Lightweight logging helpers with optional ANSI color support shared across nanochat modules.
"""

import os
import sys
from typing import TextIO


def _detect_default_colors() -> tuple[str, str, str, str, str, str]:
    """Return color codes (tag, info, success, warn, error, reset)."""
    if os.environ.get("NO_COLOR"):
        return "", "", "", "", "", ""

    stdout_is_tty = sys.stdout.isatty()
    stderr_is_tty = sys.stderr.isatty()
    if not (stdout_is_tty or stderr_is_tty):
        return "", "", "", "", "", ""

    tag = "\033[38;5;244m"
    info = "\033[1;36m"
    success = "\033[1;32m"
    warn = "\033[1;33m"
    error = "\033[1;31m"
    reset = "\033[0m"
    return tag, info, success, warn, error, reset


COLOR_TAG = os.environ.get("NANOCHAT_COLOR_TAG", "")
COLOR_INFO = os.environ.get("NANOCHAT_COLOR_INFO", "")
COLOR_SUCCESS = os.environ.get("NANOCHAT_COLOR_SUCCESS", "")
COLOR_WARN = os.environ.get("NANOCHAT_COLOR_WARN", "")
COLOR_ERROR = os.environ.get("NANOCHAT_COLOR_ERROR", "")
COLOR_RESET = os.environ.get("NANOCHAT_COLOR_RESET", "")

if not any([COLOR_RESET, COLOR_TAG, COLOR_INFO, COLOR_SUCCESS, COLOR_WARN, COLOR_ERROR]):
    (
        COLOR_TAG,
        COLOR_INFO,
        COLOR_SUCCESS,
        COLOR_WARN,
        COLOR_ERROR,
        COLOR_RESET,
    ) = _detect_default_colors()


def _colorize(color: str, message: str) -> str:
    if color and COLOR_RESET:
        return f"{color}{message}{COLOR_RESET}"
    return message


def _prefix(tag: str) -> str:
    if COLOR_TAG and COLOR_RESET:
        return f"{COLOR_TAG}[{tag}]{COLOR_RESET} "
    return f"[{tag}] "


def _emit(
    tag: str,
    message: str,
    *,
    color: str = "",
    stream: TextIO = sys.stdout,
    quiet: bool = False,
) -> None:
    if quiet and stream is sys.stdout:
        return
    stream.write(f"{_prefix(tag)}{_colorize(color, message)}\n")
    stream.flush()


def info(tag: str, message: str, *, quiet: bool = False) -> None:
    _emit(tag, message, color=COLOR_INFO, quiet=quiet)


def success(tag: str, message: str, *, quiet: bool = False) -> None:
    _emit(tag, message, color=COLOR_SUCCESS, quiet=quiet)


def warn(tag: str, message: str) -> None:
    _emit(tag, message, color=COLOR_WARN, stream=sys.stderr)


def error(tag: str, message: str) -> None:
    color = COLOR_ERROR or COLOR_WARN
    _emit(tag, message, color=color, stream=sys.stderr)


__all__ = ["info", "success", "warn", "error"]
