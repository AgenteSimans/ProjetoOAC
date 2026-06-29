// =============================================================================
// pl_control.sv
// Unidade de Controle Principal -- RV32I pipelined (P&H secao 4.4)
//
// Decodifica o opcode de 7 bits (estagio ID) e gera os sinais de controle
// que serao propagados pelos registradores de pipeline.
//
// Instrucoes suportadas (versao completa RV32I):
//   R-type   (0110011): ADD, SUB, XOR, OR, AND, SLL, SRL, SRA, SLT, SLTU
//   I-arith  (0010011): ADDI, ANDI, ORI, SLTI, SLTIU, XORI, SLLI, SRLI, SRAI
//   I-load   (0000011): LW, LH, LB, LHU, LBU
//   S-type   (0100011): SW, SH, SB
//   B-type   (1100011): BEQ, BNE, BLT, BGE, BLTU, BGEU
//   LUI      (0110111): LUI
//   AUIPC    (0010111): AUIPC
//   JAL      (1101111): JAL
//   JALR     (1100111): JALR
//
// Tabela de sinais de controle:
//   Sinal      | R   | I-arith | Load | Store | Branch | LUI | AUIPC | JAL | JALR
//   -----------|-----|---------|------|-------|--------|-----|-------|-----|------
//   ALUSrc     |  0  |    1    |   1  |   1   |   0    |  1  |   1   |  -  |  1
//   ALUSrcPC   |  0  |    0    |   0  |   0   |   0    |  0  |   1   |  0  |  0
//   MemtoReg   | 00  |   00    |  01  |   -   |   -    | 00  |  00   | 10  | 10
//   RegWrite   |  1  |    1    |   1  |   0   |   0    |  1  |   1   |  1  |  1
//   MemRead    |  0  |    0    |   1  |   0   |   0    |  0  |   0   |  0  |  0
//   MemWrite   |  0  |    0    |   0  |   1   |   0    |  0  |   0   |  0  |  0
//   Branch     |  0  |    0    |   0  |   0   |   1    |  0  |   0   |  0  |  0
//   Jump       |  0  |    0    |   0  |   0   |   0    |  0  |   0   |  1  |  1
//   ALUOp[1:0] | 10  |   11    |  00  |  00   |  01    | 00  |  00   | 00  | 00
//
// Notas:
//   ALUSrcPC=1  : SrcA da ALU recebe PC em vez de registrador (AUIPC)
//   MemtoReg=10 : WB escreve PC+4 (JAL/JALR)
//   Jump=1      : salto incondicional; target calculado no estagio EX
//   ALUOp=2'b11 : I-arith; pl_alu_ctrl decodifica via Funct3 (sem Funct7[5])
// =============================================================================

`timescale 1ns / 1ps

module pl_control (
    input  logic [6:0] Opcode,
    output logic       ALUSrc,
    output logic       ALUSrcPC,    // 1 = SrcA e PC (AUIPC)
    output logic [1:0] MemtoReg,    // 00=ALU 01=mem 10=PC+4
    output logic       RegWrite,
    output logic       MemRead,
    output logic       MemWrite,
    output logic       Branch,
    output logic       Jump,        // JAL / JALR
    output logic [1:0] ALUOp
);

    localparam R_TYPE  = 7'b0110011;
    localparam I_ARITH = 7'b0010011;
    localparam LOAD    = 7'b0000011;
    localparam STORE   = 7'b0100011;
    localparam BRANCH  = 7'b1100011;
    localparam LUI     = 7'b0110111;
    localparam AUIPC   = 7'b0010111;
    localparam JAL     = 7'b1101111;
    localparam JALR    = 7'b1100111;

    always_comb begin
        // Valores padrao (instrucao desconhecida ou NOP)
        ALUSrc   = 1'b0;
        ALUSrcPC = 1'b0;
        MemtoReg = 2'b00;
        RegWrite = 1'b0;
        MemRead  = 1'b0;
        MemWrite = 1'b0;
        Branch   = 1'b0;
        Jump     = 1'b0;
        ALUOp    = 2'b00;

        case (Opcode)
            R_TYPE: begin
                ALUSrc   = 1'b0;
                MemtoReg = 2'b00;
                RegWrite = 1'b1;
                ALUOp    = 2'b10;
            end

            I_ARITH: begin
                ALUSrc   = 1'b1;
                MemtoReg = 2'b00;
                RegWrite = 1'b1;
                ALUOp    = 2'b11;   // decodifica por Funct3 em pl_alu_ctrl
            end

            LOAD: begin
                ALUSrc   = 1'b1;
                MemtoReg = 2'b01;
                RegWrite = 1'b1;
                MemRead  = 1'b1;
                ALUOp    = 2'b00;
            end

            STORE: begin
                ALUSrc   = 1'b1;
                MemWrite = 1'b1;
                ALUOp    = 2'b00;
            end

            BRANCH: begin
                Branch   = 1'b1;
                ALUOp    = 2'b01;   // pl_alu_ctrl gera SUB; pl_datapath avalia
            end

            LUI: begin
                // ALU opera ADD de 0 + imm; SrcA=0 e imm ja tem os 20 bits
                // em [31:12] apos sign_ext; resultado vai para rd
                ALUSrc   = 1'b1;
                MemtoReg = 2'b00;
                RegWrite = 1'b1;
                ALUOp    = 2'b00;   // ADD; SrcA=x0 (rs1=0 por convencao LUI)
            end

            AUIPC: begin
                ALUSrc   = 1'b1;
                ALUSrcPC = 1'b1;    // SrcA = PC (em vez de registrador)
                MemtoReg = 2'b00;
                RegWrite = 1'b1;
                ALUOp    = 2'b00;   // ADD: PC + (imm << 12)
            end

            JAL: begin
                // target = PC + imm (J-type); rd = PC+4
                // ALU calcula PC+imm; Jump faz o salto; MemtoReg=10 escreve PC+4
                ALUSrcPC = 1'b1;    // SrcA = PC
                ALUSrc   = 1'b1;    // SrcB = imm
                MemtoReg = 2'b10;
                RegWrite = 1'b1;
                Jump     = 1'b1;
                ALUOp    = 2'b00;   // ADD: PC + imm
            end

            JALR: begin
                // target = (rs1 + imm) & ~1; rd = PC+4
                ALUSrc   = 1'b1;    // SrcB = imm
                MemtoReg = 2'b10;
                RegWrite = 1'b1;
                Jump     = 1'b1;
                ALUOp    = 2'b00;   // ADD: rs1 + imm
            end

            default: ;  // sinais permanecem em zero (seguro)
        endcase
    end

endmodule
