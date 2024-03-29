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
      yifive Memory-mapped Timer                                          
                                                                          
                                                                          
      Description:                                                        
         Memory-mapped Timer                                              
                                                                          
      To Do:                                                              
        nothing                                                           
                                                                          
      Author(s):                                                          
          - syntacore, https://github.com/syntacore/scr1                   
          - Dinesh Annayya <dinesha@opencores.org>               
          - Dinesh Annayya <dinesh@siplusplus.com>               
                                                                          
      Revision :                                                          
         v0:    Jan 2021- Initial version picked from                     
                https://github.com/syntacore/scr1                         
         v1:    June 7, 2021, Dinesh A                                    
                 opentool(iverilog/yosys) related cleanup                 
         v2:    18 July 2021 - Dinesh A                                   
              A.To break the timing path, input and output path are       
                 registered                                               
              B.Spilt the 64 bit adder into two 32 bit adder with         
                taking care ofoverflow                                    
         v3:    18 Jan 2024 - Dinesh A                                    
              Bug Fix: timer roll over at 32 bit boundary                 
                                                                          
 ***************************************************************************************************/


`include "ycr_arch_description.svh"
`include "ycr_memif.svh"

module ycr_timer (
    // Common
    input   logic                                   rst_n,
    input   logic                                   clk,
    input   logic                                   rtc_clk,

    // Memory interface
    input   logic                                   dmem_req,
    input   logic                                   dmem_cmd,
    input   logic [1:0]                             dmem_width,
    input   logic [`YCR_DMEM_AWIDTH-1:0]            dmem_addr,
    input   logic [`YCR_DMEM_DWIDTH-1:0]            dmem_wdata,
    output  logic                                   dmem_req_ack,
    output  logic [`YCR_DMEM_DWIDTH-1:0]            dmem_rdata,
    output  logic [1:0]                             dmem_resp,

    // Timer interface
    output  logic [63:0]                            timer_val,
    output  logic [3:0]                             timer_irq,

    output  logic [3:0]                             soft_irq,

    output  logic [31:0]                            riscv_glbl_cfg,
    output  logic [23:0]                            riscv_clk_cfg,
    output  logic [7:0]                             riscv_sleep,    // riscv core sleep level signal
    input   logic [7:0]                             riscv_wakeup    // riscv core wakeup trigger
);

//-------------------------------------------------------------------------------
// Local parameters declaration
//-------------------------------------------------------------------------------
localparam int unsigned YCR_TIMER_ADDR_WIDTH                               = 8;
localparam logic [YCR_TIMER_ADDR_WIDTH-1:0] YCR_TIMER_CONTROL             = 8'h0;
localparam logic [YCR_TIMER_ADDR_WIDTH-1:0] YCR_TIMER_DIVIDER             = 8'h4;
localparam logic [YCR_TIMER_ADDR_WIDTH-1:0] YCR_TIMER_MTIMELO             = 8'h8;
localparam logic [YCR_TIMER_ADDR_WIDTH-1:0] YCR_TIMER_MTIMEHI             = 8'hC;

localparam logic [YCR_TIMER_ADDR_WIDTH-1:0] YCR_TIMER_MTIMECMP0LO          = 8'h10;
localparam logic [YCR_TIMER_ADDR_WIDTH-1:0] YCR_TIMER_MTIMECMP0HI          = 8'h14;

localparam logic [YCR_TIMER_ADDR_WIDTH-1:0] YCR_TIMER_MTIMECMP1LO          = 8'h18;
localparam logic [YCR_TIMER_ADDR_WIDTH-1:0] YCR_TIMER_MTIMECMP1HI          = 8'h1C;

localparam logic [YCR_TIMER_ADDR_WIDTH-1:0] YCR_TIMER_MTIMECMP2LO          = 8'h20;
localparam logic [YCR_TIMER_ADDR_WIDTH-1:0] YCR_TIMER_MTIMECMP2HI          = 8'h24;

localparam logic [YCR_TIMER_ADDR_WIDTH-1:0] YCR_TIMER_MTIMECMP3LO          = 8'h28;
localparam logic [YCR_TIMER_ADDR_WIDTH-1:0] YCR_TIMER_MTIMECMP3HI          = 8'h2C;

// MSIP register for inter processor software interrupt generation
localparam logic [YCR_TIMER_ADDR_WIDTH-1:0] YCR_MSIP_HART0                 = 8'h30;
localparam logic [YCR_TIMER_ADDR_WIDTH-1:0] YCR_MSIP_HART1                 = 8'h34;
localparam logic [YCR_TIMER_ADDR_WIDTH-1:0] YCR_MSIP_HART2                 = 8'h38;
localparam logic [YCR_TIMER_ADDR_WIDTH-1:0] YCR_MSIP_HART3                 = 8'h3C;


localparam logic [YCR_TIMER_ADDR_WIDTH-1:0] YCR_GLBL_CONTROL              = 8'h40;
localparam logic [YCR_TIMER_ADDR_WIDTH-1:0] YCR_CLK_CONTROL               = 8'h44;

localparam int unsigned YCR_TIMER_CONTROL_EN_OFFSET                        = 0;
localparam int unsigned YCR_TIMER_CONTROL_CLKSRC_OFFSET                    = 1;
localparam int unsigned YCR_TIMER_DIVIDER_WIDTH                            = 10;

//-------------------------------------------------------------------------------
// Local signals declaration
//-------------------------------------------------------------------------------
logic [63:0]                                        mtime_reg;
logic                                               mtime_32b_ovr; // Indicate 32b Ovr flow
logic [63:0]                                        mtime_new;

logic [63:0]                                        mtimecmp0_reg;
logic [63:0]                                        mtimecmp0_new;
logic [63:0]                                        mtimecmp1_reg;
logic [63:0]                                        mtimecmp1_new;
logic [63:0]                                        mtimecmp2_reg;
logic [63:0]                                        mtimecmp2_new;
logic [63:0]                                        mtimecmp3_reg;
logic [63:0]                                        mtimecmp3_new;

logic [3:0]                                         mtimecmplo_up;
logic [3:0]                                         mtimecmphi_up;
logic [3:0]                                         time_cmp_flag;

logic [3:0]                                         msip_hart_up;

logic                                               timer_en;
logic                                               timer_clksrc_rtc;
logic [YCR_TIMER_DIVIDER_WIDTH-1:0]                timer_div;

logic                                               control_up;
logic                                               divider_up;
logic                                               mtimelo_up;
logic                                               mtimehi_up;
logic                                               glbl_cfg_up;
logic                                               clk_cfg_up;

logic                                               dmem_req_valid;

logic [3:0]                                         rtc_sync;
logic                                               rtc_ext_pulse;
logic [YCR_TIMER_DIVIDER_WIDTH-1:0]                timeclk_cnt;
logic                                               timeclk_cnt_en;
logic                                               time_posedge;

//-------------------------------------------------------------------------------
// Registers
//-------------------------------------------------------------------------------

// CONTROL
always_ff @(posedge clk, negedge rst_n) begin
    if (~rst_n) begin
        timer_en            <= 1'b1;
        timer_clksrc_rtc    <= 1'b0;
    end else begin
        if (control_up) begin
            timer_en            <= dmem_wdata[YCR_TIMER_CONTROL_EN_OFFSET];
            timer_clksrc_rtc    <= dmem_wdata[YCR_TIMER_CONTROL_CLKSRC_OFFSET];
        end
    end
end

// DIVIDER
always_ff @(posedge clk, negedge rst_n) begin
    if (~rst_n) begin
        timer_div   <= '0;
    end else begin
        if (divider_up) begin
            timer_div   <= dmem_wdata[YCR_TIMER_DIVIDER_WIDTH-1:0];
        end
    end
end

// MTIME
assign time_posedge = (timeclk_cnt_en & (timeclk_cnt == 0));

always_comb begin
    mtime_new   = mtime_reg;
    if (time_posedge) begin
        mtime_new[31:0]    = mtime_reg[31:0] + 1'b1;
        mtime_new[63:32]   = mtime_32b_ovr ? (mtime_new[63:32] + 1'b1) : mtime_new[63:32];
    end else if (mtimelo_up) begin
        mtime_new[31:0]     = dmem_wdata;
    end else if (mtimehi_up) begin
        mtime_new[63:32]    = dmem_wdata;
    end
end

always_ff @(posedge clk, negedge rst_n) begin
    if (~rst_n) begin
        mtime_reg   <= '0;
	mtime_32b_ovr <= '0;
    end else begin
        if (time_posedge | mtimelo_up | mtimehi_up) begin
            mtime_reg   <= mtime_new;
	    mtime_32b_ovr <= &mtime_new[31:0]; // Indicate 32B Overflow in next increment by check all one
        end
    end
end

//--------------------------------------
// MTIMECMP-0
//--------------------------------------
always_comb begin
    mtimecmp0_new    = mtimecmp0_reg;
    if (mtimecmplo_up[0]) begin
        mtimecmp0_new[31:0]  = dmem_wdata;
    end
    if (mtimecmphi_up[0]) begin
        mtimecmp0_new[63:32] = dmem_wdata;
    end
end

always_ff @(posedge clk, negedge rst_n) begin
    if (~rst_n) begin
        mtimecmp0_reg    <= '0;
    end else begin
        if (mtimecmplo_up[0] | mtimecmphi_up[0]) begin
            mtimecmp0_reg    <= mtimecmp0_new;
        end
    end
end

//-------------------------------------------------------------------
// Timer Interrupt Generation
//-------------------------------------------------------------------
assign time_cmp_flag[0] = (mtime_reg >= ((mtimecmplo_up[0] | mtimecmphi_up[0]) ? mtimecmp0_new : mtimecmp0_reg));

always_ff @(posedge clk, negedge rst_n) begin
    if (~rst_n) begin
        timer_irq[0]   <= 1'b0;
    end else begin
        if (~timer_irq[0]) begin
            timer_irq[0]   <= time_cmp_flag[0];
        end else begin // 1'b1
            if (mtimecmplo_up[0] | mtimecmphi_up[0]) begin
                timer_irq[0]   <= time_cmp_flag[0];
            end
        end
    end
end

//--------------------------------------
// MTIMECMP-1
//--------------------------------------
always_comb begin
    mtimecmp1_new    = mtimecmp1_reg;
    if (mtimecmplo_up[1]) begin
        mtimecmp1_new[31:0]  = dmem_wdata;
    end
    if (mtimecmphi_up[1]) begin
        mtimecmp1_new[63:32] = dmem_wdata;
    end
end

always_ff @(posedge clk, negedge rst_n) begin
    if (~rst_n) begin
        mtimecmp1_reg    <= '0;
    end else begin
        if (mtimecmplo_up[1] | mtimecmphi_up[1]) begin
            mtimecmp1_reg    <= mtimecmp1_new;
        end
    end
end

//----------------------------------------------
// Timer Interrupt Generation
//----------------------------------------------
assign time_cmp_flag[1] = (mtime_reg >= ((mtimecmplo_up[1] | mtimecmphi_up[1]) ? mtimecmp1_new : mtimecmp1_reg));

always_ff @(posedge clk, negedge rst_n) begin
    if (~rst_n) begin
        timer_irq[1]   <= 1'b0;
    end else begin
        if (~timer_irq[1]) begin
            timer_irq[1]   <= time_cmp_flag[1];
        end else begin // 1'b1
            if (mtimecmplo_up[1] | mtimecmphi_up[1]) begin
                timer_irq[1]   <= time_cmp_flag[1];
            end
        end
    end
end

//--------------------------------------
// MTIMECMP-2
//--------------------------------------
always_comb begin
    mtimecmp2_new    = mtimecmp2_reg;
    if (mtimecmplo_up[2]) begin
        mtimecmp2_new[31:0]  = dmem_wdata;
    end
    if (mtimecmphi_up[2]) begin
        mtimecmp2_new[63:32] = dmem_wdata;
    end
end

always_ff @(posedge clk, negedge rst_n) begin
    if (~rst_n) begin
        mtimecmp2_reg    <= '0;
    end else begin
        if (mtimecmplo_up[2] | mtimecmphi_up[2]) begin
            mtimecmp2_reg    <= mtimecmp2_new;
        end
    end
end

//----------------------------------------------
// Timer Interrupt Generation
//----------------------------------------------
assign time_cmp_flag[2] = (mtime_reg >= ((mtimecmplo_up[2] | mtimecmphi_up[2]) ? mtimecmp2_new : mtimecmp2_reg));

always_ff @(posedge clk, negedge rst_n) begin
    if (~rst_n) begin
        timer_irq[2]   <= 1'b0;
    end else begin
        if (~timer_irq[2]) begin
            timer_irq[2]   <= time_cmp_flag[2];
        end else begin // 1'b1
            if (mtimecmplo_up[2] | mtimecmphi_up[2]) begin
                timer_irq[2]   <= time_cmp_flag[2];
            end
        end
    end
end

//--------------------------------------
// MTIMECMP-3
//--------------------------------------
always_comb begin
    mtimecmp3_new    = mtimecmp3_reg;
    if (mtimecmplo_up[3]) begin
        mtimecmp3_new[31:0]  = dmem_wdata;
    end
    if (mtimecmphi_up[3]) begin
        mtimecmp3_new[63:32] = dmem_wdata;
    end
end

always_ff @(posedge clk, negedge rst_n) begin
    if (~rst_n) begin
        mtimecmp3_reg    <= '0;
    end else begin
        if (mtimecmplo_up[3] | mtimecmphi_up[3]) begin
            mtimecmp3_reg    <= mtimecmp3_new;
        end
    end
end

//----------------------------------------------
// Timer Interrupt Generation
//----------------------------------------------
assign time_cmp_flag[3] = (mtime_reg >= ((mtimecmplo_up[3] | mtimecmphi_up[3]) ? mtimecmp3_new : mtimecmp3_reg));

always_ff @(posedge clk, negedge rst_n) begin
    if (~rst_n) begin
        timer_irq[3]   <= 1'b0;
    end else begin
        if (~timer_irq[3]) begin
            timer_irq[3]   <= time_cmp_flag[3];
        end else begin // 1'b1
            if (mtimecmplo_up[3] | mtimecmphi_up[3]) begin
                timer_irq[3]   <= time_cmp_flag[3];
            end
        end
    end
end


//-------------------------------------------------
// Software IRQ generation per core
//------------------------------------------------

generic_register #(1,0  ) u_msip_hart0 (
	      .we            (msip_hart_up[0]     ),
	      .data_in       (dmem_wdata[0]    ),
	      .reset_n       (rst_n            ),
	      .clk           (clk              ),
	      
	      //List of Outs
	      .data_out      (soft_irq[0]      )
          );

generic_register #(1,0  ) u_msip_hart1 (
	      .we            (msip_hart_up[1]     ),
	      .data_in       (dmem_wdata[0]    ),
	      .reset_n       (rst_n            ),
	      .clk           (clk              ),
	      
	      //List of Outs
	      .data_out      (soft_irq[1]      )
          );

generic_register #(1,0  ) u_msip_hart2  (
	      .we            (msip_hart_up[2]     ),
	      .data_in       (dmem_wdata[0]    ),
	      .reset_n       (rst_n            ),
	      .clk           (clk              ),
	      
	      //List of Outs
	      .data_out      (soft_irq[2]      )
          );

generic_register #(1,0  ) u_msip_hart3  (
	      .we            (msip_hart_up[3]  ),
	      .data_in       (dmem_wdata[0]    ),
	      .reset_n       (rst_n            ),
	      .clk           (clk              ),
	      
	      //List of Outs
	      .data_out      (soft_irq[3]      )
          );


//------------------------------------------
//   Global Register
//---------------------------------------------

always_ff @(posedge clk, negedge rst_n) begin
    if (~rst_n) begin
        riscv_glbl_cfg    <= '0;
    end else begin
        if (glbl_cfg_up) begin
            riscv_glbl_cfg    <= dmem_wdata;
        end
    end
end

// Clock control register
always_ff @(posedge clk, negedge rst_n) begin
    if (~rst_n) begin
        riscv_clk_cfg[23:0]    <= '0;
    end else begin
        if (clk_cfg_up) begin
            riscv_clk_cfg[23:0]    <= dmem_wdata[23:0];
        end 
    end
end


//------------------------
// CPU core Sleep Register
//   Set by CPU writting '1' and clean on wakeup
//-------------------------
// As there is large skew difference between wake-up signal from clock gating logic
// better to double sync it to local clock
logic [7:0] riscv_wakeup_ss;
ctech_dsync_high  #(.WB(8)) u_wakeup_dsync(
              .in_data    ( riscv_wakeup      ),
              .out_clk    ( clk               ),
              .out_rst_n  ( rst_n             ),
              .out_data   ( riscv_wakeup_ss   )
          );

generate
   genvar tcnt;
   for (tcnt = 0; $unsigned(tcnt) < 8; tcnt=tcnt+1) begin : g_sleep

    req_register #(0  ) u_sleep_req (
    	      .cpu_we       (clk_cfg_up             ),
    	      .cpu_req      (dmem_wdata[24+tcnt]    ),
    	      .hware_ack    (riscv_wakeup_ss[tcnt]     ),
    	      .reset_n      (rst_n                  ),
    	      .clk          (clk                    ),
    	      
    	      //List of Outs
    	      .data_out      (riscv_sleep[tcnt])
              );

   end
   endgenerate


//-------------------------------------------------------------------------------
// Timer divider
//-------------------------------------------------------------------------------
assign timeclk_cnt_en   = (~timer_clksrc_rtc ? 1'b1 : rtc_ext_pulse) & timer_en;

always_ff @(negedge rst_n, posedge clk) begin
    if (~rst_n) begin
        timeclk_cnt <= '0;
    end else begin
        case (1'b1)
            divider_up      : timeclk_cnt   <= dmem_wdata[YCR_TIMER_DIVIDER_WIDTH-1:0];
            time_posedge    : timeclk_cnt   <= timer_div;
            timeclk_cnt_en  : timeclk_cnt   <= timeclk_cnt - 1'b1;
            default         : begin end
        endcase
    end
end

//-------------------------------------------------------------------------------
// RTC synchronization
//-------------------------------------------------------------------------------
assign rtc_ext_pulse    = rtc_sync[3] ^ rtc_sync[2];

always_ff @(negedge rst_n, posedge rtc_clk) begin
    if (~rst_n) begin
        rtc_sync[0] <= 1'b0;
    end else begin
        if (timer_clksrc_rtc) begin
            rtc_sync[0] <= ~rtc_sync[0];
        end
    end
end

always_ff @(negedge rst_n, posedge clk) begin
    if (~rst_n) begin
        rtc_sync[3:1]   <= '0;
    end else begin
        if (timer_clksrc_rtc) begin
            rtc_sync[3:1]   <= rtc_sync[2:0];
        end
    end
end

//-------------------------------------------------------------------------------
// Memory interface
//-------------------------------------------------------------------------------
logic                           dmem_cmd_ff;
logic [YCR_TIMER_ADDR_WIDTH-1:0]   dmem_addr_ff;
always_ff @(negedge rst_n, posedge clk) begin
    if (~rst_n) begin
       dmem_req_valid <= '0;
       dmem_req_ack  <= '0;
       dmem_cmd_ff  <= '0;
       dmem_addr_ff <= '0;
    end else begin
       dmem_req_valid <=  (dmem_req) && (dmem_req_ack == 0) && (dmem_addr[YCR_TIMER_ADDR_WIDTH-1:2] <= YCR_CLK_CONTROL[YCR_TIMER_ADDR_WIDTH-1:2]);
       dmem_req_ack   <= dmem_req & (dmem_req_ack ==0);
       dmem_cmd_ff    <= dmem_cmd;
       dmem_addr_ff   <= dmem_addr[YCR_TIMER_ADDR_WIDTH-1:0];
    end
end

always_ff @(negedge rst_n, posedge clk) begin
    if (~rst_n) begin
        dmem_resp   <= YCR_MEM_RESP_NOTRDY;
        dmem_rdata  <= '0;
    end else begin
        if (dmem_req_valid) begin
                dmem_resp   <= YCR_MEM_RESP_RDY_OK;
                if (dmem_cmd_ff == YCR_MEM_CMD_RD) begin
                    case (dmem_addr_ff)
                        YCR_TIMER_CONTROL      : dmem_rdata    <= `YCR_DMEM_DWIDTH'({timer_clksrc_rtc, timer_en});
                        YCR_TIMER_DIVIDER      : dmem_rdata    <= `YCR_DMEM_DWIDTH'(timer_div);
                        YCR_TIMER_MTIMELO      : dmem_rdata    <= mtime_reg[31:0];
                        YCR_TIMER_MTIMEHI      : dmem_rdata    <= mtime_reg[63:32];

                        YCR_TIMER_MTIMECMP0LO   : dmem_rdata    <= mtimecmp0_reg[31:0];
                        YCR_TIMER_MTIMECMP0HI   : dmem_rdata    <= mtimecmp0_reg[63:32];

                        YCR_TIMER_MTIMECMP1LO   : dmem_rdata    <= mtimecmp1_reg[31:0];
                        YCR_TIMER_MTIMECMP1HI   : dmem_rdata    <= mtimecmp1_reg[63:32];

                        YCR_TIMER_MTIMECMP2LO   : dmem_rdata    <= mtimecmp2_reg[31:0];
                        YCR_TIMER_MTIMECMP2HI   : dmem_rdata    <= mtimecmp2_reg[63:32];

                        YCR_TIMER_MTIMECMP3LO   : dmem_rdata    <= mtimecmp3_reg[31:0];
                        YCR_TIMER_MTIMECMP3HI   : dmem_rdata    <= mtimecmp3_reg[63:32];

                        YCR_MSIP_HART0          : dmem_rdata    <= {31'h0, soft_irq[0]};
                        YCR_MSIP_HART1          : dmem_rdata    <= {31'h0, soft_irq[1]};
                        YCR_MSIP_HART2          : dmem_rdata    <= {31'h0, soft_irq[2]};
                        YCR_MSIP_HART3          : dmem_rdata    <= {31'h0, soft_irq[3]};

                        YCR_GLBL_CONTROL        : dmem_rdata    <= riscv_glbl_cfg;
                        YCR_CLK_CONTROL         : dmem_rdata    <= {riscv_sleep,riscv_clk_cfg};
                        default                 : begin end
                    endcase
                end
        end else begin
            dmem_resp   <= YCR_MEM_RESP_NOTRDY;
            dmem_rdata  <= '0;
        end
    end
end

always_comb begin
    control_up      = 1'b0;
    divider_up      = 1'b0;
    mtimelo_up      = 1'b0;
    mtimehi_up      = 1'b0;
    mtimecmplo_up   = 'h0;
    mtimecmphi_up   = 'h0;
    glbl_cfg_up     = 1'b0;
    clk_cfg_up      = 1'b0;
    msip_hart_up    = 'h0;
    if (dmem_req_valid & (dmem_cmd_ff == YCR_MEM_CMD_WR)) begin
        case (dmem_addr_ff)
            YCR_TIMER_CONTROL      : control_up      = 1'b1;
            YCR_TIMER_DIVIDER      : divider_up      = 1'b1;
            YCR_TIMER_MTIMELO      : mtimelo_up      = 1'b1;
            YCR_TIMER_MTIMEHI      : mtimehi_up      = 1'b1;
            YCR_TIMER_MTIMECMP0LO  : mtimecmplo_up[0]  = 1'b1;
            YCR_TIMER_MTIMECMP0HI  : mtimecmphi_up[0]  = 1'b1;
            YCR_TIMER_MTIMECMP1LO  : mtimecmplo_up[1]  = 1'b1;
            YCR_TIMER_MTIMECMP1HI  : mtimecmphi_up[1]  = 1'b1;
            YCR_TIMER_MTIMECMP2LO  : mtimecmplo_up[2]  = 1'b1;
            YCR_TIMER_MTIMECMP2HI  : mtimecmphi_up[2]  = 1'b1;
            YCR_TIMER_MTIMECMP3LO  : mtimecmplo_up[3]  = 1'b1;
            YCR_TIMER_MTIMECMP3HI  : mtimecmphi_up[3]  = 1'b1;

            YCR_MSIP_HART0         : msip_hart_up[0]   = 1'b1;
            YCR_MSIP_HART1         : msip_hart_up[1]   = 1'b1;
            YCR_MSIP_HART2         : msip_hart_up[2]   = 1'b1;
            YCR_MSIP_HART3         : msip_hart_up[3]   = 1'b1;

	        YCR_GLBL_CONTROL       : glbl_cfg_up     = 1'b1;
	        YCR_CLK_CONTROL        : clk_cfg_up      = 1'b1;
            default                : begin end
        endcase
    end
end

//-------------------------------------------------------------------------------
// Timer interface
//-------------------------------------------------------------------------------
assign timer_val    = mtime_reg;

endmodule : ycr_timer
