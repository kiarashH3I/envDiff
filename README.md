# env-diff

Fast, safe diff between `.env.example` and `.env` with GitHub-like output.
- Values are **hidden by default**.
- Color output when run in a TTY.
- CI-friendly exit codes.

## One-liner

> Replace `USER` and `REPO` with your GitHub path.

```bash
bash <(curl -Ls https://raw.githubusercontent.com/kiarashH3I/envDiff/refs/heads/main/env-diff.sh)
