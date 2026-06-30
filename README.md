# Relatório do Projeto de AOC

## Etapa 1

### Instruções Implementadas
- **Aritmética, lógica e deslocamentos (R-type)**
  - XOR, SLL, SRL, SRA, SLTU
- **Aritmética, lógica e deslocamentos com valores imediatos (I-type)**
  - ADDI, ANDI, ORI, SLTI, SLLI, SRLI, SRAI

---

### Divisão de Tarefas

| Integrante       | Instruções Atribuídas                  |
|------------------|----------------------------------------|
| Eduardo Lucas    | SLL, SRL, SRA                          |
| Gabriel Vieira   | XOR, ADDI, SLTU                        |
| Guilherme Vitor  | ANDI, ORI, SLTI                        |
| Jose Lucas       | SLLI, SRLI, SRAI                       |

---

### Problemas e Soluções

- **Problema:** Houve um erro no comportamento dos deslocamentos.
- **Solução:** Após analisar o fluxo de dados, identificou-se que o ADDI estava influenciando o deslocamento no arquivo `.mif` de teste. Isso ocorria porque a lógica de deslocamento não separava corretamente o conteúdo das outras variáveis, ficando vulnerável a "lixo" (dados residuais). O integrante Gabriel Vieira percebeu a causa raiz e corrigiu o ADDI, resolvendo o problema.

---

## Etapa 2

### Instruções Implementadas
- **Acesso à memória (I-type load e S-type)**
  - LB, LH, LBU, LHU
  - SB, SH
- **Desvios e jumps (B-type e J-type)**
  - BNE, BLT, BGE, BLTU, BGEU
  - JAL, JALR
- **Imediato superior (U-type)**
  - LUI, AUIPC

---

### Divisão de Tarefas

| Integrante       | Instruções Atribuídas                               |
|------------------|-----------------------------------------------------|
| Eduardo Lucas    | BNE, BLT, BGE, BLTU                                 |
| Gabriel Vieira   | JAL, JALR, LUI, BLTU                                |
| Guilherme Vitor  | SB, SH, BGEU                                        |
| Jose Lucas       | LB, LH, LBU, LHU                                    |

---

### Problemas e Soluções

*(Nenhum problema registrado até o momento.)*
