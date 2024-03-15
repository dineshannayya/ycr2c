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
module ycr_serial_debug  #(parameter DEBUG_WD = 64)(

         input logic                reset_n,
         input logic                clk    ,
         input logic [DEBUG_WD-1:0] debug_bus,
         output logic               serial_debug_data,
         output logic               serial_debug_sync 
       );


logic [7:0] cnt;
logic [DEBUG_WD-1:0] debug_load;

assign serial_debug_data = debug_load[0];

always @(negedge reset_n or posedge clk)
begin
   if(reset_n == 1'b0) begin
       cnt        <= 'h0;
       serial_debug_sync <= 1'b0;
       debug_load <= 'h0;
   end else begin
       if(cnt == 0) begin
          serial_debug_sync <= 1'b1;
          debug_load <= debug_bus;
          cnt <= cnt + 1;
       end begin
          serial_debug_sync <= 1'b0;
          debug_load <= {1'b0,debug_load[DEBUG_WD-1:1]};
          if(cnt == DEBUG_WD-1) begin
             cnt <= 0;
          end else begin
             cnt <= cnt + 1;
          end
       end
   end
end


endmodule
               
