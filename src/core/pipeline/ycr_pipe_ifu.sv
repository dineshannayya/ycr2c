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
      yifive Instruction Fetch Unit (IFU)                                 
                                                                          
                                                                          
      Description:                                                        
         Instruction Fetch Unit (IFU)                                     
                                                                          
     Functionality:                                                       
     - Controls instruction fetching process:                             
       - Fetches instructions either from IMEM or from Program Buffer,    
         supporting pending IMEM instructions handling                    
       - Handles new PC misalignment and constructs the correct instruction
         (supports RVI and RVC instructions)                               
       - Either stores instructions in the instruction queue or bypasses to
         the IDU if the corresponding option is used                      
       - Flushes instruction queue if requested                           
                                                                          
     Structure:                                                           
     - Instruction queue                                                  
     - IFU FSM                                                            
     - IFU <-> IMEM i/f                                                   
     - IFU <-> IDU i/f                                                    
     - IFU <-> HDU i/f                                                    
                                                                          
      To Do:                                                              
        nothing                                                           
                                                                          
  Author(s):                                                  
          - syntacore, https://github.com/syntacore/scr1                   
          - Dinesh Annayya <dinesha@opencores.org>               
          - Dinesh Annayya <dinesh@siplusplus.com>               
                                                                          
      Revision :                                                          
         0.0:   Jan 2021- Initial version picked from                     
                https://github.com/syntacore/scr1                         
         0.1:    June 7, 2021, Dinesh A                                   
                 opentool(iverilog/yosys) related cleanup                 
         0.2:    Jan 22, 2022, Dinesh A                                   
                 Bug fix: Do avoid abort imem request removal, we have    
                 qualified it with imem_resp_discard_cnt_upd              
                                                                          
 ***************************************************************************************************/
                                                                          


`include "ycr_memif.svh"
`include "ycr_arch_description.svh"
`ifdef YCR_DBG_EN
`include "ycr_hdu.svh"
`endif // YCR_DBG_EN

module ycr_pipe_ifu
(
    // Control signals
    input   logic                                   rst_n,                      // IFU reset
    input   logic                                   clk,                        // IFU clock
    input   logic                                   pipe2ifu_stop_fetch_i,      // Stop instruction fetch

    // IFU <-> IMEM interface
    input   logic                                   imem2ifu_req_ack_i,         // Instruction memory request acknowledgement
    output  logic                                   ifu2imem_req_o,             // Instruction memory request
    output  logic                                   ifu2imem_cmd_o,             // Instruction memory command (READ/WRITE)
    output  logic [`YCR_IMEM_AWIDTH-1:0]           ifu2imem_addr_o,            // Instruction memory address
    output  logic [`YCR_IMEM_BSIZE-1:0]            ifu2imem_bl_o,              // Instruction memory burst size
    input   logic [`YCR_IMEM_DWIDTH-1:0]           imem2ifu_rdata_i,           // Instruction memory read data
    input   logic [1:0]                             imem2ifu_resp_i,            // Instruction memory response

    // IFU <-> EXU New PC interface
    input   logic                                   exu2ifu_pc_new_req_i,       // New PC request (jumps, branches, traps etc)
    input   logic [`YCR_XLEN-1:0]                  exu2ifu_pc_new_i,           // New PC

`ifdef YCR_DBG_EN
    // IFU <-> HDU Program Buffer interface
    input   logic                                   hdu2ifu_pbuf_fetch_i,       // Fetch instructions provided by Program Buffer
    output  logic                                   ifu2hdu_pbuf_rdy_o,         // Program Buffer Instruction i/f ready
    input   logic                                   hdu2ifu_pbuf_vd_i,          // Program Buffer Instruction valid
    input   logic                                   hdu2ifu_pbuf_err_i,         // Program Buffer Instruction i/f error
    input   logic [YCR_HDU_CORE_INSTR_WIDTH-1:0]   hdu2ifu_pbuf_instr_i,       // Program Buffer Instruction itself
`endif // YCR_DBG_EN

`ifdef YCR_CLKCTRL_EN
    output  logic                                   ifu2pipe_imem_txns_pnd_o,   // There are pending imem transactions
`endif // YCR_CLKCTRL_EN

    // IFU <-> IDU interface
    input   logic                                   idu2ifu_rdy_i,              // IDU ready for new data
    output  logic [`YCR_IMEM_DWIDTH-1:0]           ifu2idu_instr_o,            // IFU instruction
    output  logic                                   ifu2idu_imem_err_o,         // Instruction access fault exception
    output  logic                                   ifu2idu_err_rvi_hi_o,       // 1 - imem fault when trying to fetch second half of an unaligned RVI instruction
    output  logic                                   ifu2idu_vd_o                // IFU request
);

//------------------------------------------------------------------------------
// Local parameters declaration
//------------------------------------------------------------------------------

localparam YCR_IFU_Q_SIZE_WORD     = 8;
localparam YCR_IFU_Q_BURST_SIZE    = YCR_IFU_Q_SIZE_WORD/2;
localparam YCR_IFU_Q_SIZE_HALF     = YCR_IFU_Q_SIZE_WORD * 2;
localparam YCR_TXN_CNT_W           = 4;

localparam YCR_IFU_QUEUE_ADR_W     = $clog2(YCR_IFU_Q_SIZE_HALF);
localparam YCR_IFU_QUEUE_PTR_W     = YCR_IFU_QUEUE_ADR_W + 1;

localparam YCR_IFU_Q_FREE_H_W      = $clog2(YCR_IFU_Q_SIZE_HALF + 1);
localparam YCR_IFU_Q_FREE_W_W      = $clog2(YCR_IFU_Q_SIZE_WORD + 1);

//------------------------------------------------------------------------------
// Local types declaration
//------------------------------------------------------------------------------

//typedef enum logic {
parameter    YCR_IFU_FSM_IDLE    = 1'b0;
parameter    YCR_IFU_FSM_FETCH   = 1'b1;
//} type_ycr_ifu_fsm_e;

//typedef enum logic[1:0] {
parameter    YCR_IFU_QUEUE_WR_NONE = 2'b00;  // No write to queue
parameter    YCR_IFU_QUEUE_WR_FULL = 2'b01;  // Write 32 rdata bits to queue
parameter    YCR_IFU_QUEUE_WR_HI   = 2'b10;  // Write 16 upper rdata bits to queue
//} type_ycr_ifu_queue_wr_e;

//typedef enum logic[1:0] {
parameter    YCR_IFU_QUEUE_RD_NONE  = 2'b00; // No queue read
parameter    YCR_IFU_QUEUE_RD_HWORD = 2'b01; // Read halfword
parameter    YCR_IFU_QUEUE_RD_WORD  = 2'b10; // Read word
//} type_ycr_ifu_queue_rd_e;

`ifdef YCR_NO_DEC_STAGE
typedef enum logic[1:0] {
    YCR_BYPASS_NONE,               // No bypass
    YCR_BYPASS_RVC,                // Bypass RVC
    YCR_BYPASS_RVI_RDATA_QUEUE,    // Bypass RVI, rdata+queue
    YCR_BYPASS_RVI_RDATA           // Bypass RVI, rdata only
} type_ycr_bypass_e;
`endif // YCR_NO_DEC_STAGE

//typedef enum logic [2:0] {
    // YCR_IFU_INSTR_<UPPER_16_BITS>_<LOWER_16_BITS>
parameter     YCR_IFU_INSTR_NONE           = 3'b000 ; // No valid instruction
parameter     YCR_IFU_INSTR_RVI_HI_RVI_LO  = 3'b001 ; // Full RV32I instruction
parameter     YCR_IFU_INSTR_RVC_RVC        = 3'b010 ;
parameter     YCR_IFU_INSTR_RVI_LO_RVC     = 3'b011 ;
parameter     YCR_IFU_INSTR_RVC_RVI_HI     = 3'b100 ;
parameter     YCR_IFU_INSTR_RVI_LO_RVI_HI  = 3'b101 ;
parameter     YCR_IFU_INSTR_RVC_NV         = 3'b110 ;  // Instruction after unaligned new_pc
parameter     YCR_IFU_INSTR_RVI_LO_NV      = 3'b111 ;  // Instruction after unaligned new_pc
//} type_ycr_ifu_instr_e;

//------------------------------------------------------------------------------
// Local signals declaration
//------------------------------------------------------------------------------

// Instruction queue signals
//------------------------------------------------------------------------------

// New PC unaligned flag register
logic                               new_pc_unaligned_ff;
logic                               new_pc_unaligned_next;
logic                               new_pc_unaligned_upd;

// IMEM instruction type decoder
logic                               instr_hi_is_rvi;
logic                               instr_lo_is_rvi;
logic [2:0]                         instr_type;

// Register to store if the previous IMEM instruction had low part of RVI instruction
// in its high part
logic                               instr_hi_rvi_lo_ff;
logic                               instr_hi_rvi_lo_next;

// Queue read/write size decoders
logic [1:0]                         q_rd_size;
logic                               q_rd_vd;
logic                               q_rd_none;
logic                               q_rd_hword;
logic [1:0]                         q_wr_size;
logic                               q_wr_none;
logic                               q_wr_full;

// Write/read pointer registers
logic [YCR_IFU_QUEUE_PTR_W-1:0]    q_rptr;
logic [YCR_IFU_QUEUE_PTR_W-1:0]    q_rptr_next;
logic                               q_rptr_upd;
logic [YCR_IFU_QUEUE_PTR_W-1:0]    q_wptr;
logic [YCR_IFU_QUEUE_PTR_W-1:0]    q_wptr_next;
logic                               q_wptr_upd;

// Instruction queue control signals
logic                               q_wr_en;
logic                               q_flush_req;

// Queue data registers
logic [`YCR_IMEM_DWIDTH/2-1:0]     q_data  [YCR_IFU_Q_SIZE_HALF];
logic [`YCR_IMEM_DWIDTH/2-1:0]     q_data_head;
logic [`YCR_IMEM_DWIDTH/2-1:0]     q_data_next;

// Queue error flags registers
logic                               q_err   [YCR_IFU_Q_SIZE_HALF];
logic                               q_err_head;
logic                               q_err_next;

// Instruction queue status signals
logic                               q_is_empty;
logic                               q_has_free_slots;
logic                               q_has_1_ocpd_hw;
logic                               q_head_is_rvc;
logic                               q_head_is_rvi;
logic [YCR_IFU_Q_FREE_H_W-1:0]     q_ocpd_h;
logic [YCR_IFU_Q_FREE_H_W-1:0]     q_free_h;
logic [YCR_IFU_Q_FREE_W_W-1:0]     q_free_w;
logic [YCR_IFU_Q_FREE_W_W-1:0]     q_free_slots;

// IFU FSM signals
//------------------------------------------------------------------------------

// IFU FSM control signals
logic                               ifu_fetch_req;
logic                               ifu_stop_req;

logic                               ifu_fsm_curr;
logic                               ifu_fsm_next;
logic                               ifu_fsm_fetch;

// IMEM signals
//------------------------------------------------------------------------------

// IMEM response signals
logic                               imem_resp_ok;
logic                               imem_resp_er;
logic                               imem_resp_er_discard_pnd;
logic                               imem_resp_discard_req;
logic                               imem_resp_received;
logic                               imem_resp_vd;
logic                               imem_handshake_done;
logic  [`YCR_IMEM_BSIZE-1:0]       imem_handshake_size;

logic [15:0]                        imem_rdata_lo;
logic [31:16]                       imem_rdata_hi;

// IMEM address signals
logic                               imem_addr_upd;
logic [`YCR_XLEN-1:2]              imem_addr_ff;
logic [`YCR_XLEN-1:2]              imem_addr_h_ff;
logic                              exu2ifu_pc_new_req_h;
logic [`YCR_XLEN-1:2]              imem_addr_next;

// IMEM pending transactions counter
logic                               imem_pnd_txns_cnt_upd;
logic [YCR_TXN_CNT_W-1:0]          imem_pnd_txns_cnt;
logic [YCR_TXN_CNT_W-1:0]          imem_pnd_txns_cnt_next;
logic [YCR_TXN_CNT_W-1:0]          imem_vd_pnd_txns_cnt;
logic                               imem_pnd_txns_q_full;

// IMEM responses discard counter
logic                               imem_resp_discard_cnt_upd;
logic [YCR_TXN_CNT_W-1:0]          imem_resp_discard_cnt;
logic [YCR_TXN_CNT_W-1:0]          imem_resp_discard_cnt_next;

logic                               new_pc_req_ff;

// Instruction bypass signals
`ifdef YCR_NO_DEC_STAGE
type_ycr_bypass_e                  instr_bypass_type;
logic                               instr_bypass_vd;
`endif // YCR_NO_DEC_STAGE

//------------------------------------------------------------------------------
// Instruction queue
//------------------------------------------------------------------------------
//
 // Instruction queue consists of the following functional units:
 // - New PC unaligned flag register
 // - Instruction type decoder, including register to store if the previous
 //   IMEM instruction had low part of RVI instruction in its high part
 // - Read/write size decoders
 // - Read/write pointer registers
 // - Data and error flag registers
 // - Status logic
//

// New PC unaligned flag register
//------------------------------------------------------------------------------

assign new_pc_unaligned_upd = exu2ifu_pc_new_req_i | imem_resp_vd;

always_ff @(posedge clk, negedge rst_n) begin
    if (~rst_n) begin
        new_pc_unaligned_ff <= 1'b0;
    end else if (new_pc_unaligned_upd) begin
        new_pc_unaligned_ff <= new_pc_unaligned_next;
    end
end

assign new_pc_unaligned_next = exu2ifu_pc_new_req_i ? exu2ifu_pc_new_i[1]
                             : ~imem_resp_vd        ? new_pc_unaligned_ff
                                                    : 1'b0;

// Instruction type decoder
//------------------------------------------------------------------------------

assign instr_hi_is_rvi = &imem2ifu_rdata_i[17:16];
assign instr_lo_is_rvi = &imem2ifu_rdata_i[1:0];

always_comb begin
    instr_type = YCR_IFU_INSTR_NONE;

    if (imem_resp_ok & ~imem_resp_discard_req) begin
        if (new_pc_unaligned_ff) begin
            instr_type = instr_hi_is_rvi ? YCR_IFU_INSTR_RVI_LO_NV
                                         : YCR_IFU_INSTR_RVC_NV;
        end else begin // ~new_pc_unaligned_ff
            if (instr_hi_rvi_lo_ff) begin
                instr_type = instr_hi_is_rvi ? YCR_IFU_INSTR_RVI_LO_RVI_HI
                                             : YCR_IFU_INSTR_RVC_RVI_HI;
            end else begin // YCR_OTHER
                casez ({instr_hi_is_rvi, instr_lo_is_rvi})
                    2'b?1   : instr_type   = YCR_IFU_INSTR_RVI_HI_RVI_LO;
                    2'b00   : instr_type   = YCR_IFU_INSTR_RVC_RVC;
                    2'b10   : instr_type   = YCR_IFU_INSTR_RVI_LO_RVC;
                endcase
            end
        end
    end
end

// Register to store if the previous IMEM instruction had low part of RVI
// instruction in its high part
//------------------------------------------------------------------------------

always_ff @(posedge clk, negedge rst_n) begin
    if (~rst_n) begin
        instr_hi_rvi_lo_ff <= 1'b0;
    end else begin
        if (exu2ifu_pc_new_req_i) begin
            instr_hi_rvi_lo_ff <= 1'b0;
        end else if (imem_resp_vd) begin
            instr_hi_rvi_lo_ff <= instr_hi_rvi_lo_next;
        end
    end
end

assign instr_hi_rvi_lo_next = (instr_type == YCR_IFU_INSTR_RVI_LO_NV)
                            | (instr_type == YCR_IFU_INSTR_RVI_LO_RVI_HI)
                            | (instr_type == YCR_IFU_INSTR_RVI_LO_RVC);

// Queue write/read size decoders
//------------------------------------------------------------------------------

// Queue read size decoder
assign q_rd_vd    = ~q_is_empty & ifu2idu_vd_o & idu2ifu_rdy_i;
assign q_rd_hword = q_head_is_rvc | q_err_head
`ifdef YCR_NO_DEC_STAGE
                  | (q_head_is_rvi & instr_bypass_vd)
`endif // YCR_NO_DEC_STAGE
                  ;
assign q_rd_size  = ~q_rd_vd   ? YCR_IFU_QUEUE_RD_NONE
                  : q_rd_hword ? YCR_IFU_QUEUE_RD_HWORD
                               : YCR_IFU_QUEUE_RD_WORD;
assign q_rd_none  = (q_rd_size == YCR_IFU_QUEUE_RD_NONE);

// Queue write size decoder
always_comb begin
    q_wr_size = YCR_IFU_QUEUE_WR_NONE;
    if (~imem_resp_discard_req) begin
        if (imem_resp_ok) begin
`ifdef YCR_NO_DEC_STAGE
            case (instr_type)
                YCR_IFU_INSTR_NONE         : q_wr_size = YCR_IFU_QUEUE_WR_NONE;
                YCR_IFU_INSTR_RVI_LO_NV    : q_wr_size = YCR_IFU_QUEUE_WR_HI;
                YCR_IFU_INSTR_RVC_NV       : q_wr_size = (instr_bypass_vd & idu2ifu_rdy_i)
                                                        ? YCR_IFU_QUEUE_WR_NONE
                                                        : YCR_IFU_QUEUE_WR_HI;
                YCR_IFU_INSTR_RVI_HI_RVI_LO: q_wr_size = (instr_bypass_vd & idu2ifu_rdy_i)
                                                        ? YCR_IFU_QUEUE_WR_NONE
                                                        : YCR_IFU_QUEUE_WR_FULL;
                YCR_IFU_INSTR_RVC_RVC,
                YCR_IFU_INSTR_RVI_LO_RVC,
                YCR_IFU_INSTR_RVC_RVI_HI,
                YCR_IFU_INSTR_RVI_LO_RVI_HI: q_wr_size = (instr_bypass_vd & idu2ifu_rdy_i)
                                                        ? YCR_IFU_QUEUE_WR_HI
                                                        : YCR_IFU_QUEUE_WR_FULL;
            endcase // instr_type
`else // YCR_NO_DEC_STAGE
            case (instr_type)
                YCR_IFU_INSTR_NONE         : q_wr_size = YCR_IFU_QUEUE_WR_NONE;
                YCR_IFU_INSTR_RVC_NV,
                YCR_IFU_INSTR_RVI_LO_NV    : q_wr_size = YCR_IFU_QUEUE_WR_HI;
                default                     : q_wr_size = YCR_IFU_QUEUE_WR_FULL;
            endcase // instr_type
`endif // YCR_NO_DEC_STAGE
        end else if (imem_resp_er) begin
            q_wr_size = YCR_IFU_QUEUE_WR_FULL;
        end // imem_resp_er
    end // ~imem_resp_discard_req
end

assign q_wr_none   = (q_wr_size == YCR_IFU_QUEUE_WR_NONE);
assign q_wr_full   = (q_wr_size == YCR_IFU_QUEUE_WR_FULL);

// Write/read pointer registers
//------------------------------------------------------------------------------

assign q_flush_req = exu2ifu_pc_new_req_i | pipe2ifu_stop_fetch_i;

// Queue write pointer register
assign q_wptr_upd  = q_flush_req | ~q_wr_none;

always_ff @(posedge clk, negedge rst_n) begin
    if (~rst_n) begin
        q_wptr <= '0;
    end else if (q_wptr_upd) begin
        q_wptr <= q_wptr_next;
    end
end

assign q_wptr_next = q_flush_req ? '0
                   : ~q_wr_none  ? q_wptr + (q_wr_full ? 2'd2 : 1'b1)
                                 : q_wptr;

// Queue read pointer register
assign q_rptr_upd  = q_flush_req | ~q_rd_none;

always_ff @(posedge clk, negedge rst_n) begin
    if (~rst_n) begin
        q_rptr <= '0;
    end else if (q_rptr_upd) begin
        q_rptr <= q_rptr_next;
    end
end

assign q_rptr_next = q_flush_req ? '0
                   : ~q_rd_none  ? q_rptr + (q_rd_hword ? 1'b1 : 2'd2)
                                 : q_rptr;

// Queue data and error flag registers
//------------------------------------------------------------------------------

assign imem_rdata_hi = imem2ifu_rdata_i[31:16];
assign imem_rdata_lo = imem2ifu_rdata_i[15:0];

assign q_wr_en = imem_resp_vd & ~q_flush_req;

always_ff @(posedge clk, negedge rst_n) begin
    if (~rst_n) begin
     `ifdef YCR_MPRF_RST_EN // Two dimensional array init not allowed in YOSYS - cp.13
        q_data  <= '{YCR_IFU_Q_SIZE_HALF{'0}};
        q_err   <= '{YCR_IFU_Q_SIZE_HALF{1'b0}};
     `endif
    end else if (q_wr_en) begin
        case (q_wr_size)
            YCR_IFU_QUEUE_WR_HI    : begin
                q_data[YCR_IFU_QUEUE_ADR_W'(q_wptr)]         <= imem_rdata_hi;
                q_err [YCR_IFU_QUEUE_ADR_W'(q_wptr)]         <= imem_resp_er;
            end
            YCR_IFU_QUEUE_WR_FULL  : begin
                q_data[YCR_IFU_QUEUE_ADR_W'(q_wptr)]         <= imem_rdata_lo;
                q_err [YCR_IFU_QUEUE_ADR_W'(q_wptr)]         <= imem_resp_er;
                q_data[YCR_IFU_QUEUE_ADR_W'(q_wptr + 1'b1)]  <= imem_rdata_hi;
                q_err [YCR_IFU_QUEUE_ADR_W'(q_wptr + 1'b1)]  <= imem_resp_er;
            end
        endcase
    end
end

assign q_data_head = q_data [YCR_IFU_QUEUE_ADR_W'(q_rptr)];
assign q_data_next = q_data [YCR_IFU_QUEUE_ADR_W'(q_rptr + 1'b1)];
assign q_err_head  = q_err  [YCR_IFU_QUEUE_ADR_W'(q_rptr)];
assign q_err_next  = q_err  [YCR_IFU_QUEUE_ADR_W'(q_rptr + 1'b1)];

// Queue status logic
//------------------------------------------------------------------------------

assign q_ocpd_h         = YCR_IFU_Q_FREE_H_W'(q_wptr - q_rptr);
assign q_free_h    = YCR_IFU_Q_FREE_H_W'(YCR_IFU_Q_SIZE_HALF - (q_wptr - q_rptr));
assign q_free_w    = YCR_IFU_Q_FREE_W_W'(q_free_h >> 1'b1);

assign q_is_empty       = (q_rptr == q_wptr);
assign q_has_free_slots = (YCR_TXN_CNT_W'(q_free_w) > imem_vd_pnd_txns_cnt);
assign q_has_1_ocpd_hw  = (q_ocpd_h == YCR_IFU_Q_FREE_H_W'(1));
assign q_free_slots     = (q_has_free_slots) ? (YCR_TXN_CNT_W'(q_free_w) - YCR_TXN_CNT_W'(imem_vd_pnd_txns_cnt)) : 'h0;

assign q_head_is_rvi    = &(q_data_head[1:0]);
assign q_head_is_rvc    = ~q_head_is_rvi;

//------------------------------------------------------------------------------
// IFU FSM
//------------------------------------------------------------------------------

// IFU FSM control signals
assign ifu_fetch_req = exu2ifu_pc_new_req_i & ~pipe2ifu_stop_fetch_i;
assign ifu_stop_req  = pipe2ifu_stop_fetch_i
                     | (imem_resp_er_discard_pnd & ~exu2ifu_pc_new_req_i);

always_ff @(posedge clk, negedge rst_n) begin
    if (~rst_n) begin
        ifu_fsm_curr <= YCR_IFU_FSM_IDLE;
    end else begin
        ifu_fsm_curr <= ifu_fsm_next;
    end
end

always_comb begin
    case (ifu_fsm_curr)
        YCR_IFU_FSM_IDLE   : begin
            ifu_fsm_next = ifu_fetch_req ? YCR_IFU_FSM_FETCH
                                         : YCR_IFU_FSM_IDLE;
        end
        YCR_IFU_FSM_FETCH  : begin
            ifu_fsm_next = ifu_stop_req  ? YCR_IFU_FSM_IDLE
                                         : YCR_IFU_FSM_FETCH;
        end
    endcase
end

assign ifu_fsm_fetch = (ifu_fsm_curr == YCR_IFU_FSM_FETCH);

//------------------------------------------------------------------------------
// IFU <-> IMEM interface
//------------------------------------------------------------------------------
//
 // IFU <-> IMEM interface consists of the following functional units:
 // - IMEM response logic
 // - IMEM address register
 // - Pending IMEM transactions counter
 // - IMEM discard responses counter
 // - IFU <-> IMEM interface output signals
//

// IMEM response logic
//------------------------------------------------------------------------------

assign imem_resp_er             = (imem2ifu_resp_i == YCR_MEM_RESP_RDY_ER);
assign imem_resp_ok             = (imem2ifu_resp_i == YCR_MEM_RESP_RDY_OK);
assign imem_resp_received       = imem_resp_ok | imem_resp_er;
assign imem_resp_vd             = imem_resp_received & ~imem_resp_discard_req;
assign imem_resp_er_discard_pnd = imem_resp_er & ~imem_resp_discard_req;

assign imem_handshake_done      = ifu2imem_req_o & imem2ifu_req_ack_i;

assign imem_handshake_size      = (imem_handshake_done) ? ifu2imem_bl_o : 'h0;

// IMEM address register
//------------------------------------------------------------------------------

assign imem_addr_upd = imem_handshake_done | exu2ifu_pc_new_req_i;

// If request is already rised and new address change request received, the
// register it in imem_addr_h_ff
always_ff @(posedge clk, negedge rst_n) begin
    if (~rst_n) begin
        imem_addr_ff <= '0;
	exu2ifu_pc_new_req_h <= 1'b0;
    end else if (imem_addr_upd) begin
	if(ifu2imem_req_o && exu2ifu_pc_new_req_i) begin // Clash case , Pending Req and New Req
	   exu2ifu_pc_new_req_h <= 1'b1;
           imem_addr_h_ff       <= exu2ifu_pc_new_i[`YCR_XLEN-1:2];
        end else if(exu2ifu_pc_new_req_h) begin // Wait for Req Done
           imem_addr_ff         <= imem_addr_h_ff;
	   exu2ifu_pc_new_req_h <= 1'b0;
        end else begin
           imem_addr_ff <= imem_addr_next;
	end
    end 
end


// Generate response pending, To avoid back-to back request pipe lineing - Dinesh A
// Added this to block the timing loop imem_addr => req => reg_ack => req =>
logic imem_resp_pending;
always_ff @(posedge clk, negedge rst_n) begin
    if (~rst_n) begin
        imem_resp_pending <= '0;
    end else if (ifu2imem_req_o & imem2ifu_req_ack_i) begin
            imem_resp_pending <= 1'b1;
    end else if(imem_pnd_txns_cnt == 'h0) begin
            imem_resp_pending <= 1'b0;
    end
end

assign imem_addr_next = exu2ifu_pc_new_req_i ? exu2ifu_pc_new_i[`YCR_XLEN-1:2]
                                             : {imem_addr_ff[`YCR_XLEN-1:2] + imem_handshake_size};

// Pending IMEM transactions counter
//------------------------------------------------------------------------------
// Pending IMEM transactions occur if IFU request has been acknowledged, but
// response comes in the next cycle or later

assign imem_pnd_txns_cnt_upd  = imem_handshake_done ^ imem_resp_received;

always_ff @(posedge clk, negedge rst_n) begin
    if (~rst_n) begin
        imem_pnd_txns_cnt <= '0;
    end else if (imem_pnd_txns_cnt_upd) begin
        imem_pnd_txns_cnt <= imem_pnd_txns_cnt_next;
    end
end

assign imem_pnd_txns_cnt_next = imem_pnd_txns_cnt + (imem_handshake_size - imem_resp_received);
assign imem_pnd_txns_q_full   = &imem_pnd_txns_cnt;

// IMEM discard responses counter
//------------------------------------------------------------------------------
// IMEM instructions should be discarded in the following 2 cases:
// 1. New PC is requested by jump, branch, mret or other instruction
// 2. IMEM response was erroneous and not discarded
//
// In both cases the number of instructions to be discarded equals to the number
// of pending instructions.
// In the 1st case we don't need all the instructions that haven't been fetched
// yet, since the PC has changed.
// In the 2nd case, since the IMEM responce was erroneous there is no guarantee
// that subsequent IMEM instructions would be valid.

assign imem_resp_discard_cnt_upd = exu2ifu_pc_new_req_i | imem_resp_er | exu2ifu_pc_new_req_h 
                                 | (imem_resp_ok & imem_resp_discard_req);

always_ff @(posedge clk, negedge rst_n) begin
    if (~rst_n) begin
        imem_resp_discard_cnt <= '0;
    end else if (imem_resp_discard_cnt_upd) begin
        imem_resp_discard_cnt <= imem_resp_discard_cnt_next;
    end
end

assign imem_resp_discard_cnt_next = (exu2ifu_pc_new_req_i | imem_resp_er_discard_pnd | exu2ifu_pc_new_req_h)
                                  ? imem_pnd_txns_cnt_next
                                  : imem_resp_discard_cnt - 1'b1;

assign imem_vd_pnd_txns_cnt  = imem_pnd_txns_cnt - imem_resp_discard_cnt;
assign imem_resp_discard_req = |imem_resp_discard_cnt;

// IFU <-> IMEM interface output signals
//------------------------------------------------------------------------------


// Check current request is map to non-volatile memory range
wire  imem_addr_range = ((ifu2imem_addr_o & YCR_DCACHE_ADDR_MASK) == YCR_ICACHE_ADDR_PATTERN);
wire  q_free_burst_avail = (q_free_slots >= YCR_IFU_Q_BURST_SIZE);

// Bug fix: Do avoid abort request removal, we have qualified it with imem_resp_discard_cnt_upd
// For the imem address space (0x0000_00000 to 0x07FFF_FFFF), generate request only if there is atleast
// 1 burst free space, For outsize imem address range generate request when
// ever there is a atleast one free space
assign ifu2imem_req_o  = (imem_addr_range) ? ifu_fsm_fetch & ~imem_pnd_txns_q_full & q_free_burst_avail & !(imem_resp_pending) :
                                             ifu_fsm_fetch & ~imem_pnd_txns_q_full & q_has_free_slots   & !(imem_resp_pending) ;
assign ifu2imem_addr_o = {imem_addr_ff, 2'b00};
// Currently only imem support burst access, rest of
// the interface linke dmem,tcm,timer support single
// access 
assign ifu2imem_bl_o = (((ifu2imem_addr_o & YCR_DCACHE_ADDR_MASK) == YCR_ICACHE_ADDR_PATTERN) && (q_free_slots >= YCR_IFU_Q_BURST_SIZE)) ? YCR_IFU_Q_BURST_SIZE  :  'h1;

assign ifu2imem_cmd_o  = YCR_MEM_CMD_RD;

`ifdef YCR_CLKCTRL_EN
assign ifu2pipe_imem_txns_pnd_o = |imem_pnd_txns_cnt;
`endif // YCR_CLKCTRL_EN

//------------------------------------------------------------------------------
// IFU <-> IDU interface
//------------------------------------------------------------------------------
//
 // IFU <-> IDU interface consists of the following functional units:
 // - Instruction bypass type decoder
 // - IFU <-> IDU status signals
 // - Output instruction multiplexer
//

`ifdef YCR_NO_DEC_STAGE

// Instruction bypass type decoder
//------------------------------------------------------------------------------

assign instr_bypass_vd  = (instr_bypass_type != YCR_BYPASS_NONE);

always_comb begin
    instr_bypass_type    = YCR_BYPASS_NONE;

    if (imem_resp_vd) begin
        if (q_is_empty) begin
            case (instr_type)
                YCR_IFU_INSTR_RVC_NV,
                YCR_IFU_INSTR_RVC_RVC,
                YCR_IFU_INSTR_RVI_LO_RVC       : begin
                    instr_bypass_type = YCR_BYPASS_RVC;
                end
                YCR_IFU_INSTR_RVI_HI_RVI_LO    : begin
                    instr_bypass_type = YCR_BYPASS_RVI_RDATA;
                end
                default : begin end
            endcase // instr_type
        end else if (q_has_1_ocpd_hw & q_head_is_rvi) begin
            if (instr_hi_rvi_lo_ff) begin
                instr_bypass_type = YCR_BYPASS_RVI_RDATA_QUEUE;
            end
        end
    end // imem_resp_vd
end

// IFU <-> IDU interface status signals
//------------------------------------------------------------------------------

always_comb begin
    ifu2idu_vd_o         = 1'b0;
    ifu2idu_imem_err_o   = 1'b0;
    ifu2idu_err_rvi_hi_o = 1'b0;

    if (ifu_fsm_fetch | ~q_is_empty) begin
        if (instr_bypass_vd) begin
            ifu2idu_vd_o          = 1'b1;
            ifu2idu_imem_err_o    = (instr_bypass_type == YCR_BYPASS_RVI_RDATA_QUEUE)
                                  ? (imem_resp_er | q_err_head)
                                  : imem_resp_er;
            ifu2idu_err_rvi_hi_o  = (instr_bypass_type == YCR_BYPASS_RVI_RDATA_QUEUE) & imem_resp_er;
        end else if (~q_is_empty) begin
            if (q_has_1_ocpd_hw) begin
                ifu2idu_vd_o         = q_head_is_rvc | q_err_head;
                ifu2idu_imem_err_o   = q_err_head;
                ifu2idu_err_rvi_hi_o = ~q_err_head & q_head_is_rvi & q_err_next;
            end else begin
                ifu2idu_vd_o         = 1'b1;
                ifu2idu_imem_err_o   = q_err_head ? 1'b1 : (q_head_is_rvi & q_err_next);
            end
        end // ~q_is_empty
    end
`ifdef YCR_DBG_EN
    if (hdu2ifu_pbuf_fetch_i) begin
        ifu2idu_vd_o          = hdu2ifu_pbuf_vd_i;
        ifu2idu_imem_err_o    = hdu2ifu_pbuf_err_i;
    end
`endif // YCR_DBG_EN
end

// Output instruction multiplexer
//------------------------------------------------------------------------------

always_comb begin
    case (instr_bypass_type)
        YCR_BYPASS_RVC            : begin
            ifu2idu_instr_o = `YCR_IMEM_DWIDTH'(new_pc_unaligned_ff ? imem_rdata_hi
                                                                     : imem_rdata_lo);
        end
        YCR_BYPASS_RVI_RDATA      : begin
            ifu2idu_instr_o = imem2ifu_rdata_i;
        end
        YCR_BYPASS_RVI_RDATA_QUEUE: begin
            ifu2idu_instr_o = {imem_rdata_lo, q_data_head};
        end
        default                    : begin
            ifu2idu_instr_o = `YCR_IMEM_DWIDTH'(q_head_is_rvc ? q_data_head
                                                               : {q_data_next, q_data_head});
        end
    endcase // instr_bypass_type
`ifdef YCR_DBG_EN
    if (hdu2ifu_pbuf_fetch_i) begin
        ifu2idu_instr_o = `YCR_IMEM_DWIDTH'({'0, hdu2ifu_pbuf_instr_i});
    end
`endif // YCR_DBG_EN
end

`else   // YCR_NO_DEC_STAGE

// IFU <-> IDU interface status signals
//------------------------------------------------------------------------------

always_comb begin
    ifu2idu_vd_o          = 1'b0;
    ifu2idu_imem_err_o    = 1'b0;
    ifu2idu_err_rvi_hi_o  = 1'b0;
    if (~q_is_empty) begin
        if (q_has_1_ocpd_hw) begin
            ifu2idu_vd_o          = q_head_is_rvc | q_err_head;
            ifu2idu_imem_err_o    = q_err_head;
        end else begin
            ifu2idu_vd_o          = 1'b1;
            ifu2idu_imem_err_o    = q_err_head ? 1'b1 : (q_head_is_rvi & q_err_next);
            ifu2idu_err_rvi_hi_o  = ~q_err_head & q_head_is_rvi & q_err_next;
        end
    end // ~q_is_empty
`ifdef YCR_DBG_EN
    if (hdu2ifu_pbuf_fetch_i) begin
        ifu2idu_vd_o          = hdu2ifu_pbuf_vd_i;
        ifu2idu_imem_err_o    = hdu2ifu_pbuf_err_i;
    end
`endif // YCR_DBG_EN
end

// Output instruction multiplexer
//------------------------------------------------------------------------------

always_comb begin
    ifu2idu_instr_o = q_head_is_rvc ? `YCR_IMEM_DWIDTH'(q_data_head)
                                    : {q_data_next, q_data_head};
`ifdef YCR_DBG_EN
    if (hdu2ifu_pbuf_fetch_i) begin
        ifu2idu_instr_o = `YCR_IMEM_DWIDTH'({'0, hdu2ifu_pbuf_instr_i});
    end
`endif // YCR_DBG_EN
end

`endif  // YCR_NO_DEC_STAGE

`ifdef YCR_DBG_EN
assign ifu2hdu_pbuf_rdy_o = idu2ifu_rdy_i;
`endif // YCR_DBG_EN

`ifdef YCR_TRGT_SIMULATION

//------------------------------------------------------------------------------
// Assertions
//------------------------------------------------------------------------------

// X checks

YCR_SVA_IFU_XCHECK : assert property (
    @(negedge clk) disable iff (~rst_n)
    !$isunknown({imem2ifu_req_ack_i, idu2ifu_rdy_i, exu2ifu_pc_new_req_i})
    ) else $error("IFU Error: unknown values");

YCR_SVA_IFU_XCHECK_REQ : assert property (
    @(negedge clk) disable iff (~rst_n)
    ifu2imem_req_o |-> !$isunknown({ifu2imem_addr_o, ifu2imem_cmd_o})
    ) else $error("IFU Error: unknown {ifu2imem_addr_o, ifu2imem_cmd_o}");

// Behavior checks
`ifndef VERILATOR
YCR_SVA_IFU_DRC_UNDERFLOW : assert property (
    @(negedge clk) disable iff (~rst_n)
    ~imem_resp_discard_req |=> ~(imem_resp_discard_cnt == YCR_TXN_CNT_W'('1))
    ) else $error("IFU Error: imem_resp_discard_cnt underflow");
`endif // VERILATOR
YCR_SVA_IFU_DRC_RANGE : assert property (
    @(negedge clk) disable iff (~rst_n)
    (imem_resp_discard_cnt >= 0) & (imem_resp_discard_cnt <= imem_pnd_txns_cnt)
    ) else $error("IFU Error: imem_resp_discard_cnt out of range");

YCR_SVA_IFU_QUEUE_OVF : assert property (
    @(negedge clk) disable iff (~rst_n)
    (q_ocpd_h >= YCR_IFU_Q_FREE_H_W'(YCR_IFU_Q_SIZE_HALF-1)) |->
    ((q_ocpd_h == YCR_IFU_Q_FREE_H_W'(YCR_IFU_Q_SIZE_HALF-1)) ? (q_wr_size != YCR_IFU_QUEUE_WR_FULL)
                                                                : (q_wr_size == YCR_IFU_QUEUE_WR_NONE))
    ) else $error("IFU Error: queue overflow");

`ifndef VERILATOR
YCR_SVA_IFU_IMEM_ERR_BEH : assert property (
    @(negedge clk) disable iff (~rst_n)
    (imem_resp_er & ~imem_resp_discard_req & ~exu2ifu_pc_new_req_i) |=>
    (ifu_fsm_curr == YCR_IFU_FSM_IDLE) & (imem_resp_discard_cnt == imem_pnd_txns_cnt)
    ) else $error("IFU Error: incorrect behavior after memory error");

YCR_SVA_IFU_NEW_PC_REQ_BEH : assert property (
    @(negedge clk) disable iff (~rst_n)
    exu2ifu_pc_new_req_i |=> q_is_empty
    ) else $error("IFU Error: incorrect behavior after exu2ifu_pc_new_req_i");
`endif // VERILATOR
YCR_SVA_IFU_IMEM_ADDR_ALIGNED : assert property (
    @(negedge clk) disable iff (~rst_n)
    ifu2imem_req_o |-> ~|ifu2imem_addr_o[1:0]
    ) else $error("IFU Error: unaligned IMEM access");

`ifndef VERILATOR
YCR_SVA_IFU_STOP_FETCH : assert property (
    @(negedge clk) disable iff (~rst_n)
    pipe2ifu_stop_fetch_i |=> (ifu_fsm_curr == YCR_IFU_FSM_IDLE)
    ) else $error("IFU Error: fetch not stopped");
`endif // VERILATOR
YCR_SVA_IFU_IMEM_FAULT_RVI_HI : assert property (
    @(negedge clk) disable iff (~rst_n)
    ifu2idu_err_rvi_hi_o |-> ifu2idu_imem_err_o
    ) else $error("IFU Error: ifu2idu_imem_err_o == 0");

`endif // YCR_TRGT_SIMULATION

endmodule : ycr_pipe_ifu
