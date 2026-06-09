module control_unit (
    input [17:0] sw,           // Os 18 switches da placa DE2-115
    output reg [2:0] opcode,   // Opcode de 3 bits UNIFICADO em sw[17:15]
    output reg [3:0] dst_reg,  // Registrador de Destino (Reg 1) -> sw[14:11]
    output reg [3:0] src1,     // Registrador Fonte 1 (Reg 2)    -> sw[10:7]
    output reg [3:0] src2,     // Registrador Fonte 2 (Reg 3)    -> sw[6:3]
    output reg signed [15:0] immediate, // Valor imediato com extensão de sinal segura
    output reg we,             // Write Enable para a memória
    output reg clear_reg       // Sinal especial para a instrução CLEAR
);

    always @(*) begin
        // Valores padrão (Default) para evitar a criação de Latches no Quartus
        opcode    = 3'b000;
        dst_reg   = 4'd0;
        src1      = 4'd0;
        src2      = 4'd0;
        immediate = 16'd0;
        we        = 1'b0;
        clear_reg = 1'b0;

        // O Opcode é extraído ESTRITAMENTE de uma única parte fixa
        opcode = sw[17:15];

        case (opcode)
            // ================================================================
            // TIPO 3: Operação de Carga (LOAD = 000)
            // ================================================================
            3'b000: begin
                dst_reg = sw[14:11]; // Mantém o alinhamento padrão do Reg 1
                we      = 1'b1;
                
                // Extensão de sinal do imediato de 6 bits (sw[5:0]) com base no sinal (sw[6])
                if (sw[6] == 1'b1) 
                    immediate = - $signed({10'd0, sw[5:0]});
                else 
                    immediate = $signed({10'd0, sw[5:0]});
            end

            // ================================================================
            // TIPO 1: Operações entre Registradores (ADD = 001, SUB = 011)
            // ================================================================
            3'b001, 
            3'b011: begin
                dst_reg = sw[14:11]; // Reg 1
                src1    = sw[10:7];  // Reg 2
                src2    = sw[6:3];   // Reg 3
                we      = 1'b1;
            end

            // ================================================================
            // TIPO 2: Operações com Imediatos (ADDI = 010, SUBI = 100, MUL = 101)
            // ================================================================
            3'b010, 
            3'b100, 
            3'b101: begin
                dst_reg = sw[14:11]; // Reg 1
                src1    = sw[10:7];  // Reg 2
                we      = 1'b1;
                
                // Extensão de sinal do imediato de 6 bits (sw[5:0]) com base no sinal (sw[6])
                if (sw[6] == 1'b1) 
                    immediate = - $signed({10'd0, sw[5:0]});
                else 
                    immediate = $signed({10'd0, sw[5:0]});
            end

            // ================================================================
            // TIPO ESPECIAL: Controle e Exibição (CLEAR = 110, DISPLAY = 111)
            // ================================================================
            3'b110: begin // CLEAR
                clear_reg = 1'b1;
            end

            3'b111: begin // DISPLAY
                src1    = sw[14:11]; // Lês o registrador a exibir a partir do campo padrão Reg 1
                dst_reg = sw[14:11]; // Passas também para o LCD identificar o alvo
            end

            default: begin
                // Estado seguro (instrução inválida ou não implementada)
            end
        endcase
    end
endmodule
