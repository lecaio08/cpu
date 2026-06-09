module cpu_top(

    input clk,
    input [17:0] SW,

    input KEY0,      // reset
    input KEY1,      // executar instrução

    inout [7:0] LCD_DATA,
    output LCD_RS,
    output LCD_RW,
    output LCD_EN

);

    // FIOS INTERNOS

    wire [2:0] opcode;

    wire [3:0] src1;
    wire [3:0] src2;
    wire [3:0] dst;

    wire we;

    wire [15:0] reg_a;
    wire [15:0] reg_b;

    wire [15:0] alu_result;

    // CONTROL UNIT

    control_unit CU(

        .clk(clk),
        .rst(~KEY0),

        .instruction(SW),

        .opcode(opcode),

        .src1(src1),
        .src2(src2),
        .dst(dst),

        .we(we)

    );

    // MEMORY

    memory MEM(

        .data(alu_result),

        .src_addr1(src1),
        .src_addr2(src2),

        .dst_addr(dst),

        .we(we),

        .clk(clk),
        .rst(~KEY0),

        .rdata1(reg_a),
        .rdata2(reg_b)

    );

    // ALU

    module_alu ALU(

        .opcode(opcode),

        .opA(reg_a),
        .opB(reg_b),

        .result(alu_result)

    );

    // LCD

    lcd_controller LCD(

        .clk(clk),
        .rst(~KEY0),

        .opcode(opcode),
        .dst_reg(dst),

        .result(alu_result),

        .LCD_DATA(LCD_DATA),
        .LCD_RS(LCD_RS),
        .LCD_RW(LCD_RW),
        .LCD_EN(LCD_EN)

    );

endmodule
