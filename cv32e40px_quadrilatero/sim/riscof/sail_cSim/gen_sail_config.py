#!/usr/bin/env python3
"""Generate a Sail RISC-V configuration matching the CV32E40P.

Since sail-riscv 0.9 the emulator is configured with a JSON file rather than
command line flags: the historic '-C' and '--enable-misaligned' switches are
gone, and '--rv32' alone enables roughly a hundred extensions. Left as is, the
reference model would accept instructions the DUT traps on.

This script takes the emulator's own '--rv32' defaults as the base - so it
tracks whatever sail version is installed - and narrows them to
RV32IMFC_Zicsr_Zifencei:

  - every extension except M, F, Zca, Zcf, Zicsr and Zifencei is disabled
    (C on RV32 is Zca plus Zcf; V takes 'Disabled' rather than a bool)
  - misa is read-only, as on the CV32E40P
  - a RAM region is added at 0x20000000 for the HTIF window. The arch-test
    link scripts put .tohost there, outside the default memory map, and the
    halt store would otherwise take an access fault

Two knock-on settings the emulator's own validator demands once S and V are
off: mstatus.VS must be read-only zero, and physaddr_bits must drop to 32
because Sv32 is disabled.

Misaligned load/store behaviour is inherited from the defaults, which allow it
without trapping - matching hw_data_misaligned_support in the ISA yaml.

Usage:
    gen_sail_config.py <path-to-sail_riscv_sim> <output.json>
"""

import copy
import json
import re
import subprocess
import sys

KEEP_EXTENSIONS = {'M', 'F', 'Zicsr', 'Zifencei', 'Zca', 'Zcf'}

HTIF_BASE = 0x20000000
HTIF_SIZE = 0x1000


def default_rv32_config(sail_exe):
    """Return the emulator's built-in RV32 configuration as a dict."""
    raw = subprocess.run([sail_exe, '--rv32', '--print-default-config'],
                         capture_output=True, text=True, check=True).stdout
    # The emulator emits a commented JSON preamble describing the file.
    return json.loads(re.sub(r'^\s*//.*$', '', raw, flags=re.M))


def narrow(config):
    for name, node in config['extensions'].items():
        if not isinstance(node, dict):
            continue
        if 'supported' in node:
            node['supported'] = name in KEEP_EXTENSIONS
        if 'support_level' in node:
            node['support_level'] = 'Disabled'
    # Nested rather than a plain 'supported' flag.
    config['extensions']['Stateen']['Smstateen'] = {'supported': False}
    config['extensions']['Stateen']['Ssstateen'] = {'supported': False}

    config['base']['writable_misa'] = False
    config['base']['mstatus']['vs_legal_states'] = 'ExtContext_Off'
    config['memory']['physaddr_bits'] = 32

    regions = config['memory']['regions']
    htif = copy.deepcopy(next(r for r in regions
                              if r['attributes']['mem_type'] == 'MainMemory'))
    htif['base']['value'] = hex(HTIF_BASE)
    htif['size']['value'] = hex(HTIF_SIZE)
    htif['include_in_device_tree'] = False
    regions.append(htif)
    regions.sort(key=lambda r: int(r['base']['value'], 16))
    return config


def main(argv):
    if len(argv) != 3:
        sys.stderr.write(__doc__)
        return 1
    sail_exe, output = argv[1], argv[2]

    config = narrow(default_rv32_config(sail_exe))
    with open(output, 'w') as handle:
        json.dump(config, handle, indent=2)

    isa = subprocess.run([sail_exe, '--config', output, '--print-isa-string'],
                         capture_output=True, text=True, check=True)
    print("wrote {0}".format(output))
    print("sail ISA string: {0}".format(isa.stdout.strip()))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
