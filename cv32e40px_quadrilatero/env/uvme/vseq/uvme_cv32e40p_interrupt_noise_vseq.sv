// Copyright 2020 OpenHW Group
// Copyright 2020 Datum Technology Corporation
//
// Licensed under the Solderpad Hardware Licence, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://solderpad.org/licenses/
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.


`ifndef __UVME_CV32E40P_INTERRUPT_NOISE_SV__
`define __UVME_CV32E40P_INTERRUPT_NOISE_SV__

/**
 * Virtual sequence responsible for starting the system clock and issuing
 * the initial reset pulse to the DUT.
 */
class uvme_cv32e40p_interrupt_noise_c extends uvme_cv32e40p_base_vseq_c;

   rand int unsigned short_delay_wgt;
   rand int unsigned med_delay_wgt;
   rand int unsigned long_delay_wgt;
   rand int unsigned initial_delay_assert_until_ack;
   rand int unsigned initial_delay_assert;
   rand int unsigned initial_delay_deassert;

   rand bit [31:0]   reserved_irq_mask;

   // Starvation guard (STIMULUS change): the
   // unbounded assert-until-ack stream (E[popcount(irq_mask)] ~ 16 lines x
   // repeat_count, one item per ~1060 clk) refills pending interrupts 5-8x
   // faster than the handler drains them (1 ack per iteration), so the DUT
   // main thread starves at boot (4 campaign lanes TIMEOUT with sim-time
   // advancing - not a livelock). Bound the work-rate per item and grant a
   // quiet window proportional to the injected work so drain > refill even
   // with long FP save/restore handlers (~400 clk/ack); up to 4 concurrent
   // lines keeps the nested/noise coverage pressure.
   // Randomized ONCE per sequence invocation (not per item): a fixed rate
   // cap for the life of the body() loop. The initializer covers a
   // non-randomized start; the hard range keeps any override from silently
   // zeroing the guard (degenerate irq_mask==0 items) or unbounding it.
   rand int unsigned max_lines_per_item = 4;

   // Rotating index of the "standing line" asserted alongside each throttled
   // burst (coverage companion to the rate cap, see body()). Not randomized:
   // it must sweep the valid ids deterministically so every replica of
   // c_irq_masked_then_enabled gets its turn, run after run.
   int unsigned sticky_irq_idx = 0;

   `uvm_object_utils_begin(uvme_cv32e40p_interrupt_noise_c)
   `uvm_object_utils_end

   constraint default_delay_c {
     soft short_delay_wgt == 2;
     soft med_delay_wgt == 5;
     soft long_delay_wgt == 3;
   }

   constraint starvation_guard_c {
     soft max_lines_per_item == 4;
     max_lines_per_item inside {[1:8]};
   }

   constraint valid_delay_c {
     short_delay_wgt != 0 || med_delay_wgt != 0 || long_delay_wgt != 0;
   }

   constraint valid_initial_delay_assert_until_ack_c {
     initial_delay_assert_until_ack dist { 0 :/ 1,
                                           [10:500] :/ 4,
                                           [500:1000] :/ 3};
   }

   constraint valid_initial_delay_assert_c {
     initial_delay_assert dist { 0 :/ 2,
                                 [10:500] :/ 4,
                                 [500:1000] :/ 3};
   }

   constraint valid_initial_delay_deassert_c {
     initial_delay_deassert dist { 0 :/ 2,
                                   [10:500] :/ 4,
                                   [500:1000] :/ 3};
   }

   /**
    * Default constructor.
    */
   extern function new(string name="uvme_cv32e40p_interrupt_noise");

   /**
    * Starts the clock, waits, then resets the DUT.
    */
   extern virtual task body();
   extern virtual task rand_delay();
endclass : uvme_cv32e40p_interrupt_noise_c

function uvme_cv32e40p_interrupt_noise_c::new(string name="uvme_cv32e40p_interrupt_noise");

   super.new(name);

endfunction : new

task uvme_cv32e40p_interrupt_noise_c::rand_delay();
  randcase
    // SVTB.29.1.3.1 - Banned random number system functions and methods calls
    // Waive because the calls to the sys fns are controlled by constrained vars.
    //@DVT_LINTER_WAIVER_START "MT20211214_1" disable SVTB.29.1.3.1
    short_delay_wgt: repeat($urandom_range(   100,    1)) @(cntxt.interrupt_cntxt.vif.drv_cb);
    med_delay_wgt:   repeat($urandom_range(   500,  100)) @(cntxt.interrupt_cntxt.vif.drv_cb);
    long_delay_wgt:  repeat($urandom_range( 5_000,1_000)) @(cntxt.interrupt_cntxt.vif.drv_cb);
    //@DVT_LINTER_WAIVER_END "MT20211214_1"
  endcase
endtask : rand_delay

task uvme_cv32e40p_interrupt_noise_c::body();

  fork
    begin : gen_assert_until_ack

      repeat (initial_delay_assert_until_ack) @(cntxt.interrupt_cntxt.vif.drv_cb);

      while(1) begin
        uvma_interrupt_seq_item_c irq_req;

        `uvm_create_on(irq_req, p_sequencer.interrupt_sequencer);
        start_item(irq_req);
        irq_req.default_repeat_count_c.constraint_mode(0);
        assert(irq_req.randomize() with {
          action        == UVMA_INTERRUPT_SEQ_ITEM_ACTION_ASSERT_UNTIL_ACK;
          repeat_count dist { 1 :/ 9, [2:3] :/ 1 };
          $countones(irq_mask) <= local::max_lines_per_item;
          (irq_mask & local::reserved_irq_mask) == 0;
        })
        else `uvm_fatal("INTERRUPT_NOISE_VSEQ",
                        "assert_until_ack irq_req.randomize() failed - a solver conflict here would drive a stale item")
        finish_item(irq_req);

        // Quiet window proportional to the work just injected: each asserted
        // line owes repeat_count acks at ~250-410 clk of handler each, so
        // ~500 clk per owed ack guarantees drain > refill (starvation guard,
        // see starvation_guard_c above).
        repeat ($countones(irq_req.irq_mask) * irq_req.repeat_count * 500)
          @(cntxt.interrupt_cntxt.vif.drv_cb);
        rand_delay();

      end
    end

    // NOTE ON THE BLOCK NAMES (upstream, kept for diff hygiene): the two
    // blocks below do the OPPOSITE of what their labels say. "gen_assert"
    // drives DEASSERT items, "gen_deassert" drives ASSERT items. The
    // starvation throttling therefore belongs to gen_deassert, not to
    // gen_assert - read the `action ==` line, never the label.
    begin : gen_assert   // action == DEASSERT (drains unowned lines)

      repeat (initial_delay_assert) @(cntxt.interrupt_cntxt.vif.drv_cb);

      while(1) begin
        uvma_interrupt_seq_item_c irq_req;

        `uvm_do_on_with(irq_req, p_sequencer.interrupt_sequencer, {
          action        == UVMA_INTERRUPT_SEQ_ITEM_ACTION_DEASSERT;
          (irq_mask & local::reserved_irq_mask) == 0;
        })

        rand_delay();

      end
    end

    begin : gen_deassert   // action == ASSERT (this is the REFILL source)

      repeat (initial_delay_deassert) @(cntxt.interrupt_cntxt.vif.drv_cb);

      while(1) begin
        uvma_interrupt_seq_item_c irq_req;

        // Same rate cap as the until-ack stream above (STIMULUS change): an
        // unconstrained 32-bit mask asserts E[popcount]=16 lines per item
        // every ~1060 clk, i.e. a refill of ~4.7e-3 enabled lines/clk against
        // a drain of at most one line per take (~3.8-4.5e-3): the pending set
        // never empties and the application thread starves. Capping the mask
        // brings refill to ~1.2e-3, a 3-4x margin, and the quiet window keeps
        // the injected burst from being immediately re-stacked.
        `uvm_do_on_with(irq_req, p_sequencer.interrupt_sequencer, {
          action        == UVMA_INTERRUPT_SEQ_ITEM_ACTION_ASSERT;
          $countones(irq_mask) <= local::max_lines_per_item;
          (irq_mask & local::reserved_irq_mask) == 0;
        })

        // Coverage companion to the rate cap - it PAYS BACK the cap instead of
        // relaxing it. Capping the burst and adding the quiet window rarefies
        // c_irq_masked_then_enabled (uvmt_cv32e40p_interrupt_assert.sv), which
        // needs one specific line HIGH while its own mie bit is still 0 and
        // mstatus.MIE is 1, and that same bit rising the very next cycle: the
        // line has to be standing when the program happens to write mie.
        // So keep exactly ONE line standing through the quiet window, rotating
        // over the valid ids so each of the 19 cover replicas gets its turn.
        // Starvation-neutral by construction: while the line is MASKED it
        // produces no take at all (and that is precisely the covered shape);
        // if it happens to be enabled it produces at most ONE take before
        // irq_ack_clear drops it - against a drain of one take per ~250 clk.
        for (int k = 0; k < 32; k++) begin
          sticky_irq_idx = (sticky_irq_idx + 1) % 32;
          if (!reserved_irq_mask[sticky_irq_idx]) break;
        end
        if (!reserved_irq_mask[sticky_irq_idx]) begin
          uvma_interrupt_seq_item_c sticky_req;
          `uvm_do_on_with(sticky_req, p_sequencer.interrupt_sequencer, {
            action    == UVMA_INTERRUPT_SEQ_ITEM_ACTION_ASSERT;
            irq_mask  == (32'h1 << local::sticky_irq_idx);
          })
        end

        repeat ($countones(irq_req.irq_mask) * 500)
          @(cntxt.interrupt_cntxt.vif.drv_cb);
        rand_delay();

      end
    end
  join
endtask : body

`endif // __UVME_CV32E40P_INTERRUPT_NOISE_SV__
