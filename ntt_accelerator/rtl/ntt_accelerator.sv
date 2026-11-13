`timescale 1ns/1ps
// 256-point ML-DSA NTT / inverse NTT, standard residues, two additive shares.
// Never recombine shares here. See docs/SECURITY.md for the threat boundary.
module ntt_accelerator (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        zeroize_i,
  input  logic        start_i,
  output logic        start_ready_o,
  input  logic        inverse_i,
  input  logic        in_valid_i,
  output logic        in_ready_o,
  input  logic [22:0] in_share0_i,
  input  logic [22:0] in_share1_i,
  output logic        out_valid_o,
  input  logic        out_ready_i,
  output logic [22:0] out_share0_o,
  output logic [22:0] out_share1_o,
  output logic        out_last_o,
  output logic        busy_o,
  output logic        done_o,
  output logic        error_o
);
  import ntt_pkg::*;
  typedef enum logic [3:0] {
    S_SCRUB, S_INPUT, S_READY, S_READ, S_ISSUE, S_WAIT, S_OUTPUT, S_FAULT
  } state_t;
  state_t state_q;
  // Deliberately separate storage/datapaths. Physical separation still needs
  // synthesis constraints and post-route inspection on the selected target.
  logic [22:0] mem0 [0:255];
  logic [22:0] mem1 [0:255];
  logic [7:0] io_index_q, scrub_index_q;
  logic [8:0] len_q, start_q, j_q;
  logic [7:0] k_q;
  logic inverse_q, scale_q;
  logic [22:0] a0_q, b0_q, a1_q, b1_q;
  logic [22:0] zeta, factor, mul_a0, mul_a1, mul_r0, mul_r1;
  logic mul_valid0, mul_valid1, mul_issue, mul_clear;
  logic [8:0] second_index, next_block;

  assign second_index = j_q + len_q;
  assign next_block = start_q + (len_q << 1);
  assign in_ready_o = rst_ni && !zeroize_i && state_q == S_INPUT;
  assign start_ready_o = rst_ni && !zeroize_i && state_q == S_READY;
  assign out_valid_o = rst_ni && !zeroize_i && state_q == S_OUTPUT;
  assign out_share0_o = out_valid_o ? mem0[io_index_q] : 23'b0;
  assign out_share1_o = out_valid_o ? mem1[io_index_q] : 23'b0;
  assign out_last_o = out_valid_o && io_index_q == 8'd255;
  assign busy_o = state_q == S_SCRUB || state_q == S_READ ||
                  state_q == S_ISSUE || state_q == S_WAIT;
  assign mul_issue = state_q == S_ISSUE && !zeroize_i;
  assign mul_clear = zeroize_i || state_q == S_SCRUB ||
                     state_q == S_OUTPUT || state_q == S_FAULT;
  assign factor = scale_q ? N_INV : (inverse_q ? Q - zeta : zeta);
  assign mul_a0 = scale_q ? a0_q : (inverse_q ? sub_mod(a0_q,b0_q) : b0_q);
  assign mul_a1 = scale_q ? a1_q : (inverse_q ? sub_mod(a1_q,b1_q) : b1_q);

  ntt_twiddle_rom u_twiddle (.index_i(k_q), .zeta_o(zeta));
  ntt_modmul u_mul0 (
    .clk_i(clk_i), .rst_ni(rst_ni), .clear_i(mul_clear),
    .in_valid_i(mul_issue), .a_i(mul_a0), .b_i(factor),
    .out_valid_o(mul_valid0), .result_o(mul_r0)
  );
  ntt_modmul u_mul1 (
    .clk_i(clk_i), .rst_ni(rst_ni), .clear_i(mul_clear),
    .in_valid_i(mul_issue), .a_i(mul_a1), .b_i(factor),
    .out_valid_o(mul_valid1), .result_o(mul_r1)
  );

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= S_SCRUB;
      scrub_index_q <= '0;
      io_index_q <= '0;
      len_q <= '0;
      start_q <= '0;
      j_q <= '0;
      k_q <= '0;
      inverse_q <= 1'b0;
      scale_q <= 1'b0;
      a0_q <= '0; b0_q <= '0; a1_q <= '0; b1_q <= '0;
      done_o <= 1'b0;
      error_o <= 1'b0;
    end else if (zeroize_i) begin
      state_q <= S_SCRUB;
      scrub_index_q <= '0;
      io_index_q <= '0;
      len_q <= '0;
      start_q <= '0;
      j_q <= '0;
      k_q <= '0;
      inverse_q <= 1'b0;
      scale_q <= 1'b0;
      a0_q <= '0; b0_q <= '0; a1_q <= '0; b1_q <= '0;
      done_o <= 1'b0;
      error_o <= 1'b0;
    end else begin
      done_o <= 1'b0;
      case (state_q)
        S_SCRUB: begin
          mem0[scrub_index_q] <= '0;
          mem1[scrub_index_q] <= '0;
          a0_q <= '0; b0_q <= '0; a1_q <= '0; b1_q <= '0;
          if (scrub_index_q == 8'd255) begin
            scrub_index_q <= '0;
            io_index_q <= '0;
            state_q <= error_o ? S_FAULT : S_INPUT;
          end else scrub_index_q <= scrub_index_q + 1'b1;
        end
        S_INPUT: begin
          if (in_valid_i) begin
            if (in_share0_i >= Q || in_share1_i >= Q) begin
              error_o <= 1'b1;
              scrub_index_q <= '0;
              state_q <= S_SCRUB;
            end else begin
              mem0[io_index_q] <= in_share0_i;
              mem1[io_index_q] <= in_share1_i;
              if (io_index_q == 8'd255) begin
                io_index_q <= '0;
                state_q <= S_READY;
              end else io_index_q <= io_index_q + 1'b1;
            end
          end
        end
        S_READY: begin
          if (start_i) begin
            inverse_q <= inverse_i;
            len_q <= inverse_i ? 9'd1 : 9'd128;
            k_q <= inverse_i ? 8'd255 : 8'd1;
            start_q <= '0;
            j_q <= '0;
            scale_q <= 1'b0;
            state_q <= S_READ;
          end
        end
        S_READ: begin
          a0_q <= mem0[j_q[7:0]];
          a1_q <= mem1[j_q[7:0]];
          b0_q <= scale_q ? 23'b0 : mem0[second_index[7:0]];
          b1_q <= scale_q ? 23'b0 : mem1[second_index[7:0]];
          state_q <= S_ISSUE;
        end
        S_ISSUE: state_q <= S_WAIT;
        S_WAIT: begin
          if (mul_valid0 && mul_valid1) begin
            if (scale_q) begin
              mem0[j_q[7:0]] <= mul_r0;
              mem1[j_q[7:0]] <= mul_r1;
              if (j_q == 9'd255) begin
                state_q <= S_OUTPUT;
                io_index_q <= '0;
                done_o <= 1'b1;
                a0_q <= '0; b0_q <= '0; a1_q <= '0; b1_q <= '0;
              end else begin
                j_q <= j_q + 1'b1;
                state_q <= S_READ;
              end
            end else begin
              mem0[j_q[7:0]] <= inverse_q ? add_mod(a0_q,b0_q) : add_mod(a0_q,mul_r0);
              mem1[j_q[7:0]] <= inverse_q ? add_mod(a1_q,b1_q) : add_mod(a1_q,mul_r1);
              mem0[second_index[7:0]] <= inverse_q ? mul_r0 : sub_mod(a0_q,mul_r0);
              mem1[second_index[7:0]] <= inverse_q ? mul_r1 : sub_mod(a1_q,mul_r1);
              state_q <= S_READ;
              if (j_q == start_q + len_q - 1'b1) begin
                k_q <= inverse_q ? k_q - 1'b1 : k_q + 1'b1;
                if (next_block == 9'd256) begin
                  start_q <= '0;
                  j_q <= '0;
                  if ((!inverse_q && len_q == 9'd1) ||
                      (inverse_q && len_q == 9'd128)) begin
                    if (inverse_q) scale_q <= 1'b1;
                    else begin
                      state_q <= S_OUTPUT;
                      io_index_q <= '0;
                      done_o <= 1'b1;
                      a0_q <= '0; b0_q <= '0; a1_q <= '0; b1_q <= '0;
                    end
                  end else len_q <= inverse_q ? len_q << 1 : len_q >> 1;
                end else begin
                  start_q <= next_block;
                  j_q <= next_block;
                end
              end else j_q <= j_q + 1'b1;
            end
          end
        end
        S_OUTPUT: begin
          if (out_ready_i) begin
            // Scrub consumed words too; a full sweep follows the final word.
            mem0[io_index_q] <= '0;
            mem1[io_index_q] <= '0;
            if (io_index_q == 8'd255) begin
              io_index_q <= '0;
              scrub_index_q <= '0;
              len_q <= '0; start_q <= '0; j_q <= '0; k_q <= '0;
              scale_q <= 1'b0; inverse_q <= 1'b0;
              state_q <= S_SCRUB;
            end else io_index_q <= io_index_q + 1'b1;
          end
        end
        S_FAULT: begin end // Reset or explicit zeroize is required.
        default: begin
          error_o <= 1'b1;
          scrub_index_q <= '0;
          state_q <= S_SCRUB;
        end
      endcase
    end
  end
endmodule
