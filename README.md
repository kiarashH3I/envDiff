# env-diff

Compare `.env.example` and `.env` with:
- Missing/extra keys
- Changed values
- Placeholder or empty values (like `yourkeyhere`, `XXXXXXXX`, `<YOUR_KEY>`)

Values are shown by default. Color output when TTY. CI-friendly exit codes.

---

## Quick Start

Run directly from GitHub:

```bash
curl -Ls https://raw.githubusercontent.com/kiarashH3I/envDiff/refs/heads/main/env-diff.sh -o /tmp/env-diff.sh
bash /tmp/env-diff.sh
