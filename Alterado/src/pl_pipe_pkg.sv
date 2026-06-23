// =============================================================================
// pl_pipe_pkg.sv
// Definicoes dos registradores de pipeline -- processador RV32I pipelined
// =============================================================================

package pl_pipe_pkg;

    // ---- IF/ID --------------------------------------------------------------
    typedef struct packed {
        logic [31:0] pc;
        logic [31:0] instr;
    } if_id_t;

    // ---- ID/EX --------------------------------------------------------------
    typedef struct packed {
        // sinais de controle
        logic        alu_src;
        logic        mem_to_reg;
        logic        reg_write;
        logic        mem_read;
        logic        mem_write;
        logic [1:0]  alu_op;
        logic        branch;          // 1 = instrucao de branch (B-type)
        // dados
        logic [31:0] pc;
        logic [31:0] rd1;
        logic [31:0] rd2;
        logic [4:0]  rs1;
        logic [4:0]  rs2;
        logic [4:0]  rd;
        logic [31:0] imm_ext;
        logic [2:0]  funct3;          // para branches( BEQ=000, BNE=001, BLT=100, BGE=101, BLTU=110, BGEU=111)
        logic [6:0]  funct7;
    } id_ex_t;

    // ---- EX/MEM -------------------------------------------------------------
    typedef struct packed {
        logic        mem_to_reg;
        logic        reg_write;
        logic        mem_read;
        logic        mem_write;
        logic [31:0] alu_result;
        logic [31:0] write_data;
        logic [4:0]  rd;
        logic [2:0]  funct3;
    } ex_mem_t;

    // ---- MEM/WB -------------------------------------------------------------
    typedef struct packed {
        logic        mem_to_reg;
        logic        reg_write;
        logic [31:0] alu_result;
        logic [31:0] read_data;
        logic [4:0]  rd;
    } mem_wb_t;

endpackage