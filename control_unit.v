module control_unit (
    input clk,
    input btn_ligar_pulse,       // Pulso do botão de ligar (vindo do debounce)
    input instructionPulse,      // Pulso do botão de enviar (vindo do debounce)
    input [17:0] switches,       // Switches da placa FPGA (Instrução)
    
    // Interface com a Memória/Banco de Registradores
    output reg [3:0] mem_addr_rd1, // Endereço de leitura 1
    output reg [3:0] mem_addr_rd2, // Endereço de leitura 2
    output reg [3:0] mem_addr_wr,  // Endereço de escrita
    output reg mem_we,             // Write Enable da memória
    output reg mem_clear,          // Limpa todos os registradores (Zera a memória)
    output reg [15:0] mem_data_wr, // Dados a serem gravados
    input [15:0] mem_data_rd1,     // Dados lidos 1
    input [15:0] mem_data_rd2,     // Dados lidos 2
    
    // Interface com a ULA (ALU)
    output reg [2:0] alu_op,       // Opcode para a ULA
    output reg [15:0] alu_in1,     // Entrada 1 da ULA
    output reg [15:0] alu_in2,     // Entrada 2 da ULA
    input [15:0] alu_out,          // Resultado vindo da ULA
    
    // Interface de Controle do LCD
    output reg lcd_start,          // Pulso para iniciar atualização do LCD
    output reg [2:0] lcd_cmd_type, // Tipo de comando/operação a ser exibida
    output reg [3:0] lcd_dest_reg, // Registrador de destino para exibir no LCD
    output reg [15:0] lcd_result,  // Valor do resultado para exibir no LCD
    input lcd_ready,               // Sinal do LCD indicando término de operação/espera
    
    output reg system_on           // Sinalizador se o sistema está ativo/ligado
);

    // Definição dos Estados da CPU
    parameter STATE_OFF       = 3'b000; // Sistema desligado
    parameter STATE_IDLE      = 3'b001; // Esperando instrução (Ligado)
    parameter STATE_FETCH     = 3'b010; // Busca da instrução dos switches
    parameter STATE_DECODE    = 3'b011; // Decodificação e leitura de registradores
    parameter STATE_EXECUTE   = 3'b100; // Execução na ULA
    parameter STATE_STORE     = 3'b101; // Escrita do resultado na memória (Writeback)
    parameter STATE_LCD_WAIT  = 3'b110; // Espera da propagação do sinal do LCD

    // Registradores de Estado
    reg [2:0] state = STATE_OFF;
    reg [2:0] next_state;

    // Registradores internos para armazenamento temporário do ciclo
    reg [17:0] instr_reg;
    reg [2:0]  opcode;
    reg [3:0]  dest_reg;
    reg [3:0]  src1_reg;
    reg [3:0]  src2_reg;
    reg [15:0] imm_value;

    // -------------------------------------------------------------------------
    // PARTE COMBINACIONAL: Lógica de alteração/transição de estados
    // -------------------------------------------------------------------------
    always @(*) begin
        case (state)
            STATE_OFF: begin
                if (btn_ligar_pulse) 
                    next_state = STATE_IDLE;
                else 
                    next_state = STATE_OFF;
            end
            
            STATE_IDLE: begin
                if (btn_ligar_pulse) 
                    next_state = STATE_OFF; // Se apertar ligar de novo, desliga
                else if (instructionPulse) 
                    next_state = STATE_FETCH;
                else 
                    next_state = STATE_IDLE;
            end
            
            STATE_FETCH: begin
                next_state = STATE_DECODE;
            end
            
            STATE_DECODE: begin
                next_state = STATE_EXECUTE;
            end
            
            STATE_EXECUTE: begin
                next_state = STATE_STORE;
            end
            
            STATE_STORE: begin
                next_state = STATE_LCD_WAIT;
            end
            
            STATE_LCD_WAIT: begin
                if (lcd_ready) 
                    next_state = STATE_IDLE; // Retorna para IDLE após atualizar tela
                else 
                    next_state = STATE_LCD_WAIT;
            end
            
            default: next_state = STATE_OFF;
        endcase
    end

    // -------------------------------------------------------------------------
    // PARTE SEQUENCIAL: Atualização de estados e saídas/registradores
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        // Atualização do estado atual
        state <= next_state;

        // Controle síncrono das saídas baseado no estado corrente
        case (state)
            STATE_OFF: begin
                system_on    <= 0;
                mem_we       <= 0;
                mem_clear    <= 1; // Mantém a memória zerada enquanto desligado
                lcd_start    <= 0;
                alu_op       <= 3'b000;
                alu_in1      <= 16'h0000;
                alu_in2      <= 16'h0000;
            end

            STATE_IDLE: begin
                system_on    <= 1;
                mem_we       <= 0;
                mem_clear    <= 0;
                lcd_start    <= 0;
            end

            STATE_FETCH: begin
                // Captura a palavra de instrução atual dos switches
                instr_reg <= switches;
            end

            STATE_DECODE: begin
                // O Opcode está sempre localizado nos 3 bits mais significativos (switches [17:15])
                opcode <= instr_reg[17:15];
                
                case (instr_reg[17:15])
                    // Tipo 1: Operações Aritméticas com Registradores (ADD=001, SUB=011)
                    3'b001, 3'b011: begin
                        dest_reg     <= instr_reg[14:11];
                        src1_reg     <= instr_reg[10:7];
                        src2_reg     <= instr_reg[6:3];
                        // Configura os endereços para ler imediatamente da memória no próximo ciclo
                        mem_addr_rd1 <= instr_reg[10:7];
                        mem_addr_rd2 <= instr_reg[6:3];
                    end

                    // Tipo 2: Operações Aritméticas com Imediatos (ADDI=010, SUBI=100, MUL=101)
                    3'b010, 3'b100, 3'b101: begin
                        dest_reg     <= instr_reg[14:11];
                        src1_reg     <= instr_reg[10:7];
                        mem_addr_rd1 <= instr_reg[10:7];
                        // Tratamento do Imediato com Sinal (Módulo + Sinal)
                        // instr_reg[6] é o sinal (1 = negativo, 0 = positivo). instr_reg[5:0] é o valor.
                        if (instr_reg[6] == 1'b1)
                            imm_value <= -{10'b0, instr_reg[5:0]};
                        else
                            imm_value <= {10'b0, instr_reg[5:0]};
                    end

                    // Tipo 3: Operação de Carga (LOAD=000)
                    3'b000: begin
                        dest_reg <= instr_reg[14:11];
                        // LOAD usa switch[10] para sinal e [9:4] para imediato conforme alinhamento contíguo
                        if (instr_reg[10] == 1'b1)
                            imm_value <= -{10'b0, instr_reg[9:4]};
                        else
                            imm_value <= {10'b0, instr_reg[9:4]};
                    end

                    // Tipo Especial: DISPLAY (111)
                    3'b111: begin
                        src1_reg     <= instr_reg[14:11]; // Registrador que se deseja exibir
                        mem_addr_rd1 <= instr_reg[14:11];
                    end

                    // Tipo Especial: CLEAR (110)
                    3'b110: begin
                        // Nenhuma decodificação de campo necessária
                    end
                endcase
            end

            STATE_EXECUTE: begin
                // Encaminha a operação para a ULA
                alu_op <= opcode;
                
                case (opcode)
                    3'b001, 3'b011: begin // ADD, SUB
                        alu_in1 <= mem_data_rd1;
                        alu_in2 <= mem_data_rd2;
                    end
                    3'b010, 3'b100, 3'b101: begin // ADDI, SUBI, MUL
                        alu_in1 <= mem_data_rd1;
                        alu_in2 <= imm_value;
                    end
                    3'b000: begin // LOAD (passa o imediato direto através da ULA ou atribuição)
                        alu_in1 <= imm_value;
                        alu_in2 <= 16'h0000;
                    end
                    3'b111: begin // DISPLAY (passa o valor lido do registrador)
                        alu_in1 <= mem_data_rd1;
                        alu_in2 <= 16'h0000;
                    end
                    default: begin
                        alu_in1 <= 16'h0000;
                        alu_in2 <= 16'h0000;
                    end
                endcase
            end

            STATE_STORE: begin
                // Envia dados para gravação na Memória RAM se aplicável
                if (opcode == 3'b110) begin
                    mem_clear <= 1'b1; // Ativa o sinal para zerar todos os registradores (CLEAR)
                end 
                else if (opcode != 3'b111) begin // Não escreve na memória se for DISPLAY
                    mem_addr_wr <= dest_reg;
                    mem_data_wr <= alu_out;
                    mem_we      <= 1'b1; // Habilita a escrita síncrona
                end

                // Prepara os dados de comando de atualização para o módulo do LCD
                lcd_cmd_type   <= opcode;
                lcd_dest_reg   <= dest_reg;
                lcd_result     <= (opcode == 3'b111) ? mem_data_rd1 : alu_out;
                lcd_start      <= 1'b1; // Dispara a atualização do LCD
            end

            STATE_LCD_WAIT: begin
                mem_we    <= 1'b0; // Desativa escrita da memória
                mem_clear <= 1'b0; // Desativa pulso de CLEAR
                lcd_start <= 1'b0; // Finaliza o pulso de gatilho do LCD
            end
        endcase
    end

endmodule
