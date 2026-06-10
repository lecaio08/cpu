module lcd_controller(
    input clk,
    input rst,
    input start_write,       // Nova entrada vinda da FSM da CPU

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
    reg start_init;

    // Garante que a inicialização do LCD começa assim que o sistema sai do reset
    always @(*) begin
        start_init = 1'b1;
    end

    lcd_init_hd44780 INIT(
        .clk(clk),
        .rst(rst),
        .start(start_init),
        .done(init_done),
        .lcd_data(init_data),
        .lcd_rs(init_rs),
        .lcd_rw(init_rw),
        .lcd_e(init_e)
    );

    reg [7:0] lcd_data_reg;
    reg lcd_rs_reg;
    reg lcd_rw_reg;
    reg lcd_e_reg;

    assign LCD_DATA = init_done ? lcd_data_reg : init_data;
    assign LCD_RS   = init_done ? lcd_rs_reg   : init_rs;
    assign LCD_RW   = init_done ? lcd_rw_reg   : init_rw;
    assign LCD_EN   = init_done ? lcd_e_reg    : init_e;

    // Texto da operação (Combinacional)
    reg [7:0] op0, op1, op2;
    always @(*) begin
        case(opcode)
            3'b000: begin op0="L"; op1="D"; op2=" "; end // LOAD
            3'b001: begin op0="A"; op1="D"; op2="D"; end // ADD
            3'b010: begin op0="A"; op1="D"; op2="I"; end // ADDI
            3'b011: begin op0="S"; op1="U"; op2="B"; end // SUB
            3'b100: begin op0="S"; op1="B"; op2="I"; end // SUBI
            3'b101: begin op0="M"; op1="U"; op2="L"; end // MUL
            3'b110: begin op0="C"; op1="L"; op2="R"; end // CLEAR
            3'b111: begin op0="D"; op1="S"; op2="P"; end // DISPLAY
            default: begin op0=" "; op1=" "; op2=" "; end
        endcase
    end

    // Conversão decimal (Combinacional)
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

   // Máquina de Estados do LCD Atualizada
    parameter S_IDLE   = 0;
    parameter S_LINE1  = 1;
    parameter S_SETUP1 = 2; // Estado de preparação para a Linha 1
    parameter S_WRITE1 = 3;
    parameter S_LINE2  = 4;
    parameter S_SETUP2 = 5; // Estado de preparação para a Linha 2
    parameter S_WRITE2 = 6;
    parameter S_DONE   = 7;

    reg [2:0] state;
    reg [3:0] index; 
    reg [7:0] line1 [0:15];
    reg [7:0] line2 [0:15];

    // Registos internos para congelar os valores da CPU
    reg [2:0] opcode_reg;
    reg [3:0] dst_reg_internal;
    
    // Flag interna para sabermos se o comando capturado veio do reset inicial
    reg is_boot_reset;

    // Divisor de clock interno para o LCD (50MHz -> ~1ms)
    reg [15:0] clk_div;
    wire lcd_clk_tick = (clk_div == 16'd50000);

    integer i;

    always @(posedge clk or posedge rst) begin
        if(rst) begin
            state <= S_IDLE;
            index <= 0;
            clk_div <= 0;
            lcd_e_reg <= 0;
            opcode_reg <= 3'b110; // Começa apontando para uma inicialização segura
            dst_reg_internal <= 0;
            is_boot_reset <= 1'b1; // Ativa flag de boot inicial sob reset físico
            
            // Força memórias de linha a começarem com o padrão exigido
            line1[0]<="-"; line1[1]<="-"; line1[2]<="-"; line1[3]<="-";
            line1[4]<=" "; line1[5]<=" "; line1[6]<=" "; line1[7]<=" "; line1[8]<=" "; line1[9]<=" ";
            line1[10]<="["; line1[11]<="-"; line1[12]<="-"; line1[13]<="-"; line1[14]<="-"; line1[15]<="]";
            
            line2[0]<=" "; line2[1]<=" "; line2[2]<=" "; line2[3]<=" "; line2[4]<=" ";
            line2[5]<=" "; line2[6]<=" "; line2[7]<=" "; line2[8]<=" "; line2[9]<=" ";
            line2[11]<="0"; line2[12]<="0"; line2[13]<="0"; line2[14]<="0"; line2[15]<="0";
        end else begin
            // Contador do divisor de clock
            if (clk_div >= 16'd50000)
                clk_div <= 0;
            else
                clk_div <= clk_div + 1;

            case(state)
                S_IDLE: begin
                    lcd_e_reg <= 0;
                    
                    // Se o sistema acabou de ligar, pula o start_write da CPU e força a primeira renderização
                    if(init_done && is_boot_reset) begin
                        opcode_reg    <= 3'b110;
                        state         <= S_SETUP1;
                    end
                    // Caso contrário, segue o fluxo normal ativado pela CPU
                    else if(init_done && start_write) begin
                        opcode_reg       <= opcode;
                        dst_reg_internal <= dst_reg;
                        is_boot_reset    <= 1'b0; // Certifica-se de desligar o modo boot

                        // Limpa as memórias do display com espaços vazios antes de mapear nova instrução
                        for(i=0; i<16; i=i+1) begin
                            line1[i] <= " ";
                            line2[i] <= " ";
                        end

                        state <= S_SETUP1;
                    end
                end

                S_SETUP1: begin
                    // INTERCEPÇÃO DE INICIALIZAÇÃO / RESET: 
                    // Se estivermos em Boot ou o Opcode recebido for o CLEAR estrito da inicialização
                    if (is_boot_reset || (opcode_reg == 3'b110 && start_write == 1'b0)) begin
                        // 1. Canto superior esquerdo: ----
                        line1[0] <= "-"; line1[1] <= "-"; line1[2] <= "-"; line1[3] <= "-";
                        
                        // 2. Canto superior direito: [----]
                        line1[10] <= "["; line1[11] <= "-"; line1[12] <= "-"; line1[13] <= "-"; line1[14] <= "-"; line1[15] <= "]";
                        
                        // 3. Canto inferior direito: 00000
                        line2[11] <= "0"; line2[12] <= "0"; line2[13] <= "0"; line2[14] <= "0"; line2[15] <= "0";
                    end 
                    // CÓDIGO ORIGINAL: Executado se for uma operação normal de instrução
                    else begin
                        case(opcode_reg)
                            3'b000: begin line1[0]<="L"; line1[1]<="O"; line1[2]<="A"; line1[3]<="D"; end // LOAD 
                            3'b001: begin line1[0]<="A"; line1[1]<="D"; line1[2]<="D"; end                 // ADD 
                            3'b010: begin line1[0]<="A"; line1[1]<="D"; line1[2]<="D"; line1[3]<="I"; end // ADDI 
                            3'b011: begin line1[0]<="S"; line1[1]<="U"; line1[2]<="B"; end                 // SUB 
                            3'b100: begin line1[0]<="S"; line1[1]<="B"; line1[2]<="I"; end                 // SUBI 
                            3'b101: begin line1[0]<="M"; line1[1]<="U"; line1[2]<="L"; end                 // MUL 
                            3'b110: begin line1[0]<="C"; line1[1]<="L"; line1[2]<="R"; end                 // CLEAR 
                            3'b111: begin line1[0]<="D"; line1[1]<="P"; line1[2]<="L"; end                 // DISPLAY -> DPL 
                            default: begin line1[0]<=" "; line1[1]<=" "; line1[2]<=" "; end
                        endcase

                        // Formata o registrador e os números rigidamente empurrados para as últimas colunas (10 a 15)
                        if (opcode_reg != 3'b110) begin
                            line1[10] <= "[";
                            line1[11] <= dst_reg_internal[3] ? "1" : "0"; 
                            line1[12] <= dst_reg_internal[2] ? "1" : "0"; 
                            line1[13] <= dst_reg_internal[1] ? "1" : "0"; 
                            line1[14] <= dst_reg_internal[0] ? "1" : "0"; 
                            line1[15] <= "]";

                            line2[10] <= sign ? "-" : "+";
                            line2[11] <= d4 + 8'd48;
                            line2[12] <= d3 + 8'd48;
                            line2[13] <= d2 + 8'd48;
                            line2[14] <= d1 + 8'd48;
                            line2[15] <= d0 + 8'd48;
                        end
                    end

                    index <= 0;
                    state <= S_LINE1;
                end

                S_LINE1: begin
                    if (lcd_clk_tick) begin
                        if (lcd_e_reg == 1'b1) begin
                            lcd_e_reg <= 0;    // Desliga o pulso do comando
                            index <= 0;        // Garante que começa no 0
                            state <= S_WRITE1; // Só agora avança para escrever a palavra
                        end else begin
                            lcd_rs_reg <= 0;
                            lcd_rw_reg <= 0;
                            lcd_data_reg <= 8'h80; // Comando: Cursor no início da Linha 1
                            lcd_e_reg <= 1;        // Ativa o pulso
                        end
                    end
                end
                
                S_WRITE1: begin
                    if (lcd_clk_tick) begin
                        if (lcd_e_reg == 1'b1) begin
                            lcd_e_reg <= 0; // Desliga o Enable (grava o dado no LCD)
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
                            lcd_e_reg <= 0;    // Desliga o pulso do comando
                            index <= 0;        // Garante que começa no 0
                            state <= S_WRITE2; // Só agora avança para escrever os números
                        end else begin
                            lcd_rs_reg <= 0;
                            lcd_rw_reg <= 0;
                            lcd_data_reg <= 8'hC0; // Comando: Cursor no início da Linha 2
                            lcd_e_reg <= 1;        // Ativa o pulso
                        end
                    end
                end
                
                S_WRITE2: begin
                    if (lcd_clk_tick) begin
                        if (lcd_e_reg == 1'b1) begin
                            lcd_e_reg <= 0; // Desliga o Enable
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
                    is_boot_reset <= 1'b0; // Garante que saiu do modo boot após a primeira varredura completa
                    state <= S_IDLE; 
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
