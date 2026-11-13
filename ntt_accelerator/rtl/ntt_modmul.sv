`timescale 1ns/1ps
// Four registered stages, one input per clock. No data-dependent iteration.
module ntt_modmul (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        clear_i,
  input  logic        in_valid_i,
  input  logic [22:0] a_i,
  input  logic [22:0] b_i,
  output logic        out_valid_o,
  output logic [22:0] result_o
);
  import ntt_pkg::*;
  logic [3:0] valid_q;
  logic [45:0] product_q;
  logic [35:0] fold1_q;
  logic [26:0] fold2_q;

  assign out_valid_o = valid_q[3];
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      valid_q <= '0;
      product_q <= '0;
      fold1_q <= '0;
      fold2_q <= '0;
      result_o <= '0;
    end else if (clear_i) begin
      valid_q <= '0;
      product_q <= '0;
      fold1_q <= '0;
      fold2_q <= '0;
      result_o <= '0;
    end else begin
      valid_q <= {valid_q[2:0], in_valid_i};
      // Enables depend only on the public transaction schedule.
      product_q <= in_valid_i ? a_i * b_i : 46'b0;
      fold1_q <= valid_q[0] ? fold_first(product_q) : 36'b0;
      fold2_q <= valid_q[1] ? fold_second(fold1_q) : 27'b0;
      result_o <= valid_q[2] ? fold_final(fold2_q) : 23'b0;
    end
  end
endmodule
