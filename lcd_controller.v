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

    // Máquina de Estados do LCD com divisor de tempo para o Enable (LCD_EN)
    parameter S_IDLE   = 0;
    parameter S_LINE1  = 1;
    parameter S_WRITE1 = 2;
    parameter S_LINE2  = 3;
    parameter S_WRITE2 = 4;
    parameter S_DONE   = 5;

    reg [2:0] state;
    reg [3:0] index; // Reduzido para 4 bits (0 a 15 basta)
    reg [7:0] line1 [0:15];
    reg [7:0] line2 [0:15];
    
    // Divisor de clock interno para o LCD (O HD44780 não aguenta 50MHz direto no pino Enable)
    reg [15:0] clk_div;
    wire lcd_clk_tick = (clk_div == 16'd50000); // Gera um pulso a cada ~1ms (fácil de ler pelo LCD)

    integer i;

    always @(posedge clk or posedge rst) begin
        if(rst) begin
            state <= S_IDLE;
            index <= 0;
            clk_div <= 0;
            lcd_e_reg <= 0;
        end else begin
            // Contador do divisor de clock
            if (clk_div >= 16'd50000)
                clk_div <= 0;
            else
                clk_div <= clk_div + 1;

            case(state)
                S_IDLE: begin
                    lcd_e_reg <= 0;
                    // Altera de: if(init_done) para esperar também pelo comando de escrita da CPU
                    if(init_done && start_write) begin
                        line1[0]  <= op0;
                        line1[1]  <= op1;
                        line1[2]  <= op2;
                        line1[3]  <= " ";
                        line1[4]  <= "[";
                        line1[5]  <= src1 + 8'd48; // Transforma o número do Reg em caractere ASCII
                        line1[6]  <= "]";
                        line1[7]  <= "[";
                        line1[8]  <= src2 + 8'd48;
                        line1[9]  <= "]";

                        for(i=10; i<16; i=i+1)
                            line1[i] <= " ";

                        line2[0] <= sign ? "-" : "+";
                        line2[1] <= d4 + 8'd48;
                        line2[2] <= d3 + 8'd48;
                        line2[3] <= d2 + 8'd48;
                        line2[4] <= d1 + 8'd48;
                        line2[5] <= d0 + 8'd48;

                        for(i=6; i<16; i=i+1)
                            line2[i] <= " ";

                        state <= S_LINE1;
                    end
                end

                S_LINE1: begin
                    if (lcd_clk_tick) begin
                        lcd_rs_reg <= 0;
                        lcd_rw_reg <= 0;
                        lcd_data_reg <= 8'h80; // Comando: Forçar cursor no início da Linha 1
                        lcd_e_reg <= 1;        // Dá o pulso de escrita
                        index <= 0;
                        state <= S_WRITE1;
                    end
                end

                S_WRITE1: begin
                    if (lcd_clk_tick) begin
                        if (lcd_e_reg == 1'b1) begin
                            lcd_e_reg <= 0; // Desliga o pulso (borda de descida grava o dado no LCD)
                            if(index == 4'd15) begin
                                state <= S_LINE2;
                            end else begin
                                index <= index + 1;
                            end
                        end else begin
                            lcd_rs_reg <= 1; // Modo Dado
                            lcd_rw_reg <= 0;
                            lcd_data_reg <= line1[index];
                            lcd_e_reg <= 1;  // Liga o pulso para o próximo caractere
                        end
                    end
                end

                S_LINE2: begin
                    if (lcd_clk_tick) begin
                        lcd_rs_reg <= 0;
                        lcd_rw_reg <= 0;
                        lcd_data_reg <= 8'hC0; // Comando: Forçar cursor no início da Linha 2
                        lcd_e_reg <= 1;
                        index <= 0;
                        state <= S_WRITE2;
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
                    // Altera de: state <= S_DONE (que travava) para retornar ao IDLE
                    // permitindo novas atualizações quando houver outro comando
                    state <= S_IDLE; 
                end
                
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
