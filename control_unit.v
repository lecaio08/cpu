module control_unit (
    input clk,
    input rst,                     // Reset global (Certifique-se de que é ativo em ALTO se usar posedge)
    input instructionPulse,        // Pulso do botão Enviar (vindo do debounce)
    input [17:0] sw,               // Switches da placa

    output reg [2:0] opcode,       // Código da instrução
    output reg [3:0] dst,          // Registrador de Destino
    output reg [3:0] src1,         // Registrador Fonte 1
    output reg [3:0] src2,         // Registrador Fonte 2
    output reg signed [15:0] immediate, // Valor Imediato com sinal
    output reg we,                 // Write Enable (Escrita na memória)
    output reg clear_reg,          // Sinal para limpar a memória
    output reg lcd_start           // Gatilho para atualizar o LCD
);

    // Definição dos Estados da FSM
    parameter S_IDLE    = 2'b00;
    parameter S_EXECUTE = 2'b01;
    parameter S_WRITE   = 2'b10;
    parameter S_UPDATE  = 2'b11;

    reg [1:0] state;
    reg [1:0] next_state;

    // -------------------------------------------------------------------------
    // PARTE COMBINACIONAL: Lógica para alteração de estados
    // -------------------------------------------------------------------------
    always @(*) begin
        case (state)
            S_IDLE: begin
                if (instructionPulse) 
                    next_state = S_EXECUTE;
                else 
                    next_state = S_IDLE;
            end
            
            S_EXECUTE: begin
                next_state = S_WRITE;
            end
            
            S_WRITE: begin
                next_state = S_UPDATE;
            end
            
            S_UPDATE: begin
                next_state = S_IDLE;
            end
            
            default: next_state = S_IDLE;
        endcase
    end

    // -------------------------------------------------------------------------
    // PARTE SEQUENCIAL: Atualização de estados, saídas e decodificação
    // -------------------------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state     <= S_IDLE;
            opcode    <= 3'b000;
            dst       <= 4'd0;
            src1      <= 4'd0;
            src2      <= 4'd0;
            immediate <= 16'd0;
            we        <= 1'b0;
            clear_reg <= 1'b0;
            lcd_start <= 1'b0;
        end else begin
            // Avança para o próximo estado
            state <= next_state;

            // Decodificação da instrução: feita apenas quando o pulso ocorre em S_IDLE
            if (state == S_IDLE && instructionPulse) begin
                opcode <= sw[17:15]; // Isola o Opcode unificado 
                
                case (sw[17:15])
                    3'b000: begin // LOAD [cite: 94]
                        dst       <= sw[14:11];
                        src1      <= 4'd0;
                        src2      <= 4'd0;
                        // Correção da extensão de sinal (Sign-Magnitude para Complemento de 2)
                        immediate <= sw[6] ? -sw[5:0] : sw[5:0]; 
                    end
                    3'b001, 3'b011: begin // ADD, SUB [cite: 94]
                        dst       <= sw[14:11];
                        src1      <= sw[10:7];
                        src2      <= sw[6:3];
                        immediate <= 16'd0;
                    end
                    3'b010, 3'b100, 3'b101: begin // ADDI, SUBI, MUL [cite: 94]
                        dst       <= sw[14:11];
                        src1      <= sw[10:7];
                        src2      <= 4'd0;
                        // Correção da extensão de sinal
                        immediate <= sw[6] ? -sw[5:0] : sw[5:0]; 
                    end
                    3'b111: begin // DISPLAY [cite: 94]
                        src1      <= sw[14:11];
                        dst       <= sw[14:11];
                        src2      <= 4'd0;
                        immediate <= 16'd0;
                    end
                    default: begin // CLEAR (110) ou opcodes inválidos [cite: 94]
                        dst       <= 4'd0;
                        src1      <= 4'd0;
                        src2      <= 4'd0;
                        immediate <= 16'd0;
                    end
                endcase
            end

            // Atualização Síncrona Segura de todas as saídas em todos os estados
            case (state)
                S_IDLE: begin
                    we        <= 1'b0;
                    clear_reg <= 1'b0;
                    lcd_start <= 1'b0;
                end

                S_EXECUTE: begin
                    we        <= 1'b0;
                    clear_reg <= 1'b0;
                    lcd_start <= 1'b0;
                end

                S_WRITE: begin
                    lcd_start <= 1'b0;
                    if (opcode == 3'b110) begin // CLEAR [cite: 94]
                        clear_reg <= 1'b1; 
                        we        <= 1'b0;
                    end else if (opcode != 3'b111) begin // Escreve se não for DISPLAY nem CLEAR [cite: 94]
                        we        <= 1'b1;        
                        clear_reg <= 1'b0;
                    end else begin // DISPLAY não escreve na memória [cite: 129]
                        we        <= 1'b0;
                        clear_reg <= 1'b0;
                    end
                end

                S_UPDATE: begin
                    we        <= 1'b0; 
                    clear_reg <= 1'b0; 
                    lcd_start <= 1'b1; // Dispara a atualização do LCD após estabilizar a memória
                end
                
                default: begin
                    we        <= 1'b0;
                    clear_reg <= 1'b0;
                    lcd_start <= 1'b0;
                end
            endcase
        end
    end
endmodule
