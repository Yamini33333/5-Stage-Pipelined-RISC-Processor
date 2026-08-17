`timescale 1ns / 1ps

module processor (
    input  wire clk,
    input  wire reset
);

    // =========================================================
    // Instruction Memory
    // =========================================================
    reg [31:0] instruction_memory [0:255];

    // Data Memory
    reg [31:0] data_memory [0:255];

    // Register File
    reg [31:0] registers [0:31];

    // Program Counter
    reg [31:0] pc;

    integer i;

    // =========================================================
    // Pipeline Registers
    // =========================================================

    // IF/ID
    reg [31:0] IF_ID_PC;
    reg [31:0] IF_ID_INSTRUCTION;

    // ID/EX
    reg [31:0] ID_EX_PC;
    reg [31:0] ID_EX_READ_DATA1;
    reg [31:0] ID_EX_READ_DATA2;
    reg [31:0] ID_EX_IMMEDIATE;
    reg [4:0]  ID_EX_RS;
    reg [4:0]  ID_EX_RT;
    reg [4:0]  ID_EX_RD;

    reg ID_EX_REG_WRITE;
    reg ID_EX_MEM_READ;
    reg ID_EX_MEM_WRITE;
    reg ID_EX_MEM_TO_REG;
    reg ID_EX_ALUSRC;
    reg [3:0] ID_EX_ALU_CONTROL;

    // EX/MEM
    reg [31:0] EX_MEM_ALU_RESULT;
    reg [31:0] EX_MEM_WRITE_DATA;
    reg [4:0]  EX_MEM_RD;

    reg EX_MEM_REG_WRITE;
    reg EX_MEM_MEM_READ;
    reg EX_MEM_MEM_WRITE;
    reg EX_MEM_MEM_TO_REG;

    // MEM/WB
    reg [31:0] MEM_WB_READ_DATA;
    reg [31:0] MEM_WB_ALU_RESULT;
    reg [4:0]  MEM_WB_RD;

    reg MEM_WB_REG_WRITE;
    reg MEM_WB_MEM_TO_REG;

    // =========================================================
    // Instruction Decode
    // =========================================================

    wire [5:0] opcode = IF_ID_INSTRUCTION[31:26];
    wire [4:0] rs = IF_ID_INSTRUCTION[25:21];
    wire [4:0] rt = IF_ID_INSTRUCTION[20:16];
    wire [4:0] rd = IF_ID_INSTRUCTION[15:11];

    wire [15:0] immediate = IF_ID_INSTRUCTION[15:0];

    wire [31:0] sign_extended_immediate =
        {{16{immediate[15]}}, immediate};

    // =========================================================
    // Control Signals
    // =========================================================

    reg reg_write;
    reg mem_read;
    reg mem_write;
    reg mem_to_reg;
    reg alu_src;

    reg [3:0] alu_control;

    always @(*) begin

        reg_write  = 1'b0;
        mem_read   = 1'b0;
        mem_write  = 1'b0;
        mem_to_reg = 1'b0;
        alu_src    = 1'b0;
        alu_control = 4'b0000;

        case (opcode)

            // R-Type
            6'b000000: begin
                reg_write = 1'b1;

                case (IF_ID_INSTRUCTION[5:0])

                    6'b100000: alu_control = 4'b0010; // ADD
                    6'b100010: alu_control = 4'b0110; // SUB
                    6'b100100: alu_control = 4'b0000; // AND
                    6'b100101: alu_control = 4'b0001; // OR

                    default:
                        alu_control = 4'b0010;

                endcase
            end

            // ADDI
            6'b001000: begin
                reg_write = 1'b1;
                alu_src = 1'b1;
                alu_control = 4'b0010;
            end

            // LW
            6'b100011: begin
                reg_write = 1'b1;
                mem_read = 1'b1;
                mem_to_reg = 1'b1;
                alu_src = 1'b1;
                alu_control = 4'b0010;
            end

            // SW
            6'b101011: begin
                mem_write = 1'b1;
                alu_src = 1'b1;
                alu_control = 4'b0010;
            end

            default: begin
                reg_write = 1'b0;
            end

        endcase
    end

    // =========================================================
    // Register File Read
    // =========================================================

    wire [31:0] read_data1 =
        (rs == 0) ? 32'b0 : registers[rs];

    wire [31:0] read_data2 =
        (rt == 0) ? 32'b0 : registers[rt];

    // =========================================================
    // Hazard Detection
    // =========================================================

    wire load_use_hazard;

    assign load_use_hazard =
        ID_EX_MEM_READ &&
        (ID_EX_RT != 0) &&
        ((ID_EX_RT == rs) || (ID_EX_RT == rt));

    // =========================================================
    // Forwarding Unit
    // =========================================================

    reg [1:0] forwardA;
    reg [1:0] forwardB;

    always @(*) begin

        forwardA = 2'b00;
        forwardB = 2'b00;

        // EX hazard
        if (EX_MEM_REG_WRITE &&
            (EX_MEM_RD != 0) &&
            (EX_MEM_RD == ID_EX_RS))
            forwardA = 2'b10;

        if (EX_MEM_REG_WRITE &&
            (EX_MEM_RD != 0) &&
            (EX_MEM_RD == ID_EX_RT))
            forwardB = 2'b10;

        // MEM hazard
        if (MEM_WB_REG_WRITE &&
            (MEM_WB_RD != 0) &&
            !(EX_MEM_REG_WRITE &&
              (EX_MEM_RD != 0) &&
              (EX_MEM_RD == ID_EX_RS)) &&
            (MEM_WB_RD == ID_EX_RS))
            forwardA = 2'b01;

        if (MEM_WB_REG_WRITE &&
            (MEM_WB_RD != 0) &&
            !(EX_MEM_REG_WRITE &&
              (EX_MEM_RD != 0) &&
              (EX_MEM_RD == ID_EX_RT)) &&
            (MEM_WB_RD == ID_EX_RT))
            forwardB = 2'b01;

    end

    // =========================================================
    // Execute Stage
    // =========================================================

    reg [31:0] alu_input_A;
    reg [31:0] alu_input_B;
    reg [31:0] alu_result;

    always @(*) begin

        case (forwardA)

            2'b10:
                alu_input_A = EX_MEM_ALU_RESULT;

            2'b01:
                alu_input_A =
                    MEM_WB_MEM_TO_REG ?
                    MEM_WB_READ_DATA :
                    MEM_WB_ALU_RESULT;

            default:
                alu_input_A = ID_EX_READ_DATA1;

        endcase

        case (forwardB)

            2'b10:
                alu_input_B = EX_MEM_ALU_RESULT;

            2'b01:
                alu_input_B =
                    MEM_WB_MEM_TO_REG ?
                    MEM_WB_READ_DATA :
                    MEM_WB_ALU_RESULT;

            default:
                alu_input_B = ID_EX_READ_DATA2;

        endcase

        if (ID_EX_ALUSRC)
            alu_input_B = ID_EX_IMMEDIATE;

        case (ID_EX_ALU_CONTROL)

            4'b0000: alu_result = alu_input_A & alu_input_B;
            4'b0001: alu_result = alu_input_A | alu_input_B;
            4'b0010: alu_result = alu_input_A + alu_input_B;
            4'b0110: alu_result = alu_input_A - alu_input_B;

            default:
                alu_result = 32'b0;

        endcase

    end

    // =========================================================
    // Sequential Pipeline Operation
    // =========================================================

    always @(posedge clk or posedge reset) begin

        if (reset) begin

            pc <= 32'b0;

            IF_ID_PC <= 0;
            IF_ID_INSTRUCTION <= 0;

            ID_EX_PC <= 0;
            ID_EX_READ_DATA1 <= 0;
            ID_EX_READ_DATA2 <= 0;
            ID_EX_IMMEDIATE <= 0;
            ID_EX_RS <= 0;
            ID_EX_RT <= 0;
            ID_EX_RD <= 0;

            ID_EX_REG_WRITE <= 0;
            ID_EX_MEM_READ <= 0;
            ID_EX_MEM_WRITE <= 0;
            ID_EX_MEM_TO_REG <= 0;
            ID_EX_ALUSRC <= 0;
            ID_EX_ALU_CONTROL <= 0;

            EX_MEM_ALU_RESULT <= 0;
            EX_MEM_WRITE_DATA <= 0;
            EX_MEM_RD <= 0;

            EX_MEM_REG_WRITE <= 0;
            EX_MEM_MEM_READ <= 0;
            EX_MEM_MEM_WRITE <= 0;
            EX_MEM_MEM_TO_REG <= 0;

            MEM_WB_READ_DATA <= 0;
            MEM_WB_ALU_RESULT <= 0;
            MEM_WB_RD <= 0;

            MEM_WB_REG_WRITE <= 0;
            MEM_WB_MEM_TO_REG <= 0;

            for (i = 0; i < 32; i = i + 1)
                registers[i] <= 0;

        end

        else begin

            // =================================================
            // Write Back Stage
            // =================================================

            if (MEM_WB_REG_WRITE && MEM_WB_RD != 0) begin

                if (MEM_WB_MEM_TO_REG)
                    registers[MEM_WB_RD] <= MEM_WB_READ_DATA;

                else
                    registers[MEM_WB_RD] <= MEM_WB_ALU_RESULT;

            end

            // =================================================
            // Memory Stage
            // =================================================

            MEM_WB_ALU_RESULT <= EX_MEM_ALU_RESULT;
            MEM_WB_RD <= EX_MEM_RD;

            MEM_WB_REG_WRITE <= EX_MEM_REG_WRITE;
            MEM_WB_MEM_TO_REG <= EX_MEM_MEM_TO_REG;

            if (EX_MEM_MEM_READ)
                MEM_WB_READ_DATA <=
                    data_memory[EX_MEM_ALU_RESULT[9:2]];

            if (EX_MEM_MEM_WRITE)
                data_memory[EX_MEM_ALU_RESULT[9:2]]
                    <= EX_MEM_WRITE_DATA;

            // =================================================
            // Execute → Memory
            // =================================================

            EX_MEM_ALU_RESULT <= alu_result;
            EX_MEM_WRITE_DATA <= alu_input_B;
            EX_MEM_RD <= ID_EX_RD;

            EX_MEM_REG_WRITE <= ID_EX_REG_WRITE;
            EX_MEM_MEM_READ <= ID_EX_MEM_READ;
            EX_MEM_MEM_WRITE <= ID_EX_MEM_WRITE;
            EX_MEM_MEM_TO_REG <= ID_EX_MEM_TO_REG;

            // =================================================
            // Decode → Execute
            // =================================================

            if (load_use_hazard) begin

                ID_EX_REG_WRITE <= 0;
                ID_EX_MEM_READ <= 0;
                ID_EX_MEM_WRITE <= 0;
                ID_EX_MEM_TO_REG <= 0;
                ID_EX_ALUSRC <= 0;
                ID_EX_ALU_CONTROL <= 0;

            end

            else begin

                ID_EX_PC <= IF_ID_PC;

                ID_EX_READ_DATA1 <= read_data1;
                ID_EX_READ_DATA2 <= read_data2;

                ID_EX_IMMEDIATE <= sign_extended_immediate;

                ID_EX_RS <= rs;
                ID_EX_RT <= rt;
                ID_EX_RD <=
                    (opcode == 6'b000000) ? rd : rt;

                ID_EX_REG_WRITE <= reg_write;
                ID_EX_MEM_READ <= mem_read;
                ID_EX_MEM_WRITE <= mem_write;
                ID_EX_MEM_TO_REG <= mem_to_reg;
                ID_EX_ALUSRC <= alu_src;
                ID_EX_ALU_CONTROL <= alu_control;

            end

            // =================================================
            // Instruction Fetch
            // =================================================

            if (!load_use_hazard) begin

                IF_ID_PC <= pc;
                IF_ID_INSTRUCTION <= instruction_memory[pc[9:2]];

                pc <= pc + 4;

            end

        end

    end

endmodule
