module cpu_top(
    input clk,
    input [17:0] SW,
    input KEY0,            // Reset (Ativo em 0)
    input KEY1,            // Enviar instrução (Ativo em 0)

    inout [7:0] LCD_DATA,
    output LCD_RS,
    output LCD_RW,
    output LCD_EN
);

    // Fio do botão Debounce
    wire btn_execute_pulse;

    debounce DB1 (
        .clk(clk),
        .btn(~KEY1), 
        .instructionPulse(btn_execute_pulse)
    );

    // Fios internos interligando a CPU (com os nomes corretos)
    wire [2:0] opcode;
    wire [3:0] dst, src1, src2;
    wire signed [15:0] immediate;
    wire we, clear_reg, lcd_start;
    
    wire [15:0] reg_a, reg_b, alu_result;

    // Instanciação da Control Unit
    control_unit CU(
        .clk(clk),
        .rst(~KEY0),
        .instructionPulse(btn_execute_pulse),
        .sw(SW),
        .opcode(opcode),
        .dst(dst),
        .src1(src1),
        .src2(src2),
        .immediate(immediate),
        .we(we),
        .clear_reg(clear_reg),
        .lcd_start(lcd_start)
    );

    // Instanciação da Memória
    memory MEM(
        .data(alu_result),
        .src_addr1(src1),
        .src_addr2(src2),
        .dst_addr(dst),
        .we(we), 
        .clk(clk),
        .rst(~KEY0),
        .clear_reg(clear_reg),
        .rdata1(reg_a),
        .rdata2(reg_b)
    );

    // Instanciação da ULA
    module_alu ALU(
        .opcode(opcode),
        .opA(reg_a),
        .opB(reg_b),
        .immediate(immediate),
        .result(alu_result)
    );

    // Instanciação do Controlador do LCD
    lcd_controller LCD(
        .clk(clk),
        .rst(~KEY0),
        .start_write(lcd_start), // Recebe o gatilho da Control Unit
        .opcode(opcode),
        .src1(src1),
        .src2(src2),
        .dst_reg(dst),
        .result(alu_result),
        .LCD_DATA(LCD_DATA),
        .LCD_RS(LCD_RS),
        .LCD_RW(LCD_RW),
        .LCD_EN(LCD_EN)
    );

endmodule
