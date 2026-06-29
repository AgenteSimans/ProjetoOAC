// =============================================================================
// pl_alu.sv
// Unidade Logica e Aritmetica de 32 bits -- RV32I pipelined
//
// Codificacao de operacao (Operation[3:0]):
//   4'd01 : ADD   -- adicao (com ou sem sinal; resultado identico em 2C)
//   4'd02 : SUB   -- subtracao (BEQ/BNE/BLT/BGE/BLTU/BGEU usam Zero/Result)
//   4'd03 : XOR   -- XOR bit a bit
//   4'd04 : OR    -- OR bit a bit
//   4'd05 : AND   -- AND bit a bit
//   4'd06 : SLL   -- shift left logical  (shamt = SrcB[4:0])
//   4'd07 : SRL   -- shift right logical (shamt = SrcB[4:0])
//   4'd08 : SRA   -- shift right aritmetico com sinal (shamt = SrcB[4:0])
//   4'd09 : SLTU  -- set-less-than sem sinal
//   4'd10 : PASSB -- passa SrcB diretamente (LUI: rd = imm << 12)
//   4'd11 : SLT   -- set-less-than com sinal
//
// Saidas:
//   ALUResult[31:0] : resultado da operacao
//   Zero            : 1 quando ALUResult == 0 (usado por BEQ)
//   Negative        : bit de sinal de ALUResult (usado por BLT/BGE)
//   Overflow        : overflow de adicao/subtracao com sinal (usado por SLT logico)
//   Carry           : carry-out da subtracao sem sinal (usado por BLTU/BGEU)
//
// Obs.: BEQ  -> Zero
//       BNE  -> ~Zero
//       BLT  -> Negative ^ Overflow  (equivalente a $signed(a) < $signed(b))
//       BGE  -> ~(Negative ^ Overflow)
//       BLTU -> ~Carry  (Carry=0 significa borrow, logo a < b sem sinal)
//       BGEU -> Carry
// =============================================================================

`timescale 1ns / 1ps

module pl_alu (
    input  logic [31:0] SrcA,
    input  logic [31:0] SrcB,
    input  logic [3:0]  Operation,
    output logic [31:0] ALUResult,
    output logic        Zero,
    output logic        Negative,
    output logic        Overflow,
    output logic        Carry
);

    logic [32:0] sub_ext;   // subtracao com carry-out para BLTU/BGEU

    always_comb begin
        sub_ext   = {1'b0, SrcA} - {1'b0, SrcB};

        case (Operation)
            4'd01:   ALUResult = SrcA + SrcB;
            4'd02:   ALUResult = sub_ext[31:0];
            4'd03:   ALUResult = SrcA ^ SrcB;
            4'd04:   ALUResult = SrcA | SrcB;
            4'd05:   ALUResult = SrcA & SrcB;
            4'd06:   ALUResult = SrcA << SrcB[4:0];
            4'd07:   ALUResult = SrcA >> SrcB[4:0];
            4'd08:   ALUResult = 32'($signed(SrcA) >>> SrcB[4:0]);
            4'd09:   ALUResult = 32'(SrcA < SrcB);                      // SLTU
            4'd10:   ALUResult = SrcB;                                   // PASSB (LUI)
            4'd11:   ALUResult = 32'($signed(SrcA) < $signed(SrcB));    // SLT
            default: ALUResult = 32'b0;
        endcase
    end

    assign Zero     = (ALUResult == 32'b0);
    assign Negative = ALUResult[31];

    // Overflow de adicao/subtracao com sinal:
    //   SUB: overflow quando sinais de SrcA e SrcB diferem e resultado
    //        tem sinal oposto ao de SrcA.
    //   ADD: overflow quando sinais de SrcA e SrcB iguais mas resultado
    //        tem sinal diferente.
    // Para BLT/BGE so SUB e usada, entao a logica abaixo e suficiente.
    assign Overflow = (Operation == 4'd02) ?
                      (~(SrcA[31] ^ SrcB[31]) == 1'b0 &&  // sinais distintos
                       (SrcA[31] ^ ALUResult[31]))      :  // resultado inverteu
                      (Operation == 4'd01) ?
                      (~(SrcA[31] ^ SrcB[31]) &&          // sinais iguais
                       (SrcA[31] ^ ALUResult[31]))      :  // resultado inverteu
                      1'b0;

    // Carry-out da subtracao sem sinal: sub_ext[32]=0 significa borrow (a<b)
    // BLTU: branch se a < b sem sinal, ou seja, se Carry == 0
    // BGEU: branch se a >= b sem sinal, ou seja, se Carry == 1
    assign Carry = (Operation == 4'd02) ? ~sub_ext[32] : 1'b0;
    // Nota: sub_ext[32]=0 => houve borrow (a<b), logo Carry=1 indica a>=b

endmodule
