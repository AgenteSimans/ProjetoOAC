// =============================================================================
// pl_alu_ctrl.sv
// Unidade de Controle da ALU -- RV32I pipelined (P&H secao 4.4)
//
// Entradas (do estagio EX -- registrador ID/EX):
//   ALUOp[1:0] : codigo do controlador principal
//     2'b00 : Load/Store/LUI/AUIPC/JAL/JALR -> forccar ADD
//     2'b01 : Branch -> forccar SUB (datapath avalia condicao via Funct3)
//     2'b10 : R-type -> decodificar via Funct3/Funct7
//     2'b11 : I-arith -> decodificar via Funct3 (Funct7 so em SRAI)
//   Funct7[6:0], Funct3[2:0] : campos da instrucao
//
// Saida Operation[3:0] -> pl_alu.sv:
//   4'd01 ADD    4'd02 SUB    4'd03 XOR
//   4'd04 OR     4'd05 AND    4'd06 SLL
//   4'd07 SRL    4'd08 SRA    4'd09 SLTU
//   4'd10 PASSB  4'd11 SLT
//
// Nota sobre PASSB (4'd10):
//   Usado por LUI: ALUResult = SrcB (imediato U-type).
//   O datapath conecta rs1=x0 como SrcA, portanto ADD tambem funcionaria,
//   mas PASSB deixa a intencao explicita e isola qualquer dependencia de SrcA.
// =============================================================================

`timescale 1ns / 1ps

module pl_alu_ctrl (
    input  logic [1:0] ALUOp,
    input  logic [6:0] Funct7,
    input  logic [2:0] Funct3,
    output logic [3:0] Operation
);

    always_comb begin
        case (ALUOp)
            // ------------------------------------------------------------------
            // 2'b00 : Load / Store / LUI / AUIPC / JAL / JALR -> ADD
            // ------------------------------------------------------------------
            2'b00: Operation = 4'd01;

            // ------------------------------------------------------------------
            // 2'b01 : Branch condicional -> SUB (Zero/resultado avaliado no EX)
            // ------------------------------------------------------------------
            2'b01: Operation = 4'd02;

            // ------------------------------------------------------------------
            // 2'b10 : R-type -- decodifica Funct3 + Funct7[5]
            // ------------------------------------------------------------------
            2'b10: begin
                case (Funct3)
                    3'h0: Operation = Funct7[5] ? 4'd02 : 4'd01; // SUB ou ADD
                    3'h4: Operation = 4'd03;  // XOR
                    3'h6: Operation = 4'd04;  // OR
                    3'h7: Operation = 4'd05;  // AND
                    3'h1: Operation = 4'd06;  // SLL
                    3'h5: Operation = Funct7[5] ? 4'd08 : 4'd07; // SRA ou SRL
                    3'h3: Operation = 4'd09;  // SLTU
                    3'h2: Operation = 4'd11;  // SLT
                    default: Operation = 4'd01;
                endcase
            end

            // ------------------------------------------------------------------
            // 2'b11 : I-arith -- decodifica Funct3; Funct7[5] so em SRAI
            // ------------------------------------------------------------------
            2'b11: begin
                case (Funct3)
                    3'h0: Operation = 4'd01;  // ADDI  -> ADD
                    3'h4: Operation = 4'd03;  // XORI  -> XOR
                    3'h6: Operation = 4'd04;  // ORI   -> OR
                    3'h7: Operation = 4'd05;  // ANDI  -> AND
                    3'h1: Operation = 4'd06;  // SLLI  -> SLL
                    3'h5: Operation = Funct7[5] ? 4'd08 : 4'd07; // SRAI ou SRLI
                    3'h3: Operation = 4'd09;  // SLTIU -> SLTU
                    3'h2: Operation = 4'd11;  // SLTI  -> SLT
                    default: Operation = 4'd01;
                endcase
            end

            default: Operation = 4'd01;
        endcase
    end

endmodule
