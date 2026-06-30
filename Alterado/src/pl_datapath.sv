// =============================================================================
// pl_datapath.sv  (versao final consolidada)
// Datapath pipeline de 5 estagios -- RV32I (P&H secoes 4.6-4.10)
// =============================================================================

`timescale 1ns / 1ps

import pl_pipe_pkg::*;

module pl_datapath (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        ALUSrc,
    input  logic        ALUSrcPC,
    input  logic [1:0]  MemtoReg,
    input  logic        RegWrite,
    input  logic        MemRead,
    input  logic        MemWrite,
    input  logic        Branch,
    input  logic        Jump,
    input  logic [1:0]  ALUOp,
    input  logic [3:0]  ALU_CC,

    output logic [6:0]  Opcode,
    output logic [2:0]  Funct3_EX,
    output logic [6:0]  Funct7_EX,
    output logic [1:0]  ALUOp_EX,

    output logic [31:0] PC,

    input  logic [17:0] SW,
    input  logic [3:0]  KEY,
    output logic [17:0] LEDR,
    output logic [8:0]  LEDG,
    output logic        UART_TXD,
    input  logic        UART_RXD,

    output logic        wb_reg_write,
    output logic [4:0]  wb_reg_dst,
    output logic [31:0] wb_reg_data,
    output logic        mem_wr_en,
    output logic [7:0]  mem_wr_addr,
    output logic [31:0] mem_wr_data
);

    // =========================================================================
    // Sinais internos
    // =========================================================================
    logic [31:0] pc_reg, pc_plus4;

    if_id_t  if_id;
    id_ex_t  id_ex;
    ex_mem_t ex_mem;
    mem_wb_t mem_wb;

    logic        stall;
    logic        pc_src;
    logic [31:0] branch_target;

    logic [31:0] rd1, rd2, imm_ext;

    logic [1:0]  fwd_a, fwd_b;
    logic [31:0] fwd_srca, fwd_srcb, alu_srca, alu_srcb;
    logic [31:0] alu_result;
    logic        zero, negative, overflow, carry;
    logic        branch_taken;

    logic [31:0] wb_data;

    logic        mmio_sel;
    logic [31:0] dmem_rd, mmio_rd, mem_read_data;

    logic [3:0]  byte_en_ex, byte_en_mem;
    logic [31:0] store_data_ex;

    logic [31:0] load_extended;
    logic [7:0]  load_byte;
    logic [15:0] load_half;

    logic [31:0] instr_if;

    // =========================================================================
    // IF
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)      pc_reg <= 32'b0;
        else if (pc_src) pc_reg <= branch_target;
        else if (!stall) pc_reg <= pc_plus4;
    end

    assign PC       = pc_reg;
    assign pc_plus4 = pc_reg + 32'd4;

    pl_imem imem (
        .addr  (pc_reg[9:2]),
        .instr (instr_if)
    );

    // =========================================================================
    // Registrador IF/ID
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_id.pc    <= 32'b0;
            if_id.instr <= 32'b0;
        end else if (pc_src) begin
            if_id.pc    <= 32'b0;
            if_id.instr <= 32'b0;
        end else if (!stall) begin
            if_id.pc    <= pc_reg;
            if_id.instr <= instr_if;
        end
    end

    // =========================================================================
    // ID
    // =========================================================================
    assign Opcode = if_id.instr[6:0];

    pl_hazard hazard (
        .if_id_rs1      (if_id.instr[19:15]),
        .if_id_rs2      (if_id.instr[24:20]),
        .id_ex_rd       (id_ex.rd),
        .id_ex_mem_read (id_ex.mem_read),
        .stall          (stall)
    );

    // ---------------------------------------------------------------------------
    // Load extension: seleciona byte/halfword e estende sinal/zero
    // ---------------------------------------------------------------------------
    always_comb begin
        case (mem_wb.alu_result[1:0])
            2'b00: load_byte = mem_wb.read_data[7:0];
            2'b01: load_byte = mem_wb.read_data[15:8];
            2'b10: load_byte = mem_wb.read_data[23:16];
            2'b11: load_byte = mem_wb.read_data[31:24];
        endcase

        case (mem_wb.alu_result[1])
            1'b0: load_half = mem_wb.read_data[15:0];
            1'b1: load_half = mem_wb.read_data[31:16];
        endcase

        case (mem_wb.funct3)
            3'h0:    load_extended = {{24{load_byte[7]}}, load_byte};   // LB
            3'h1:    load_extended = {{16{load_half[15]}}, load_half};  // LH
            3'h2:    load_extended = mem_wb.read_data;                  // LW
            3'h4:    load_extended = {24'b0, load_byte};                // LBU
            3'h5:    load_extended = {16'b0, load_half};                // LHU
            default: load_extended = mem_wb.read_data;
        endcase
    end

    // ---------------------------------------------------------------------------
    // WB mux (3:1): ALU result | Load (com extensao) | PC+4
    // ---------------------------------------------------------------------------
    always_comb begin
        case (mem_wb.mem_to_reg)
            2'b01:   wb_data = load_extended;     // Load: byte/half/word extendido
            2'b10:   wb_data = mem_wb.pc_plus4;   // JAL/JALR: retorna PC+4
            default: wb_data = mem_wb.alu_result;  // R/I/LUI/AUIPC
        endcase
    end

    pl_regfile regfile (
        .clk       (clk),
        .RegWrite  (mem_wb.reg_write),
        .rs1       (if_id.instr[19:15]),
        .rs2       (if_id.instr[24:20]),
        .rd        (mem_wb.rd),
        .WriteData (wb_data),
        .ReadData1 (rd1),
        .ReadData2 (rd2)
    );

    pl_sign_ext sign_ext (
        .Instr  (if_id.instr),
        .ImmExt (imm_ext)
    );

    assign wb_reg_write = mem_wb.reg_write;
    assign wb_reg_dst   = mem_wb.rd;
    assign wb_reg_data  = wb_data;

    // =========================================================================
    // Registrador ID/EX
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || stall || pc_src) begin
            id_ex.alu_src    <= 1'b0;
            id_ex.alu_src_pc <= 1'b0;
            id_ex.mem_to_reg <= 2'b00;
            id_ex.reg_write  <= 1'b0;
            id_ex.mem_read   <= 1'b0;
            id_ex.mem_write  <= 1'b0;
            id_ex.alu_op     <= 2'b00;
            id_ex.branch     <= 1'b0;
            id_ex.jump       <= 1'b0;
            id_ex.pc         <= 32'b0;
            id_ex.rd1        <= 32'b0;
            id_ex.rd2        <= 32'b0;
            id_ex.rs1        <= 5'b0;
            id_ex.rs2        <= 5'b0;
            id_ex.rd         <= 5'b0;
            id_ex.imm_ext    <= 32'b0;
            id_ex.funct3     <= 3'b0;
            id_ex.funct7     <= 7'b0;
        end else begin
            id_ex.alu_src    <= ALUSrc;
            id_ex.alu_src_pc <= ALUSrcPC;
            id_ex.mem_to_reg <= MemtoReg;
            id_ex.reg_write  <= RegWrite;
            id_ex.mem_read   <= MemRead;
            id_ex.mem_write  <= MemWrite;
            id_ex.alu_op     <= ALUOp;
            id_ex.branch     <= Branch;
            id_ex.jump       <= Jump;
            id_ex.pc         <= if_id.pc;
            id_ex.rd1        <= rd1;
            id_ex.rd2        <= rd2;
            id_ex.rs1        <= if_id.instr[19:15];
            id_ex.rs2        <= if_id.instr[24:20];
            id_ex.rd         <= if_id.instr[11:7];
            id_ex.imm_ext    <= imm_ext;
            id_ex.funct3     <= if_id.instr[14:12];
            id_ex.funct7     <= if_id.instr[31:25];
        end
    end

    assign Funct3_EX = id_ex.funct3;
    assign Funct7_EX = id_ex.funct7;
    assign ALUOp_EX  = id_ex.alu_op;

    // =========================================================================
    // EX
    // =========================================================================
    pl_forward forward (
        .id_ex_rs1        (id_ex.rs1),
        .id_ex_rs2        (id_ex.rs2),
        .ex_mem_rd        (ex_mem.rd),
        .mem_wb_rd        (mem_wb.rd),
        .ex_mem_reg_write (ex_mem.reg_write),
        .mem_wb_reg_write (mem_wb.reg_write),
        .forward_a        (fwd_a),
        .forward_b        (fwd_b)
    );

    always_comb begin
        case (fwd_a)
            2'b10:   fwd_srca = ex_mem.alu_result;
            2'b01:   fwd_srca = wb_data;
            default: fwd_srca = id_ex.rd1;
        endcase
    end

    always_comb begin
        case (fwd_b)
            2'b10:   fwd_srcb = ex_mem.alu_result;
            2'b01:   fwd_srcb = wb_data;
            default: fwd_srcb = id_ex.rd2;
        endcase
    end

    // MUX SrcA: PC (AUIPC/JAL) ou registrador adiantado
    assign alu_srca = id_ex.alu_src_pc ? id_ex.pc : fwd_srca;

    // MUX SrcB: imediato ou registrador adiantado
    assign alu_srcb = id_ex.alu_src ? id_ex.imm_ext : fwd_srcb;

    pl_alu alu (
        .SrcA      (alu_srca),
        .SrcB      (alu_srcb),
        .Operation (ALU_CC),
        .ALUResult (alu_result),
        .Zero      (zero),
        .Negative  (negative),
        .Overflow  (overflow),
        .Carry     (carry)
    );

    // -------------------------------------------------------------------------
    // Avaliacao da condicao de branch via Funct3
    // -------------------------------------------------------------------------
    always_comb begin
        case (id_ex.funct3)
            3'h0:    branch_taken = zero;                    // BEQ
            3'h1:    branch_taken = ~zero;                   // BNE
            3'h4:    branch_taken = negative ^ overflow;     // BLT
            3'h5:    branch_taken = ~(negative ^ overflow);  // BGE
            3'h6:    branch_taken = ~carry;                  // BLTU
            3'h7:    branch_taken = carry;                   // BGEU
            default: branch_taken = 1'b0;
        endcase
    end

    // -------------------------------------------------------------------------
    // Calculo de target e pc_src
    // -------------------------------------------------------------------------
    always_comb begin
        if (id_ex.jump) begin
            // JAL : alu_result = PC + imm (ALUSrcPC=1)
            // JALR: alu_result = rs1 + imm (ALUSrcPC=0); bit 0 = 0 por spec
            branch_target = alu_result & 32'hFFFF_FFFE;
            pc_src        = 1'b1;
        end else if (id_ex.branch && branch_taken) begin
            branch_target = id_ex.pc + id_ex.imm_ext;
            pc_src        = 1'b1;
        end else begin
            branch_target = 32'b0;
            pc_src        = 1'b0;
        end
    end

    // -------------------------------------------------------------------------
    // Byte enables e alinhamento de store
    // -------------------------------------------------------------------------
    always_comb begin
        case (id_ex.funct3)
            3'h0: begin   // SB
                case (alu_result[1:0])
                    2'b00: begin byte_en_ex = 4'b0001; store_data_ex = {24'b0, fwd_srcb[7:0]}; end
                    2'b01: begin byte_en_ex = 4'b0010; store_data_ex = {16'b0, fwd_srcb[7:0], 8'b0}; end
                    2'b10: begin byte_en_ex = 4'b0100; store_data_ex = {8'b0, fwd_srcb[7:0], 16'b0}; end
                    2'b11: begin byte_en_ex = 4'b1000; store_data_ex = {fwd_srcb[7:0], 24'b0}; end
                endcase
            end
            3'h1: begin   // SH
                case (alu_result[1])
                    1'b0: begin byte_en_ex = 4'b0011; store_data_ex = {16'b0, fwd_srcb[15:0]}; end
                    1'b1: begin byte_en_ex = 4'b1100; store_data_ex = {fwd_srcb[15:0], 16'b0}; end
                endcase
            end
            default: begin  // SW
                byte_en_ex    = 4'b1111;
                store_data_ex = fwd_srcb;
            end
        endcase
    end

    // =========================================================================
    // Registrador EX/MEM
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_mem.mem_to_reg  <= 2'b00;
            ex_mem.reg_write   <= 1'b0;
            ex_mem.mem_read    <= 1'b0;
            ex_mem.mem_write   <= 1'b0;
            ex_mem.jump        <= 1'b0;
            ex_mem.alu_result  <= 32'b0;
            ex_mem.write_data  <= 32'b0;
            ex_mem.pc_plus4    <= 32'b0;
            ex_mem.rd          <= 5'b0;
            ex_mem.funct3      <= 3'b0;
        end else begin
            ex_mem.mem_to_reg  <= id_ex.mem_to_reg;
            ex_mem.reg_write   <= id_ex.reg_write;
            ex_mem.mem_read    <= id_ex.mem_read;
            ex_mem.mem_write   <= id_ex.mem_write;
            ex_mem.jump        <= id_ex.jump;
            ex_mem.alu_result  <= alu_result;
            ex_mem.write_data  <= store_data_ex;
            ex_mem.pc_plus4    <= id_ex.pc + 32'd4;
            ex_mem.rd          <= id_ex.rd;
            ex_mem.funct3      <= id_ex.funct3;
        end
    end

    // Byte enables: registrador separado (mesmo ciclo do EX/MEM)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) byte_en_mem <= 4'b0000;
        else        byte_en_mem <= byte_en_ex;
    end

    // =========================================================================
    // MEM
    // =========================================================================
    assign mmio_sel = ex_mem.alu_result[10];

    pl_dmem dmem (
        .clk       (clk),
        .MemWrite  (ex_mem.mem_write & ~mmio_sel),
        .ByteEn    (byte_en_mem),
        .addr      (ex_mem.alu_result[9:2]),
        .WriteData (ex_mem.write_data),
        .ReadData  (dmem_rd)
    );

    pl_mmio mmio (
        .clk       (clk),
        .rst_n     (rst_n),
        .MemWrite  (ex_mem.mem_write &  mmio_sel),
        .MemRead   (ex_mem.mem_read  &  mmio_sel),
        .addr      (ex_mem.alu_result[4:2]),
        .WriteData (ex_mem.write_data),
        .SW        (SW),
        .KEY       (KEY),
        .ReadData  (mmio_rd),
        .LEDR      (LEDR),
        .LEDG      (LEDG),
        .UART_TXD  (UART_TXD),
        .UART_RXD  (UART_RXD)
    );

    assign mem_read_data = mmio_sel ? mmio_rd : dmem_rd;

    assign mem_wr_en   = ex_mem.mem_write & ~mmio_sel;
    assign mem_wr_addr = ex_mem.alu_result[9:2];
    assign mem_wr_data = ex_mem.write_data;

    // =========================================================================
    // Registrador MEM/WB
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_wb.mem_to_reg <= 2'b00;
            mem_wb.reg_write  <= 1'b0;
            mem_wb.alu_result <= 32'b0;
            mem_wb.read_data  <= 32'b0;
            mem_wb.pc_plus4   <= 32'b0;
            mem_wb.rd         <= 5'b0;
            mem_wb.funct3     <= 3'b0;
        end else begin
            mem_wb.mem_to_reg <= ex_mem.mem_to_reg;
            mem_wb.reg_write  <= ex_mem.reg_write;
            mem_wb.alu_result <= ex_mem.alu_result;
            mem_wb.read_data  <= mem_read_data;
            mem_wb.pc_plus4   <= ex_mem.pc_plus4;
            mem_wb.rd         <= ex_mem.rd;
            mem_wb.funct3     <= ex_mem.funct3;
        end
    end

endmodule
