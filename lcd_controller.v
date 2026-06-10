module lcd_controller(
    input clk,
    input rst,
    input start_write,       // Entrada vinda da FSM da CPU (lcd_start)

    input [2:0] opcode,
    input [3:0] src1,
    input [3:0] src2,
    input [3:0] dst_reg,

    input signed [15:0] result,

    inout [7:0] LCD_DATA,
    output LCD_RS,
    output LCD_RW,
    output LCD_EN
);

    wire init_done;
    wire [7:0] init_data;
    wire init_rs;
    wire init_rw;
    wire init_e;
    
    // A inicialização física de hardware (HD44780) ocorre apenas uma vez quando liga a energia
    lcd_init_hd44780 INIT(
        .clk(clk),
        .rst(rst),
        .start(1'b1),
        .done(init_done),
        .lcd_data(init_data),
        .lcd_rs(init_rs),
        .lcd_rw(init_rw),
        .lcd_e(init_e)
    );

    // =========================================================================
    // LÓGICA DE TOGGLE (CHAVE LIGA/DESLIGA) NO BOTÃO DE RESET
    // =========================================================================
    reg power_state = 1'b0; // 0 = LCD Desligado (começa assim), 1 = LCD Ligado
    reg rst_d1 = 1'b0;
    reg rst_d2 = 1'b0;

    // Deteta quando o botão de Reset é SOLTO (borda de descida) para inverter o estado
    always @(posedge clk) begin
        rst_d1 <= rst;
        rst_d2 <= rst_d1;
        // Quando rst vai de 1 para 0 (soltou o botão)
        if (!rst_d1 && rst_d2) begin
            power_state <= ~power_state; // Alterna entre ligado e desligado
        end
    end
    // =========================================================================

    reg [7:0] lcd_data_reg;
    reg lcd_rs_reg;
    reg lcd_rw_reg;
    reg lcd_e_reg;

    assign LCD_DATA = init_done ? lcd_data_reg : init_data;
    assign LCD_RS   = init_done ? lcd_rs_reg   : init_rs;
    assign LCD_RW   = init_done ? lcd_rw_reg   : init_rw;
    assign LCD_EN   = init_done ? lcd_e_reg    : init_e;

    // --- CONVERSÃO DECIMAL E SINAL ---
    reg sign;
    reg [15:0] abs_result;
    reg [3:0] d0, d1, d2, d3, d4;

    always @(*) begin
        if(result < 0) begin
            sign = 1'b1;
            abs_result = -result;
        end else begin
            sign = 1'b0;
            abs_result = result;
        end

        d4 = (abs_result / 10000) % 10;
        d3 = (abs_result / 1000)  % 10;
        d2 = (abs_result / 100)   % 10;
        d1 = (abs_result / 10)    % 10;
        d0 = abs_result % 10;
    end

    // --- MÁQUINA DE ESTADOS DO LCD ---
    parameter S_IDLE   = 0;
    parameter S_SETUP  = 1; 
    parameter S_LINE1  = 2;
    parameter S_WRITE1 = 3;
    parameter S_LINE2  = 4;
    parameter S_WRITE2 = 5;
    parameter S_DONE   = 6;

    reg [2:0] state;
    reg [3:0] index; 
    reg [7:0] line1 [0:15];
    reg [7:0] line2 [0:15];

    // Registos internos estáveis congelados no pulso de escrita
    reg [2:0] opcode_reg;
    reg [3:0] dst_reg_internal;
    reg sign_reg;
    reg [3:0] d4_reg, d3_reg, d2_reg, d1_reg, d0_reg;

    // Controladores de estado do ecrã
    reg last_power_state = 1'b0;
    reg is_off_mode = 1'b0;

    // Divisor de clock interno para o LCD (50MHz)
    reg [15:0] clk_div;
    wire lcd_clk_tick = (clk_div == 16'd50000);

    integer i;

    always @(posedge clk or posedge rst) begin
        if(rst) begin
            state <= S_IDLE;
            index <= 0;
            clk_div <= 0;
            lcd_e_reg <= 0;
            lcd_rs_reg <= 0;
            lcd_rw_reg <= 0;
            lcd_data_reg <= 8'h00;
            // IMPORTANTE: Não dar reset no last_power_state aqui, senão a transição não é detetada!
        end else begin
            // Contador do divisor de clock
            if (clk_div >= 16'd50000)
                clk_div <= 0;
            else
                clk_div <= clk_div + 1;

            // 1. PRIORIDADE: Verifica se houve alteração no estado de energia (Clicaram no Reset)
            if (init_done && (last_power_state != power_state)) begin
                last_power_state <= power_state; // Atualiza memória interna
                
                if (power_state == 1'b1) begin
                    // AÇÃO: LIGOU O LCD
                    opcode_reg  <= 3'b110; // Força operação de CLEAR internamente
                    is_off_mode <= 1'b0;
                    state <= S_SETUP;
                end else begin
                    // AÇÃO: DESLIGOU O LCD
                    is_off_mode <= 1'b1;   // Ativa modo escuro (apaga tudo)
                    state <= S_SETUP;
                end
            end 
            // 2. MODO NORMAL: FSM normal se o estado de energia estiver estável
            else begin
                case(state)
                    S_IDLE: begin
                        lcd_e_reg <= 0;
                        // BLOQUEIO SEGURO: Só atende a CPU se init_done=1, start_write=1 E o LCD estiver LIGADO
                        if(init_done && start_write && (power_state == 1'b1)) begin
                            opcode_reg       <= opcode;
                            dst_reg_internal <= dst_reg;
                            sign_reg         <= sign;
                            d4_reg           <= d4;
                            d3_reg           <= d3;
                            d2_reg           <= d2;
                            d1_reg           <= d1;
                            d0_reg           <= d0;
                            is_off_mode      <= 1'b0;
                            state <= S_SETUP;
                        end
                    end

                    S_SETUP: begin
                        // Preenchimento padrão com espaços vazios para evitar "fantasmas"
                        for(i=0; i<16; i=i+1) begin
                            line1[i] <= 8'h20;
                            line2[i] <= 8'h20;
                        end

                        if (is_off_mode) begin
                            // SE ESTÁ DESLIGADO: não desenha absolutamente nada, 
                            // as linhas já estão cheias de espaço em branco (0x20).
                        end 
                        else begin
                            // SE ESTÁ LIGADO: Faz a formatação normal da instrução
                            case(opcode_reg)
                                3'b000: begin line1[0]<=8'h4C; line1[1]<=8'h4F; line1[2]<=8'h41; line1[3]<=8'h44; end // "LOAD"
                                3'b001: begin line1[0]<=8'h41; line1[1]<=8'h44; line1[2]<=8'h44; end                  // "ADD"
                                3'b010: begin line1[0]<=8'h41; line1[1]<=8'h44; line1[2]<=8'h44; line1[3]<=8'h49; end // "ADDI"
                                3'b011: begin line1[0]<=8'h53; line1[1]<=8'h55; line1[2]<=8'h42; end                  // "SUB"
                                3'b100: begin line1[0]<=8'h53; line1[1]<=8'h42; line1[2]<=8'h49; end                  // "SBI"
                                3'b101: begin line1[0]<=8'h4D; line1[1]<=8'h55; line1[2]<=8'h4C; end                  // "MUL"
                                3'b110: begin line1[0]<=8'h43; line1[1]<=8'h4C; line1[2]<=8'h52; end                  // "CLR"
                                3'b111: begin line1[0]<=8'h44; line1[1]<=8'h50; line1[2]<=8'h4C; end                  // "DPL"
                                default:begin line1[0]<=8'h20; line1[1]<=8'h20; line1[2]<=8'h20; end
                            endcase

                            if (opcode_reg == 3'b110) begin
                                // TELA DE CLEAR (Forçada ou requisitada)
                                line1[0] <= 8'h2D; line1[1] <= 8'h2D; line1[2] <= 8'h2D; line1[3] <= 8'h2D; // "----"
                                line1[10]<= 8'h5B; // "["
                                line1[11]<= 8'h2D; line1[12]<= 8'h2D; line1[13]<= 8'h2D; line1[14]<= 8'h2D; // "----"
                                line1[15]<= 8'h5D; // "]"

                                line2[10]<= 8'h2B; // "+"
                                line2[11]<= 8'h30; line2[12]<= 8'h30; line2[13]<= 8'h30; line2[14]<= 8'h30; line2[15]<= 8'h30;
                            end else begin
                                // OUTRAS INSTRUÇÕES DA CPU
                                line1[10] <= 8'h5B;
                                line1[11] <= dst_reg_internal[3] ? 8'h31 : 8'h30;
                                line1[12] <= dst_reg_internal[2] ? 8'h31 : 8'h30;
                                line1[13] <= dst_reg_internal[1] ? 8'h31 : 8'h30;
                                line1[14] <= dst_reg_internal[0] ? 8'h31 : 8'h30;
                                line1[15] <= 8'h5D;

                                line2[10] <= sign_reg ? 8'h2D : 8'h2B;
                                line2[11] <= d4_reg + 8'h30;
                                line2[12] <= d3_reg + 8'h30;
                                line2[13] <= d2_reg + 8'h30;
                                line2[14] <= d1_reg + 8'h30;
                                line2[15] <= d0_reg + 8'h30;
                            end
                        end

                        index <= 0;
                        state <= S_LINE1;
                    end

                    S_LINE1: begin
                        if (lcd_clk_tick) begin
                            if (lcd_e_reg == 1'b1) begin
                                lcd_e_reg <= 0;   
                                index <= 0;       
                                state <= S_WRITE1;
                            end else begin
                                lcd_rs_reg <= 0;
                                lcd_rw_reg <= 0;
                                lcd_data_reg <= 8'h80;
                                lcd_e_reg <= 1;        
                            end
                        end
                    end

                    S_WRITE1: begin
                        if (lcd_clk_tick) begin
                            if (lcd_e_reg == 1'b1) begin
                                lcd_e_reg <= 0; 
                                if(index == 4'd15) begin
                                    state <= S_LINE2;
                                end else begin
                                    index <= index + 1;
                                end
                            end else begin
                                lcd_rs_reg <= 1; 
                                lcd_rw_reg <= 0;
                                lcd_data_reg <= line1[index];
                                lcd_e_reg <= 1;  
                            end
                        end
                    end

                    S_LINE2: begin
                        if (lcd_clk_tick) begin
                            if (lcd_e_reg == 1'b1) begin
                                lcd_e_reg <= 0;    
                                index <= 0;        
                                state <= S_WRITE2; 
                            end else begin
                                lcd_rs_reg <= 0;
                                lcd_rw_reg <= 0;
                                lcd_data_reg <= 8'hC0;
                                lcd_e_reg <= 1;        
                            end
                        end
                    end

                    S_WRITE2: begin
                        if (lcd_clk_tick) begin
                            if (lcd_e_reg == 1'b1) begin
                                lcd_e_reg <= 0; 
                                if(index == 4'd15) begin
                                    state <= S_DONE;
                                end else begin
                                    index <= index + 1;
                                end
                            end else begin
                                lcd_rs_reg <= 1;
                                lcd_rw_reg <= 0;
                                lcd_data_reg <= line2[index];
                                lcd_e_reg <= 1;
                            end
                        end
                    end

                    S_DONE: begin
                        state <= S_IDLE; 
                    end

                    default: state <= S_IDLE;
                endcase
            end
        end
    end
endmodule
