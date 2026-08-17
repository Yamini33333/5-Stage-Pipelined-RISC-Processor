`timescale 1ns / 1ps

module processor_tb;

    reg clk;
    reg reset;

    processor uut (
        .clk(clk),
        .reset(reset)
    );

    // Clock: 10 ns period
    always #5 clk = ~clk;

    initial begin

        clk = 0;
        reset = 1;

        #20;
        reset = 0;

        // Simple test program
        // ADDI R1, R0, 10
        uut.instruction_memory[0] = 32'b00100000000000010000000000001010;

        // ADDI R2, R0, 20
        uut.instruction_memory[1] = 32'b00100000000000100000000000010100;

        // ADD R3, R1, R2
        uut.instruction_memory[2] = 32'b00000000001000100001100000100000;

        // SUB R4, R2, R1
        uut.instruction_memory[3] = 32'b00000000010000010010000000100010;

        #200;

        $display("R1 = %d", uut.registers[1]);
        $display("R2 = %d", uut.registers[2]);
        $display("R3 = %d", uut.registers[3]);
        $display("R4 = %d", uut.registers[4]);

        $finish;

    end

endmodule
