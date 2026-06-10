module lcd_controller_top (
    input wire        clk,        // Clock principal (50 MHz)
    input wire [2:0]  opcode,     // Opcode vindo da Unidade de Controle
    input wire [3:0]  reg_addr,   // Número do registrador (dst_reg ou src_reg1)
    input wire [15:0] result,     // Conteúdo do registrador (16 bits com sinal)
    inout wire [7:0]  LCD_DATA,   // Barramento de dados físico do LCD
    output wire       LCD_RS,     // Register Select
    output wire       LCD_RW,     // Read/Write
    output wire       LCD_EN      // Enable
);

    // -----------------------------------------------------------------------
    // 1. GERAÇÃO DE RESET INTERNO (Power-On Reset)
    // -----------------------------------------------------------------------
    reg [15:0] por_counter = 0;
    reg        rst_internal = 1;
    reg        init_start = 0;

    always @(posedge clk) begin
        if (por_counter < 16'hFFFF) begin
            por_counter  <= por_counter + 1;
            rst_internal <= 1'b1;
            init_start   <= 1'b0;
        end else begin
            rst_internal <= 1'b0;
            init_start   <= 1'b1;
        end
    end

    // -----------------------------------------------------------------------
    // 2. MÓDULO DE INICIALIZAÇÃO (Instanciação do teu lcd_init_hd44780)
    // -----------------------------------------------------------------------
    wire [7:0] init_data;
    wire       init_rs, init_rw, init_en, init_done;

    lcd_init_hd44780 init_unit (
        .clk(clk),
        .rst(rst_internal),
        .start(init_start),
        .done(init_done),
        .lcd_data(init_data),
        .lcd_rs(init_rs),
        .lcd_rw(init_rw),
        .lcd_e(init_en)
    );

    // -----------------------------------------------------------------------
    // 3. CONVERSÃO EXATA DO RESULTADO PARA DECIMAL COM SINAL (5 DÍGITOS)
    // -----------------------------------------------------------------------
    wire        is_negative = result[15];
    wire [15:0] abs_value   = is_negative ? (~result + 1'b1) : result;
    wire [7:0]  sign_char   = is_negative ? "-" : "+";

    // Extração combinacional de dígitos decimais (Totalmente sintetizável no Quartus)
    wire [3:0] d4 = (abs_value / 10000) % 10;
    wire [3:0] d3 = (abs_value / 1000) % 10;
    wire [3:0] d2 = (abs_value / 100) % 10;
    wire [3:0] d1 = (abs_value / 10) % 10;
    wire [3:0] d0 = abs_value % 10;

    // Conversão do endereço do registrador para bits ASCII individuais
    wire [7:0] bit3 = reg_addr[3] ? "1" : "0";
    wire [7:0] bit2 = reg_addr[2] ? "1" : "0";
    wire [7:0] bit1 = reg_addr[1] ? "1" : "0";
    wire [7:0] bit0 = reg_addr[0] ? "1" : "0";

    // -----------------------------------------------------------------------
    // 4. DECODIFICAÇÃO DE TEXTO DO OPCODE CONFORME O PDF
    // -----------------------------------------------------------------------
    reg [7:0] op_c0, op_c1, op_c2, op_c3, op_c4;
    always @(*) begin
        op_c0 = " "; op_c1 = " "; op_c2 = " "; op_c3 = " "; op_c4 = " ";
        case (opcode)
            3'b000: begin op_c0 = "L"; op_c1 = "O"; op_c2 = "A"; op_c3 = "D"; end // LOAD
            3'b001: begin op_c0 = "A"; op_c1 = "D"; op_c2 = "D"; end             // ADD
            3'b010: begin op_c0 = "A"; op_c1 = "D"; op_c2 = "D"; op_c3 = "I"; end // ADDI
            3'b011: begin op_c0 = "S"; op_c1 = "U"; op_c2 = "B"; end             // SUB
            3'b100: begin op_c0 = "S"; op_c1 = "U"; op_c2 = "B"; op_c3 = "I"; end // SUBI
            3'b101: begin op_c0 = "M"; op_c1 = "U"; op_c2 = "L"; end             // MUL
            3'b110: begin op_c0 = "C"; op_c1 = "L"; op_c2 = "E"; op_c3 = "A"; op_c4 = "R"; end // CLEAR
            3'b111: begin op_c0 = "D"; op_c1 = "P"; op_c2 = "L"; end             // DISPLAY -> DPL
        endcase
    end

    // -----------------------------------------------------------------------
    // 5. MAPEAMENTO DE MATRIZ DO MONITOR (16 COLUNAS x 2 LINHAS)
    // -----------------------------------------------------------------------
    reg [7:0] out_byte;
    reg       out_rs;

    always @(*) begin
        out_rs = 1'b1; // Padrão: Escrita de caractere
        case (seq_idx)
            // --- LINHA 1: Nome da Instrução [0-4] e Registrador [10-15] ---
            6'd0:  begin out_byte = 8'h80; out_rs = 1'b0; end // Comando: Posiciona na Linha 1, Col 0
            6'd1:  out_byte = op_c0;
            6'd2:  out_byte = op_c1;
            6'd3:  out_byte = op_c2;
            6'd4:  out_byte = op_c3;
            6'd5:  out_byte = op_c4;
            6'd6:  out_byte = " ";
            6'd7:  out_byte = " ";
            6'd8:  out_byte = " ";
            6'd9:  out_byte = " ";
            6'd10: out_byte = " ";
            6'd11: out_byte = (opcode == 3'b110) ? " " : "[";
            6'd12: out_byte = (opcode == 3'b110) ? " " : bit3;
            6'd13: out_byte = (opcode == 3'b110) ? " " : bit2;
            6'd14: out_byte = (opcode == 3'b110) ? " " : bit1;
            6'd15: out_byte = (opcode == 3'b110) ? " " : bit0;
            6'd16: out_byte = (opcode == 3'b110) ? " " : "]";

            // --- LINHA 2: Espaços em branco [0-9] e Valor Decimal com Sinal [10-15] ---
            6'd17: begin out_byte = 8'hC0; out_rs = 1'b0; end // Comando: Posiciona na Linha 2, Col 0
            6'd18: out_byte = " ";
            6'd19: out_byte = " ";
            6'd20: out_byte = " ";
            6'd21: out_byte = " ";
            6'd22: out_byte = " ";
            6'd23: out_byte = " ";
            6'd24: out_byte = " ";
            6'd25: out_byte = " ";
            6'd26: out_byte = " ";
            6'd27: out_byte = " ";
            6'd28: out_byte = (opcode == 3'b110) ? " " : sign_char;
            6'd29: out_byte = (opcode == 3'b110) ? " " : (8'h30 + d4);
            3'd30: out_byte = (opcode == 3'b110) ? " " : (8'h30 + d3);
            6'd31: out_byte = (opcode == 3'b110) ? " " : (8'h30 + d2);
            6'd32: out_byte = (opcode == 3'b110) ? " " : (8'h30 + d1);
            6'd33: out_byte = (opcode == 3'b110) ? " " : (8'h30 + d0);
            default: begin out_byte = 8'h20; out_rs = 1'b1; end
        endcase
    end

    // -----------------------------------------------------------------------
    // 6. FSM DE ATUALIZAÇÃO SEQUENCIAL DO DISPLAY
    // -----------------------------------------------------------------------
    localparam S_SEQ_IDLE  = 2'd0;
    localparam S_SEQ_SETUP = 2'd1;
    localparam S_SEQ_PULSE = 2'd2;
    localparam S_SEQ_HOLD  = 2'd3;

    reg [1:0]  seq_state = S_SEQ_IDLE;
    reg [5:0]  seq_idx   = 0;
    reg [31:0] clk_cnt   = 0;

    reg [7:0]  reg_data;
    reg        reg_rs;
    reg        reg_en;

    reg [15:0] prev_result   = 0;
    reg [2:0]  prev_opcode   = 0;
    reg [3:0]  prev_reg_addr = 0;
    reg [23:0] refresh_cnt   = 0;
    reg        refresh_pulse = 0;

    // Pulso interno de auto-refresh periódico (~0.1s) para estabilidade física
    always @(posedge clk) begin
        prev_result   <= result;
        prev_opcode   <= opcode;
        prev_reg_addr <= reg_addr;

        if (refresh_cnt < 24'd5_000_000) begin
            refresh_cnt   <= refresh_cnt + 1'b1;
            refresh_pulse <= 1'b0;
        end else begin
            refresh_cnt   <= 0;
            refresh_pulse <= 1'b1;
        end
    end

    always @(posedge clk) begin
        if (rst_internal) begin
            seq_state <= S_SEQ_IDLE;
            seq_idx   <= 0;
            clk_cnt   <= 0;
            reg_en    <= 0;
        end else if (init_done) begin
            case (seq_state)
                S_SEQ_IDLE: begin
                    reg_en <= 1'b0;
                    if ((result != prev_result) || (opcode != prev_opcode) || (reg_addr != prev_reg_addr) || refresh_pulse) begin
                        seq_idx   <= 0;
                        seq_state <= S_SEQ_SETUP;
                    end
                end

                S_SEQ_SETUP: begin
                    if (seq_idx < 6'd34) begin // 34 passos mapeados (2 Comandos + 32 caracteres)
                        reg_data  <= out_byte;
                        reg_rs    <= out_rs;
                        reg_en    <= 1'b0;
                        clk_cnt   <= 0;
                        seq_state <= S_SEQ_PULSE;
                    end else begin
                        seq_state <= S_SEQ_IDLE;
                    end
                end

                S_SEQ_PULSE: begin
                    reg_en <= 1'b1; // Levanta o Enable do LCD
                    if (clk_cnt < 32'd60) begin // Pulso de ~1.2 us
                        clk_cnt <= clk_cnt + 1'b1;
                    end else begin
                        reg_en  <= 1'b0;
                        clk_cnt <= 0;
                        seq_state <= S_SEQ_HOLD;
                    end
                end

                S_SEQ_HOLD: begin
                    reg_en <= 1'b0;
                    if (clk_cnt < 32'd2500) begin // Delay de processamento interno (~50 us)
                        clk_cnt <= clk_cnt + 1'b1;
                    end else begin
                        seq_idx   <= seq_idx + 1'b1;
                        seq_state <= S_SEQ_SETUP;
                    end
                end
            endcase
        end
    end

    // -----------------------------------------------------------------------
    // 7. MULTIPLEXAÇÃO FINAL DE SAÍDA PARA OS PINOS
    // -----------------------------------------------------------------------
    assign LCD_DATA = init_done ? reg_data : init_data;
    assign LCD_RS   = init_done ? reg_rs   : init_rs;
    assign LCD_RW   = init_done ? 1'b0     : init_rw; 
    assign LCD_EN   = init_done ? reg_en   : init_en;

endmodule
