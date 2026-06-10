module control_unit (
    input clk,
    input rst,                     // Reset global (~KEY0)
    input instructionPulse,        // Pulso do botão Enviar (vindo do debounce)
    input [17:0] instruction,      // Instrução vinda dos switches

    output reg [2:0] opcode,       // Código da instrução
    output reg [3:0] dst,          // Registrador de Destino
    output reg [3:0] src1,         // Registrador Fonte 1
    output reg [3:0] src2,         // Registrador Fonte 2
    output reg signed [15:0] immediate, // Valor Imediato com sinal
    output reg we,                 // Write Enable (Escrita na memória)
    output reg clear_reg,          // Sinal para limpar a memória
    output reg lcd_start           // Gatilho para atualizar o LCD
);

    // Definição dos Estados da FSM (Aumentado para 3 bits para acomodar o S_INIT)
    parameter S_INIT    = 3'b000;
    parameter S_IDLE    = 3'b001;
    parameter S_EXECUTE = 3'b010;
    parameter S_WRITE   = 3'b011;
    parameter S_UPDATE  = 3'b100;

    reg [2:0] state;
    reg [2:0] next_state;

    // -------------------------------------------------------------------------
    // PARTE COMBINACIONAL: Lógica estável para alteração de estados
    // -------------------------------------------------------------------------
    always @(*) begin
        case (state)
            S_INIT: begin
                // Executa uma única vez no boot/reset e vai direto para a espera estável (S_IDLE)
                next_state = S_IDLE;
            end

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
                // Siga para IDLE e espere o pulso do botão apagar completamente
                if (instructionPulse)
                    next_state = S_UPDATE; // Trava aqui caso o pulso do botão seja longo
                else
                    next_state = S_IDLE;
            end
            
            default: next_state = S_IDLE;
        endcase
    end

    // -------------------------------------------------------------------------
    // PARTE SEQUENCIAL: Atualização de estados e decodificação precisa
    // -------------------------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state     <= S_INIT; // Força entrar no estado de inicialização no reset físico
            opcode    <= 3'b110; // Código temporário de CLEAR/Reset para o LCD ler
            dst       <= 4'd0;
            src1      <= 4'd0;
            src2      <= 4'd0;
            immediate <= 16'd0;
            we        <= 1'b0;
            clear_reg <= 1'b1;   // Ativa a limpeza da memória de forma pura
            lcd_start <= 1'b1;   // Dispara o LCD imediatamente para renderizar os traços/zeros
        end else begin
            state <= next_state;

            // Tratamento das saídas estritamente no estado de inicialização pós-reset lógico
            if (state == S_INIT) begin
                we        <= 1'b0;
                clear_reg <= 1'b1; // Mantém a memória limpando
                lcd_start <= 1'b1; // Continua sustentando o disparo inicial do LCD
                opcode    <= 3'b110;
            end
            // Decodificação: feita estritamente na transição exata do disparo em IDLE
            else if (state == S_IDLE && instructionPulse) begin
                opcode <= instruction[17:15];
                clear_reg <= 1'b0; // Desliga o sinal de limpar que veio do reset antes de operar
                
                case (instruction[17:15])
                    3'b000: begin // LOAD
                        dst  <= instruction[14:11];
                        src1 <= 4'd0;
                        src2 <= 4'd0;
                        if (instruction[6]) 
                            immediate <= - $signed({10'd0, instruction[5:0]});
                        else      
                            immediate <= $signed({10'd0, instruction[5:0]});
                    end
                    
                    3'b001, 3'b011: begin // ADD, SUB
                        dst       <= instruction[14:11];
                        src1      <= instruction[10:7];
                        src2      <= instruction[6:3];
                        immediate <= 16'd0;
                    end
                    
                    3'b010, 3'b100, 3'b101: begin // ADDI, SUBI, MUL
                        dst  <= instruction[14:11];
                        src1 <= instruction[10:7];
                        src2 <= 4'd0;
                        if (instruction[6]) 
                            immediate <= - $signed({10'd0, instruction[5:0]});
                        else      
                            immediate <= $signed({10'd0, instruction[5:0]});
                    end
                    
                    3'b111: begin // DISPLAY
                        src1      <= instruction[14:11];
                        dst       <= instruction[14:11];
                        src2      <= 4'd0;
                        immediate <= 16'd0;
                    end
                    
                    3'b110: begin // CLEAR
                        dst       <= 4'd0;
                        src1      <= 4'd0;
                        src2      <= 4'd0;
                        immediate <= 16'd0;
                    end
                    
                    default: begin
                        dst       <= 4'd0;
                        src1      <= 4'd0;
                        src2      <= 4'd0;
                        immediate <= 16'd0;
                    end
                endcase
            end else begin
                // Atualização Controlada das Saídas nos estados correspondentes (Ignora se estiver no S_INIT)
                case (next_state)
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
                        if (opcode == 3'b110) begin
                            clear_reg <= 1'b1; // Ativa CLEAR apenas se a instrução atual for CLEAR
                        end else if (opcode != 3'b111) begin
                            we <= 1'b1;        // Ativa escrita na RAM
                        end
                    end

                    S_UPDATE: begin
                        we        <= 1'b0;     // Corta a escrita imediatamente
                        clear_reg <= 1'b0;
                        lcd_start <= 1'b1;     // Dispara o LCD com segurança
                    end
                endcase
            end
        end
    end
endmodule
