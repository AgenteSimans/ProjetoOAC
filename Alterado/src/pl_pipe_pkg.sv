// =============================================================================
// pl_pipe_pkg.sv
// Definicoes dos registradores de pipeline -- processador RV32I pipelined
//
// Quatro registradores de pipeline (P&H secao 4.6):
//   IF/ID  : resultado da busca de instrucao
//   ID/EX  : resultado da decodificacao + leitura do banco de registradores
//   EX/MEM : resultado da execucao (ALU)
//   MEM/WB : resultado do acesso a memoria
//
// Alteracoes em relacao a versao anterior:
//   id_ex_t  : adicionado alu_src_pc (AUIPC), jump, mem_to_reg[1:0]
//   ex_mem_t : adicionado jump, mem_to_reg[1:0], pc_plus4
//   mem_wb_t : adicionado mem_to_reg[1:0], pc_plus4, funct3
// =============================================================================

package pl_pipe_pkg;

    // ---- IF/ID --------------------------------------------------------------
    typedef struct packed {
        logic [31:0] pc;
        logic [31:0] instr;
    } if_id_t;

    // ---- ID/EX --------------------------------------------------------------
    typedef struct packed {
        // sinais de controle propagados para os estagios seguintes
        logic        alu_src;      // 0=reg, 1=imm (SrcB da ALU)
        logic        alu_src_pc;   // 1=SrcA da ALU e PC (AUIPC); 0=registrador
        logic [1:0]  mem_to_reg;   // 00=ALU, 01=mem, 10=PC+4 (JAL/JALR)
        logic        reg_write;
        logic        mem_read;
        logic        mem_write;
        logic [1:0]  alu_op;
        logic        branch;       // instrucao de branch condicional
        logic        jump;         // instrucao de salto incondicional (JAL/JALR)
        // dados
        logic [31:0] pc;
        logic [31:0] rd1;
        logic [31:0] rd2;
        logic [4:0]  rs1;
        logic [4:0]  rs2;
        logic [4:0]  rd;
        logic [31:0] imm_ext;
        logic [2:0]  funct3;
        logic [6:0]  funct7;
    } id_ex_t;

    // ---- EX/MEM -------------------------------------------------------------
    typedef struct packed {
        // sinais de controle
        logic [1:0]  mem_to_reg;   // 00=ALU, 01=mem, 10=PC+4
        logic        reg_write;
        logic        mem_read;
        logic        mem_write;
        logic        jump;
        // dados
        logic [31:0] alu_result;
        logic [31:0] write_data;   // rs2 apos forwarding (para SW/SH/SB)
        logic [31:0] pc_plus4;     // PC+4 salvo para JAL/JALR
        logic [4:0]  rd;
        logic [2:0]  funct3;       // para LB/LH/LBU/LHU/SB/SH no estagio MEM
    } ex_mem_t;

    // ---- MEM/WB -------------------------------------------------------------
    typedef struct packed {
        // sinais de controle
        logic [1:0]  mem_to_reg;   // 00=ALU, 01=mem, 10=PC+4
        logic        reg_write;
        // dados
        logic [31:0] alu_result;
        logic [31:0] read_data;    // dado lido da memoria (LW/LH/LB/LHU/LBU)
        logic [31:0] pc_plus4;     // para JAL/JALR
        logic [4:0]  rd;
        logic [2:0]  funct3;       // para extensao de sinal no WB (LB/LH/LBU/LHU)
    } mem_wb_t;

endpackage
