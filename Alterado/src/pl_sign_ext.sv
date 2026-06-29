// =============================================================================
// pl_sign_ext.sv
// Extensao de Sinal de Imediatos -- RV32I pipelined (P&H secao 4.4)
//
// Formatos suportados (P&H Fig 2.17):
//
//   I-type  (Load, JALR)    : imm[11:0]  = inst[31:20]
//   I-arith (ADDI...SRAI)   : mesmo encoding que I-type
//   S-type  (SW, SH, SB)    : imm[11:5] = inst[31:25], imm[4:0] = inst[11:7]
//   B-type  (BEQ ... BGEU)  : imm[12]=inst[31], imm[11]=inst[7],
//                              imm[10:5]=inst[30:25], imm[4:1]=inst[11:8],
//                              imm[0]=0
//   U-type  (LUI, AUIPC)    : imm[31:12] = inst[31:12], imm[11:0] = 0
//   J-type  (JAL)           : imm[20]=inst[31], imm[19:12]=inst[19:12],
//                              imm[11]=inst[20], imm[10:1]=inst[30:21],
//                              imm[0]=0
//
// Opcodes usados para selecionar formato:
//   I-load  7'b0000011   I-arith 7'b0010011   JALR  7'b1100111
//   S-type  7'b0100011
//   B-type  7'b1100011
//   LUI     7'b0110111   AUIPC   7'b0010111
//   JAL     7'b1101111
// =============================================================================

`timescale 1ns / 1ps

module pl_sign_ext (
    input  logic [31:0] Instr,
    output logic [31:0] ImmExt
);

    localparam I_LOAD  = 7'b0000011;
    localparam I_ARITH = 7'b0010011;
    localparam JALR    = 7'b1100111;
    localparam STORE   = 7'b0100011;
    localparam BRANCH  = 7'b1100011;
    localparam LUI     = 7'b0110111;
    localparam AUIPC   = 7'b0010111;
    localparam JAL     = 7'b1101111;

    always_comb begin
        case (Instr[6:0])

            // I-type: Load (LW, LH, LB, LHU, LBU) e JALR
            I_LOAD,
            JALR:    ImmExt = {{20{Instr[31]}}, Instr[31:20]};

            // I-type: Aritmetico/Logico (ADDI, ANDI, ORI, SLTI, XORI, SLLI, SRLI, SRAI)
            // Para shifts (SLLI/SRLI/SRAI), shamt = Instr[24:20]; extensao nao faz diferenca
            // pois a ALU usa apenas SrcB[4:0]
            I_ARITH: ImmExt = {{20{Instr[31]}}, Instr[31:20]};

            // S-type: Store (SW, SH, SB)
            STORE:   ImmExt = {{20{Instr[31]}}, Instr[31:25], Instr[11:7]};

            // B-type: Branch (BEQ, BNE, BLT, BGE, BLTU, BGEU)
            // Imediato representa offset em bytes (multiplo de 2); bit 0 sempre 0
            BRANCH:  ImmExt = {{19{Instr[31]}}, Instr[31], Instr[7],
                                Instr[30:25], Instr[11:8], 1'b0};

            // U-type: LUI e AUIPC
            // Imediato ocupa os 20 bits altos; 12 bits baixos = 0
            LUI,
            AUIPC:   ImmExt = {Instr[31:12], 12'b0};

            // J-type: JAL
            // Imediato de 21 bits com bit 0 = 0 (alinhamento de instrucao)
            JAL:     ImmExt = {{11{Instr[31]}}, Instr[31], Instr[19:12],
                                Instr[20], Instr[30:21], 1'b0};

            default: ImmExt = 32'b0;
        endcase
    end

endmodule
