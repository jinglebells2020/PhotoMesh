"""CLI: convert datasets to records.jsonl and split them.

    python -m photomesh_ml.data.convert_cli --synthetic data/synth --digitize-hcd data/Digitize-HCD\\ Dataset \\
        --cghd data/cghd --out data/records
"""
from __future__ import annotations

import argparse
from collections import Counter
from pathlib import Path

from . import cghd, digitize_hcd, synthetic
from .records import Record, write_jsonl
from .splits import partition


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--synthetic", action="append", default=[])
    parser.add_argument("--digitize-hcd", default=None)
    parser.add_argument("--no-ports", action="store_true")
    parser.add_argument("--cghd", default=None)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    records: list[Record] = []
    for d in args.synthetic:
        records += synthetic.convert(Path(d))
    if args.digitize_hcd:
        records += digitize_hcd.convert(Path(args.digitize_hcd), include_ports=not args.no_ports)
    if args.cghd:
        records += cghd.convert(Path(args.cghd))
    parts = partition(records)
    out = Path(args.out)
    for name, rows in parts.items():
        n = write_jsonl(rows, out / f"{name}.jsonl")
        print(f"{name}: {n} records", dict(Counter(r.source for r in rows)))


if __name__ == "__main__":
    main()
