OUTPUT_ARCH( "riscv" )
ENTRY(rvtest_entry_point)

/* Memory layout for the GVSOC cv32e40p-v2-standalone* targets.

   Text and data addresses are deliberately identical to the RTL and SAIL
   plugins (riscof/cv32e40p/env/link.ld, riscof/sail_cSim/env/link.ld) so a
   signature mismatch can never be an artefact of a different load address:
   any PC-derived value captured in the signature is the same on all three
   models.

   Two GVSOC-specific deviations, both forced by the platform memory map
   (vendor_lib/gvsoc_rvvi/gvsoc/pulp/pulp/cv32e40p_v2_standalone.py):

   1. .text.boot at 0x80 - the core fetches from the fixed BOOT_ADDR (0x80,
      as in the RTL), not from the ELF entry point. RVMODEL_BOOT emits a
      three-instruction trampoline into this section.

   2. .tohost is NOT placed at 0x20000000. That address is the virtual exit
      device; the ELF loader writing the initial tohost/fromhost words there
      would hit the exit_valid register and stop the simulation before the
      first instruction. RVMODEL_HALT writes the halt magic to the device
      explicitly instead. */

SECTIONS
{
  . = 0x80;
  .text.boot : { *(.text.boot) }

  . = 0x80000000;
  .text.init : { *(.text.init) }
  . = ALIGN(0x1000);
  .text : { *(.text) }

  . = 0x80800000;
  .data : { *(.data) }
  .data.string : { *(.data.string)}
  .bss : { *(.bss) }
  _end = .;

  . = 0x80900000;
  .tohost : { *(.tohost) }
}
