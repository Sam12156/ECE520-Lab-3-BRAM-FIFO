`timescale 1ns / 1ps

module tb_sc_fifo();

parameter CLK_PERIOD = 20;                  // 50 MHz
parameter WIDTH = 16;
parameter DEPTH = 32;
parameter ALMOST_EMPTY_THRESHOLD = 1;
parameter ALMOST_FULL_THRESHOLD = 31;
parameter READ_LATENCY = 1;
parameter NUM_WORDS = 3 * DEPTH + 200;      // lines in input_data.txt

reg clk;
reg srst;
reg [WIDTH-1:0] data_in;
reg write_enable;
reg read_enable;
wire [$clog2(DEPTH + 1)-1:0] data_count;
wire valid;
wire [WIDTH-1:0] data_out;
wire almost_full;
wire almost_empty;
wire full;
wire empty;

integer errors = 0;
integer i = 0;
integer idx = 0;
integer raw_fd;
integer results_fd;

// input_data.txt: DEPTH words of all 1s, DEPTH of all 0s,
// DEPTH alternating 0xAAAA/0x5555, then random words
reg [WIDTH-1:0] file_data [0:NUM_WORDS-1];

sc_fifo #(
    .WIDTH(WIDTH),
    .DEPTH(DEPTH),
    .ALMOST_EMPTY_THRESHOLD(ALMOST_EMPTY_THRESHOLD),
    .ALMOST_FULL_THRESHOLD(ALMOST_FULL_THRESHOLD),
    .READ_LATENCY(READ_LATENCY)
) UUT (
    .clk(clk),
    .srst(srst),
    .data_in(data_in),
    .write_enable(write_enable),
    .read_enable(read_enable),
    .data_count(data_count),
    .valid(valid),
    .data_out(data_out),
    .almost_full(almost_full),
    .almost_empty(almost_empty),
    .full(full),
    .empty(empty)
);

initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD / 2) clk = ~clk;
end

// Check data_count and the status flags against the expected number of words
task check_status(input integer expected_count);
begin
    if (data_count !== expected_count
        || full !== (expected_count == DEPTH)
        || empty !== (expected_count == 0)
        || almost_full !== (expected_count >= ALMOST_FULL_THRESHOLD)
        || almost_empty !== (expected_count <= ALMOST_EMPTY_THRESHOLD)) begin
        errors = errors + 1;
        $fdisplay(results_fd, "[%0t] FAIL: data_count=%0d full=%b empty=%b almost_full=%b almost_empty=%b, expected %0d words",
                  $time, data_count, full, empty, almost_full, almost_empty, expected_count);
    end
end
endtask

// Wait out the read latency, then check valid and data_out
task check_read(input expect_valid, input [WIDTH-1:0] expected);
begin
    repeat (READ_LATENCY - 1) #(CLK_PERIOD);
    if (valid !== expect_valid || (expect_valid && data_out !== expected)) begin
        errors = errors + 1;
        $fdisplay(results_fd, "[%0t] FAIL: valid=%b data_out=%h, expected valid=%b data_out=%h",
                  $time, valid, data_out, expect_valid, expected);
    end
end
endtask

task write_word(input [WIDTH-1:0] data);
begin
    write_enable = 1'b1;
    data_in = data;
    #(CLK_PERIOD);
    write_enable = 1'b0;
end
endtask

task read_word(input expect_valid, input [WIDTH-1:0] expected);
begin
    read_enable = 1'b1;
    #(CLK_PERIOD);
    read_enable = 1'b0;
    check_read(expect_valid, expected);
end
endtask

task read_write_word(input [WIDTH-1:0] data, input expect_valid, input [WIDTH-1:0] expected);
begin
    write_enable = 1'b1;
    read_enable = 1'b1;
    data_in = data;
    #(CLK_PERIOD);
    write_enable = 1'b0;
    read_enable = 1'b0;
    check_read(expect_valid, expected);
end
endtask

// Write every memory location, try to overflow, read every location back,
// then try to underflow
task fill_and_drain(input integer start);
begin
    for (i = 0; i < DEPTH; i = i + 1) begin
        write_word(file_data[start + i]);
        check_status(i + 1);
    end
    write_word(~file_data[start]);              // overflow: ignored
    check_status(DEPTH);
    for (i = 0; i < DEPTH; i = i + 1) begin
        read_word(1'b1, file_data[start + i]);
        check_status(DEPTH - 1 - i);
    end
    read_word(1'b0, 0);                         // underflow: ignored
    check_status(0);
end
endtask

initial begin
    raw_fd = $fopen("test_results.txt");
    results_fd = raw_fd | 1;
    $readmemh("input_data.txt", file_data);
    srst = 1'b1;
    data_in = 0;
    write_enable = 1'b0;
    read_enable = 1'b0;
    #(2 * CLK_PERIOD);

    // Reset: empty, data_count 0, valid 0 and data_out 0
    srst = 1'b0;
    #(CLK_PERIOD);
    check_status(0);
    if (valid !== 1'b0 || data_out !== 0) begin
        errors = errors + 1;
        $fdisplay(results_fd, "[%0t] FAIL: after reset valid=%b data_out=%h", $time, valid, data_out);
    end

    // Read while empty (underflow)
    read_word(1'b0, 0);
    check_status(0);

    // All 1s, then all 0s, then alternating 0xAAAA/0x5555 through every location
    fill_and_drain(0);
    fill_and_drain(DEPTH);
    fill_and_drain(2 * DEPTH);

    // Random data: fill every location, then read and write while full
    // (only the read is accepted) and drain
    idx = 3 * DEPTH;
    for (i = 0; i < DEPTH; i = i + 1) begin
        write_word(file_data[idx + i]);
        check_status(i + 1);
    end
    read_write_word(file_data[idx + DEPTH], 1'b1, file_data[idx]);
    check_status(DEPTH - 1);
    for (i = 1; i < DEPTH; i = i + 1) begin
        read_word(1'b1, file_data[idx + i]);
        check_status(DEPTH - 1 - i);
    end
    idx = idx + DEPTH + 1;

    // Read and write while empty (only the write is accepted), then keep
    // reading and writing together for the rest of the random words
    read_write_word(file_data[idx], 1'b0, 0);
    check_status(1);
    for (i = idx + 1; i < NUM_WORDS; i = i + 1) begin
        read_write_word(file_data[i], 1'b1, file_data[i - 1]);
        check_status(1);
    end
    read_word(1'b1, file_data[NUM_WORDS - 1]);
    check_status(0);

    // Reset with data in the FIFO: data_out must return to 0
    write_word(16'h1234);
    write_word(16'h5678);
    read_word(1'b1, 16'h1234);
    srst = 1'b1;
    #(CLK_PERIOD);
    srst = 1'b0;
    check_status(0);
    if (valid !== 1'b0 || data_out !== 0) begin
        errors = errors + 1;
        $fdisplay(results_fd, "[%0t] FAIL: after reset valid=%b data_out=%h", $time, valid, data_out);
    end

    #(2 * CLK_PERIOD);
    if (errors == 0) begin
        $fdisplay(results_fd, "TEST PASSED");
    end else begin
        $fdisplay(results_fd, "TEST FAILED: %0d errors", errors);
    end
    $fclose(raw_fd);
    $finish;
end

endmodule
