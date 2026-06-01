// =============================================================================
// pl_alu_ctrl.sv
// Unidade de Controle da ALU -- RV32I pipelined (P&H secao 4.4)
//
// Entradas (do estagio EX -- registrador ID/EX):
//   ALUOp[1:0] : codigo do controlador principal
//     2'b00 : Load/Store  -> forcar ADD
//     2'b01 : Branch BEQ  -> forcar SUB
//     2'b10 : R-type      -> decodificar via Funct3/Funct7
//   Funct7[6:0], Funct3[2:0] : campos da instrucao
//
// Saida Operation[3:0] -> pl_alu.sv:
//   4'd01 ADD  4'd02 SUB  4'd04 OR  4'd05 AND  4'd11 SLT
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
            2'b00: begin                // I-type
                case (Funct3)
                    3'h2: Operation = 4'd01; // Load/Store -> ADD

                    default: Operation = 4'd01;
                endcase
            end

            2'b01: Operation = 4'd02;   // Branch BEQ  -> SUB

            2'b10: begin                // R-type: decodificar Funct
                case (Funct3)
                    3'h0: Operation = Funct7[5] ? 4'd02 : 4'd01; // SUB ou ADD
                    3'h6: Operation = 4'd04;  // OR
                    3'h7: Operation = 4'd05;  // AND
                    3'h2: Operation = 4'd11;  // SLT
                    3'h1: Operation = 4'd07; // sll (funct7 vai no 0x00,logo nadinha)
                    3'h5: Operation = Funct7[5] ? 4'd09 : 4'd08; // SRA ou o SRL depende de um bit do func7
                    3'h4: Operation = 4'd06;  // XOR 
                    3'h3: Operation = 4'd10;  // SLTU

                    default: Operation = 4'd01;
                endcase
            end
            
            2'b11 begin
                case (Funct3)
                    3'h0: Operation = 4'd01; //ADDI -> ADD
                    3'h1: Operation = 4'd07; //SLLI -> SLL
                    3'h2: Operation = 4'd11; //SLTI -> SLT
                    3'h3: Operation = 4'd10; //SLTIU -> SLTU
                    3'h4: Operation = 4'd06; //XORI -> XOR
                    3'h5: Operation = Funct7[5] ? 4'd09 : 4'd08; // SRAI ou SRLI
                    3'h6: Operation = 4'd04; // ORI -> OR
                    3'h7: Operation = 4'd05; // ANDI -> AND

                    default: Operation = 4'd01;
                endcase
            end 


            2'b11: begin                // I-type
                case (Funct3)
                    3'h0: Operation = 4'd01; // ADDI  -> ADD
                    3'h6: Operation = 4'd04; // ORI   -> OR
                    3'h7: Operation = 4'd05; // ANDI  -> AND
                    3'h2: Operation = 4'd11; // SLTI  -> SLT

                    default: Operation = 4'd01;
                endcase
            end

            default: Operation = 4'd01;
        endcase
    end

endmodule
