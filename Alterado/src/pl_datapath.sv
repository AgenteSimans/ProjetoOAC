// =============================================================================
// pl_datapath.sv
// Datapath pipeline de 5 estagios -- RV32I (P&H secoes 4.6-4.10)
//
// Estagios:
//   IF  -- busca instrucao (pl_imem, PC)
//   ID  -- decodificacao, leitura de registradores, deteccao de hazard
//   EX  -- execucao (ALU), resolucao de branch, forwarding
//   MEM -- acesso a memoria de dados / MMIO
//   WB  -- escrita no banco de registradores
//
// Tratamento de hazards:
//   Load-use stall : 1 ciclo de bolha (pl_hazard)
//   RAW data       : forwarding EX/MEM -> EX e MEM/WB -> EX (pl_forward)
//   Branch taken   : flush de IF e ID (2 NOPs) na resolucao em EX
//
// Decodificacao de endereco (estagio MEM):
//   alu_result[10] = 0 -> memoria de dados  (0x000-0x3FF)
//   alu_result[10] = 1 -> MMIO              (0x400-0x7FF)
//     alu_result[4:2] seleciona periferico dentro da janela MMIO
// =============================================================================

`timescale 1ns / 1ps

import pl_pipe_pkg::*;

module pl_datapath (
    input  logic        clk,
    input  logic        rst_n,

    // Sinais de controle vindos do estagio ID (pl_control)
    input  logic        ALUSrc,
    input  logic        MemtoReg,
    input  logic        RegWrite,
    input  logic        MemRead,
    input  logic        MemWrite,
    input  logic        Branch,
    input  logic [2:0]  ALUOp,

    // Codigo de operacao da ALU (pl_alu_ctrl, usa campos do estagio EX)
    input  logic [3:0]  ALU_CC,

    // Campos realimentados ao pl_cpu para controle e ALU ctrl
    output logic [6:0]  Opcode,       // opcode do estagio ID (para pl_control)
    output logic [2:0]  Funct3_EX,    // funct3 do estagio EX (para pl_alu_ctrl)
    output logic [6:0]  Funct7_EX,    // funct7 do estagio EX (para pl_alu_ctrl)
    output logic [2:0]  ALUOp_EX,     // ALUOp do estagio EX  (para pl_alu_ctrl)

    output logic [31:0] PC,           // PC atual (testbench / debug)

    // E/S Mapeada em Memoria -- DE2-115
    input  logic [17:0] SW,
    input  logic [3:0]  KEY,
    output logic [17:0] LEDR,
    output logic [8:0]  LEDG,
    output logic        UART_TXD,
    input  logic        UART_RXD,

    // Observabilidade para o testbench
    output logic        wb_reg_write,   // pulso quando WB escreve registrador
    output logic [4:0]  wb_reg_dst,     // registrador destino (WB)
    output logic [31:0] wb_reg_data,    // dado escrito (WB)
    output logic        mem_wr_en,      // escrita na dmem (nao MMIO)
    output logic [7:0]  mem_wr_addr,    // endereco de palavra da dmem (MEM)
    output logic [31:0] mem_wr_data     // dado escrito na dmem (MEM)
);

    // =========================================================================
    // Sinais internos
    // =========================================================================

    // PC
    logic [31:0] pc_reg, pc_plus4;

    // Registradores de pipeline
    if_id_t  if_id;
    id_ex_t  id_ex;
    ex_mem_t ex_mem;
    mem_wb_t mem_wb;

    // Hazard / branch
    logic        stall;
    logic        pc_src;
    logic [31:0] branch_target;

    // ID
    logic [31:0] rd1, rd2, imm_ext;

    // EX -- forwarding
    logic [1:0]  fwd_a, fwd_b;
    logic [31:0] fwd_srca, fwd_srcb, alu_srcb;
    logic [31:0] alu_result;
    logic        zero;

    // WB
    logic [31:0] wb_data;

    // MEM
    logic        mmio_sel;
    logic [31:0] dmem_rd, mmio_rd, mem_read_data;

    // =========================================================================
    // IF -- Busca de instrucao
    // =========================================================================
    logic [31:0] instr_if;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)      pc_reg <= 32'b0;
        else if (pc_src) pc_reg <= branch_target;   // branch tem prioridade
        else if (!stall) pc_reg <= pc_plus4;
        // else stall: PC mantido
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
        if (!rst_n) begin                    // reset assicrono (unico sinal na lista)
            if_id.pc    <= 32'b0;
            if_id.instr <= 32'b0;
        end else if (pc_src) begin           // flush sincrono: branch taken
            if_id.pc    <= 32'b0;
            if_id.instr <= 32'b0;
        end else if (!stall) begin           // avanco normal
            if_id.pc    <= pc_reg;
            if_id.instr <= instr_if;
        end
        // else stall: mantido
    end

    // =========================================================================
    // ID -- Decodificacao, banco de registradores, imediato, hazard
    // =========================================================================
    assign Opcode = if_id.instr[6:0];

    // Deteccao de hazard load-use
    pl_hazard hazard (
        .if_id_rs1      (if_id.instr[19:15]),
        .if_id_rs2      (if_id.instr[24:20]),
        .id_ex_rd       (id_ex.rd),
        .id_ex_mem_read (id_ex.mem_read),
        .stall          (stall)
    );

    // Dado de write-back (mux WB): usado tambem pelo forwarding MEM/WB->EX
    assign wb_data = mem_wb.mem_to_reg ? mem_wb.read_data : mem_wb.alu_result;

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

    // Saidas para o testbench (estagio WB)
    assign wb_reg_write = mem_wb.reg_write;
    assign wb_reg_dst   = mem_wb.rd;
    assign wb_reg_data  = wb_data;

    // =========================================================================
    // Registrador ID/EX
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin                      // reset assicrono (unico sinal na lista)
            id_ex.alu_src    <= 1'b0;
            id_ex.mem_to_reg <= 1'b0;
            id_ex.reg_write  <= 1'b0;
            id_ex.mem_read   <= 1'b0;
            id_ex.mem_write  <= 1'b0;
            id_ex.alu_op     <= 2'b00;
            id_ex.branch     <= 1'b0;
            id_ex.pc         <= 32'b0;
            id_ex.rd1        <= 32'b0;
            id_ex.rd2        <= 32'b0;
            id_ex.rs1        <= 5'b0;
            id_ex.rs2        <= 5'b0;
            id_ex.rd         <= 5'b0;
            id_ex.imm_ext    <= 32'b0;
            id_ex.funct3     <= 3'b0;
            id_ex.funct7     <= 7'b0;
        end else if (stall || pc_src) begin    // NOP sincrono: load-use ou branch
            id_ex.alu_src    <= 1'b0;
            id_ex.mem_to_reg <= 1'b0;
            id_ex.reg_write  <= 1'b0;
            id_ex.mem_read   <= 1'b0;
            id_ex.mem_write  <= 1'b0;
            id_ex.alu_op     <= 3'b000;
            id_ex.branch     <= 1'b0;
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
            id_ex.mem_to_reg <= MemtoReg;
            id_ex.reg_write  <= RegWrite;
            id_ex.mem_read   <= MemRead;
            id_ex.mem_write  <= MemWrite;
            id_ex.alu_op     <= ALUOp;
            id_ex.branch     <= Branch;
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

    // Realimentacao para pl_alu_ctrl (usa campos do estagio EX)
    assign Funct3_EX = id_ex.funct3;
    assign Funct7_EX = id_ex.funct7;
    assign ALUOp_EX  = id_ex.alu_op;

    // =========================================================================
    // EX -- Forwarding, ALU, resolucao de branch
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

    // Mux de forwarding para SrcA
    always_comb begin
        case (fwd_a)
            2'b10:   fwd_srca = ex_mem.alu_result;
            2'b01:   fwd_srca = wb_data;
            default: fwd_srca = id_ex.rd1;
        endcase
    end

    // Mux de forwarding para SrcB (antes do mux ALUSrc)
    always_comb begin
        case (fwd_b)
            2'b10:   fwd_srcb = ex_mem.alu_result;
            2'b01:   fwd_srcb = wb_data;
            default: fwd_srcb = id_ex.rd2;
        endcase
    end

    logic [31:0] alu_srca;
    always_comb begin
        case (id_ex.alu_op)
            3'b100:  alu_srca = 32'b0;       // LUI: força 0
            3'b101:  alu_srca = id_ex.pc;    // AUIPC: PC
            3'b110, 3'b111: alu_srca = id_ex.pc; // JAL, JALR: Usa PC para calcular PC+4  
            default: alu_srca = fwd_srca;    
        endcase
    end
    // Mux ALUSrc: imediato ou registrador
    //assign alu_srcb = id_ex.alu_src ? id_ex.imm_ext : fwd_srcb;
    always_comb begin
        case (id_ex.alu_op)
            3'b110, 3'b111: alu_srcb = 32'd4; // JAL, JALR: Usa +4 constante
            default: alu_srcb = id_ex.alu_src ? id_ex.imm_ext : fwd_srcb; // Comportamento original
        endcase
    end

    pl_alu alu (
        .SrcA      (alu_srca),
        .SrcB      (alu_srcb),
        .Operation (ALU_CC),
        .ALUResult (alu_result),
        .Zero      (zero)
    );

    // --- CÁLCULO DO ALVO DE SALTO (BRANCH / JAL / JALR) ---
    always_comb begin
        if (id_ex.alu_op == 3'b111) // JALR
            branch_target = (fwd_srca + id_ex.imm_ext) & 32'hFFFFFFFE; 
        else
            // Branch normal ou JAL 
            branch_target = id_ex.pc + id_ex.imm_ext;
    end

    // --- GATILHO PARA ALTERAR O PC (FLUSH/PULO) ---
    logic is_jump;
    assign is_jump = (id_ex.alu_op == 3'b110) || (id_ex.alu_op == 3'b111);
    
    assign pc_src = is_jump || (id_ex.branch && branch_condition);

    // Branch resolvido no estagio EX (flush 2 instrucoes se taken)
    //assign branch_target = id_ex.pc + id_ex.imm_ext;
    //assign pc_src        = id_ex.branch && zero;

    // --- LÓGICA DE AVALIAÇÃO DE CONDIÇÃO DE SALTO (BEQ, BNE, BLT, BGE, BLTU, BGEU) ---
    logic branch_condition;

    always_comb begin
        case (id_ex.funct3)
            3'b000:  branch_condition = (fwd_srca == fwd_srcb);                      // BEQ
            3'b001:  branch_condition = (fwd_srca != fwd_srcb);                      // BNE
            3'b100:  branch_condition = ($signed(fwd_srca) < $signed(fwd_srcb));     // BLT  (com sinal)
            3'b101:  branch_condition = ($signed(fwd_srca) >= $signed(fwd_srcb));    // BGE  (com sinal)
            3'b110:  branch_condition = ($unsigned(fwd_srca) < $unsigned(fwd_srcb));   // BLTU (sem sinal)
            3'b111:  branch_condition = ($unsigned(fwd_srca) >= $unsigned(fwd_srcb));  // BGEU sem sinal)
            default: branch_condition = 1'b0;
        endcase
    end

   
    //assign pc_src = id_ex.branch && branch_condition;

    // =========================================================================
    // Registrador EX/MEM
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_mem.mem_to_reg  <= 1'b0;
            ex_mem.reg_write   <= 1'b0;
            ex_mem.mem_read    <= 1'b0;
            ex_mem.mem_write   <= 1'b0;
            ex_mem.alu_result  <= 32'b0;
            ex_mem.write_data  <= 32'b0;
            ex_mem.rd          <= 5'b0;
            ex_mem.funct3      <= 3'b0;
        end else begin
            ex_mem.mem_to_reg  <= id_ex.mem_to_reg;
            ex_mem.reg_write   <= id_ex.reg_write;
            ex_mem.mem_read    <= id_ex.mem_read;
            ex_mem.mem_write   <= id_ex.mem_write;
            ex_mem.alu_result  <= alu_result;
            ex_mem.write_data  <= fwd_srcb;   // rs2 adiantado (para SW/MMIO)
            ex_mem.rd          <= id_ex.rd;
            ex_mem.funct3      <= id_ex.funct3;
        end
    end

    // =========================================================================
    // MEM -- Memoria de dados + MMIO
    // =========================================================================
    assign mmio_sel = ex_mem.alu_result[10];

    pl_dmem dmem (
        .clk       (clk),
        .MemWrite  (ex_mem.mem_write & ~mmio_sel),
        .addr      (ex_mem.alu_result[9:2]),
        .WriteData (mem_write_data_formatted),
        .ReadData  (dmem_rd)
    );

    pl_mmio mmio (
        .clk       (clk),
        .rst_n     (rst_n),
        .MemWrite  (ex_mem.mem_write &  mmio_sel),
        .MemRead   (ex_mem.mem_read  &  mmio_sel),
        .addr      (ex_mem.alu_result[4:2]),
        .WriteData (mem_write_data_formatted),
        .SW        (SW),
        .KEY       (KEY),
        .ReadData  (mmio_rd),
        .LEDR      (LEDR),
        .LEDG      (LEDG),
        .UART_TXD  (UART_TXD),
        .UART_RXD  (UART_RXD)
    );

    //assign mem_read_data = mmio_sel ? mmio_rd : dmem_rd;
    // Mudamos o nome da leitura bruta da memória para evitar conflito
    logic [31:0] mem_read_data_raw;
    assign mem_read_data_raw = mmio_sel ? mmio_rd : dmem_rd;

    // --- LÓGICA DE ALINHAMENTO PARA STORES (SB, SH, SW) ---
    logic [31:0] mem_write_data_formatted;

    always_comb begin
        if (ex_mem.mem_write) begin
            case (ex_mem.funct3)
                3'b000: begin // SB (Store Byte)
                    case (ex_mem.alu_result[1:0])
                        2'b00: mem_write_data_formatted = {mem_read_data_raw[31:8], ex_mem.write_data[7:0]};
                        2'b01: mem_write_data_formatted = {mem_read_data_raw[31:16], ex_mem.write_data[7:0], mem_read_data_raw[7:0]};
                        2'b10: mem_write_data_formatted = {mem_read_data_raw[31:24], ex_mem.write_data[7:0], mem_read_data_raw[15:0]};
                        2'b11: mem_write_data_formatted = {ex_mem.write_data[7:0], mem_read_data_raw[23:0]};
                    endcase
                end
                3'b001: begin // SH (Store Halfword)
                    case (ex_mem.alu_result[1])
                        1'b0: mem_write_data_formatted = {mem_read_data_raw[31:16], ex_mem.write_data[15:0]};
                        1'b1: mem_write_data_formatted = {ex_mem.write_data[15:0], mem_read_data_raw[15:0]};
                    endcase
                end
                default: mem_write_data_formatted = ex_mem.write_data; // SW (Store Word - 3'b010)
            endcase
        end else begin
            mem_write_data_formatted = ex_mem.write_data;
        end
    end

    // --- LÓGICA DE ALINHAMENTO E EXTENSÃO PARA LOADS (LB, LH, LW, LBU, LHU) ---
    logic [31:0] mem_read_data_formatted;
    logic [7:0]  byte_data;
    logic [15:0] half_data;

    
    always_comb begin
        case (ex_mem.alu_result[1:0])
            2'b00: byte_data = mem_read_data_raw[7:0];
            2'b01: byte_data = mem_read_data_raw[15:8];
            2'b10: byte_data = mem_read_data_raw[23:16];
            2'b11: byte_data = mem_read_data_raw[31:24];
        endcase
    end

    always_comb begin
        case (ex_mem.alu_result[1])
            1'b0: half_data = mem_read_data_raw[15:0];
            1'b1: half_data = mem_read_data_raw[31:16];
        endcase
    end

    // 3. Seleção final e extensão de sinal/zero baseada no funct3
    always_comb begin
        if (ex_mem.mem_read) begin
            case (ex_mem.funct3)
                3'b000: mem_read_data_formatted = {{24{byte_data[7]}}, byte_data};  // LB  (extensão de sinal)
                3'b001: mem_read_data_formatted = {{16{half_data[15]}}, half_data}; // LH  (extensão de sinal)
                3'b010: mem_read_data_formatted = mem_read_data_raw;                // LW  (palavra inteira)
                3'b100: mem_read_data_formatted = {24'b0, byte_data};               // LBU (extensão de zero)
                3'b101: mem_read_data_formatted = {16'b0, half_data};               // LHU (extensão de zero)
                default: mem_read_data_formatted = mem_read_data_raw;               // Segurança
            endcase
        end else begin
            mem_read_data_formatted = mem_read_data_raw; // Ignora se não for load
        end
    end

    // Saidas de observabilidade para o testbench
    assign mem_wr_en   = ex_mem.mem_write & ~mmio_sel;
    assign mem_wr_addr = ex_mem.alu_result[9:2];
    assign mem_wr_data = mem_write_data_formatted;

    // =========================================================================
    // Registrador MEM/WB
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_wb.mem_to_reg <= 1'b0;
            mem_wb.reg_write  <= 1'b0;
            mem_wb.alu_result <= 32'b0;
            mem_wb.read_data  <= 32'b0;
            mem_wb.rd         <= 5'b0;
        end else begin
            mem_wb.mem_to_reg <= ex_mem.mem_to_reg;
            mem_wb.reg_write  <= ex_mem.reg_write;
            mem_wb.alu_result <= ex_mem.alu_result;
            //mem_wb.read_data  <= mem_read_data;
            mem_wb.read_data  <= mem_read_data_formatted;
            mem_wb.rd         <= ex_mem.rd;
        end
    end

    // WB: wb_data = mem_to_reg ? read_data : alu_result  (definido acima, no bloco ID)

endmodule
