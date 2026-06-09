module control_unit (
    input clk,
    input rst,
    input [17:0] instruction,
    output reg [2:0] opcode,
    output reg [3:0] src1,
    output reg [3:0] src2,
    output reg [3:0] dst,
    output reg [15:0] imm_ext, // Nova saída para o imediato estendido
    output reg use_imm,        // Flag para avisar a ULA para usar o imediato
    output reg we
);

    always @(*) begin
        // Valores padrão
        we = 1'b0;
        use_imm = 1'b0;
        imm_ext = 16'd0;

        // 1º Passo: Checar se o topo bate com alguma instrução Tipo 2 (ex: ADDI=010, SUBI=100, MUL=101 nas posições 17:15)
        // OBS: Adapte os códigos binários exatos de 17:15 de acordo com a tabela do seu PDF!
        if (instruction[17:15] == 3'b010 || instruction[17:15] == 3'b100 || instruction[17:15] == 3'b101 || instruction[17:15] == 3'b000) begin
            // FORMATO TIPO 2 (Imediato)
            opcode  = instruction[17:15];
            dst     = instruction[14:11];
            src1    = instruction[10:7];
            src2    = 4'b0000; // Não usado
            use_imm = 1'b1;
            
            // Extensão de sinal do imediato de 6 bits (instruction[5:0]) usando o bit de sinal (instruction[6])
            if (instruction[6] == 1'b1)
                imm_ext = {10'b1111111111, instruction[5:0]}; // Negativo
            else
                imm_ext = {10'b0000000000, instruction[5:0]}; // Positivo
        end 
        else begin
            // FORMATO TIPO 1 (Reg x Reg)
            opcode  = instruction[14:12];
            dst     = instruction[11:9];
            src1    = instruction[8:6];
            src2    = instruction[5:3];
            use_imm = 1'b0;
        end

        // Controle da Escrita (WE)
        case(opcode)
            3'b000: we = 1'b1; // LOAD
            3'b001: we = 1'b1; // ADD
            3'b010: we = 1'b1; // ADDI
            3'b011: we = 1'b1; // SUB
            3'b100: we = 1'b1; // SUBI
            3'b101: we = 1'b1; // MUL
            default: we = 1'b0;
        endcase
    end
endmodule
