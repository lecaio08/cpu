module module_alu (
    input [2:0] opcode,
    input signed [15:0] opA,
    input signed [15:0] opB,
    input signed [15:0] imm_ext, // Entrada do imediato vindo da CU
    output reg signed [15:0] result
);
    parameter LOAD    = 3'b000; // LOAD x1, a
    parameter ADD     = 3'b001; // ADD  x3, x1, x2
    parameter ADDI    = 3'b010; // ADDI x2, x1, 10
    parameter SUB     = 3'b011; // SUB  x3, x1, x2
    parameter SUBI    = 3'b100; // SUBI x2, x1, 5
    parameter MUL     = 3'b101; // MUL  x3, x1, x2
    parameter CLEAR   = 3'b110; // zera os registradores
    parameter DISPLAY = 3'b111; // DISPLAY x0
    
    // parte combinacional: definição dos outputs de acordo com a instrução
always @(*) begin
        case (opcode)
            3'b000:  result = imm_ext; // LOAD joga o imediato direto no registrador
            3'b001:  result = opA + opB;
            3'b010:  result = opA + imm_ext; // Usa o Imediato
            3'b011:  result = opA - opB;
            3'b100:  result = opA - imm_ext; // Usa o Imediato
            3'b101:  result = opA * imm_ext; //Usa o imediato
            3'b110:  result = 16'd0; 
            3'b111:  result = opA;
            default: result = 16'd0;
        endcase
    end
endmodule
