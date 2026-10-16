#!/usr/bin/env python3
"""Rebuild a RISCOF signature from a GVSOC run log.

The GVSOC virtual exit device does not implement its signature registers, so
the test itself streams [begin_signature, end_signature) to the device at
offset +0x80 (see riscof/gvsoc/env/model_test.h). Every such store is logged
on the device debug trace as

    unknown offset 0x80 wdata=0x........

This script pulls those words out of the log, in order, and writes them in
the format RISCOF compares: one lowercase 8-digit hex word per line.

The expected word count is derived from the ELF symbols, so a run that died
early is reported as a truncated signature instead of silently turning into a
content mismatch. A short signature is still written out - the partial data is
what makes the failure diagnosable - but the shortfall is recorded in a
<output>.incomplete sidecar.

The exit status stays 0 on a short signature: the length mismatch already
fails the RISCOF comparison for that test, and failing the make target here
would only make the batch noisier. A malformed trace, by contrast, exits
non-zero - that means the extraction itself can no longer be trusted.
"""

import argparse
import re
import sys

from elftools.elf.elffile import ELFFile

# Match the whole hex field rather than a fixed width, so a field that is not
# eight digits is reported instead of being silently sliced down to eight.
WORD_RE = re.compile(rb"unknown offset 0x80 wdata=0x([0-9a-fA-F]+)\b")
PASS_RE = re.compile(rb"tests_passed=1")


def signature_bounds(elf_path):
    """Return (begin_signature, end_signature) from the ELF symbol table."""
    wanted = {"begin_signature": None, "end_signature": None}
    with open(elf_path, "rb") as handle:
        elf = ELFFile(handle)
        for section in elf.iter_sections():
            if not hasattr(section, "iter_symbols"):
                continue
            for symbol in section.iter_symbols():
                if symbol.name in wanted:
                    wanted[symbol.name] = symbol["st_value"]
    missing = [name for name, value in wanted.items() if value is None]
    if missing:
        raise SystemExit("sig_extract: symbol(s) not found in {0}: {1}".format(
            elf_path, ", ".join(missing)))
    return wanted["begin_signature"], wanted["end_signature"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", help="GVSOC run log")
    parser.add_argument("elf", help="test ELF, used for the signature bounds")
    parser.add_argument("output", help="signature file to write")
    args = parser.parse_args()

    try:
        with open(args.log, "rb") as handle:
            raw = handle.read()
    except OSError as exc:
        raise SystemExit("sig_extract: cannot read {0}: {1}".format(args.log, exc))

    words = [match.group(1).decode("ascii").lower() for match in WORD_RE.finditer(raw)]

    odd = {len(word) for word in words} - {8}
    if odd:
        raise SystemExit("sig_extract: {0} has signature writes that are not "
                         "8 hex digits (widths seen: {1}); the trace format has "
                         "changed".format(args.log, sorted(odd)))

    begin, end = signature_bounds(args.elf)
    if end < begin:
        raise SystemExit("sig_extract: end_signature (0x{0:08x}) precedes "
                         "begin_signature (0x{1:08x})".format(end, begin))
    expected = (end - begin) // 4

    with open(args.output, "w") as handle:
        handle.write("".join(word + "\n" for word in words))

    if len(words) != expected:
        kind = "truncated" if len(words) < expected else "over-long"
        reason = ("signature {0}: expected {1} words, captured {2}"
                  .format(kind, expected, len(words)))
        if not PASS_RE.search(raw):
            reason += " (no tests_passed marker - the run did not reach RVMODEL_HALT)"
        with open(args.output + ".incomplete", "w") as handle:
            handle.write(reason + "\n")
        sys.stderr.write("sig_extract: " + reason + "\n")

    return 0


if __name__ == "__main__":
    sys.exit(main())
