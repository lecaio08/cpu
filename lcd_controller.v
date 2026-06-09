module lcd_controller(

    input clk,
    input rst,

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

    //----------------------------------------------------
    // Texto da operação
    //----------------------------------------------------

    reg [7:0] op0;
    reg [7:0] op1;
    reg [7:0] op2;

    always @(*) begin

        case(opcode)

            3'b000: begin
                op0="L"; op1="D"; op2=" ";
            end

            3'b001: begin
                op0="A"; op1="D"; op2="D";
            end

            3'b010: begin
                op0="A"; op1="D"; op2="I";
            end

            3'b011: begin
                op0="S"; op1="U"; op2="B";
            end

            3'b100: begin
                op0="S"; op1="B"; op2="I";
            end

            3'b101: begin
                op0="M"; op1="U"; op2="L";
            end

            3'b110: begin
                op0="C"; op1="L"; op2="R";
            end

            3'b111: begin
                op0="D"; op1="S"; op2="P";
            end

        endcase

    end

    //----------------------------------------------------
    // Conversão decimal
    //----------------------------------------------------

    reg sign;
    reg [15:0] abs_result;

    reg [3:0] d0;
    reg [3:0] d1;
    reg [3:0] d2;
    reg [3:0] d3;
    reg [3:0] d4;

    always @(*) begin

        if(result < 0) begin
            sign = 1'b1;
            abs_result = -result;
        end
        else begin
            sign = 1'b0;
            abs_result = result;
        end

        d4 = (abs_result / 10000) % 10;
        d3 = (abs_result / 1000)  % 10;
        d2 = (abs_result / 100)   % 10;
        d1 = (abs_result / 10)    % 10;
        d0 = abs_result % 10;

    end

    //----------------------------------------------------
    // FSM
    //----------------------------------------------------

    parameter S_IDLE      = 0;
    parameter S_LINE1     = 1;
    parameter S_WRITE1    = 2;
    parameter S_LINE2     = 3;
    parameter S_WRITE2    = 4;
    parameter S_DONE      = 5;

    reg [2:0] state;

    reg [5:0] index;

    reg [7:0] line1 [0:15];
    reg [7:0] line2 [0:15];

    integer i;

    always @(posedge clk or posedge rst) begin

        if(rst) begin

            state <= S_IDLE;
            index <= 0;

        end
        else begin

            case(state)

                S_IDLE:

                    if(init_done) begin

                        line1[0]  <= op0;
                        line1[1]  <= op1;
                        line1[2]  <= op2;
                        line1[3]  <= " ";

                        line1[4]  <= "[";
                        line1[5]  <= src1 + 8'd48;
                        line1[6]  <= "]";
                        line1[7]  <= "[";

                        line1[8]  <= src2 + 8'd48;
                        line1[9]  <= "]";

                        for(i=10;i<16;i=i+1)
                            line1[i] <= " ";

                        line2[0] <= sign ? "-" : "+";

                        line2[1] <= d4 + 8'd48;
                        line2[2] <= d3 + 8'd48;
                        line2[3] <= d2 + 8'd48;
                        line2[4] <= d1 + 8'd48;
                        line2[5] <= d0 + 8'd48;

                        for(i=6;i<16;i=i+1)
                            line2[i] <= " ";

                        state <= S_LINE1;

                    end

                S_LINE1: begin

                    lcd_rs_reg <= 0;
                    lcd_rw_reg <= 0;
                    lcd_data_reg <= 8'h80;
                    lcd_e_reg <= 1;

                    index <= 0;

                    state <= S_WRITE1;

                end

                S_WRITE1: begin

                    lcd_rs_reg <= 1;
                    lcd_rw_reg <= 0;

                    lcd_data_reg <= line1[index];

                    lcd_e_reg <= ~lcd_e_reg;

                    if(index == 15)
                        state <= S_LINE2;
                    else
                        index <= index + 1;

                end

                S_LINE2: begin

                    lcd_rs_reg <= 0;
                    lcd_rw_reg <= 0;

                    lcd_data_reg <= 8'hC0;

                    lcd_e_reg <= 1;

                    index <= 0;

                    state <= S_WRITE2;

                end

                S_WRITE2: begin

                    lcd_rs_reg <= 1;
                    lcd_rw_reg <= 0;

                    lcd_data_reg <= line2[index];

                    lcd_e_reg <= ~lcd_e_reg;

                    if(index == 15)
                        state <= S_DONE;
                    else
                        index <= index + 1;

                end

                S_DONE: begin

                    state <= S_DONE;

                end

            endcase

        end

    end

    always @(*) begin
        start_init = 1'b1;
    end

endmodule
