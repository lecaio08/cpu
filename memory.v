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
	// matriz p/ memoria e contador
	reg [15:0] ram [15:0];
	integer i;
	// escrita síncrona
	always @(posedge clk) begin
		// se for detectado um sinal de reset, zerar a memoria
		if (rst) begin
			for (i = 0; i < 16; i = i + 1) begin // analogo a um for dentro de um for, p/ leitura de matriz em C
				ram[i] = 16'd0;
			end
		end
		// write
		else if (we) begin
			ram[dst_addr] <= data;
		end
	end
	// leitura assincrona
	assign rdata1 = ram[src_addr1];
	assign rdata2 = ram[src_addr2];
endmodule
// opcode dst_reg, src_reg1, src_reg2 (Imm)
