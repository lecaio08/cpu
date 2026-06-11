module memory (
    input [15:0] data,
    input [3:0] src_addr1,
    input [3:0] src_addr2,
    input [3:0] dst_addr,
    input we,
    input clk,
    input rst,
    output [15:0] rdata1,
    output [15:0] rdata2
);
    reg [15:0] ram [15:0];

    // Escrita síncrona
    always @(posedge clk) begin
        if (rst) begin
            // Reset manual de cada posição da memória (desenrolado)
            ram[0]  <= 16'd0;
            ram[1]  <= 16'd0;
            ram[2]  <= 16'd0;
            ram[3]  <= 16'd0;
            ram[4]  <= 16'd0;
            ram[5]  <= 16'd0;
            ram[6]  <= 16'd0;
            ram[7]  <= 16'd0;
            ram[8]  <= 16'd0;
            ram[9]  <= 16'd0;
            ram[10] <= 16'd0;
            ram[11] <= 16'd0;
            ram[12] <= 16'd0;
            ram[13] <= 16'd0;
            ram[14] <= 16'd0;
            ram[15] <= 16'd0;
        end
        else if (we) begin
            ram[dst_addr] <= data;
        end
    end

    // Leitura assíncrona
    assign rdata1 = ram[src_addr1];
    assign rdata2 = ram[src_addr2];
endmodule
