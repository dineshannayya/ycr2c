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
      yifive multi-core interface block                                   
                                                                          
                                                                          
      Description:                                                        
         connect the multi-core to common icache/dcache/tcm/timer         
         Instruction memory router                                        
                                                                          
      To Do:                                                              
        nothing                                                           
                                                                          
      Author(s):                                                          
          - Dinesh Annayya <dinesha@opencores.org>               
          - Dinesh Annayya <dinesh@siplusplus.com>               
                                                                          
      Revision :                                                          
         v0:    Feb 21, 2021, Dinesh A                                    
                 Initial version                                          
         v1:    Mar 10, 2023, Dinesh A                                    
                all cpu clock is branch are routed through iconnect       
                                                                          
 ***************************************************************************************************/

`include "ycr_arch_description.svh"
`include "ycr_memif.svh"
`include "ycr_wb.svh"
`ifdef YCR_IPIC_EN
`include "ycr_ipic.svh"
`endif // YCR_IPIC_EN

`ifdef YCR_TCM_EN
 `define YCR_IMEM_ROUTER_EN
`endif // YCR_TCM_EN

module ycr2_iconnect (
`ifdef USE_POWER_PINS
    input logic                          VPWR,    // User area 1 1.8V supply
    input logic                          VGND,    // User area 1 digital ground
`endif

    // Control
    input   logic                        core_clk_int  ,
    output  logic                        core_clk_skew ,

    input   logic                        core_clk,               // Core clock
    input   logic                        rtc_clk,                // Real-time clock
    input   logic                        pwrup_rst_n,            // Power-Up Reset
    input   logic                        cpu_intf_rst_n,        // CPU interface reset

    input   logic [YCR_IRQ_LINES_NUM-1:0] core_irq_lines_i,     // External interrupt request lines
    input   logic                         core_irq_soft_i,         // Software generated interrupt request

    input   logic [1:0]                  core_debug_sel,
`ifdef YCR_SERIAL_DEBUG
    input logic                          dbg_clkin  , // debug clock, like uart baud clock
    input logic                          dbg_syncin , // Sync for offset computation 
    input logic                          dbg_si     , // previous dbg data
   
    output logic                         dbg_clkout  , // debug clock, like uart baud clock
    output logic                         dbg_syncout , // Sync for offset computation 
    output logic                         dbg_so     ,

`else
    output  logic [63:0]                 riscv_debug,
`endif

    output   logic                       cfg_dcache_force_flush,
    input   logic [3:0]                  cfg_sram_lphase,
    input   logic                        cfg_bypass_icache,  // Bypass ichache
    input   logic                        cfg_bypass_dcache,  // bypass dchance

    // CORE-0
    output   logic                          core0_clk                 ,
    output   logic                          core0_sleep               , // core0 sleep indication
    input    logic   [48:0]                 core0_debug               ,
    output   logic     [1:0]                core0_uid                 ,
    output   logic [63:0]                   core0_timer_val           , // Machine timer value
    output   logic                          core0_timer_irq           ,
    output   logic [YCR_IRQ_LINES_NUM-1:0]  core0_irq_lines           , // External interrupt request lines
    output   logic                          core0_irq_soft            , // Software generated interrupt request
    // Instruction Memory Interface
    output   logic                          core0_imem_req_ack        , // IMEM request acknowledge
    input    logic                          core0_imem_req            , // IMEM request
    input    logic                          core0_imem_cmd,            // IMEM command
    input    logic [`YCR_IMEM_AWIDTH-1:0]   core0_imem_addr           , // IMEM address
    input    logic [`YCR_IMEM_BSIZE-1:0]    core0_imem_bl             , // IMEM burst size
    output   logic [`YCR_IMEM_DWIDTH-1:0]   core0_imem_rdata          , // IMEM read data
    output   logic [1:0]                    core0_imem_resp           , // IMEM response


    // Data Memory Interface
    output   logic                          core0_dmem_req_ack        , // DMEM request acknowledge
    input    logic                          core0_dmem_req            , // DMEM request
    input    logic                          core0_dmem_cmd            , // DMEM command
    input    logic[1:0]                     core0_dmem_width          , // DMEM data width
    input    logic [`YCR_DMEM_AWIDTH-1:0]   core0_dmem_addr           , // DMEM address
    input    logic [`YCR_DMEM_DWIDTH-1:0]   core0_dmem_wdata          , // DMEM write data
    output   logic [`YCR_DMEM_DWIDTH-1:0]   core0_dmem_rdata          , // DMEM read data
    output   logic [1:0]                    core0_dmem_resp,           // DMEM response

    // CORE-1
    output   logic                          core1_clk                 ,
    output   logic                          core1_sleep               , // core0 sleep indication
    input    logic   [48:0]                 core1_debug               ,
    output   logic     [1:0]                core1_uid                 ,
    output   logic [63:0]                   core1_timer_val           , // Machine timer value
    output   logic                          core1_timer_irq           ,
    output   logic [YCR_IRQ_LINES_NUM-1:0]  core1_irq_lines           , // External interrupt request lines
    output   logic                          core1_irq_soft            , // Software generated interrupt request
    // Instruction Memory Interface
    output   logic                          core1_imem_req_ack,        // IMEM request acknowledge
    input    logic                          core1_imem_req,            // IMEM request
    input    logic                          core1_imem_cmd,            // IMEM command
    input    logic [`YCR_IMEM_AWIDTH-1:0]   core1_imem_addr,           // IMEM address
    input    logic [`YCR_IMEM_BSIZE-1:0]    core1_imem_bl,             // IMEM burst size
    output   logic [`YCR_IMEM_DWIDTH-1:0]   core1_imem_rdata,          // IMEM read data
    output   logic [1:0]                    core1_imem_resp,           // IMEM response


    // Data Memory Interface
    output   logic                          core1_dmem_req_ack,        // DMEM request acknowledge
    input    logic                          core1_dmem_req,            // DMEM request
    input    logic                          core1_dmem_cmd,            // DMEM command
    input    logic[1:0]                     core1_dmem_width,          // DMEM data width
    input    logic [`YCR_DMEM_AWIDTH-1:0]   core1_dmem_addr,           // DMEM address
    input    logic [`YCR_DMEM_DWIDTH-1:0]   core1_dmem_wdata,          // DMEM write data
    output   logic [`YCR_DMEM_DWIDTH-1:0]   core1_dmem_rdata,          // DMEM read data
    output   logic [1:0]                    core1_dmem_resp,           // DMEM response
    

    //------------------------------------------------------------------
    // Toward ycr_intf
    // -----------------------------------------------------------------

    output   logic                          cpu_clk_intf              ,

    // Instruction Memory Interface
    input    logic                          core_icache_req_ack       , // IMEM request acknowledge
    output   logic                          core_icache_req           , // IMEM request
    output   logic                          core_icache_cmd           , // IMEM command
    output   logic [1:0]                    core_icache_width           , // IMEM command
    output   logic [`YCR_IMEM_AWIDTH-1:0]   core_icache_addr          , // IMEM address
    output   logic [`YCR_IMEM_BSIZE-1:0]    core_icache_bl            , // IMEM burst size
    output   logic [`YCR_IMEM_DWIDTH-1:0]   core_icache_wdata         , // IMEM write data - for rvc command
    input    logic [`YCR_IMEM_DWIDTH-1:0]   core_icache_rdata         , // IMEM read data
    input    logic [1:0]                    core_icache_resp          , // IMEM response

    // Data Memory Interface
    input    logic                          core_dcache_req_ack       , // DMEM request acknowledge
    output   logic                          core_dcache_req           , // DMEM request
    output   logic                          core_dcache_cmd           , // DMEM command
    output   logic[1:0]                     core_dcache_width         , // DMEM data width
    output   logic [`YCR_DMEM_AWIDTH-1:0]   core_dcache_addr          , // DMEM address
    output   logic [`YCR_DMEM_DWIDTH-1:0]   core_dcache_wdata         , // DMEM write data
    input    logic [`YCR_DMEM_DWIDTH-1:0]   core_dcache_rdata         , // DMEM read data
    input    logic [1:0]                    core_dcache_resp          , // DMEM response

    // Data memory interface from router to WB bridge
    input    logic                          core_dmem_req_ack         ,
    output   logic                          core_dmem_req             ,
    output   logic                          core_dmem_cmd             ,
    output   logic [1:0]                    core_dmem_width           ,
    output   logic [`YCR_DMEM_AWIDTH-1:0]   core_dmem_addr            ,
    output   logic [`YCR_IMEM_BSIZE-1:0]    core_dmem_bl              ,
    output   logic [`YCR_DMEM_DWIDTH-1:0]   core_dmem_wdata           ,
    input    logic [`YCR_DMEM_DWIDTH-1:0]   core_dmem_rdata           ,
    input    logic [1:0]                    core_dmem_resp            ,


`ifdef YCR_TCM_MEM_2KB
    // SRAM-0 PORT-0
    output  logic                           sram0_clk0                ,
    output  logic                           sram0_csb0                ,
    output  logic                           sram0_web0                ,
    output  logic   [8:0]                   sram0_addr0               ,
    output  logic   [3:0]                   sram0_wmask0              ,
    output  logic   [31:0]                  sram0_din0                ,
    input   logic   [31:0]                  sram0_dout0               ,

    // SRAM-0 PORT-1
    output  logic                           sram0_clk1                ,
    output  logic                           sram0_csb1                ,
    output  logic  [8:0]                    sram0_addr1               ,
    input   logic  [31:0]                   sram0_dout1               ,

`endif

`ifdef YCR_TCM_MEM_8KB
    // SRAM-1 PORT-0
    output  logic                           sram1_clk0                ,
    output  logic                           sram1_csb0                ,
    output  logic                           sram1_web0                ,
    output  logic   [8:0]                   sram1_addr0               ,
    output  logic   [3:0]                   sram1_wmask0              ,
    output  logic   [31:0]                  sram1_din0                ,
    input   logic   [31:0]                  sram1_dout0               ,

    // SRAM-1 PORT-1
    output  logic                           sram1_clk1                ,
    output  logic                           sram1_csb1                ,
    output  logic  [8:0]                    sram1_addr1               ,
    input   logic  [31:0]                   sram1_dout1               ,

    // SRAM-2 PORT-0
    output  logic                           sram2_clk0                ,
    output  logic                           sram2_csb0                ,
    output  logic                           sram2_web0                ,
    output  logic   [8:0]                   sram2_addr0               ,
    output  logic   [3:0]                   sram2_wmask0              ,
    output  logic   [31:0]                  sram2_din0                ,
    input   logic   [31:0]                  sram2_dout0               ,

    // SRAM-1 PORT-1
    output  logic                           sram2_clk1                ,
    output  logic                           sram2_csb1                ,
    output  logic  [8:0]                    sram2_addr1               ,
    input   logic  [31:0]                   sram2_dout1               ,

    // SRAM-3 PORT-0
    output  logic                           sram3_clk0                ,
    output  logic                           sram3_csb0                ,
    output  logic                           sram3_web0                ,
    output  logic   [8:0]                   sram3_addr0               ,
    output  logic   [3:0]                   sram3_wmask0              ,
    output  logic   [31:0]                  sram3_din0                ,
    input   logic   [31:0]                  sram3_dout0               ,

    // SRAM-3 PORT-1
    output  logic                           sram3_clk1                ,
    output  logic                           sram3_csb1                ,
    output  logic  [8:0]                    sram3_addr1               ,
    input   logic  [31:0]                   sram3_dout1               ,
`endif

    // AES DMEM I/F
    output   logic                          cpu_clk_aes               ,
    input    logic                          aes_dmem_req_ack          ,
    output   logic                          aes_dmem_req              ,
    output   logic                          aes_dmem_cmd              ,
    output   logic [1:0]                    aes_dmem_width            ,
    output   logic [6:0]                    aes_dmem_addr             ,
    output   logic [`YCR_DMEM_DWIDTH-1:0]   aes_dmem_wdata            ,
    input    logic [`YCR_DMEM_DWIDTH-1:0]   aes_dmem_rdata            ,
    input    logic [1:0]                    aes_dmem_resp             ,
    input    logic                          aes_idle                  ,

    // FPU DMEM I/F
    output   logic                          cpu_clk_fpu               ,
    input    logic                          fpu_dmem_req_ack          ,
    output   logic                          fpu_dmem_req              ,
    output   logic                          fpu_dmem_cmd              ,
    output   logic [1:0]                    fpu_dmem_width            ,
    output   logic [4:0]                    fpu_dmem_addr             ,
    output   logic [`YCR_DMEM_DWIDTH-1:0]   fpu_dmem_wdata            ,
    input    logic [`YCR_DMEM_DWIDTH-1:0]   fpu_dmem_rdata            ,
    input    logic [1:0]                    fpu_dmem_resp             ,
    input    logic                          fpu_idle                  




);
//-------------------------------------------------------------------------------
// Local parameters
//-------------------------------------------------------------------------------
localparam int unsigned YCR_CLUSTER_TOP_RST_SYNC_STAGES_NUM            = 2;

//-------------------------------------------------------------------------------
// Local signal declaration
//-------------------------------------------------------------------------------
logic                                              cpu_intf_rst_n_sync;

`ifdef YCR_TCM_EN
// Instruction memory interface from router to TCM
logic                                              tcm_imem_req_ack;
logic                                              tcm_imem_req;
logic                                              tcm_imem_cmd;
logic [`YCR_IMEM_AWIDTH-1:0]                       tcm_imem_addr;
logic [`YCR_IMEM_DWIDTH-1:0]                       tcm_imem_rdata;
logic [1:0]                                        tcm_imem_resp;

// Data memory interface from router to TCM
logic                                              tcm_dmem_req_ack;
logic                                              tcm_dmem_req;
logic                                              tcm_dmem_cmd;
logic [1:0]                                        tcm_dmem_width;
logic [`YCR_DMEM_AWIDTH-1:0]                       tcm_dmem_addr;
logic [`YCR_DMEM_DWIDTH-1:0]                       tcm_dmem_wdata;
logic [`YCR_DMEM_DWIDTH-1:0]                       tcm_dmem_rdata;
logic [1:0]                                        tcm_dmem_resp;
`endif // YCR_TCM_EN

// Data memory interface from router to memory-mapped local
logic                                              local_dmem_req_ack;
logic                                              local_dmem_req;
logic                                              local_dmem_cmd;
logic [1:0]                                        local_dmem_width;
logic [`YCR_DMEM_AWIDTH-1:0]                       local_dmem_addr;
logic [`YCR_DMEM_DWIDTH-1:0]                       local_dmem_wdata;
logic [`YCR_DMEM_DWIDTH-1:0]                       local_dmem_rdata;
logic [1:0]                                        local_dmem_resp;

// Data memory interface from router to memory-mapped timer
logic                                              timer_dmem_req_ack;
logic                                              timer_dmem_req;
logic                                              timer_dmem_cmd;
logic [1:0]                                        timer_dmem_width;
logic [`YCR_DMEM_AWIDTH-1:0]                       timer_dmem_addr;
logic [`YCR_DMEM_DWIDTH-1:0]                       timer_dmem_wdata;
logic [`YCR_DMEM_DWIDTH-1:0]                       timer_dmem_rdata;
logic [1:0]                                        timer_dmem_resp;

logic  [3:0]                                        core_soft_irq;         // Software generated interrupt request

`ifndef YCR_TCM_MEM_8KB
    // SRAM-1 PORT-0
    logic                                          sram1_clk0;
    logic                                          sram1_csb0;
    logic                                          sram1_web0;
    logic   [8:0]                                  sram1_addr0;
    logic   [3:0]                                  sram1_wmask0;
    logic   [31:0]                                 sram1_din0;
    logic   [31:0]                                 sram1_dout0;

    // SRAM-1 PORT-1
    logic                                          sram1_clk1;
    logic                                          sram1_csb1;
    logic  [8:0]                                   sram1_addr1;
    logic  [31:0]                                  sram1_dout1;

    // SRAM-2 PORT-0
    logic                                          sram2_clk0;
    logic                                          sram2_csb0;
    logic                                          sram2_web0;
    logic   [8:0]                                  sram2_addr0;
    logic   [3:0]                                  sram2_wmask0;
    logic   [31:0]                                 sram2_din0;
    logic   [31:0]                                 sram2_dout0;

    // SRAM-2 PORT-1
    logic                                          sram2_clk1;
    logic                                          sram2_csb1;
    logic  [8:0]                                   sram2_addr1;
    logic  [31:0]                                  sram2_dout1;

    // SRAM-3 PORT-0
    logic                                          sram3_clk0;
    logic                                          sram3_csb0;
    logic                                          sram3_web0;
    logic   [8:0]                                  sram3_addr0;
    logic   [3:0]                                  sram3_wmask0;
    logic   [31:0]                                 sram3_din0;
    logic   [31:0]                                 sram3_dout0;

    // SRAM-3 PORT-1
    logic                                          sram3_clk1;
    logic                                          sram3_csb1;
    logic  [8:0]                                   sram3_addr1;
    logic  [31:0]                                  sram3_dout1;
`endif

logic [31:0]                                       riscv_glbl_cfg          ;   
logic [23:0]                                       riscv_clk_cfg           ;   
logic [7:0]                                        riscv_sleep             ;
logic [7:0]                                        riscv_wakeup            ;
logic [63:0]                                       timer_val               ;                // Machine timer value
logic [3:0]                                        timer_irq               ;
logic [`YCR_DMEM_AWIDTH-1:0]                       aes_dmem_addr_tmp       ;
logic [`YCR_DMEM_AWIDTH-1:0]                       fpu_dmem_addr_tmp       ;

//-----------------------------------------------------------------------------------
// Variable for sram mux for sram0
// ---------------------------------------------------------------------------------
// PORT-0
logic                             sram0_csb0_int       ; // CS#
logic                             sram0_web0_int       ; // WE#
logic   [8:0]                     sram0_addr0_int      ; // Address
logic   [3:0]                     sram0_wmask0_int     ; // WMASK#
logic   [31:0]                    sram0_din0_int       ; // Write Data
   
// SRAM-0 PORT-1
logic                             sram0_csb1_int       ; // CS#
logic  [8:0]                      sram0_addr1_int      ; // Address

//-----------------------------------------------------------------------------------
// Variable for sram mux for sram1
// ---------------------------------------------------------------------------------
// PORT-0
logic                             sram1_csb0_int       ; // CS#
logic                             sram1_web0_int       ; // WE#
logic   [8:0]                     sram1_addr0_int      ; // Address
logic   [3:0]                     sram1_wmask0_int     ; // WMASK#
logic   [31:0]                    sram1_din0_int       ; // Write Data
   
// SRAM-0 PORT-1
logic                             sram1_csb1_int       ; // CS#
logic  [8:0]                      sram1_addr1_int      ; // Address

//-----------------------------------------------------------------------------------
// Variable for sram mux for sram2
// ---------------------------------------------------------------------------------
// PORT-0
logic                             sram2_csb0_int       ; // CS#
logic                             sram2_web0_int       ; // WE#
logic   [8:0]                     sram2_addr0_int      ; // Address
logic   [3:0]                     sram2_wmask0_int     ; // WMASK#
logic   [31:0]                    sram2_din0_int       ; // Write Data
   
// SRAM-0 PORT-1
logic                             sram2_csb1_int       ; // CS#
logic  [8:0]                      sram2_addr1_int      ; // Address

//-----------------------------------------------------------------------------------
// Variable for sram mux for sram3
// ---------------------------------------------------------------------------------
// PORT-0
logic                             sram3_csb0_int       ; // CS#
logic                             sram3_web0_int       ; // WE#
logic   [8:0]                     sram3_addr0_int      ; // Address
logic   [3:0]                     sram3_wmask0_int     ; // WMASK#
logic   [31:0]                    sram3_din0_int       ; // Write Data
   
// SRAM-0 PORT-1
logic                             sram3_csb1_int       ; // CS#
logic  [8:0]                      sram3_addr1_int      ; // Address


//---------------------------------------------------------------------------------
// Providing cpu clock feed through iconnect for better physical routing
//---------------------------------------------------------------------------------


assign      core0_sleep = riscv_sleep[0];
assign      core1_sleep = riscv_sleep[1];

ycr_cclk_ctrl_top u_cclk_gate (
     .rst_n              (cpu_intf_rst_n      ) ,
     .core_clk_int       (core_clk_int        ) , // core clock without skew
                                             
     .riscv_clk_cfg      (riscv_clk_cfg[23:0] ) ,
     .aes_idle           (aes_idle            ) ,
     .aes_req            (aes_dmem_req        ) ,
                                             
     .fpu_idle           (fpu_idle            ) ,
     .fpu_req            (fpu_dmem_req        ) ,
                                             
     .riscv_sleep        (riscv_sleep         ) ,
     .riscv_wakeup       (riscv_wakeup        ) ,
                                             
     .timer_irq          (timer_irq           ) ,
     .core_irq_lines_i   (core_irq_lines_i    ) , // External interrupt request lines
     .core_irq_soft_i    (core_irq_soft_i     ) , // Software generated interrupt request
                                             
     .core0_clk          (core0_clk           ) ,
     .core1_clk          (core1_clk           ) ,
     .cpu_clk_fpu        (cpu_clk_fpu         ) ,
     .cpu_clk_aes        (cpu_clk_aes         ) ,
     .cpu_clk_intf       (cpu_clk_intf        ) 


    );


//---------------------------------------------------------------------------------
// To improve the physical routing irq signal are buffer inside the block
// --------------------------------------------------------------------------------
assign core0_irq_lines  =  core_irq_lines_i         ; // External interrupt request lines
assign core0_irq_soft   =  core_soft_irq[0]         ; // Software generated interrupt request
assign core1_irq_lines  =  core_irq_lines_i         ; // External interrupt request lines
assign core1_irq_soft   =  core_soft_irq[1]         ; // Software generated interrupt request
//---------------------------------------------------------------------------------
// To avoid core level power hook up, we have brought this signal inside, to
// avoid any cell at digital core level
// --------------------------------------------------------------------------------
wire test_mode = 1'b0;
wire test_rst_n = 1'b0;

wire [63:0]  riscv_debug0 = {core0_imem_req,core0_imem_req_ack,core0_imem_resp[1:0],
	                     core0_dmem_req,core0_dmem_req_ack,core0_dmem_resp[1:0],
	                     core_dmem_req,core_dmem_req_ack, core_icache_req,core_icache_req_ack,
	                     core_dcache_req,core_dcache_req_ack, tcm_dmem_req, 
		             core0_debug };
wire [63:0]  riscv_debug1 = {core1_imem_req,core1_imem_req_ack,core1_imem_resp[1:0],
	                     core1_dmem_req,core1_dmem_req_ack,core1_dmem_resp[1:0],
	                     core_dmem_req,core_dmem_req_ack, core_icache_req,core_icache_req_ack,
	                     core_dcache_req,core_dcache_req_ack, tcm_dmem_req, 
		             core1_debug };

//---------------------------------------
// change debug from from parallel to serial format

`ifdef YCR_SERIAL_DEBUG

logic dbg_clkout_c0,dbg_syncout_c0,dbg_so_c0;

dbg_port  #(.DEBUG_WD(64),.DEBUG_OFFSET(DBG_CORE0_OFFSET)) u_debug0(

         .src_rst_n  (cpu_intf_rst_n   ),
         .src_clk    (core0_clk        ),
         .src_din    (riscv_debug0     ),

         .dbg_clkin  (dbg_clkin        ), // debug clock, like uart baud clock
         .dbg_syncin (dbg_syncin       ), // Sync for offset computation 
         .dbg_si     (dbg_si           ), // previous dbg data

         .dbg_clkout (dbg_clkout_c0    ), // debug clock, like uart baud clock
         .dbg_syncout(dbg_syncout_c0   ), // Sync for offset computation 
         .dbg_so     (dbg_so_c0        )
       );

dbg_port  #(.DEBUG_WD(64),.DEBUG_OFFSET(DBG_CORE1_OFFSET)) u_debug1(

         .src_rst_n  (cpu_intf_rst_n   ),
         .src_clk    (core1_clk        ),
         .src_din    (riscv_debug1     ),

         .dbg_clkin  (dbg_clkout_c0    ), // debug clock, like uart baud clock
         .dbg_syncin (dbg_syncout_c0   ), // Sync for offset computation 
         .dbg_si     (dbg_so_c0        ), // previous dbg data

         .dbg_clkout (dbg_clkout       ), // debug clock, like uart baud clock
         .dbg_syncout(dbg_syncout      ), // Sync for offset computation 
         .dbg_so     (dbg_so           )
       );

`else

assign riscv_debug = (core_debug_sel == 2'b00) ? riscv_debug0 : riscv_debug1 ;

`endif

assign cfg_dcache_force_flush   = riscv_glbl_cfg[0];

assign core0_timer_val          = timer_val     ;                // Machine timer value
assign core0_timer_irq          = timer_irq[0]  ;

assign core1_timer_val          = timer_val     ;                // Machine timer value
assign core1_timer_irq          = timer_irq[1]  ;

//assign core2_timer_val          = timer_val   ;                // Machine timer value
//assign core2_timer_irq          = timer_irq[2];
//
//assign core3_timer_val          = timer_val   ;                // Machine timer value
//assign core3_timer_irq          = timer_irq[3];

assign aes_dmem_addr            = aes_dmem_addr_tmp[6:0];
assign fpu_dmem_addr            = fpu_dmem_addr_tmp[4:0];

// OpenSource CTS tool does not work with buffer as source point
// changed buf to max with select tied=0
//ctech_clk_buf u_lineclk_buf  (.A(line_clk_16x_in),  .X(line_clk_16x));
logic core_clk_cts;
logic core_clk_g;
ctech_clk_gate u_cclk_g (.GATE (1'b1), . CLK(core_clk), .GCLK(core_clk_g));
ctech_mux2x1 u_cclk_cts  (.A0(core_clk_g), .A1(1'b0), .S(1'b0), .X(core_clk_cts));

//--------------------------------------------
// RISCV clock skew control
//--------------------------------------------
ctech_clk_buf u_skew_core_clk
       (
	    .A              (core_clk_int            ), 
	    .X              (core_clk_skew           ) 
       );

//-------------------------------------------------------------------------------
// Reset logic
//-------------------------------------------------------------------------------
// Power-Up Reset synchronizer

// CPU Reset synchronizer
ycr_reset_sync_cell #(
    .STAGES_AMOUNT       (YCR_CLUSTER_TOP_RST_SYNC_STAGES_NUM)
) i_cpu_intf_rstn_reset_sync (
    .rst_n          (pwrup_rst_n          ),
    .clk            (core_clk_cts         ),
    .test_rst_n     (test_rst_n           ),
    .test_mode      (test_mode            ),
    .rst_n_in       (cpu_intf_rst_n       ),
    .rst_n_out      (cpu_intf_rst_n_sync  )
);

// Unique core it lower bits
assign core0_uid = 2'b00;
assign core1_uid = 2'b01;



ycr2_cross_bar u_crossbar (
    
    .rst_n                 (cpu_intf_rst_n_sync        ),
    .clk                   (core_clk_cts               ),

   
    .cfg_bypass_icache     (cfg_bypass_icache          ),
    .cfg_bypass_dcache     (cfg_bypass_dcache          ),

    .core0_imem_req_ack    (core0_imem_req_ack         ),
    .core0_imem_req        (core0_imem_req             ),
    .core0_imem_cmd        (core0_imem_cmd             ),
    .core0_imem_width      (YCR_MEM_WIDTH_WORD         ),
    .core0_imem_addr       (core0_imem_addr            ),
    .core0_imem_bl         (core0_imem_bl              ),             
    .core0_imem_wdata      ('h0                        ),
    .core0_imem_rdata      (core0_imem_rdata           ),
    .core0_imem_resp       (core0_imem_resp            ),
                                                 
                                                 
    .core0_dmem_req_ack    (core0_dmem_req_ack         ),
    .core0_dmem_req        (core0_dmem_req             ),
    .core0_dmem_cmd        (core0_dmem_cmd             ),
    .core0_dmem_width      (core0_dmem_width           ),
    .core0_dmem_addr       (core0_dmem_addr            ),
    .core0_dmem_bl         (3'h1                       ),             
    .core0_dmem_wdata      (core0_dmem_wdata           ),
    .core0_dmem_rdata      (core0_dmem_rdata           ),
    .core0_dmem_resp       (core0_dmem_resp            ),
                                                 
                                                 
    .core1_imem_req_ack    (core1_imem_req_ack         ),
    .core1_imem_req        (core1_imem_req             ),
    .core1_imem_cmd        (core1_imem_cmd             ),
    .core1_imem_width      (YCR_MEM_WIDTH_WORD         ),
    .core1_imem_addr       (core1_imem_addr            ),
    .core1_imem_bl         (core1_imem_bl              ),             
    .core1_imem_wdata      ('h0                        ),
    .core1_imem_rdata      (core1_imem_rdata           ),
    .core1_imem_resp       (core1_imem_resp            ),
                                                 
                                                 
    .core1_dmem_req_ack    (core1_dmem_req_ack         ),
    .core1_dmem_req        (core1_dmem_req             ),
    .core1_dmem_cmd        (core1_dmem_cmd             ),
    .core1_dmem_width      (core1_dmem_width           ),
    .core1_dmem_addr       (core1_dmem_addr            ),
    .core1_dmem_bl         (3'h1                       ),             
    .core1_dmem_wdata      (core1_dmem_wdata           ),
    .core1_dmem_rdata      (core1_dmem_rdata           ),
    .core1_dmem_resp       (core1_dmem_resp            ),
                                                 
                                                 
    // Interface to WB bridge
    .port0_req_ack         (core_dmem_req_ack          ),
    .port0_req             (core_dmem_req              ),
    .port0_cmd             (core_dmem_cmd              ),
    .port0_width           (core_dmem_width            ),
    .port0_addr            (core_dmem_addr             ),
    .port0_bl              (core_dmem_bl               ), 
    .port0_wdata           (core_dmem_wdata            ),
    .port0_rdata           (core_dmem_rdata            ),
    .port0_resp            (core_dmem_resp             ),
    
`ifdef YCR_ICACHE_EN
    // Interface to TCM
    .port1_req_ack         (core_icache_req_ack        ),
    .port1_req             (core_icache_req            ),
    .port1_cmd             (core_icache_cmd            ),
    .port1_width           (core_icache_width          ),
    .port1_addr            (core_icache_addr           ),
    .port1_bl              (core_icache_bl             ),
    .port1_wdata           (core_icache_wdata          ),
    .port1_rdata           (core_icache_rdata          ),
    .port1_resp            (core_icache_resp           ),
`else // YCR_ICACHE_EN
    .port1_req_ack         (1'b0                       ),
    .port1_req             (                           ),
    .port1_cmd             (                           ),
    .port1_width           (                           ),
    .port1_addr            (                           ),
    .port1_wdata           (                           ),
    .port1_rdata           (32'h0                      ),
    .port1_resp            (YCR_MEM_RESP_RDY_ER        ),
`endif // YCR_ICACHE_EN

`ifdef YCR_DCACHE_EN
    // Interface to TCM
    .port2_req_ack         (core_dcache_req_ack        ),
    .port2_req             (core_dcache_req            ),
    .port2_cmd             (core_dcache_cmd            ),
    .port2_width           (core_dcache_width          ),
    .port2_addr            (core_dcache_addr           ),
    .port2_bl              (                           ), // bl not supported in dcache
    .port2_wdata           (core_dcache_wdata          ),
    .port2_rdata           (core_dcache_rdata          ),
    .port2_resp            (core_dcache_resp           ),
`else // YCR_ICACHE_EN
    .port2_req_ack         (1'b0                       ),
    .port2_req             (                           ),
    .port2_cmd             (                           ),
    .port2_width           (                           ),
    .port2_addr            (                           ),
    .port2_wdata           (                           ),
    .port2_rdata           (32'h0                      ),
    .port2_resp            (YCR_MEM_RESP_RDY_ER        ),
`endif // YCR_ICACHE_EN

`ifdef YCR_TCM_EN
    // Interface to TCM
    .port3_req_ack         (tcm_dmem_req_ack           ),
    .port3_req             (tcm_dmem_req               ),
    .port3_cmd             (tcm_dmem_cmd               ),
    .port3_width           (tcm_dmem_width             ),
    .port3_addr            (tcm_dmem_addr              ),
    .port3_bl              (                           ), // Not Supported
    .port3_wdata           (tcm_dmem_wdata             ),
    .port3_rdata           (tcm_dmem_rdata             ),
    .port3_resp            (tcm_dmem_resp              ),
`else // YCR_TCM_EN
    .port3_req_ack         (1'b0                       ),
    .port3_req             (                           ),
    .port3_cmd             (                           ),
    .port3_width           (                           ),
    .port3_addr            (                           ),
    .port3_wdata           (                           ),
    .port3_rdata           (32'h0                      ),
    .port3_resp            (YCR_MEM_RESP_RDY_ER        ),
`endif // YCR_TCM_EN

    // Interface to memory-mapped timer
    .port4_req_ack         (local_dmem_req_ack         ),
    .port4_req             (local_dmem_req             ),
    .port4_cmd             (local_dmem_cmd             ),
    .port4_width           (local_dmem_width           ),
    .port4_addr            (local_dmem_addr            ),
    .port4_bl              (                           ), // Not Supported
    .port4_wdata           (local_dmem_wdata           ),
    .port4_rdata           (local_dmem_rdata           ),
    .port4_resp            (local_dmem_resp            )

);

/*************************************
  Local Router for TIMER/AES
**************************************/

ycr_dmem_router 
#(
    .YCR_PORT1_ADDR_MASK   (YCR_TIMER_ADDR_MASK     ),
    .YCR_PORT1_ADDR_PATTERN(YCR_TIMER_ADDR_PATTERN  ),
    .YCR_PORT2_ADDR_MASK   (YCR_FPU_ADDR_MASK       ),
    .YCR_PORT2_ADDR_PATTERN(YCR_FPU_ADDR_PATTERN    )
) u_local_router
(
    // Control signals
    .rst_n                  (cpu_intf_rst_n_sync        ),
    .clk                    (core_clk_cts               ),

    // Core interface
    .dmem_req_ack           (local_dmem_req_ack         ),
    .dmem_req               (local_dmem_req             ),
    .dmem_cmd               (local_dmem_cmd             ),
    .dmem_width             (local_dmem_width           ),
    .dmem_addr              (local_dmem_addr            ),
    .dmem_wdata             (local_dmem_wdata           ),
    .dmem_rdata             (local_dmem_rdata           ),
    .dmem_resp              (local_dmem_resp            ),

    // PORT0 interface
    .port0_req_ack          (aes_dmem_req_ack           ),
    .port0_req              (aes_dmem_req               ),
    .port0_cmd              (aes_dmem_cmd               ),
    .port0_width            (aes_dmem_width             ),
    .port0_addr             (aes_dmem_addr_tmp          ),
    .port0_wdata            (aes_dmem_wdata             ),
    .port0_rdata            (aes_dmem_rdata             ),
    .port0_resp             (aes_dmem_resp              ),

    // PORT1 interface
    .port1_req_ack          (timer_dmem_req_ack         ),
    .port1_req              (timer_dmem_req             ),
    .port1_cmd              (timer_dmem_cmd             ),
    .port1_width            (timer_dmem_width           ),
    .port1_addr             (timer_dmem_addr            ),
    .port1_wdata            (timer_dmem_wdata           ),
    .port1_rdata            (timer_dmem_rdata           ),
    .port1_resp             (timer_dmem_resp            ),

    // PORT1 interface
    .port2_req_ack          (fpu_dmem_req_ack           ),
    .port2_req              (fpu_dmem_req               ),
    .port2_cmd              (fpu_dmem_cmd               ),
    .port2_width            (fpu_dmem_width             ),
    .port2_addr             (fpu_dmem_addr_tmp          ),
    .port2_wdata            (fpu_dmem_wdata             ),
    .port2_rdata            (fpu_dmem_rdata             ),
    .port2_resp             (fpu_dmem_resp              )

);



`ifdef YCR_TCM_EN
//-------------------------------------------------------------------------------
// TCM instance
//-------------------------------------------------------------------------------
ycr_tcm #(
    .YCR_TCM_SIZE  (`YCR_DMEM_AWIDTH'(~YCR_TCM_ADDR_MASK + 1'b1))
) i_tcm (
    .clk            (core_clk_cts         ), // core clock with cts
    .clk_src        (core_clk_g           ), // core clk without cts
    .rst_n          (cpu_intf_rst_n_sync  ),

`ifndef YCR_TCM_MEM
    // SRAM-0 PORT-0
    .sram0_clk0      (sram0_clk0          ),
    .sram0_csb0      (sram0_csb0_int      ),
    .sram0_web0      (sram0_web0_int      ),
    .sram0_addr0     (sram0_addr0_int     ),
    .sram0_wmask0    (sram0_wmask0_int    ),
    .sram0_din0      (sram0_din0_int      ),
    .sram0_dout0     (sram0_dout0         ),
    
    // SRAM-0 PORT-1
    .sram0_clk1      (sram0_clk1          ),
    .sram0_csb1      (sram0_csb1_int      ),
    .sram0_addr1     (sram0_addr1_int     ),
    .sram0_dout1     (sram0_dout1         ),

    // SRAM-1 PORT-0
    .sram1_clk0      (sram1_clk0          ),
    .sram1_csb0      (sram1_csb0_int      ),
    .sram1_web0      (sram1_web0_int      ),
    .sram1_addr0     (sram1_addr0_int     ),
    .sram1_wmask0    (sram1_wmask0_int    ),
    .sram1_din0      (sram1_din0_int      ),
    .sram1_dout0     (sram1_dout0         ),
    
    // SRAM-1 PORT-1
    .sram1_clk1      (sram1_clk1          ),
    .sram1_csb1      (sram1_csb1_int      ),
    .sram1_addr1     (sram1_addr1_int     ),
    .sram1_dout1     (sram1_dout1         ),

   // SRAM-2 PORT-0
    .sram2_clk0      (sram2_clk0          ),
    .sram2_csb0      (sram2_csb0_int      ),
    .sram2_web0      (sram2_web0_int      ),
    .sram2_addr0     (sram2_addr0_int     ),
    .sram2_wmask0    (sram2_wmask0_int    ),
    .sram2_din0      (sram2_din0_int      ),
    .sram2_dout0     (sram2_dout0         ),
    
    // SRAM-2 PORT-1
    .sram2_clk1      (sram2_clk1          ),
    .sram2_csb1      (sram2_csb1_int      ),
    .sram2_addr1     (sram2_addr1_int     ),
    .sram2_dout1     (sram2_dout1         ),

   // SRAM-3 PORT-0
    .sram3_clk0      (sram3_clk0          ),
    .sram3_csb0      (sram3_csb0_int      ),
    .sram3_web0      (sram3_web0_int      ),
    .sram3_addr0     (sram3_addr0_int     ),
    .sram3_wmask0    (sram3_wmask0_int    ),
    .sram3_din0      (sram3_din0_int      ),
    .sram3_dout0     (sram3_dout0         ),
    
    // SRAM-3 PORT-1
    .sram3_clk1      (sram3_clk1          ),
    .sram3_csb1      (sram3_csb1_int      ),
    .sram3_addr1     (sram3_addr1_int     ),
    .sram3_dout1     (sram3_dout1         ),

`endif


    // TBD- how to use TCM IMEM Port - Dinesh
    .imem_req_ack   (tcm_imem_req_ack    ),
    .imem_req       (1'b0                ),
    .imem_addr      ('h0                 ),
    .imem_rdata     (                    ),
    .imem_resp      (                    ),

    // Data interface to TCM
    .dmem_req_ack   (tcm_dmem_req_ack    ),
    .dmem_req       (tcm_dmem_req        ),
    .dmem_cmd       (tcm_dmem_cmd        ),
    .dmem_width     (tcm_dmem_width      ),
    .dmem_addr      (tcm_dmem_addr       ),
    .dmem_wdata     (tcm_dmem_wdata      ),
    .dmem_rdata     (tcm_dmem_rdata      ),
    .dmem_resp      (tcm_dmem_resp       )
);
`endif // YCR_TCM_EN

//----------------------------------------------------------------
// As there SRAM timing model is not correct. we have created
// additional position drive data in negedge
// ----------------------------------------------------------------
ycr_sram_mux  u_sram0_smux (
   .rst_n                (cpu_intf_rst_n_sync    ),
   .cfg_mem_lphase       (cfg_sram_lphase[0]     ), // 0 - Posedge (Default), 1 - Negedge
   // SRAM Memory I/F, PORT-0
   .mem_clk0_i           (sram0_clk0        ), // CLK
   .mem_csb0_i           (sram0_csb0_int    ), // CS#
   .mem_web0_i           (sram0_web0_int    ), // WE#
   .mem_addr0_i          (sram0_addr0_int   ), // Address
   .mem_wmask0_i         (sram0_wmask0_int  ), // WMASK#
   .mem_din0_i           (sram0_din0_int    ), // Write Data
   
   // SRAM-0 PORT-1, 
   .mem_clk1_i           (sram0_clk1        ), // CLK
   .mem_csb1_i           (sram0_csb1_int    ), // CS#
   .mem_addr1_i          (sram0_addr1_int   ), // Address

   // SRAM Memory I/F, PORT-0
   .mem_csb0_o           (sram0_csb0        ), // CS#
   .mem_web0_o           (sram0_web0        ), // WE#
   .mem_addr0_o          (sram0_addr0       ), // Address
   .mem_wmask0_o         (sram0_wmask0      ), // WMASK#
   .mem_din0_o           (sram0_din0        ), // Write Data
   
   // SRAM-0 PORT-1, 
   .mem_csb1_o           (sram0_csb1        ), // CS#
   .mem_addr1_o          (sram0_addr1       )  // Address
);

ycr_sram_mux  u_sram1_smux (
   .rst_n                (cpu_intf_rst_n_sync    ),
   .cfg_mem_lphase       (cfg_sram_lphase[1]     ), // 0 - Posedge (Default), 1 - Negedge
   // SRAM Memory I/F, PORT-0
   .mem_clk0_i           (sram1_clk0        ), // CLK
   .mem_csb0_i           (sram1_csb0_int    ), // CS#
   .mem_web0_i           (sram1_web0_int    ), // WE#
   .mem_addr0_i          (sram1_addr0_int   ), // Address
   .mem_wmask0_i         (sram1_wmask0_int  ), // WMASK#
   .mem_din0_i           (sram1_din0_int    ), // Write Data
   
   // SRAM-0 PORT-1, 
   .mem_clk1_i           (sram1_clk1        ), // CLK
   .mem_csb1_i           (sram1_csb1_int    ), // CS#
   .mem_addr1_i          (sram1_addr1_int   ), // Address

   // SRAM Memory I/F, PORT-0
   .mem_csb0_o           (sram1_csb0        ), // CS#
   .mem_web0_o           (sram1_web0        ), // WE#
   .mem_addr0_o          (sram1_addr0       ), // Address
   .mem_wmask0_o         (sram1_wmask0      ), // WMASK#
   .mem_din0_o           (sram1_din0        ), // Write Data
   
   // SRAM-0 PORT-1, 
   .mem_csb1_o           (sram1_csb1        ), // CS#
   .mem_addr1_o          (sram1_addr1       )  // Address
);

ycr_sram_mux  u_sram2_smux (
   .rst_n                (cpu_intf_rst_n_sync    ),
   .cfg_mem_lphase       (cfg_sram_lphase[2]     ), // 0 - Posedge (Default), 1 - Negedge
   // SRAM Memory I/F, PORT-0
   .mem_clk0_i           (sram2_clk0        ), // CLK
   .mem_csb0_i           (sram2_csb0_int    ), // CS#
   .mem_web0_i           (sram2_web0_int    ), // WE#
   .mem_addr0_i          (sram2_addr0_int   ), // Address
   .mem_wmask0_i         (sram2_wmask0_int  ), // WMASK#
   .mem_din0_i           (sram2_din0_int    ), // Write Data
   
   // SRAM-0 PORT-1, 
   .mem_clk1_i           (sram2_clk1        ), // CLK
   .mem_csb1_i           (sram2_csb1_int    ), // CS#
   .mem_addr1_i          (sram2_addr1_int   ), // Address

   // SRAM Memory I/F, PORT-0
   .mem_csb0_o           (sram2_csb0        ), // CS#
   .mem_web0_o           (sram2_web0        ), // WE#
   .mem_addr0_o          (sram2_addr0       ), // Address
   .mem_wmask0_o         (sram2_wmask0      ), // WMASK#
   .mem_din0_o           (sram2_din0        ), // Write Data
   
   // SRAM-0 PORT-1, 
   .mem_csb1_o           (sram2_csb1        ), // CS#
   .mem_addr1_o          (sram2_addr1       )  // Address
);

ycr_sram_mux  u_sram3_smux (
   .rst_n                (cpu_intf_rst_n_sync    ),
   .cfg_mem_lphase       (cfg_sram_lphase[3]     ), // 0 - Posedge (Default), 1 - Negedge
   // SRAM Memory I/F, PORT-0
   .mem_clk0_i           (sram3_clk0        ), // CLK
   .mem_csb0_i           (sram3_csb0_int    ), // CS#
   .mem_web0_i           (sram3_web0_int    ), // WE#
   .mem_addr0_i          (sram3_addr0_int   ), // Address
   .mem_wmask0_i         (sram3_wmask0_int  ), // WMASK#
   .mem_din0_i           (sram3_din0_int    ), // Write Data
   
   // SRAM-0 PORT-1, 
   .mem_clk1_i           (sram3_clk1        ), // CLK
   .mem_csb1_i           (sram3_csb1_int    ), // CS#
   .mem_addr1_i          (sram3_addr1_int   ), // Address

   // SRAM Memory I/F, PORT-0
   .mem_csb0_o           (sram3_csb0        ), // CS#
   .mem_web0_o           (sram3_web0        ), // WE#
   .mem_addr0_o          (sram3_addr0       ), // Address
   .mem_wmask0_o         (sram3_wmask0      ), // WMASK#
   .mem_din0_o           (sram3_din0        ), // Write Data
   
   // SRAM-0 PORT-1, 
   .mem_csb1_o           (sram3_csb1        ), // CS#
   .mem_addr1_o          (sram3_addr1       )  // Address
);





//-------------------------------------------------------------------------------
// Memory-mapped timer instance
//-------------------------------------------------------------------------------
ycr_timer i_timer (
    // Common
    .rst_n          (cpu_intf_rst_n_sync  ),
    .clk            (core_clk_cts         ),
    .rtc_clk        (rtc_clk              ),

    // Memory interface
    .dmem_req       (timer_dmem_req    ),
    .dmem_cmd       (timer_dmem_cmd    ),
    .dmem_width     (timer_dmem_width  ),
    .dmem_addr      (timer_dmem_addr   ),
    .dmem_wdata     (timer_dmem_wdata  ),
    .dmem_req_ack   (timer_dmem_req_ack),
    .dmem_rdata     (timer_dmem_rdata  ),
    .dmem_resp      (timer_dmem_resp   ),

    // Timer interface
    .timer_val      (timer_val         ),
    .timer_irq      (timer_irq         ),

    .soft_irq       (core_soft_irq     ),

    .riscv_glbl_cfg (riscv_glbl_cfg    ),
    .riscv_clk_cfg  (riscv_clk_cfg     ),
    .riscv_sleep    (riscv_sleep       ),
    .riscv_wakeup   (riscv_wakeup      )
);



endmodule : ycr2_iconnect
