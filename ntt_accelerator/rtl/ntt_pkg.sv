`timescale 1ns/1ps
// ML-DSA field arithmetic. All operands/results are canonical unsigned residues.
package ntt_pkg;
  localparam logic [22:0] Q = 23'd8380417;
  localparam logic [22:0] N_INV = 23'd8347681;

  function automatic logic [22:0] add_mod(input logic [22:0] a, b);
    logic [23:0] sum, corrected;
    begin
      sum = {1'b0, a} + {1'b0, b};
      corrected = sum - {1'b0, Q};
      add_mod = corrected[23] ? sum[22:0] : corrected[22:0];
    end
  endfunction

  function automatic logic [22:0] sub_mod(input logic [22:0] a, b);
    logic [23:0] difference, corrected;
    begin
      difference = {1'b0, a} - {1'b0, b};
      corrected = difference + {1'b0, Q};
      sub_mod = difference[23] ? corrected[22:0] : difference[22:0];
    end
  endfunction

  // 2^23 == 8191 (mod Q). Three fixed folds replace a general divider.
  // Widths cover EVERY 46-bit input, not only products below Q^2.
  function automatic logic [35:0] fold_first(input logic [45:0] x);
    logic [35:0] high_part;
    begin
      high_part = {13'b0, x[45:23]};
      fold_first = {13'b0, x[22:0]} + (high_part << 13) - high_part;
    end
  endfunction

  function automatic logic [26:0] fold_second(input logic [35:0] x);
    logic [26:0] high_part;
    begin
      high_part = {14'b0, x[35:23]};
      fold_second = {4'b0, x[22:0]} + (high_part << 13) - high_part;
    end
  endfunction

  function automatic logic [22:0] fold_final(input logic [26:0] x);
    logic [23:0] high_part, folded, corrected;
    begin
      high_part = {20'b0, x[26:23]};
      folded = {1'b0, x[22:0]} + (high_part << 13) - high_part;
      corrected = folded - {1'b0, Q};
      fold_final = corrected[23] ? folded[22:0] : corrected[22:0];
    end
  endfunction

  function automatic logic [22:0] reduce_product(input logic [45:0] x);
    reduce_product = fold_final(fold_second(fold_first(x)));
  endfunction
endpackage
