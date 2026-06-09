module control_unit (
    input [17:0] sw,           // Os 18 switches da placa DE2-115
    output reg [2:0] opcode,   // Opcode de 3 bits enviado para a ALU e LCD
    output reg [3:0] dst_reg,  // Registrador de Destino (4 bits)
    output reg [3:0] src1,     // Registrador Fonte 1
    output reg [3:0] src2,     // Registrador Fonte 2
    output reg signed [15:0] immediate, // Valor imediato corrigido com extensão de sinal
    output reg we,             // Write Enable para a memória
    output reg clear_reg       // Sinal especial para a instrução CLEAR
);

    always @(*) begin
        // Valores padrão (Default) para evitar a criação de Latches indesejados
        opcode    = 3'b000;
        dst_reg   = 4'd0;
        src1      = 4'd0;
        src2      = 4'd0;
        immediate = 16'd0;
        we        = 1'b0;
        clear_reg = 1'b0;

        // ====================================================================
        // 1. TIPO 2: Operações com Imediatos (ADDI=010, SUBI=100, MUL=101)
        // Mapeamento exato: [17:15] Opcode, [14:11] Dest, [10:7] Src1, [6] Sinal, [5:0] Imm
        // ====================================================================
        if (sw[17:15] == 3'b010 || sw[17:15] == 3'b100 || sw[17:15] == 3'b101) begin
            opcode  = sw[17:15];
            dst_reg = sw[14:11];
            src1    = sw[10:7];
            we      = 1'b1;
            
            // Extensão de sinal segura usando casting $signed para evitar erros de zero-extend
            if (sw[6] == 1'b1) 
                immediate = - $signed({10'd0, sw[5:0]});
            else 
                immediate = $signed({10'd0, sw[5:0]});
        end

        // ====================================================================
        // 2. TIPO 1: Operações Reg x Reg (ADD=001, SUB=011)
        // Mapeamento: [14:12] Opcode, [11:8] Dest, [7:4] Src1, [3:0] Src2
        // ====================================================================
        else if (sw[14:12] == 3'b001 || sw[14:12] == 3'b011) begin
            opcode  = sw[14:12];
            dst_reg = sw[11:8];
            src1    = sw[7:4];
            src2    = sw[3:0];
            we      = 1'b1;
        end

        // ====================================================================
        // 3. TIPO ESPECIAL: Controle (CLEAR=110, DISPLAY=111)
        // Mapeamento corrigido para 3 bits [7:5] para evitar conflito de tamanho
        // ====================================================================
        else if (sw[7:5] == 3'b110 || sw[7:5] == 3'b111) begin
            opcode = sw[7:5];
            if (opcode == 3'b111) begin // DISPLAY
                src1    = sw[3:0];
                dst_reg = sw[3:0]; // Passamos para o LCD saber qual o registrador ativo entre []
            end else begin              // CLEAR
                clear_reg = 1'b1;
            end
        end

        // ====================================================================
        // 4. TIPO 3: Operação de Carga (LOAD=000)
        // Mapeamento: [13:11] Opcode, [10:7] Dest, [6] Sinal, [5:0] Imediato
        // ====================================================================
        else if (sw[13:11] == 3'b000) begin
            opcode  = 3'b000;
            dst_reg = sw[10:7];
            we      = 1'b1;
            
            if (sw[6] == 1'b1)
                immediate = - $signed({10'd0, sw[5:0]});
            else
                immediate = $signed({10'd0, sw[5:0]});
        end
    end
endmodule
