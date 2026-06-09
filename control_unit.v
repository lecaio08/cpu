module control_unit (
    input [17:0] sw,           // Os 18 switches da placa DE2-115
    output reg [2:0] opcode,   // Opcode padronizado enviado para a ALU e LCD
    output reg [3:0] dst_reg,  // Registrador de Destino
    output reg [3:0] src1,     // Registrador Fonte 1
    output reg [3:0] src2,     // Registrador Fonte 2
    output reg signed [15:0] immediate, // Valor imediato com extensão de sinal
    output reg we,             // Write Enable para a memória
    output reg clear_reg       // Sinal especial para a instrução CLEAR
);

    always @(*) begin
        // Valores padrão para evitar travas/latches
        opcode    = 3'b000;
        dst_reg   = 4'd0;
        src1      = 4'd0;
        src2      = 4'd0;
        immediate = 16'd0;
        we        = 1'b0;
        clear_reg = 1'b0;

        // --- DECODIFICAÇÃO DINÂMICA BASEADA NO DOCUMENTO DO CIn-UFPE ---

        // 1. Verifica se é TIPO 2 (Opcode nos switches [17:15])
        // Instruções: ADDI(010), SUBI(100), MUL(101)
        if (sw[17:15] == 3'b010 || sw[17:15] == 3'b100 || sw[17:15] == 3'b101) begin
            opcode  = sw[17:15];
            dst_reg = sw[14:11];
            src1    = sw[10:7];
            we      = 1'b1; // Essas operações escrevem no registrador de destino
            
            // Tratamento do Imediato com Sinal (sw[6] é o sinal, sw[5:0] é o módulo)
            if (sw[6] == 1'b1) 
                immediate = -{10'd0, sw[5:0]};
            else 
                immediate = {10'd0, sw[5:0]};
        end

        // 2. Verifica se é TIPO 3 (Opcode nos switches [13:11])
        // Instrução: LOAD(000) -> Nota: Garantimos que os switches superiores não conflitam
        else if (sw[13:11] == 3'b000 && sw[17:14] == 4'b0000) begin
            opcode  = 3'b000; // LOAD
            dst_reg = sw[10:7];
            we      = 1'b1;   // Escreve na memória
            
            if (sw[6] == 1'b1)
                immediate = -{10'd0, sw[5:0]};
            else
                immediate = {10'd0, sw[5:0]};
        end

        // 3. Verifica se é TIPO ESPECIAL (Opcode nos switches [7:4])
        // Instruções: CLEAR(110) ou DISPLAY(111)
        else if (sw[7:4] == 3'b110 || sw[7:4] == 3'b111) begin
            opcode = sw[7:4];
            if (opcode == 3'b111) begin
                src1    = sw[3:0];   // DISPLAY lê o registrador indicado em Src1
                dst_reg = sw[3:0];   // Passa para o LCD saber qual mostrar entre colchetes
            end else begin
                clear_reg = 1'b1;    // Ativa pulso de CLEAR para limpar a RAM
            end
        end

        // 4. Caso contrário, assume TIPO 1 por padrão (Opcode nos switches [14:12])
        // Instruções: ADD(001) ou SUB(011)
        else begin
            opcode  = sw[14:12];
            dst_reg = sw[11:8];
            src1    = sw[7:4];
            src2    = sw[3:0];
            // Só ativa escrita se o opcode mapeado for de fato ADD ou SUB válido
            if (sw[14:12] == 3'b001 || sw[14:12] == 3'b011)
                we = 1'b1;
        end
    end
endmodule
