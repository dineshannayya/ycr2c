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
      yifive WB header file                                               
                                                                          
                                                                          
      Description:                                                        
         WB header file                                                   
                                                                          
      To Do:                                                              
        nothing                                                           
                                                                          
  Author(s):                                                  
          - Dinesh Annayya <dinesha@opencores.org>               
          - Dinesh Annayya <dinesh@siplusplus.com>               
                                                                          
      Revision :                                                          
         v0:    June 7, 2021, Dinesh A                                    
                 wishbone define added                                    
 ***************************************************************************************************/

`ifndef YCR_WB_SVH
`define YCR_WB_SVH

`include "ycr_arch_description.svh"

parameter YCR_WB_WIDTH  = 32;
parameter YCR_WB_BL_DMEM= 3;

// Encoding for DATA SIZE
parameter logic [2:0] YCR_DSIZE_8B    = 3'b000;
parameter logic [2:0] YCR_DSIZE_16B   = 3'b001;
parameter logic [2:0] YCR_DSIZE_32B   = 3'b010;

`endif // YCR_WB_SVH
