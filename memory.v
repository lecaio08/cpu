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
    integer i;

    // Escrita síncrona
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 16; i = i + 1) begin 
                ram[i] <= 16'd0; // Alterado de '=' para '<='
            end
        end
        else if (we) begin
            ram[dst_addr] <= data;
        end
    end

    // Leitura assíncrona
    assign rdata1 = ram[src_addr1];
    assign rdata2 = ram[src_addr2];
endmodule
