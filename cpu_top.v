module cpu_top(
    input clk,             // Clock de 50 MHz da placa
    input [17:0] SW,       // Switches
    input KEY0,            // Reset (Ativo em 0)
    input KEY1,            // Executar Instrução (Ativo em 0)

    inout [7:0] LCD_DATA,
    output LCD_RS,
    output LCD_RW,
    output LCD_EN
);

    // Sinais do Debounce
    wire btn_execute_pulse;
    
    // Conecta o Debounce no KEY1 (Invertido pois pressionado é 0)
    debounce DB1 (
        .clk(clk),
        .btn(~KEY1), 
        .instructionPulse(btn_execute_pulse)
    );

    // Fios de Conexão da Control Unit
    wire [2:0] opcode;
    wire [3:0] src1, src2, dst;
    wire [15:0] imm_ext;
    wire use_imm;
    wire cu_we;

    control_unit CU(
        .clk(clk),
        .rst(~KEY0),
        .instruction(SW),
        .opcode(opcode),
        .src1(src1),
        .src2(src2),
        .dst(dst),
        .imm_ext(imm_ext),
        .use_imm(use_imm),
        .we(cu_we)
    );

    // Sinais da Memória Controlados pela FSM
    reg mem_we;
    wire [15:0] reg_a;
    wire [15:0] reg_b;

    memory MEM(
        .data(alu_result),
        .src_addr1(src1),
        .src_addr2(src2),
        .dst_addr(dst),
        .we(mem_we), // Controlado de forma síncrona pela FSM principal
        .clk(clk),
        .rst(~KEY0),
        .rdata1(reg_a),
        .rdata2(reg_b)
    );

    // Sinais da ULA
    wire [15:0] alu_result;

    module_alu ALU(
        .opcode(opcode),
        .opA(reg_a),
        .opB(reg_b),
        .imm_ext(imm_ext),
        .use_imm(use_imm),
        .result(alu_result)
    );

    // Sinais de controle do LCD
    reg lcd_start_trigger;
    wire lcd_ready;

    lcd_controller LCD(
        .clk(clk),
        .rst(~KEY0),
        .start_write(lcd_start_trigger), // FSM avisa quando desenhar
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

    // -------------------------------------------------------------
    // FSM PRINCIPAL DA CPU: Resolve o Loop Combinacional
    // -------------------------------------------------------------
    reg [1:0] cpu_state;
    localparam CPU_IDLE    = 2'b00;
    localparam CPU_EXECUTE = 2'b01;
    localparam CPU_WRITE   = 2'b10;
    localparam CPU_UPDATE  = 2'b11;

    always @(posedge clk or posedge ~KEY0) begin
        if (~KEY0) begin
            cpu_state <= CPU_IDLE;
            mem_we <= 1'b0;
            lcd_start_trigger <= 1'b0;
        end else begin
            case (cpu_state)
                CPU_IDLE: begin
                    mem_we <= 1'b0;
                    lcd_start_trigger <= 1'b0;
                    // Aguarda o pulso estável vindo do botão solto
                    if (btn_execute_pulse) begin
                        cpu_state <= CPU_EXECUTE;
                    end
                end

                CPU_EXECUTE: begin
                    // Dá 1 clock de margem para as leituras assíncronas da RAM 
                    // estabilizarem na entrada da ULA antes de gravar.
                    cpu_state <= CPU_WRITE;
                end

                CPU_WRITE: begin
                    // Ativa a escrita na RAM se a instrução permitir
                    mem_we <= cu_we; 
                    cpu_state <= CPU_UPDATE;
                end

                CPU_UPDATE: begin
                    mem_we <= 1'b0; // Desliga a escrita imediatamente
                    lcd_start_trigger <= 1'b1; // Dispara a atualização do LCD
                    cpu_state <= CPU_IDLE;     // Retorna ao repouso
                end
            endcase
        end
    end

endmodule
