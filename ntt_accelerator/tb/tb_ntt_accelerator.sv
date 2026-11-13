`timescale 1ns/1ps
`include "vector_count.svh"

// Self-checking functional/protocol test. Test RNG is NOT deployment randomness.
module tb_ntt_accelerator;
  localparam integer Q = 8380417;
  localparam integer N = 256;
  localparam integer CASES = `NTT_VECTOR_COUNT;
  logic clk_i = 0;
  always #5 clk_i = ~clk_i;
  logic rst_ni = 0, zeroize_i = 0, start_i = 0, inverse_i = 0;
  logic in_valid_i = 0, out_ready_i = 0;
  logic [22:0] in_share0_i = 0, in_share1_i = 0;
  wire start_ready_o, in_ready_o, out_valid_o, out_last_o;
  wire busy_o, done_o, error_o;
  wire [22:0] out_share0_o, out_share1_o;

  ntt_accelerator dut (.*);

  reg [22:0] vector_input [0:CASES*N-1];
  reg [22:0] vector_expected [0:CASES*N-1];
  reg vector_mode [0:CASES-1];
  integer unsigned input_data [0:N-1];
  integer unsigned golden_data [0:N-1];
  integer unsigned share0 [0:N-1], share1 [0:N-1];
  integer unsigned expected0 [0:N-1], expected1 [0:N-1];
  integer unsigned observed [0:N-1], observed0 [0:N-1];
  integer unsigned saved0 [0:N-1];
  integer unsigned product_a [0:N-1], product_b [0:N-1];
  integer unsigned roundtrip_plain [0:N-1];
  integer unsigned twiddles [0:N-1];
  reg [63:0] baseline_trace [0:16383];
  reg [1:0] trace_seen = 0;
  integer operation_count = 0;
  integer done_count = 0;
  reg previous_done = 0;
  integer seed = 32'h4d4c4453;
  integer discarded_random;

  // Model uses ordinary widened integer arithmetic and %, independently of the
  // RTL's shift/add reduction. External vectors use direct polynomial evaluation.
  function automatic integer unsigned mul_ref(input integer unsigned a, b);
    reg [63:0] product;
    begin
      product = a;
      product = product * b;
      mul_ref = product % Q;
    end
  endfunction

  function automatic integer unsigned pow_ref(input integer unsigned a, e);
    integer unsigned result, factor, exponent;
    begin
      result = 1;
      factor = a;
      exponent = e;
      while (exponent != 0) begin
        if (exponent & 1) result = mul_ref(result, factor);
        factor = mul_ref(factor, factor);
        exponent = exponent >> 1;
      end
      pow_ref = result;
    end
  endfunction

  function automatic integer unsigned bitrev8(input integer unsigned x);
    integer i;
    begin
      bitrev8 = 0;
      for (i = 0; i < 8; i = i + 1)
        bitrev8 = (bitrev8 << 1) | ((x >> i) & 1);
    end
  endfunction

  task automatic model_shares(input bit inverse_mode);
    integer lane, i, length, base, j, k;
    integer unsigned work [0:N-1];
    integer unsigned u, v, z;
    begin
      for (lane = 0; lane < 2; lane = lane + 1) begin
        for (i = 0; i < N; i = i + 1)
          work[i] = (lane == 0) ? share0[i] : share1[i];
        k = inverse_mode ? 256 : 0;
        length = inverse_mode ? 1 : 128;
        while ((inverse_mode && length < 256) ||
               (!inverse_mode && length > 0)) begin
          for (base = 0; base < N; base = base + 2*length) begin
            if (inverse_mode) begin
              k = k - 1;
              z = Q - twiddles[k];
            end else begin
              k = k + 1;
              z = twiddles[k];
            end
            for (j = base; j < base + length; j = j + 1) begin
              u = work[j];
              v = work[j+length];
              if (inverse_mode) begin
                work[j] = (u + v) % Q;
                work[j+length] = mul_ref((u + Q - v) % Q, z);
              end else begin
                v = mul_ref(v, z);
                work[j] = (u + v) % Q;
                work[j+length] = (u + Q - v) % Q;
              end
            end
          end
          length = inverse_mode ? length*2 : length/2;
        end
        for (i = 0; i < N; i = i + 1) begin
          if (inverse_mode) work[i] = mul_ref(work[i], 8347681);
          if (lane == 0) expected0[i] = work[i];
          else expected1[i] = work[i];
        end
      end
    end
  endtask

  task automatic assert_transients_wiped;
    begin
      if (dut.a0_q !== 23'd0 || dut.b0_q !== 23'd0 ||
          dut.a1_q !== 23'd0 || dut.b1_q !== 23'd0 ||
          dut.u_mul0.product_q !== 46'd0 || dut.u_mul1.product_q !== 46'd0 ||
          dut.u_mul0.fold1_q !== 36'd0 || dut.u_mul1.fold1_q !== 36'd0 ||
          dut.u_mul0.fold2_q !== 27'd0 || dut.u_mul1.fold2_q !== 27'd0 ||
          dut.u_mul0.result_o !== 23'd0 || dut.u_mul1.result_o !== 23'd0 ||
          dut.u_mul0.valid_q !== 4'd0 || dut.u_mul1.valid_q !== 4'd0)
        $fatal(1, "Sensitive pipeline registers not scrubbed");
    end
  endtask

  task automatic assert_wiped;
    integer i;
    begin
      for (i = 0; i < N; i = i + 1)
        if (dut.mem0[i] !== 23'd0 || dut.mem1[i] !== 23'd0)
          $fatal(1, "Memory not scrubbed at address %0d", i);
      if (out_valid_o !== 1'b0 || out_share0_o !== 23'd0 ||
          out_share1_o !== 23'd0 || out_last_o !== 1'b0)
        $fatal(1, "Stale output exposed after wipe");
      assert_transients_wiped();
    end
  endtask

  task automatic wait_input_ready;
    integer cycles;
    begin
      cycles = 0;
      while (in_ready_o !== 1'b1) begin
        @(posedge clk_i); #1;
        cycles = cycles + 1;
        if (cycles > 300) $fatal(1, "Input ready timeout");
      end
      if (error_o !== 1'b0) $fatal(1, "Unexpected sticky error");
    end
  endtask

  task automatic prepare_shares(input bit masked);
    integer i;
    integer unsigned r;
    begin
      for (i = 0; i < N; i = i + 1) begin
        if (masked) begin
          r = $urandom % Q;
          share0[i] = r;
          share1[i] = (input_data[i] + Q - r) % Q;
        end else begin
          share0[i] = input_data[i];
          share1[i] = 0;
        end
      end
    end
  endtask

  task automatic load_shares;
    integer i;
    begin
      wait_input_ready();
      for (i = 0; i < N; i = i + 1) begin
        if ((i % 17) == 0) begin
          @(negedge clk_i);
          in_valid_i = 0;
          @(posedge clk_i); #1;
          if (!in_ready_o) $fatal(1, "Load gap changed readiness");
        end
        @(negedge clk_i);
        if (!in_ready_o) $fatal(1, "Input not ready for coefficient %0d", i);
        in_valid_i = 1;
        in_share0_i = share0[i];
        in_share1_i = share1[i];
        @(posedge clk_i); #1;
      end
      @(negedge clk_i);
      in_valid_i = 0;
      in_share0_i = 0;
      in_share1_i = 0;
      if (start_ready_o !== 1'b1 || in_ready_o !== 1'b0)
        $fatal(1, "Exactly 256 inputs must enable start");
    end
  endtask

  task automatic start_transform(input bit inverse_mode);
    begin
      // load_shares returns at a negative edge; asserting now is race-free.
      inverse_i = inverse_mode;
      start_i = 1;
      @(posedge clk_i); #1;
      if (done_o || !busy_o || start_ready_o)
        $fatal(1, "Invalid status immediately after start");
    end
  endtask

  task automatic wait_transform(input bit inverse_mode, input bit check_trace);
    integer cycles, trace_index, expected_cycles;
    reg [63:0] current_trace;
    begin
      cycles = 0;
      expected_cycles = inverse_mode ? 7680 : 6144;
      while (done_o !== 1'b1) begin
        @(negedge clk_i);
        // Deliberately offer ignored traffic and change the live mode pin.
        start_i = ((cycles % 23) == 3);
        in_valid_i = ((cycles % 29) == 5);
        out_ready_i = ((cycles % 31) == 7);
        in_share0_i = 23'd1234;
        in_share1_i = 23'd5678;
        inverse_i = !inverse_mode;
        @(posedge clk_i); #1;
        cycles = cycles + 1;
        if (cycles > expected_cycles + 5) $fatal(1, "Transform timeout");
        if (in_ready_o || start_ready_o || error_o)
          $fatal(1, "Unexpected readiness/error while computing");
        if (!done_o && !busy_o) $fatal(1, "Busy dropped before completion");
        if (!done_o && out_valid_o) $fatal(1, "Premature result access");
        if (check_trace) begin
          current_trace = {dut.state_q, dut.len_q, dut.start_q,
                           dut.j_q, dut.k_q, dut.scale_q};
          trace_index = (inverse_mode ? 8192 : 0) + cycles - 1;
          if (!trace_seen[inverse_mode]) baseline_trace[trace_index] = current_trace;
          else if (baseline_trace[trace_index] !== current_trace)
            $fatal(1, "Data-dependent control/address trace: mode=%0d cycle=%0d",
                   inverse_mode, cycles);
        end
      end
      if (cycles != expected_cycles)
        $fatal(1, "Latency mismatch: mode=%0d expected=%0d actual=%0d",
               inverse_mode, expected_cycles, cycles);
      if (check_trace) trace_seen[inverse_mode] = 1;
      if (!out_valid_o) $fatal(1, "Done without output valid");
      @(negedge clk_i);
      start_i = 0;
      in_valid_i = 0;
      out_ready_i = 0;
      in_share0_i = 0;
      in_share1_i = 0;
    end
  endtask

  task automatic drain_results(input integer test_id);
    integer i, stall;
    reg [22:0] held0, held1;
    reg held_last;
    begin
      for (i = 0; i < N; i = i + 1) begin
        held0 = out_share0_o;
        held1 = out_share1_o;
        held_last = out_last_o;
        for (stall = 0; stall < ((i % 7) == 0 ? 3 : 0); stall = stall + 1) begin
          out_ready_i = 0;
          @(posedge clk_i); #1;
          if (!out_valid_o || out_share0_o !== held0 ||
              out_share1_o !== held1 || out_last_o !== held_last)
            $fatal(1, "Output changed under backpressure at %0d", i);
          @(negedge clk_i);
        end
        if (!out_valid_o) $fatal(1, "Missing output %0d", i);
        if (out_last_o !== (i == 255)) $fatal(1, "Incorrect last flag at %0d", i);
        if (out_share0_o >= Q || out_share1_o >= Q)
          $fatal(1, "Noncanonical output");
        if (out_share0_o !== expected0[i] || out_share1_o !== expected1[i])
          $fatal(1, "Share mismatch test=%0d i=%0d actual=(%0d,%0d) expected=(%0d,%0d)",
                 test_id, i, out_share0_o, out_share1_o, expected0[i], expected1[i]);
        observed0[i] = out_share0_o;
        observed[i] = (int'(out_share0_o) + int'(out_share1_o)) % Q;
        if (observed[i] !== golden_data[i])
          $fatal(1, "Vector mismatch test=%0d i=%0d actual=%0d expected=%0d",
                 test_id, i, observed[i], golden_data[i]);
        out_ready_i = 1;
        @(posedge clk_i); #1;
        if (done_o) $fatal(1, "Done should be a one-cycle pulse");
        @(negedge clk_i);
        out_ready_i = 0;
      end
      if (out_valid_o) $fatal(1, "Output count exceeds 256");
      wait_input_ready();
      assert_wiped();
    end
  endtask

  task automatic run_operation(input bit inverse_mode, input bit masked,
                               input integer test_id);
    integer previous_count;
    begin
      previous_count = done_count;
      prepare_shares(masked);
      model_shares(inverse_mode);
      load_shares();
      start_transform(inverse_mode);
      wait_transform(inverse_mode, 1);
      drain_results(test_id);
      if (done_count != previous_count + 1) $fatal(1, "Incorrect done pulse count");
      operation_count = operation_count + 1;
      $display("PASS core case=%0d mode=%0d masked=%0d cycles=%0d",
               test_id, inverse_mode, masked, inverse_mode ? 7680 : 6144);
    end
  endtask

  task automatic do_zeroize;
    begin
      @(negedge clk_i);
      zeroize_i = 1;
      start_i = 0;
      in_valid_i = 0;
      out_ready_i = 0;
      @(posedge clk_i); #1;
      if (out_valid_o || in_ready_o || start_ready_o || error_o ||
          out_share0_o !== 23'd0 || out_share1_o !== 23'd0)
        $fatal(1, "Zeroize did not immediately hide stale state");
      assert_transients_wiped();
      @(negedge clk_i);
      zeroize_i = 0;
      wait_input_ready();
      assert_wiped();
    end
  endtask

  task automatic check_bad_input(input bit bad_lane);
    integer cycles;
    begin
      wait_input_ready();
      @(negedge clk_i);
      in_valid_i = 1;
      in_share0_i = 23'd7654321;
      in_share1_i = 23'd1234567;
      repeat (4) begin
        @(posedge clk_i); #1;
        if (!in_ready_o || error_o) $fatal(1, "Valid partial load failed");
      end
      @(negedge clk_i);
      in_share0_i = bad_lane ? 23'd17 : 23'd8380417;
      in_share1_i = bad_lane ? 23'h7fffff : 23'd19;
      @(posedge clk_i); #1;
      if (!error_o) $fatal(1, "Out-of-range input was accepted silently");
      @(negedge clk_i);
      in_valid_i = 0;
      cycles = 0;
      while (busy_o) begin
        @(posedge clk_i); #1;
        cycles = cycles + 1;
        if (cycles > 300) $fatal(1, "Fault scrub timeout");
        if (out_valid_o) $fatal(1, "Fault exposed stale output");
      end
      if (!error_o || in_ready_o || start_ready_o)
        $fatal(1, "Fault must lock input until explicit zeroize/reset");
      assert_wiped();
      do_zeroize();
    end
  endtask

  // Global watchdog and pulse-width checks also cover aborted operations.
  always @(posedge clk_i) begin
    #2;
    if (rst_ni) begin
      if ((^{in_ready_o, start_ready_o, out_valid_o, busy_o, done_o, error_o}) === 1'bx)
        $fatal(1, "Unknown control output");
      if (done_o && previous_done) $fatal(1, "Done remained high more than one cycle");
      if (done_o) done_count = done_count + 1;
      previous_done = done_o;
    end else previous_done = 0;
  end
  initial begin
    #20000000;
    $fatal(1, "Global watchdog expired");
  end

  integer c, i, j, changed;
  integer unsigned evaluation, root;
  initial begin
    if ($test$plusargs("vcd")) begin
      $dumpfile("build/ntt_accelerator.vcd");
      $dumpvars(0, tb_ntt_accelerator);
    end
    $readmemh("build/vectors/input.memh", vector_input);
    $readmemh("build/vectors/expected.memh", vector_expected);
    $readmemh("build/vectors/modes.memh", vector_mode);
    discarded_random = $urandom(seed);
    for (i = 0; i < N; i = i + 1) twiddles[i] = pow_ref(1753, bitrev8(i));
    repeat (3) @(posedge clk_i);
    @(negedge clk_i); rst_ni = 1;
    wait_input_ready();
    assert_wiped();

    // Early start cannot transform a partial polynomial.
    @(negedge clk_i); start_i = 1;
    repeat (3) begin
      @(posedge clk_i); #1;
      if (!in_ready_o || busy_o || done_o || error_o)
        $fatal(1, "Early start must be ignored");
    end
    @(negedge clk_i); start_i = 0;

    for (c = 0; c < CASES; c = c + 1) begin
      for (i = 0; i < N; i = i + 1) begin
        input_data[i] = vector_input[c*N+i];
        golden_data[i] = vector_expected[c*N+i];
      end
      run_operation(vector_mode[c], 1, c);
    end

    // Identical polynomial under two fresh sharings; also public/unmasked mode.
    for (i = 0; i < N; i = i + 1) begin
      input_data[i] = vector_input[i];
      golden_data[i] = vector_expected[i];
    end
    run_operation(vector_mode[0], 1, 100);
    for (i = 0; i < N; i = i + 1) saved0[i] = observed0[i];
    run_operation(vector_mode[0], 1, 101);
    changed = 0;
    for (i = 0; i < N; i = i + 1)
      if (saved0[i] != observed0[i]) changed = changed + 1;
    if (changed == 0) $fatal(1, "Fresh sharing did not change output shares");
    run_operation(vector_mode[0], 0, 102);

    // Real hardware FWD -> pointwise multiply -> INV: x^255*x == -1.
    for (i = 0; i < N; i = i + 1) begin
      input_data[i] = (i == 255) ? 1 : 0;
      golden_data[i] = pow_ref(pow_ref(1753, 2*bitrev8(i)+1), 255);
    end
    run_operation(0, 1, 200);
    for (i = 0; i < N; i = i + 1) product_a[i] = observed[i];
    for (i = 0; i < N; i = i + 1) begin
      input_data[i] = (i == 1) ? 1 : 0;
      golden_data[i] = pow_ref(1753, 2*bitrev8(i)+1);
    end
    run_operation(0, 1, 201);
    for (i = 0; i < N; i = i + 1) product_b[i] = observed[i];
    for (i = 0; i < N; i = i + 1) begin
      input_data[i] = mul_ref(product_a[i], product_b[i]);
      golden_data[i] = (i == 0) ? Q-1 : 0;
    end
    run_operation(1, 1, 202);

    // A nontrivial hardware round trip, with a direct Horner forward oracle.
    for (i = 0; i < N; i = i + 1) begin
      input_data[i] = (i*123457 + 98765) % Q;
      roundtrip_plain[i] = input_data[i];
    end
    for (i = 0; i < N; i = i + 1) begin
      root = pow_ref(1753, 2*bitrev8(i)+1);
      evaluation = 0;
      for (j = N-1; j >= 0; j = j - 1)
        evaluation = (mul_ref(evaluation, root) + input_data[j]) % Q;
      golden_data[i] = evaluation;
    end
    run_operation(0, 1, 210);
    for (i = 0; i < N; i = i + 1) begin
      input_data[i] = observed[i];
      golden_data[i] = roundtrip_plain[i];
    end
    run_operation(1, 1, 211);

    // Abort a partially loaded operation.
    @(negedge clk_i);
    in_valid_i = 1; in_share0_i = 23'd123; in_share1_i = 23'd456;
    repeat (7) @(posedge clk_i);
    do_zeroize();

    // Abort mid-computation, then reset independently mid-computation.
    prepare_shares(1);
    load_shares(); start_transform(0);
    @(negedge clk_i); start_i = 0;
    repeat (100) @(posedge clk_i);
    do_zeroize();
    prepare_shares(1);
    load_shares(); start_transform(1);
    @(negedge clk_i); start_i = 0;
    repeat (117) @(posedge clk_i);
    @(negedge clk_i); rst_ni = 0;
    #1;
    if (out_valid_o || out_share0_o !== 23'd0 || out_share1_o !== 23'd0)
      $fatal(1, "Reset did not hide results");
    repeat (2) @(posedge clk_i);
    @(negedge clk_i); rst_ni = 1;
    wait_input_ready(); assert_wiped();

    // Zeroize with a valid output held under backpressure.
    prepare_shares(1); load_shares(); start_transform(0);
    wait_transform(0, 0);
    repeat (5) @(posedge clk_i);
    if (!out_valid_o) $fatal(1, "Output did not survive a stall");
    do_zeroize();
    check_bad_input(0);
    check_bad_input(1);

    // Recovery is functional, not merely a change in status bits.
    for (i = 0; i < N; i = i + 1) begin
      input_data[i] = vector_input[i];
      golden_data[i] = vector_expected[i];
    end
    run_operation(vector_mode[0], 1, 300);
    $display("PASS tb_ntt_accelerator: %0d complete transforms; sharewise/vector correctness, fixed traces, protocol and zeroization", operation_count);
    $finish;
  end
endmodule
