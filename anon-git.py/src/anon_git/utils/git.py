"""Runs git with list args, never through a shell."""

import subprocess


def git(*args):
    """Runs git with list args (never a shell) and returns stripped stdout."""
    result = subprocess.run(["git", *args], capture_output=True, text=True, check=True)
    return result.stdout.rstrip("\n")


def git_ok(*args):
    return subprocess.run(["git", *args], capture_output=True).returncode == 0


# Returns (git exit status, value). Status 1 means the key is unset.
def git_config_get(key, *flags):
    result = subprocess.run(["git", "config", *flags, "--get", key], capture_output=True, text=True)
    return result.returncode, result.stdout.rstrip("\n")
