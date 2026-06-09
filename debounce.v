module debounce (
	input clk, btn,			    // clock e sinal físico do botão
	output reg instructionPulse // sinal que habilita o envio da instrução
);
	// timeout de debounce
	parameter TIMEOUT = 50000;
	// o sinal do botão físico é assíncrono, portanto, precisamos sincronizá-lo com o clock
	reg sync, btnSync;
	
	always @(posedge clk) begin
		sync    <= btn;  // recebe o sinal físico
		btnSync <= sync; // sincroniza de fato
	end
	// estados
	parameter init            = 2'b00; // 00
	parameter debounce        = 2'b01; // 01
	parameter waitRelease     = 2'b10; // 10
	parameter sendInstruction = 2'b11; // 11
	// estado atual e contador
	reg [1:0]  state = init;
	reg [32:0] counter = 0;
	// parte combinacional
	always @(*) begin
		case (state)
			init: begin
				instructionPulse <= 0;
			end
			debounce: begin
				instructionPulse <= instructionPulse;
			end
			waitRelease: begin
				instructionPulse <= instructionPulse;
			end
			sendInstruction: begin
				instructionPulse <= 1;
			end
		endcase
	end
	// parte sequencial
	always @(posedge clk) begin
		case (state)
			init: begin
				counter <= 0;
				if (btnSync == 1) begin state <= debounce; end
				else begin state <= init; end
			end
			debounce: begin
				if (counter == TIMEOUT) begin state <= waitRelease; end
				else if (btnSync == 0) begin state <= init; end
				else begin
					counter <= counter + 1;
					state <= debounce;
				end
			end
			waitRelease: begin
        if (btnSync == 0) begin state <= sendInstruction; end
				else begin state <= waitRelease; end
			end
			sendInstruction: begin 
				state <= init; 
			end
		endcase
	end	
endmodule
