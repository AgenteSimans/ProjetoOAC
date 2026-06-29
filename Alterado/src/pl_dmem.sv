// =============================================================================
// pl_dmem.sv
// Memoria de dados -- RV32I pipelined
//
// Capacidade : 256 palavras x 32 bits = 1 KB
// Init file  : data.mif   (sintese Quartus)
//              data.hex   (simulacao ModelSim via $readmemh)
//
// Leitura  : assincrona (combinatorial) -- disponivel no estagio MEM
// Escrita  : sincrona (posedge clk, gated por byte enables)
// Endereco : alu_result[9:2]  (endereco de palavra de 8 bits)
//
// Suporte a acesso parcial (byte e halfword):
//   ByteEn[3:0] : mask de bytes habilitados para escrita
//     4'b1111 = SW  (palavra completa)
//     4'b0011 = SH  (halfword baixa, offset 0 ou 2 via ByteOffset)
//     4'b1100 = SH  (halfword alta)
//     4'b0001 = SB  (byte 0)  ...  4'b1000 = SB (byte 3)
//
// A extensao de sinal de leituras parciais (LB/LH/LBU/LHU) e feita no
// estagio WB do datapath, pois Funct3 esta disponivel no registrador MEM/WB.
//
// Para leituras parciais, ReadData retorna a palavra completa; o datapath
// extrai e estende o campo correto usando alu_result[1:0] e funct3.
// =============================================================================

`timescale 1ns / 1ps

module pl_dmem (
    input  logic        clk,
    input  logic        MemWrite,
    input  logic [3:0]  ByteEn,        // byte enables para SW/SH/SB
    input  logic [7:0]  addr,          // endereco de palavra: alu_result[9:2]
    input  logic [31:0] WriteData,     // dado alinhado em palavra
    output logic [31:0] ReadData       // palavra completa; datapath faz extensao
);

    (* ram_init_file = "data.mif" *) logic [31:0] ram [0:255];

    // synthesis translate_off
    initial begin
        for (int i = 0; i < 256; i++) ram[i] = 32'h00000000;
        $readmemh("data.hex", ram);
    end
    // synthesis translate_on

    // Escrita com byte enables (suporta SW, SH, SB)
    always_ff @(posedge clk) begin
        if (MemWrite) begin
            if (ByteEn[0]) ram[addr][7:0]   <= WriteData[7:0];
            if (ByteEn[1]) ram[addr][15:8]  <= WriteData[15:8];
            if (ByteEn[2]) ram[addr][23:16] <= WriteData[23:16];
            if (ByteEn[3]) ram[addr][31:24] <= WriteData[31:24];
        end
    end

    assign ReadData = ram[addr];

endmodule
