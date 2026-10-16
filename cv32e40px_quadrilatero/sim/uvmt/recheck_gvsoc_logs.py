#!/usr/bin/env python3
"""Robust GVSOC regression log re-checker.

The cv_regress-generated bash script uses a check_log function that can race
with vsim finalize. This script re-parses all vsim-*.log files from a regression
script and categorizes PASS / FAIL / STUCK with root-cause heuristic.

Usage: recheck_gvsoc_logs.py <regress_script.sh>
"""
from __future__ import annotations

import re
import sys
from pathlib import Path
from collections import defaultdict


def parse_log(log_path: Path) -> tuple[str, str]:
    """Return (status, reason) for a single vsim log."""
    if not log_path.exists():
        return ("MISSING", "log file does not exist")
    try:
        with log_path.open(errors="ignore") as f:
            content = f.read()
    except Exception as e:
        return ("ERROR", f"cannot read log: {e}")

    has_pass = "SIMULATION PASSED" in content
    has_fail = "SIMULATION FAILED" in content
    has_err0 = re.search(r"Errors:\s+0[,\s]", content) is not None
    has_mism = "Reference model mismatches found" in content

    if has_pass and has_err0 and not has_mism:
        return ("PASS", "")

    if has_mism:
        m = re.search(r"CSR\[(0x[0-9a-fA-F]+)\] mismatch", content)
        if m:
            csr = m.group(1)
            csr_name = {
                "0x7b1": "dpc",
                "0x7b0": "dcsr",
                "0x300": "mstatus",
                "0x341": "mepc",
                "0x342": "mcause",
                "0x343": "mtval",
                "0x304": "mie",
                "0x344": "mip",
                "0x305": "mtvec",
            }.get(csr.lower(), "?")
            return ("FAIL", f"CSR[{csr}]={csr_name} mismatch")
        m = re.search(r"PC mismatch .* DUT=(0x[0-9a-fA-F]+)", content)
        if m:
            return ("FAIL", f"PC mismatch DUT={m.group(1)}")
        m = re.search(r"GPR\[(\d+)\] mismatch", content)
        if m:
            return ("FAIL", f"GPR[x{m.group(1)}] mismatch")
        return ("FAIL", "mismatch (unknown)")

    if has_fail:
        return ("FAIL", "SIMULATION FAILED (no mismatch marker)")

    if not (has_pass or has_fail):
        if "** Fatal:" in content or "** Error:" in content:
            return ("FAIL", "vsim error")
        return ("STUCK", "no final verdict (likely killed)")

    return ("FAIL", "unknown (has_pass=%s err0=%s)" % (has_pass, has_err0))


def main() -> int:
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <regress_script.sh>")
        return 2

    sh = Path(sys.argv[1])
    if not sh.exists():
        print(f"ERROR: {sh} not found")
        return 2

    # Extract log paths from the script
    log_pattern = re.compile(r"log=(\S+\.log)")
    log_paths: list[Path] = []
    with sh.open() as f:
        for line in f:
            m = log_pattern.search(line.strip())
            if m:
                log_paths.append(Path(m.group(1)))

    results: dict[str, list[tuple[Path, str]]] = defaultdict(list)
    for lp in log_paths:
        status, reason = parse_log(lp)
        results[status].append((lp, reason))

    # Reason aggregation for FAIL
    reason_count: dict[str, int] = defaultdict(int)
    for lp, r in results.get("FAIL", []):
        reason_count[r] += 1

    print("=== ReCheck Results ===")
    for status in ("PASS", "FAIL", "STUCK", "MISSING", "ERROR"):
        print(f"{status:8s}: {len(results.get(status, []))}")
    print(f"TOTAL   : {sum(len(v) for v in results.values())}")
    print()
    print("--- FAIL reasons ---")
    for reason, n in sorted(reason_count.items(), key=lambda x: -x[1]):
        print(f"  {n:3d}  {reason}")
    print()

    if results.get("PASS"):
        print("--- PASS ---")
        for lp, _ in sorted(results["PASS"], key=lambda x: str(x[0])):
            # Show last 3 path components for brevity
            parts = lp.parts
            short = "/".join(parts[-4:]) if len(parts) > 4 else str(lp)
            print(f"  {short}")
    print()

    if results.get("FAIL"):
        print("--- FAIL ---")
        for lp, reason in sorted(results["FAIL"], key=lambda x: str(x[0])):
            parts = lp.parts
            short = "/".join(parts[-4:]) if len(parts) > 4 else str(lp)
            print(f"  {short}  [{reason}]")

    if results.get("STUCK"):
        print()
        print("--- STUCK/KILLED ---")
        for lp, reason in sorted(results["STUCK"], key=lambda x: str(x[0])):
            parts = lp.parts
            short = "/".join(parts[-4:]) if len(parts) > 4 else str(lp)
            print(f"  {short}  [{reason}]")

    return 0


if __name__ == "__main__":
    sys.exit(main())
