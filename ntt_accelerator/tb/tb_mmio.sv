`timescale 1ns/1ps
module tb_mmio;
  localparam integer Q = 8380417;
  logic clk = 1'b0;
  always #5 clk = ~clk;
  logic rst_n = 1'b0;
  logic req = 1'b0, wr = 1'b0;
  logic [11:0] addr = 12'b0;
  logic [31:0] wdata = 32'b0;
  logic [3:0] wstrb = 4'hf;
  wire rsp_valid, rsp_error;
  wire [31:0] rdata;
  integer checks = 0;
  integer i;
  reg [31:0] value, share0, share1, repeated_share0;

  ntt_mmio dut (
    .clk_i(clk), .rst_ni(rst_n), .req_i(req), .write_i(wr),
    .addr_i(addr), .wdata_i(wdata), .wstrb_i(wstrb),
    .rsp_valid_o(rsp_valid), .rdata_o(rdata), .error_o(rsp_error)
  );

  task automatic access_bus(
    input bit write_access, input logic [11:0] address,
    input logic [31:0] data, input logic [3:0] strobes,
    input bit expect_error, output logic [31:0] response
  );
    begin
      @(negedge clk);
      req = 1'b1;
      wr = write_access;
      addr = address;
      wdata = data;
      wstrb = strobes;
      @(posedge clk);
      #1;
      if (rsp_valid !== 1'b1 || rsp_error !== expect_error)
        $fatal(1, "MMIO response addr=%03h wr=%b error=%b expected=%b valid=%b",
               address, write_access, rsp_error, expect_error, rsp_valid);
      if (expect_error && rdata !== 32'b0)
        $fatal(1, "MMIO rejected access disclosed nonzero read data");
      response = rdata;
      checks = checks + 1;
      @(negedge clk);
      req = 1'b0;
      wr = 1'b0;
      addr = 12'b0;
      wdata = 32'b0;
      wstrb = 4'hf;
    end
  endtask

  task automatic write_reg(input logic [11:0] address,
                           input logic [31:0] data, input bit expect_error);
    reg [31:0] ignored;
    begin access_bus(1'b1, address, data, 4'hf, expect_error, ignored); end
  endtask

  task automatic read_reg(input logic [11:0] address, input bit expect_error,
                          output logic [31:0] data);
    begin access_bus(1'b0, address, 32'b0, 4'b0, expect_error, data); end
  endtask

  task automatic wait_status(input integer bit_index);
    reg [31:0] status;
    integer attempts;
    begin : wait_loop
      for (attempts = 0; attempts < 200000; attempts = attempts + 1) begin
        read_reg(12'h004, 1'b0, status);
        if (status[5] !== 1'b0) $fatal(1, "Unexpected core fault in MMIO test");
        if (status[bit_index] === 1'b1) disable wait_loop;
      end
      $fatal(1, "MMIO status bit %0d timeout", bit_index);
    end
  endtask

  task automatic load_constant(input integer coefficient);
    integer index, mask, second_share;
    begin
      for (index = 0; index < 256; index = index + 1) begin
        mask = 42 + index;
        second_share = (coefficient + Q - mask) % Q;
        write_reg(12'h008, mask, 1'b0);
        write_reg(12'h00c, second_share, 1'b0);
      end
    end
  endtask

  task automatic check_pair(input integer expected);
    reg [31:0] a, b;
    reg [63:0] sum;
    begin
      read_reg(12'h010, 1'b0, a);
      read_reg(12'h014, 1'b0, b);
      sum = {32'b0, a} + {32'b0, b};
      if (a >= Q || b >= Q || (sum % Q) != expected)
        $fatal(1, "MMIO coefficient got=(%0d,%0d), reconstructed=%0d expected=%0d",
               a, b, sum % Q, expected);
    end
  endtask

  initial begin
    repeat (1500000) @(posedge clk);
    $fatal(1, "tb_mmio global timeout");
  end

  initial begin
    repeat (4) @(negedge clk);
    rst_n = 1'b1;
    write_reg(12'h000, 32'd1, 1'b1); // START before load.
    read_reg(12'h010, 1'b1, value);
    wait_status(2);
    read_reg(12'h004, 1'b0, value);
    if (!value[8]) $fatal(1, "MMIO protocol error is not sticky");
    write_reg(12'h000, 32'd4, 1'b0);
    wait_status(2);
    read_reg(12'h004, 1'b0, value);
    if (value[8:4] != 0) $fatal(1, "ZEROIZE did not clear wrapper state");

    // Consecutive request edges each produce a registered response.
    @(negedge clk);
    req = 1'b1; wr = 1'b0; addr = 12'h004;
    repeat (3) begin
      @(posedge clk); #1;
      if (!rsp_valid || rsp_error || !rdata[2])
        $fatal(1, "Back-to-back MMIO response failed");
    end
    @(negedge clk); req = 1'b0;
    @(posedge clk); #1;
    if (rsp_valid || rsp_error || rdata != 0)
      $fatal(1, "Idle MMIO response did not clear");

    // Invalid requests cannot modify a staged share or consume output.
    write_reg(12'h00c, 32'd1, 1'b1);
    write_reg(12'h008, Q, 1'b1);
    write_reg(12'h008, 32'h80000001, 1'b1);
    write_reg(12'h000, 32'd0, 1'b1);
    write_reg(12'h000, 32'd8, 1'b1);
    write_reg(12'h004, 32'd0, 1'b1);
    write_reg(12'h010, 32'd0, 1'b1);
    read_reg(12'h008, 1'b1, value);
    read_reg(12'hffc, 1'b1, value);
    access_bus(1'b1, 12'h008, 32'd99, 4'b0011, 1'b1, value);
    access_bus(1'b1, 12'h009, 32'd99, 4'hf, 1'b1, value);
    write_reg(12'h008, 32'd100, 1'b0);
    write_reg(12'h008, 32'd101, 1'b1); // Preserve 100.
    write_reg(12'h00c, Q, 1'b1);       // Preserve pending 100.
    read_reg(12'h004, 1'b0, value);
    if (!value[6]) $fatal(1, "Rejected write lost staged input");
    write_reg(12'h00c, Q - 99, 1'b0); // a[0] = 1.
    write_reg(12'h000, 32'd1, 1'b1);  // Only one pair loaded.
    for (i = 1; i < 256; i = i + 1) begin
      write_reg(12'h008, 1000 + i, 1'b0);
      write_reg(12'h00c, Q - 1000 - i, 1'b0);
    end
    wait_status(1);
    write_reg(12'h008, 32'd0, 1'b1); // Cannot load coefficient 257.
    write_reg(12'h000, 32'd1, 1'b0);
    write_reg(12'h000, 32'd1, 1'b1); // Cannot restart while computing.
    read_reg(12'h010, 1'b1, value);
    wait_status(3);
    read_reg(12'h004, 1'b0, value);
    if (!value[4]) $fatal(1, "Completion did not become sticky");
    read_reg(12'h014, 1'b1, value);
    read_reg(12'h010, 1'b0, share0);
    read_reg(12'h010, 1'b0, repeated_share0);
    if (share0 !== repeated_share0) $fatal(1, "Output changed before pop");
    read_reg(12'h012, 1'b1, value);
    read_reg(12'h014, 1'b0, share1);
    if ((share0 + share1) % Q != 1) $fatal(1, "Bad impulse transform coefficient 0");
    for (i = 1; i < 256; i = i + 1) begin
      read_reg(12'h004, 1'b0, value);
      if (value[7] !== (i == 255)) $fatal(1, "Incorrect MMIO output LAST");
      check_pair(1);
    end
    read_reg(12'h014, 1'b1, value); // Final pair was consumed once.
    wait_status(2);

    // A fresh normalized inverse of all-one NTT values is e_0.
    write_reg(12'h000, 32'd4, 1'b0);
    wait_status(2);
    load_constant(1);
    write_reg(12'h000, 32'd3, 1'b0);
    read_reg(12'h004, 1'b0, value);
    if (value[4]) $fatal(1, "Accepted START did not clear DONE");
    wait_status(3);
    check_pair(1);
    for (i = 1; i < 256; i = i + 1) check_pair(0);
    wait_status(2);

    // ZEROIZE during execution cancels results and reopens a clean load.
    load_constant(0);
    write_reg(12'h000, 32'd1, 1'b0);
    write_reg(12'h000, 32'd7, 1'b0); // ZEROIZE dominates START+INVERSE.
    read_reg(12'h010, 1'b1, value);
    wait_status(2);
    read_reg(12'h004, 1'b0, value);
    if (value[7:3] != 0) $fatal(1, "Operation state survived ZEROIZE");

    // ZEROIZE also destroys the wrapper's half-loaded coefficient.
    write_reg(12'h008, 32'd77, 1'b0);
    write_reg(12'h000, 32'd4, 1'b0);
    wait_status(2);
    write_reg(12'h00c, 32'd1, 1'b1);
    load_constant(0);
    write_reg(12'h000, 32'd1, 1'b0);
    wait_status(3);
    read_reg(12'h010, 1'b0, share0);
    write_reg(12'h000, 32'd4, 1'b0);
    read_reg(12'h014, 1'b1, value);
    wait_status(2);
    read_reg(12'h004, 1'b0, value);
    if (value[7:3] != 0) $fatal(1, "Output state survived ZEROIZE");

    // Asynchronous reset clears an incomplete staging transaction too.
    write_reg(12'h008, 32'd66, 1'b0);
    @(negedge clk); rst_n = 1'b0;
    #1;
    if (rsp_valid || rsp_error || rdata != 0)
      $fatal(1, "Reset did not clear MMIO response registers");
    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    wait_status(2);
    read_reg(12'h004, 1'b0, value);
    if (value[8:3] != 0) $fatal(1, "Reset did not clear sticky/staged status");
    $display("PASS tb_mmio: %0d checked responses, forward/inverse and protocol recovery", checks);
    $finish;
  end
endmodule
