/*****************************************************************************************************
 * Copyright (c) 2024 SiPlusPlus Semiconductor
 *
 * FileContributor: Dinesh Annayya <dinesha@opencores.org>                       
 * FileContributor: Dinesh Annayya <dinesh@siplusplus.com>                       
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 ***************************************************************************************************/
/****************************************************************************************************
      yifive 32x32 Multiplier with 8 stage pipe line                      
                                                                          
                                                                          
      Description:                                                        
        32x32 Multiplier with 8 stage pipe line for timing reason         
        Support signed multiplication, bit[32] indicate sign              
                                                                          
      To Do:                                                              
        nothing                                                           
                                                                          
  Author(s):                                                  
          - syntacore, https://github.com/syntacore/scr1                   
          - Dinesh Annayya <dinesha@opencores.org>               
          - Dinesh Annayya <dinesh@siplusplus.com>               
                                                                          
      Revision :                                                          
         v0 - 25th July 2021                                              
                  Breaking two's complement into two stage for            
                  timing reason, When all lower 32 bit zero and           
                  it's complement will be '1', this will cause            
                  increment in higer bits                                 
         v1 - 11 Nov 2022                                                 
                 Added addition one cycle pipe line to break two's        
                 complements for input data                               
 ***************************************************************************************************/
                                                                          
module ycr_pipe_mul (
	input   logic        clk, 
	input   logic        rstn, 
	input   logic        data_valid,   // input valid
	input   logic [32:0] Din1,         // first operand
	input   logic [32:0] Din2,         // second operand
	output  logic [31:0] des_hig,      // first result
	output  logic [31:0] des_low,      // second result
	output  logic        mul_rdy_o,    // Multiply result ready
	input   logic        data_done     // Result processing complete indication
    );

parameter WAIT_CMD      = 3'b000; // Accept command and Do Signed to unsigned
parameter WAIT_NEG_CHECK= 3'b001; // Wait for Negative Input check
parameter WAIT_COMP     = 3'b010; // Wait for COMPUTATION
parameter WAIT_DONE     = 3'b011; // Do Signed to Unsigned conversion 
parameter WAIT_EXIT     = 3'b100; // Wait for Data Completion

// wires
logic [35:0] tmp_mul1;
logic [64:0] tmp_mul, shifted;
logic [31:0] src1,src2; // Unsigned number

// real registers
logic [2:0]  cycle,next_cycle;
logic [63:0] mul_result,mul_next;
logic [2:0]   state, next_state;
logic  mul_rdy_i;
logic  mul_32b_zero_b;

assign tmp_mul1 = src1 * src2[31:28];
//assign shifted = (cycle == 3'h0 ? 64'h0 : {mul_result[59:0], 4'b0000});
assign tmp_mul = tmp_mul1 + shifted;
assign des_hig = mul_result[63:32];
assign des_low = mul_result[31:0];

always_ff @(posedge clk or negedge rstn)
begin
   if (!rstn) begin
      state           <= WAIT_CMD;
      cycle           <= 3'b0;
      mul_result      <= 65'b0;
      mul_rdy_o       <= 1'b0;
      src1            <= 32'h0;
      src2            <= 32'h0;
      shifted         <= 'h0;
      mul_32b_zero_b  <= '0;
   end else begin
     cycle        <= next_cycle;
     state        <= next_state;
     shifted      <= {mul_next[59:0], 4'b0000};

     mul_rdy_o    <= mul_rdy_i;
     if(data_valid && state== WAIT_CMD ) begin
        src1   <= Din1[31:0];
        src2   <= Din2[31:0];
     end else if(state== WAIT_NEG_CHECK ) begin
        src1   <= (Din1[32] == 1'b1) ? (32'hFFFF_FFFF ^ src1[31:0])+1 : src1[31:0];
        src2   <= (Din2[32] == 1'b1) ? (32'hFFFF_FFFF ^ src2[31:0])+1 : src2[31:0];
     end else begin
	    src2   <= src2 << 4;
     end
     if(state== WAIT_DONE ) begin
	// If Number is negative, then do 2's complement
	// Breaking 2's complement to timing reason
        if(Din1[32] ^ Din2[32]) begin 
           mul_result[31:0] <= (32'hFFFF_FFFF ^ mul_result[31:0]) + 1;
           mul_result[63:32] <= (mul_32b_zero_b == 1'b0) ? (32'hFFFF_FFFF ^ mul_result[63:32]) + 1 : (32'hFFFF_FFFF ^ mul_result[63:32]) ;
	end
     end else begin
	mul_result   <= mul_next;
	mul_32b_zero_b  <= |mul_next[31:0]; // check all bit are zero
     end
   end
end

always_comb
begin
     mul_rdy_i = 0;
     next_cycle   = cycle;
     next_state   = state;
     mul_next     = mul_result;
     case(state)
     WAIT_CMD: if(data_valid)  begin // Start only on active High Edge
	     mul_next   = 0;
	     next_cycle = 0;
	     next_state = WAIT_NEG_CHECK;
	 end
     // One Cycle for Negative Input check
     // Added to break timing violation
     WAIT_NEG_CHECK: begin
	     mul_next   = 0;
	     next_cycle = 0;
	     next_state = WAIT_COMP;
     end 
     // WAIT for Computation
     WAIT_COMP:  
	begin
	   mul_next   = tmp_mul;
	   next_cycle = cycle +1;
	   if(cycle == 7) begin
	      next_state  = WAIT_DONE;
           end else begin
	      next_cycle = cycle +1;
	   end
	end
     WAIT_DONE:  begin
           mul_rdy_i = 1'b1;
	   next_state  = WAIT_EXIT;
	end
	WAIT_EXIT: begin
	    if(data_done) // Wait for data completion command
	       next_state  = WAIT_CMD;
	end	
    endcase
end

endmodule

