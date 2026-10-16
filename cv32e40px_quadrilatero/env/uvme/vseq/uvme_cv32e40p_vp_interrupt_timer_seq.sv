//
// Copyright 2021 OpenHW Group
// Copyright 2021 Silicon Labs
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Licensed under the Solderpad Hardware License v 2.1 (the "License"); you may
// not use this file except in compliance with the License, or, at your option,
// the Apache License version 2.0. You may obtain a copy of the License at
//
//     https://solderpad.org/licenses/SHL-2.1/
//
// Unless required by applicable law or agreed to in writing, any work
// distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
// WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
// License for the specific language governing permissions and limitations
// under the License.
//

`ifndef __UVME_CV32E40P_VP_INTERRUPT_TIMER_SEQ_SV__
`define __UVME_CV32E40P_VP_INTERRUPT_TIMER_SEQ_SV__

/**
 * Sequence implementing the virtual status flags decoding
 */
class uvme_cv32e40p_vp_interrupt_timer_seq_c extends uvma_obi_memory_vp_interrupt_timer_seq_c;

   uvme_cv32e40p_cntxt_c cv32e40p_cntxt;

   `uvm_object_utils_begin(uvme_cv32e40p_vp_interrupt_timer_seq_c)
   `uvm_object_utils_end

   extern function new(string name="uvme_cv32e40p_vp_interrupt_timer_seq_c");

   /**
    * Assert IRQ, then fork per-bit watchers that de-assert each bit
    * individually when the core acknowledges that specific interrupt.
    */
   extern virtual task set_interrupt();

endclass : uvme_cv32e40p_vp_interrupt_timer_seq_c

function uvme_cv32e40p_vp_interrupt_timer_seq_c::new(string name="uvme_cv32e40p_vp_interrupt_timer_seq_c");
   super.new(name);
endfunction : new

task uvme_cv32e40p_vp_interrupt_timer_seq_c::set_interrupt();

   if (cv32e40p_cntxt.interrupt_cntxt.vif == null) begin
      `uvm_fatal("InterruptTimer_Seq", "cv32e40p_cntxt.interrupt_cntxt.vif does NOT exist")
   end

   // Assert all requested IRQ bits
   cv32e40p_cntxt.interrupt_cntxt.vif.drv_cb.irq_drv <= interrupt_value;

   // For each asserted bit, fork a watcher that waits for that
   // specific bit's ack, then de-asserts just that bit.
   for (int i = 0; i < 32; i++) begin
      if (interrupt_value[i]) begin
         automatic int bit_idx = i;
         fork begin
            // Wait for IRQ to propagate
            @(cv32e40p_cntxt.interrupt_cntxt.vif.mon_cb);

            // Wait for ack of THIS specific IRQ
            while (!(cv32e40p_cntxt.interrupt_cntxt.vif.mon_cb.irq_ack &&
                     cv32e40p_cntxt.interrupt_cntxt.vif.mon_cb.irq_id == bit_idx))
               @(cv32e40p_cntxt.interrupt_cntxt.vif.mon_cb);

            // Small delay for handler to read mip
            repeat (3) @(cv32e40p_cntxt.interrupt_cntxt.vif.mon_cb);

            // De-assert only this bit
            cv32e40p_cntxt.interrupt_cntxt.vif.drv_cb.irq_drv[bit_idx] <= 1'b0;
         end join_none
      end
   end

endtask : set_interrupt

`endif // __UVME_CV32E40P_VP_INTERRUPT_TIMER_SEQ_SV__
