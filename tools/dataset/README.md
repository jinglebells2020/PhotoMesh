# Dataset tools

Turn what the collector stores (see `../telemetry-worker`) into a training set, an evaluation set
and a plain-text analytics report. Standard library only, except `sync.py`, which needs `boto3`.

```
pip install boto3
export R2_ACCOUNT_ID=…  R2_ACCESS_KEY_ID=…  R2_SECRET_ACCESS_KEY=…     # an R2 API token with read access
python3 tools/dataset/sync.py --out data/raw                          # incremental download of installs/**
python3 tools/dataset/build.py --raw data/raw --out data/dataset      # samples.jsonl, train/val split, eval fixtures, stats.md
python3 tools/dataset/report.py --raw data/raw --days 30              # the numbers, from the event files
```

`build.py` writes:

| File | What |
| --- | --- |
| `samples.jsonl` | one line per scan: image path, the reader's netlist, the person's correction (when there is one), the label to train on (`corrected` when present, else `recognized`), model, diff |
| `train.jsonl`, `val.jsonl` | the same, split by install id so one person's scans never sit on both sides |
| `eval/<id>.jpg` + `eval/<id>.json` | every corrected scan as a fixture in the format of the recognition benchmark (`payload` JSON with `type`, `positive_node` …), ready to drop next to the hand-made ones |
| `stats.md` | accept rate per model, what corrections change most often, duplicates dropped |

Corrected scans are the valuable half: picture in, wrong netlist, right netlist. Accepted scans are
positives the reader already gets right and keep an evaluation set honest about regressions.
