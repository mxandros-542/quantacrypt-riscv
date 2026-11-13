`timescale 1ns/1ps
`timescale 1ns/1ps
// Generic synchronous MMIO adapter. This shared bus is outside the masking boundary.
module ntt_mmio (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        req_i,
  input  logic        write_i,
  input  logic [11:0] addr_i,
  input  logic [31:0] wdata_i,
  input  logic [3:0]  wstrb_i,
  output logic        rsp_valid_o,
  output logic [31:0] rdata_o,
  output logic        error_o
);
  localparam logic [31:0] Q = 32'd8380417;
  localparam logic [11:0] CONTROL = 12'h000, STATUS = 12'h004,
    INPUT_SHARE0 = 12'h008, INPUT_SHARE1 = 12'h00c,
    OUTPUT_SHARE0 = 12'h010, OUTPUT_SHARE1 = 12'h014;

  logic zeroize, start, inverse, in_valid, in_ready, start_ready;
  logic out_valid, out_ready, out_last, busy, done, core_error;
  logic [22:0] staged_share0, out_share0, out_share1;
  logic input_pending, output_share0_seen, done_sticky, protocol_error_sticky;
  logic request_error, stage_input, mark_output;
  logic [31:0] request_rdata;

  ntt_accelerator u_core (
    .clk_i(clk_i), .rst_ni(rst_ni), .zeroize_i(zeroize),
    .start_i(start), .start_ready_o(start_ready), .inverse_i(inverse),
    .in_valid_i(in_valid), .in_ready_o(in_ready),
    .in_share0_i(staged_share0), .in_share1_i(wdata_i[22:0]),
    .out_valid_o(out_valid), .out_ready_i(out_ready),
    .out_share0_o(out_share0), .out_share1_o(out_share1),
    .out_last_o(out_last), .busy_o(busy), .done_o(done), .error_o(core_error)
  );

  // Decode a request before its sampling edge. Every accepted req_i receives
  // exactly one registered response, including requests rejected below.
  always_comb begin
    zeroize = 1'b0;
    start = 1'b0;
    inverse = wdata_i[1];
    in_valid = 1'b0;
    out_ready = 1'b0;
    stage_input = 1'b0;
    mark_output = 1'b0;
    request_error = 1'b0;
    request_rdata = 32'b0;
    if (req_i) begin
      if ((addr_i[1:0] != 2'b00) || (write_i && wstrb_i != 4'hf)) begin
        request_error = 1'b1;
      end else if (write_i) begin
        case (addr_i)
          CONTROL: begin
            if (wdata_i[31:3] != 29'b0 || (!wdata_i[2] && !wdata_i[0]))
              request_error = 1'b1;
            else if (wdata_i[2])
              zeroize = 1'b1; // Dominates START, even while busy or faulted.
            else if (start_ready && !input_pending)
              start = 1'b1;
            else
              request_error = 1'b1;
          end
          INPUT_SHARE0: begin
            if (in_ready && !input_pending && wdata_i < Q)
              stage_input = 1'b1;
            else
              request_error = 1'b1;
          end
          INPUT_SHARE1: begin
            if (in_ready && input_pending && wdata_i < Q)
              in_valid = 1'b1;
            else
              request_error = 1'b1;
          end
          default: request_error = 1'b1;
        endcase
      end else begin
        case (addr_i)
          STATUS: begin
            request_rdata[0] = busy;
            request_rdata[1] = start_ready;
            request_rdata[2] = in_ready;
            request_rdata[3] = out_valid;
            request_rdata[4] = done_sticky;
            request_rdata[5] = core_error;
            request_rdata[6] = input_pending;
            request_rdata[7] = out_valid && out_last;
            request_rdata[8] = protocol_error_sticky;
          end
          OUTPUT_SHARE0: begin
            if (out_valid) begin
              request_rdata[22:0] = out_share0;
              mark_output = 1'b1;
            end else
              request_error = 1'b1;
          end
          OUTPUT_SHARE1: begin
            if (out_valid && output_share0_seen) begin
              request_rdata[22:0] = out_share1;
              out_ready = 1'b1;
            end else
              request_error = 1'b1;
          end
          default: request_error = 1'b1;
        endcase
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rsp_valid_o <= 1'b0;
      rdata_o <= 32'b0;
      error_o <= 1'b0;
      staged_share0 <= 23'b0;
      input_pending <= 1'b0;
      output_share0_seen <= 1'b0;
      done_sticky <= 1'b0;
      protocol_error_sticky <= 1'b0;
    end else begin
      rsp_valid_o <= req_i;
      rdata_o <= request_rdata;
      error_o <= req_i && request_error;
      if (zeroize) begin
        staged_share0 <= 23'b0;
        input_pending <= 1'b0;
        output_share0_seen <= 1'b0;
        done_sticky <= 1'b0;
        protocol_error_sticky <= 1'b0;
      end else begin
        if (req_i && request_error)
          protocol_error_sticky <= 1'b1;
        if (done)
          done_sticky <= 1'b1;
        if (start)
          done_sticky <= 1'b0;
        if (stage_input) begin
          staged_share0 <= wdata_i[22:0];
          input_pending <= 1'b1;
        end
        if (in_valid) begin
          staged_share0 <= 23'b0;
          input_pending <= 1'b0;
        end
        if (mark_output)
          output_share0_seen <= 1'b1;
        if (out_ready || !out_valid)
          output_share0_seen <= 1'b0;
      end
    end
  end
endmodule
