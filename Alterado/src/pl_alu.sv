// =============================================================================
// pl_alu.sv
// Unidade Logica e Aritmetica de 32 bits -- RV32I pipelined
//
// Codificacao de operacao (Operation[3:0]):
//   4'd01 : ADD  -- adicao com sinal
//   4'd02 : SUB  -- subtracao com sinal  (BEQ usa Zero)
//   4'd04 : OR   -- OU bit a bit
//   4'd05 : AND  -- E bit a bit
//   4'd06 : XOR  -- OU exclusivo bit a bit
//   4'd10 : SLTU -- set-less-than sem sinal
//   4'd11 : SLT  -- set-less-than com sinal
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
    output logic        CarryOut      // 1 = borrow na subtração
);

    //parte das Branchs
    logic [31:0] sub     = SrcA - SrcB;
    logic [32:0] sub_ext = {1'b0, SrcA} - {1'b0, SrcB};

    assign Zero     = (sub == 32'd0);
    assign Negative = sub[31];
    assign Overflow = (SrcA[31] != SrcB[31]) && (sub[31] != SrcA[31]);
    assign CarryOut = sub_ext[32];     // '1' se houve borrow (SrcA < SrcB)

    //o resto,se nao tiver ok,substituir com a main anterior para evitar extra dor de cabeca.
    always_comb begin
        case (Operation)
            4'd01:   ALUResult = SrcA + SrcB;                         // ADD
            4'd02:   ALUResult = sub;                                 // SUB
            4'd04:   ALUResult = SrcA | SrcB;                         // OR
            4'd05:   ALUResult = SrcA & SrcB;                         // AND
            4'd06:   ALUResult = SrcA ^ SrcB;                         // XOR
            4'd07:   ALUResult = SrcA << SrcB[4:0];                  // SLL
            4'd08:   ALUResult = SrcA >> SrcB[4:0];                  // SRL
            4'd09:   ALUResult = $signed(SrcA) >>> SrcB[4:0];       // SRA
            4'd10:   ALUResult = {31'd0, $unsigned(SrcA) < $unsigned(SrcB)}; // SLTU
            4'd11:   ALUResult = {31'd0, $signed(SrcA) < $signed(SrcB)};     // SLT
            default: ALUResult = 32'd0;
        endcase
    end

endmodule