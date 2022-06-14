//////////////////////////////////////////////////////////////////////////////
// SPDX-FileCopyrightText: 2021, Dinesh Annayya                           ////
//                                                                        ////
// Licensed under the Apache License, Version 2.0 (the "License");        ////
// you may not use this file except in compliance with the License.       ////
// You may obtain a copy of the License at                                ////
//                                                                        ////
//      http://www.apache.org/licenses/LICENSE-2.0                        ////
//                                                                        ////
// Unless required by applicable law or agreed to in writing, software    ////
// distributed under the License is distributed on an "AS IS" BASIS,      ////
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.///
// See the License for the specific language governing permissions and    ////
// limitations under the License.                                         ////
// SPDX-License-Identifier: Apache-2.0                                    ////
// SPDX-FileContributor: Dinesh Annayya <dinesha@opencores.org>           ////
//////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////
////                                                                      ////
////  ycr2  router                                                        ////
////                                                                      ////
////  This file is part of the ycr cores project                          ////
////  https://github.com/dineshannayya/ycr2c.git                          ////
////                                                                      ////
////  Description:                                                        ////
////     memory router                                                    ////
////     map  the two core imem/dmem Memory request                      ////
////                                                                      ////
////  To Do:                                                              ////
////    nothing                                                           ////
////                                                                      ////
////  Author(s):                                                          ////
////      - Dinesh Annayya, dinesha@opencores.org                         ////
////                                                                      ////
////  Revision :                                                          ////
////     v0:    19 Mar 2022,  Dinesh A                                    ////
////             Initial Version                                          ////
////                                                                      ////
//////////////////////////////////////////////////////////////////////////////

`include "ycr_memif.svh"
`include "ycr_arch_description.svh"

module ycr2_router (
    // Control signals
    input   logic                           rst_n,
    input   logic                           clk,

    input   logic  [2:0]                    taget_id,

    // core0-imem interface
    input   logic [2:0]                     core0_imem_tid,
    output  logic                           core0_imem_req_ack,
    output  logic                           core0_imem_lack,
    input   logic                           core0_imem_req,
    input   logic                           core0_imem_cmd,
    input   logic [1:0]                     core0_imem_width,
    input   logic [`YCR_IMEM_AWIDTH-1:0]    core0_imem_addr,
    input   logic [`YCR_IMEM_BSIZE-1:0]     core0_imem_bl,
    input   logic [`YCR_IMEM_DWIDTH-1:0]    core0_imem_wdata,
    output  logic [`YCR_IMEM_DWIDTH-1:0]    core0_imem_rdata,
    output  logic [1:0]                     core0_imem_resp,

    // core0-dmem interface
    input   logic [2:0]                     core0_dmem_tid,
    output  logic                           core0_dmem_req_ack,
    output  logic                           core0_dmem_lack,
    input   logic                           core0_dmem_req,
    input   logic                           core0_dmem_cmd,
    input   logic [1:0]                     core0_dmem_width,
    input   logic [`YCR_IMEM_AWIDTH-1:0]    core0_dmem_addr,
    input   logic [`YCR_IMEM_BSIZE-1:0]     core0_dmem_bl,
    input   logic [`YCR_IMEM_DWIDTH-1:0]    core0_dmem_wdata,
    output  logic [`YCR_IMEM_DWIDTH-1:0]    core0_dmem_rdata,
    output  logic [1:0]                     core0_dmem_resp,

    // core1-imem interface
    input   logic [2:0]                     core1_imem_tid,
    output  logic                           core1_imem_req_ack,
    output  logic                           core1_imem_lack,
    input   logic                           core1_imem_req,
    input   logic                           core1_imem_cmd,
    input   logic [1:0]                     core1_imem_width,
    input   logic [`YCR_IMEM_AWIDTH-1:0]    core1_imem_addr,
    input   logic [`YCR_IMEM_BSIZE-1:0]     core1_imem_bl,
    input   logic [`YCR_IMEM_DWIDTH-1:0]    core1_imem_wdata,
    output  logic [`YCR_IMEM_DWIDTH-1:0]    core1_imem_rdata,
    output  logic [1:0]                     core1_imem_resp,

    // core1-dmem interface
    input   logic [2:0]                     core1_dmem_tid,
    output  logic                           core1_dmem_req_ack,
    output  logic                           core1_dmem_lack,
    input   logic                           core1_dmem_req,
    input   logic                           core1_dmem_cmd,
    input   logic [1:0]                     core1_dmem_width,
    input   logic [`YCR_IMEM_AWIDTH-1:0]    core1_dmem_addr,
    input   logic [`YCR_IMEM_BSIZE-1:0]     core1_dmem_bl,
    input   logic [`YCR_IMEM_DWIDTH-1:0]    core1_dmem_wdata,
    output  logic [`YCR_IMEM_DWIDTH-1:0]    core1_dmem_rdata,
    output  logic [1:0]                     core1_dmem_resp,

    // core interface
    input   logic                          core_req_ack,
    output  logic                          core_req,
    output  logic                          core_cmd,
    output  logic [1:0]                    core_width,
    output  logic [`YCR_IMEM_AWIDTH-1:0]   core_addr,
    output  logic [`YCR_IMEM_BSIZE-1:0]    core_bl,
    output  logic [`YCR_IMEM_DWIDTH-1:0]   core_wdata,
    input   logic [`YCR_IMEM_DWIDTH-1:0]   core_rdata,
    input   logic [1:0]                    core_resp

);


wire core_lack = (core_resp == YCR_MEM_RESP_RDY_LOK);

// Generate request based on target id
wire core0_imem_req_t = (core0_imem_req & core0_imem_tid == taget_id);
wire core0_dmem_req_t = (core0_dmem_req & core0_dmem_tid == taget_id);

wire core1_imem_req_t = (core1_imem_req & core1_imem_tid == taget_id);
wire core1_dmem_req_t = (core1_dmem_req & core1_dmem_tid == taget_id);


// Arbitor to select between external wb vs uart wb
wire [3:0] grnt;

ycr_arb #(.TREQ(4)) u_arb(
	.clk      (clk                ), 
	.rstn     (rst_n              ), 
	.req      ({
	            core1_dmem_req_t,core1_imem_req_t, 
	            core0_dmem_req_t,core0_imem_req_t
	           }), 
	.req_ack   (core_req_ack      ), 
	.lack      (core_lack         ), 
	.gnt      (grnt               )
        );


// Select  the master based on the grant
assign core_req   = 
	            (grnt == 4'b0000) ? core0_imem_req_t  : 
	            (grnt == 4'b0001) ? core0_dmem_req_t  : 
	            (grnt == 4'b0010) ? core1_imem_req_t  : 
	            (grnt == 4'b0011) ? core1_dmem_req_t  : 
		    'h0; 
assign core_cmd   = 
	            (grnt == 4'b0000) ? core0_imem_cmd  : 
	            (grnt == 4'b0001) ? core0_dmem_cmd  : 
	            (grnt == 4'b0010) ? core1_imem_cmd  : 
	            (grnt == 4'b0011) ? core1_dmem_cmd  : 
		    'h0; 
	
assign core_width = 
	            (grnt == 4'b0000) ? core0_imem_width  : 
	            (grnt == 4'b0001) ? core0_dmem_width  : 
	            (grnt == 4'b0010) ? core1_imem_width  : 
	            (grnt == 4'b0011) ? core1_dmem_width  : 
		    'h0; 
assign core_addr  = 
	            (grnt == 4'b0000) ? core0_imem_addr  : 
	            (grnt == 4'b0001) ? core0_dmem_addr  : 
	            (grnt == 4'b0010) ? core1_imem_addr  : 
	            (grnt == 4'b0011) ? core1_dmem_addr  : 
		    'h0; 
assign core_bl    = 
	            (grnt == 4'b0000) ? core0_imem_bl  : 
	            (grnt == 4'b0001) ? core0_dmem_bl  : 
	            (grnt == 4'b0010) ? core1_imem_bl  : 
	            (grnt == 4'b0011) ? core1_dmem_bl  : 
		    'h0; 
assign core_wdata = 
	            (grnt == 4'b0000) ? core0_imem_wdata  : 
	            (grnt == 4'b0001) ? core0_dmem_wdata  : 
	            (grnt == 4'b0010) ? core1_imem_wdata  : 
	            (grnt == 4'b0011) ? core1_dmem_wdata  : 
		    'h0; 

//-----------------------------------------------------------------------
// Note: 
// Last ACK is not supported by core, we are tieing *_resp[1]= 1'b0
// ----------------------------------------------------------------------
assign core0_imem_req_ack  = (grnt == 4'b0000) ? core_req_ack        : 'h0;
assign core0_imem_lack     = (grnt == 4'b0000) ? core_lack           : 'h0;
assign core0_imem_rdata    = (grnt == 4'b0000) ? core_rdata          : 'h0;
assign core0_imem_resp     = (grnt == 4'b0000) ? {1'b0,core_resp[0]} : 'h0;

assign core0_dmem_req_ack  = (grnt == 4'b0001) ? core_req_ack        : 'h0;
assign core0_dmem_lack     = (grnt == 4'b0001) ? core_lack           : 'h0;
assign core0_dmem_rdata    = (grnt == 4'b0001) ? core_rdata          : 'h0;
assign core0_dmem_resp     = (grnt == 4'b0001) ? {1'b0,core_resp[0]} : 'h0;

assign core1_imem_req_ack  = (grnt == 4'b0010) ? core_req_ack        : 'h0;
assign core1_imem_lack     = (grnt == 4'b0010) ? core_lack           : 'h0;
assign core1_imem_rdata    = (grnt == 4'b0010) ? core_rdata          : 'h0;
assign core1_imem_resp     = (grnt == 4'b0010) ? {1'b0,core_resp[0]} : 'h0;

assign core1_dmem_req_ack  = (grnt == 4'b0011) ? core_req_ack        : 'h0;
assign core1_dmem_lack     = (grnt == 4'b0011) ? core_lack           : 'h0;
assign core1_dmem_rdata    = (grnt == 4'b0011) ? core_rdata          : 'h0;
assign core1_dmem_resp     = (grnt == 4'b0011) ? {1'b0,core_resp[0]} : 'h0;


endmodule : ycr2_router
