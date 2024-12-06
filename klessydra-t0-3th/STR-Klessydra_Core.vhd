---------------------------------------------------------------------------------------------------------------------
--                                                                                                                 --
--  Author(s): Abdallah Cheikh abdallah.cheikh@uniroma1.it (abdallah93.as@gmail.com)                               --
--                                                                                                                 --
--  Date Modified: 07-04-2020                                                                                      --
---------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------
--  Klessydra-M core v.4.0:                                                                                        --
--  RISCY core pinout, RISC-V core, RV32IMA support plus the RISC-V Embedded E-extension and custom                --
--  K-extension. T13 has 4 pipeline stages F/RD/E/W, in order execution. With the execute stage being superscalar  --
--  Supports interleaved multithreading (IMT), with maximum configurable thread pool size = 16 threads.            --
--  Pure RISCV exception and interrupt handling. Only thread 0 can be interrupted extenranlly. inter-thread ints   --
--  are allowed, and used for thread synchronization. Pulpino irq/exception table fully supported by SW            --
--  runtime system.                                                                                                --
--  Contributors : Abdallah Cheikh.                                                                                --
--  last update: 27-08-2021                                                                                        --
---------------------------------------------------------------------------------------------------------------------

-- package riscv_kless is new work.riscv_klessydra
--   generic map (RV32E => 0);

-- ieee packages ------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_misc.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.textio.all;

-- local packages ------------
use work.riscv_klessydra.all;
--  use work.riscv_kless.all;

------------------------------------------------------------------------------------------------
--  ██╗  ██╗██╗     ███████╗███████╗███████╗██╗   ██╗██████╗ ██████╗  █████╗     ███╗   ███╗  --
--  ██║ ██╔╝██║     ██╔════╝██╔════╝██╔════╝╚██╗ ██╔╝██╔══██╗██╔══██╗██╔══██╗    ████╗ ████║  --
--  █████╔╝ ██║     █████╗  ███████╗███████╗ ╚████╔╝ ██║  ██║██████╔╝███████║    ██╔████╔██║  --
--  ██╔═██╗ ██║     ██╔══╝  ╚════██║╚════██║  ╚██╔╝  ██║  ██║██╔══██╗██╔══██║    ██║╚██╔╝██║  --
--  ██║  ██╗███████╗███████╗███████║███████║   ██║   ██████╔╝██║  ██║██║  ██║    ██║ ╚═╝ ██║  --
--  ╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝╚══════╝   ╚═╝   ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝    ╚═╝     ╚═╝  --
------------------------------------------------------------------------------------------------

-- core entity declaration --
entity klessydra_t0_3th_core is
  generic (
    lutram_rf               : natural := 0;   -- Changes the regfile from flip-flop type into LUTRAM type
    latch_rf                : natural := 0;   -- Changes the regfile from flip-flop type into Latch type (only works if lutram_rf is set to 0)
    RV32E                   : natural := 0;   -- Regfile size, Can be set to 32 for RV32E being 0 else 16 for RV32E being set to 1
    RV32M                   : natural := 1;   -- Enables the M-extension of the risc-v instruction set
    superscalar_exec_en     : natural := 1;   -- Enables superscalar execution when set to 1, else the stall of the pipeline will depend on tha latency of the instruction
    MCYCLE_EN               : natural := 0;   -- Can be set to 1 or 0 only. Setting to zero will disable MCYCLE and MCYCLEH
    MINSTRET_EN             : natural := 0;   -- Can be set to 1 or 0 only. Setting to zero will disable MINSTRET and MINSTRETH
    MHPMCOUNTER_EN          : natural := 0;   -- Can be set to 1 or 0 only. Setting to zero will disable all performance counters except "MCYCLE/H" and "MINSTRET/H"
    count_all               : natural := 1;   -- Perfomance counters count for all the harts instead of there own hart
    debug_en                : natural := 0;   -- Generates the debug unit
    tracer_en               : natural := 0;   -- Enables the generation of the instruction tracer disable in extremely long simulations in order to save storage space
    ----------------------------------------------------------------------------------------
    Data_Width              : natural := 32;
     ----------------------------------------------------------------------------------------
    N_EXT_PERF_COUNTERS     : integer := 0;   -- ignored in Klessydra
    INSTR_RDATA_WIDTH       : integer := 32;  -- ignored in Klessydra
    N_HWLP                  : integer := 2;   -- ignored in Klessydra
    N_HWLP_BITS             : integer := 4    -- ignored in Klessydra
    );
  port (
    -- clock, reset active low, test enable
    clk_i                   : in  std_logic;
    clock_en_i              : in  std_logic;
    rst_ni                  : in  std_logic;
    test_en_i               : in  std_logic;
    -- initialization signals 
    boot_addr_i             : in  std_logic_vector(31 downto 0);
    core_id_i               : in  std_logic_vector(3 downto 0);
    -- program memory interface
    instr_req_o             : out std_logic;
    instr_gnt_i             : in  std_logic;
    instr_rvalid_i          : in  std_logic;
    instr_addr_o            : out std_logic_vector(31 downto 0);
    instr_rdata_i           : in  std_logic_vector(31 downto 0);
    -- data memory interface
    data_req_o              : out std_logic;
    data_gnt_i              : in  std_logic;
    data_rvalid_i           : in  std_logic;
    data_we_o               : out std_logic;
    data_be_o               : out std_logic_vector(3 downto 0);
    data_addr_o             : out std_logic_vector(31 downto 0);
    data_wdata_o            : out std_logic_vector(31 downto 0);
    data_rdata_i            : in  std_logic_vector(31 downto 0);
    data_err_i              : in  std_logic;
    -- interrupt request interface
    irq_i                   : in  std_logic;
    irq_id_i                : in  std_logic_vector(4 downto 0);
    irq_ack_o               : out std_logic;
    irq_id_o                : out std_logic_vector(4 downto 0);
    irq_sec_i               : in  std_logic;  -- unused in Pulpino
    sec_lvl_o               : out std_logic;  -- unused in Pulpino
    -- debug interface
    debug_req_i             : in  std_logic;
    debug_gnt_o             : out std_logic;
    debug_rvalid_o          : out std_logic;
    debug_addr_i            : in  std_logic_vector(14 downto 0);
    debug_we_i              : in  std_logic;
    debug_wdata_i           : in  std_logic_vector(31 downto 0);
    debug_rdata_o           : out std_logic_vector(31 downto 0);
    debug_halted_o          : out std_logic;
    debug_halt_i            : in  std_logic;
    debug_resume_i          : in  std_logic;
    -- miscellanous control signals
    fetch_enable_i          : in  std_logic;
    core_busy_o             : out std_logic;
    ext_perf_counters_i     : in  std_logic_vector(N_EXT_PERF_COUNTERS to 1);
    -- klessydra-specific signals
    core_select             : in  natural range 1 downto 0;
    source_hartid_o         : out natural range THREAD_POOL_SIZE_GLOBAL-1 downto 0;
    sw_irq_o                : out std_logic_vector(THREAD_POOL_SIZE_GLOBAL-1 downto 0);
    sw_irq_served_i         : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
    sw_irq_served_o         : out std_logic_vector(THREAD_POOL_SIZE_GLOBAL-1 downto 0)
    );

end entity klessydra_t0_3th_core;

architecture Klessydra_M of klessydra_t0_3th_core is

  constant THREAD_POOL_SIZE_GEN           : natural := work.riscv_klessydra.THREAD_POOL_SIZE;
  constant THREAD_POOL_SIZE_GLOBAL_GEN    : natural := work.riscv_klessydra.THREAD_POOL_SIZE_GLOBAL;

  signal harc_EXEC               :natural range THREAD_POOL_SIZE-1 downto 0;
  signal pc_IE                   :std_logic_vector(31 downto 0);
  signal RS1_Data_IE             :std_logic_vector(31 downto 0);
  signal RS2_Data_IE             :std_logic_vector(31 downto 0);
  signal RD_Data_IE              :std_logic_vector(31 downto 0); -- unused

  constant RF_SIZE             : natural := 32-16*RV32E;
  constant RF_CEIL             : natural := integer(ceil(log2(real(RF_SIZE))));
  constant TPS_CEIL            : natural := integer(ceil(log2(real(THREAD_POOL_SIZE))));

  subtype harc_range is natural range THREAD_POOL_SIZE-1 downto 0;  -- will be used replicated units in the core

  -- Control Status Register (CSR) signals
  signal MHARTID     : MHARTID_array;
  signal MSTATUS     : MSTATUS_array;
  signal MEPC        : harc_vec_array;
  signal MCAUSE      : harc_vec_array;
  signal MIP         : harc_vec_array;
  signal MTVEC       : harc_vec_array;
  signal PCER        : harc_vec_array;

  signal sw_irq          : std_logic_vector(THREAD_POOL_SIZE_GLOBAL-1 downto 0);
  signal sw_irq_pending  : std_logic_vector(THREAD_POOL_SIZE_GLOBAL-1 downto 0);
  signal irq_pending     : std_logic_vector(harc_range);
  signal except_pc_vec_o : std_logic_vector(31 downto 0);
  signal WFI_Instr       : std_logic;

  -- Memory fault signals
  signal load_err, store_err : std_logic;

  -- Interface signals from EXEC unit to CSR management unit
  signal csr_instr_req       : std_logic;
  signal csr_instr_done      : std_logic;
  signal csr_access_denied_o : std_logic;
  signal csr_wdata_i         : std_logic_vector(31 downto 0);
  signal csr_op_i            : std_logic_vector(2 downto 0);
  signal csr_rdata_o         : std_logic_vector(31 downto 0);
  signal csr_addr_i          : std_logic_vector(11 downto 0);

  -- program counters --
  signal pc_IF     : std_logic_vector(31 downto 0);  -- pc_IF is the actual pc
  signal pc_ID     : std_logic_vector(31 downto 0);  -- pc_ID is the orogram counter of the Decode stage

  -- instruction register and instr. propagation registers --
  signal instr_word_IE    : std_logic_vector(31 downto 0);
  signal instr_rvalid_IE  : std_logic;  -- validity bit at IE input

  -- pc updater signals
  signal served_ie_except_condition      : std_logic_vector(harc_range);
  signal served_ls_except_condition      : std_logic_vector(harc_range);
  signal served_except_condition         : std_logic_vector(harc_range);
  signal served_mret_condition           : std_logic_vector(harc_range);
  signal served_irq                      : std_logic_vector(harc_range);
  signal served_pending_irq              : std_logic_vector(harc_range);
  signal taken_branch_pending            : std_logic_vector(harc_range);
  signal ie_except_data                  : std_logic_vector(31 downto 0);
  signal ls_except_data                  : std_logic_vector(31 downto 0);
  signal taken_branch                    : std_logic;
  signal ie_taken_branch                 : std_logic;
  signal ls_taken_branch                 : std_logic;
  signal set_branch_condition            : std_logic;
  signal ie_except_condition             : std_logic;
  signal ls_except_condition             : std_logic;
  signal set_except_condition            : std_logic;
  signal set_mret_condition              : std_logic;
  signal absolute_address                : std_logic_vector(31 downto 0);
  signal PC_offset                       : std_logic_vector(31 downto 0);
  signal pc_except_value                 : harc_vec_array;
  signal pc_except_value_wire            : harc_vec_array;
  signal incremented_pc                  : harc_vec_array;
  signal relative_to_PC                  : harc_vec_array;
  signal absolute_jump                   : std_logic_vector(harc_range);
  signal data_we_o_lat                   : std_logic;
  signal misaligned_err                  : std_logic;
  signal PC_offset_ID                    : std_logic_vector(31 downto 0);
  signal set_branch_condition_ID         : std_logic;
  signal core_enable_i                   : std_logic;

  -- AAA check if we need these signals
  -- signals for counting intructions
  --signal clock_cycle         : std_logic_vector(63 downto 0);  -- RDCYCLE
  --signal external_counter    : std_logic_vector(63 downto 0);  -- RDTIME
  --signal instruction_counter : std_logic_vector(63 downto 0);  -- RDINSTRET

  -- regfile replicated array
  signal regfile            : regfile_array;

  --signal used by counters
  signal set_wfi_condition          : std_logic;
  signal harc_to_csr                : natural range THREAD_POOL_SIZE_GLOBAL-1 downto 0;
  signal jump_instr                 : std_logic;
  signal jump_instr_lat             : std_logic;
  signal branch_instr               : std_logic;
  signal branch_instr_lat           : std_logic;

  -- auxiliary data memory interface signals
  signal data_addr_internal     : std_logic_vector(31 downto 0);
  signal data_be_internal       : std_logic_vector(3 downto 0);

  --Debug Unit signal and state
  signal ebreak_instr    : std_logic;

  -- hardware context id at fetch, and propagated hardware context ids
  --signal harc_count            : harc_min_range;
  signal harc_IF         : harc_range;
  signal harc_ID         : harc_range;

  -- Internal signal (VHDL1993)
  signal data_we_o_int          : std_logic;
  signal data_req_o_int         : std_logic;

  function and_const(a: natural; b: natural) return natural is
    variable c : natural;
  begin
    if a = b then
      c := 1;
    else
      c := 0;
    end if;
    return c;
  end function and_const;

  signal served_irq_lat          : std_logic_vector(harc_range);

  -- This function increments all the bits in a std_logic_vector
  function add_vect_bits(v: std_logic_vector) return natural is
    variable h: natural;
  begin
    h := 0;
    for i in v'range loop
      if v(i) = '1' then
        h := h + 1;
      end if;
    end loop;
    return h;
  end function add_vect_bits;

  component Program_Counter
  generic (
    THREAD_POOL_SIZE                  : natural
  );
  port (
    absolute_jump                     : in  std_logic_vector(harc_range);
    data_we_o_lat                     : in  std_logic;
    absolute_address                  : in  std_logic_vector(31 downto 0);
    PC_offset                         : in  std_logic_vector(31 downto 0);
    taken_branch                      : in  std_logic;
    ie_taken_branch                   : in  std_logic;
    ls_taken_branch                   : in  std_logic;
    set_branch_condition              : in  std_logic;
    ie_except_condition               : in  std_logic;
    ls_except_condition               : in  std_logic;
    set_except_condition              : in  std_logic;
    set_mret_condition                : in  std_logic;
    set_wfi_condition                 : in  std_logic;
    harc_ID                           : in  harc_range;
    harc_EXEC                         : in  natural range THREAD_POOL_SIZE-1 downto 0;
    instr_rvalid_IE                   : in  std_logic;
    pc_ID                             : in  std_logic_vector(31 downto 0);
    pc_IE                             : in  std_logic_vector(31 downto 0);
    MSTATUS                           : in  MSTATUS_array;
    MIP, MEPC, MCAUSE, MTVEC          : in  harc_vec_array;
    instr_word_IE                     : in  std_logic_vector(31 downto 0);
    pc_IF                             : out std_logic_vector(31 downto 0);
    harc_IF                           : out harc_range;
    served_ie_except_condition        : out std_logic_vector(harc_range);
    served_ls_except_condition        : out std_logic_vector(harc_range);
    served_except_condition           : out std_logic_vector(harc_range);
    served_mret_condition             : out std_logic_vector(harc_range);
    served_irq                        : in  std_logic_vector(harc_range);
    taken_branch_pending              : out std_logic_vector(harc_range);
    incremented_pc                    : out harc_vec_array;
    irq_pending                       : out std_logic_vector(harc_range);
    PC_offset_ID                      : in  std_logic_vector(31 downto 0);
    set_branch_condition_ID           : in  std_logic;
    clk_i                             : in  std_logic;
    rst_ni                            : in  std_logic;
    irq_i                             : in  std_logic;
    fetch_enable_i                    : in  std_logic;
    boot_addr_i                       : in  std_logic_vector(31 downto 0);
    instr_gnt_i                       : in  std_logic
    );
  end component;

  component CSR_Unit
  generic (
    THREAD_POOL_SIZE_GLOBAL     : natural;
    THREAD_POOL_SIZE            : natural;
    MCYCLE_EN                   : natural;
    MINSTRET_EN                 : natural;
    MHPMCOUNTER_EN              : natural;
    RF_CEIL                     : natural;
    count_all                   : natural
  );
  port (
    pc_IE                       : in  std_logic_vector(31 downto 0);
    ie_except_data              : in  std_logic_vector(31 downto 0);
    ls_except_data              : in  std_logic_vector(31 downto 0);
    served_ie_except_condition  : in  std_logic_vector(harc_range);
    served_ls_except_condition  : in  std_logic_vector(harc_range);
    harc_EXEC                   : in  natural range THREAD_POOL_SIZE-1 downto 0;
    harc_to_csr                 : in  natural range THREAD_POOL_SIZE_GLOBAL-1 downto 0;
    instr_word_IE               : in  std_logic_vector(31 downto 0);
    served_except_condition     : in  std_logic_vector(harc_range);
    served_mret_condition       : in  std_logic_vector(harc_range);
    served_irq                  : in  std_logic_vector(harc_range);
    served_pending_irq          : in  std_logic_vector(harc_range);
    pc_except_value_wire        : in  harc_vec_array;
    data_addr_internal          : in  std_logic_vector(31 downto 0);
    jump_instr                  : in  std_logic;
    branch_instr                : in  std_logic;
    set_branch_condition        : in  std_logic;
    csr_instr_req               : in  std_logic;
    misaligned_err              : in  std_logic;
    WFI_Instr                   : in  std_logic;
    csr_wdata_i                 : in  std_logic_vector(31 downto 0);
    csr_op_i                    : in  std_logic_vector(2  downto 0);
    csr_addr_i                  : in  std_logic_vector(11 downto 0);
    csr_instr_done              : out std_logic;
    csr_access_denied_o         : out std_logic;
    csr_rdata_o                 : out std_logic_vector (31 downto 0);
    MHARTID                     : out MHARTID_array;
    MSTATUS                     : out MSTATUS_array;
    MEPC                        : out harc_vec_array;
    MCAUSE                      : out harc_vec_array;
    MIP                         : out harc_vec_array;
    MTVEC                       : out harc_vec_array;
    MSCRATCH                       : out harc_vec_array;
    PCER                        : out harc_vec_array;
    fetch_enable_i              : in  std_logic;
    clk_i                       : in  std_logic;
    rst_ni                      : in  std_logic;
    core_id_i                   : in  std_logic_vector(3 downto 0);
    instr_rvalid_i              : in  std_logic;
    instr_rvalid_IE             : in  std_logic;
    data_we_o                   : in  std_logic;
    data_req_o                  : in  std_logic;
    data_gnt_i                  : in  std_logic;
    irq_i                       : in  std_logic;
    irq_id_i                    : in  std_logic_vector(4 downto 0);
    irq_id_o                    : out std_logic_vector(4 downto 0);
    irq_ack_o                   : out std_logic;
    sw_irq                      : in  std_logic_vector(THREAD_POOL_SIZE_GLOBAL-1 downto 0);
    sw_irq_pending              : in  std_logic_vector(THREAD_POOL_SIZE_GLOBAL-1 downto 0)
    );
  end component;

  component Pipeline
  generic(
    THREAD_POOL_SIZE_GLOBAL    : natural;
    THREAD_POOL_SIZE           : natural;
    lutram_rf                  : natural;
    latch_rf                   : natural;
    RV32E                      : natural;
    RV32M                      : natural;
    superscalar_exec_en        : natural;
    MCYCLE_EN                  : natural;
    MINSTRET_EN                : natural;
    MHPMCOUNTER_EN             : natural;
    count_all                  : natural;
    debug_en                   : natural;
    tracer_en                  : natural;
    -------------------------------------
    RF_SIZE                    : natural;
    RF_CEIL                    : natural
    --TPS_CEIL                   : natural
    );
  port (
    pc_IF                      : in  std_logic_vector(31 downto 0);
    harc_IF                    : in  harc_range;
    irq_pending                : in  std_logic_vector(harc_range);
    csr_instr_done             : in  std_logic;
    csr_access_denied_o        : in  std_logic;
    csr_rdata_o                : in  std_logic_vector (31 downto 0);
    MHARTID                    : in  MHARTID_array;
    MSTATUS                    : in  MSTATUS_array;
    PCER                       : in  harc_vec_array;
    served_irq                 : out std_logic_vector(harc_range);
    served_pending_irq         : out std_logic_vector(harc_range);
    misaligned_err             : out std_logic;
    pc_ID                      : out std_logic_vector(31 downto 0);
    pc_IE                      : out std_logic_vector(31 downto 0);
    ie_except_data             : out std_logic_vector(31 downto 0);
    ls_except_data             : out std_logic_vector(31 downto 0);
    taken_branch               : out std_logic;
    ie_taken_branch            : out std_logic;
    ls_taken_branch            : out std_logic;
    set_branch_condition       : out std_logic;
    set_except_condition       : out std_logic;        
    ie_except_condition        : out std_logic;
    ls_except_condition        : out std_logic;
    set_mret_condition         : out std_logic;
    set_wfi_condition          : out std_logic;
    csr_instr_req              : out std_logic;
    instr_rvalid_IE            : out std_logic;  -- validity bit at IE input
    csr_addr_i                 : out std_logic_vector (11 downto 0);
    csr_wdata_i                : out std_logic_vector (31 downto 0);
    csr_op_i                   : out std_logic_vector (2 downto 0);
    jump_instr                 : out std_logic;
    jump_instr_lat             : out std_logic;
    branch_instr               : out std_logic;
    branch_instr_lat           : out std_logic;
    harc_ID                    : out harc_range;
    harc_EXEC                  : out natural range THREAD_POOL_SIZE-1 downto 0;
    harc_to_csr                : out natural range THREAD_POOL_SIZE_GLOBAL-1 downto 0;
    instr_word_IE              : out std_logic_vector(31 downto 0);
    PC_offset                  : out std_logic_vector(31 downto 0);
    absolute_address           : out std_logic_vector(31 downto 0);
    ebreak_instr               : out std_logic;
    data_addr_internal         : out std_logic_vector(31 downto 0);
    absolute_jump              : out std_logic_vector(harc_range);
    regfile                    : out regfile_array;
    PC_offset_ID               : out std_logic_vector(31 downto 0);
    set_branch_condition_ID    : out std_logic;
    WFI_Instr                  : out std_logic;
    -- clock, reset active low, test enable
    clk_i                      : in  std_logic;
    rst_ni                     : in  std_logic;
    -- program memory interface
    instr_req_o                : out std_logic;
    instr_gnt_i                : in  std_logic;
    instr_rvalid_i             : in  std_logic;
    instr_rdata_i              : in  std_logic_vector(31 downto 0);
    -- data memory interface
    data_req_o                 : out std_logic;
    data_gnt_i                 : in  std_logic;
    data_rvalid_i              : in  std_logic;
    data_we_o                  : out std_logic;
    data_be_o                  : out std_logic_vector(3 downto 0);
    data_addr_o                : out std_logic_vector(31 downto 0);
    data_wdata_o               : out std_logic_vector(31 downto 0);
    data_rdata_i               : in  std_logic_vector(31 downto 0);
    data_err_i                 : in  std_logic;
    -- interrupt request interface
    irq_i                      : in  std_logic;
    -- miscellanous control signals
    fetch_enable_i             : in  std_logic;
    core_busy_o                : out std_logic;
    -- klessydra-specific signals
    core_enable_i              : in  std_logic;
    source_hartid_o            : out natural range THREAD_POOL_SIZE_GLOBAL-1 downto 0;
    sw_irq                     : out std_logic_vector(THREAD_POOL_SIZE_GLOBAL-1 downto 0);
    sw_irq_served_i            : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
    sw_irq_served_o            : out std_logic_vector(THREAD_POOL_SIZE_GLOBAL-1 downto 0);
    sw_irq_pending             : out std_logic_vector(THREAD_POOL_SIZE_GLOBAL-1 downto 0);
    -- VCU Signals
    RS1_Data_IE                : out std_logic_vector(31 downto 0);
    RS2_Data_IE                : out std_logic_vector(31 downto 0);
    RD_Data_IE                 : out std_logic_vector(31 downto 0);  -- unused
    state_LS                   : out fsm_LS_states
  );
  end component;
  
  
--------------------------------------------------------------------------------------------------
----------------------- ARCHITECTURE BEGIN -------------------------------------------------------              
begin
  data_we_o <= data_we_o_int;
  data_req_o <= data_req_o_int;

  -- Connecting signals to ports
  data_we_o <= data_we_o_int;
  data_req_o <= data_req_o_int;

  sw_irq_o <= sw_irq;

  assert (lutram_rf /= debug_en and lutram_rf /= 1) report "Debug-Unit cannot read from a LUTRAM regfile." severity WARNING;

  instr_addr_o <= pc_IF;

  process(pc_except_value, set_except_condition, pc_IE, pc_except_value_wire, harc_EXEC) --VHDL1993
  begin
    pc_except_value_wire <= pc_except_value;
    if set_except_condition  = '1' then
      pc_except_value_wire(harc_EXEC) <=  pc_IE;    
    end if;
  end process;

  process(clk_i, rst_ni)
  begin
    if rst_ni = '0' then
    elsif rising_edge(clk_i) then
      pc_except_value <= pc_except_value_wire;
    end if;
  end process;

  Prg_Ctr : Program_Counter
    generic map (
      THREAD_POOL_SIZE            => THREAD_POOL_SIZE_GEN
      )
    port map(
      absolute_jump               => absolute_jump,
      data_we_o_lat               => data_we_o_lat,
      absolute_address            => absolute_address,       
      PC_offset                   => PC_offset,
      taken_branch                => taken_branch,
      ie_taken_branch             => ie_taken_branch,
      ls_taken_branch             => ls_taken_branch,
      set_branch_condition        => set_branch_condition,
      ie_except_condition         => ie_except_condition,
      ls_except_condition         => ls_except_condition,
      set_except_condition        => set_except_condition,
      set_mret_condition          => set_mret_condition,
      set_wfi_condition           => set_wfi_condition,
      harc_ID                     => harc_ID,
      harc_EXEC                   => harc_EXEC,
      instr_rvalid_IE             => instr_rvalid_IE,
      pc_ID                       => pc_ID,
      pc_IE                       => pc_IE,
      MIP                         => MIP,
      MEPC                        => MEPC,
      MSTATUS                     => MSTATUS,
      MCAUSE                      => MCAUSE,
      MTVEC                       => MTVEC,
      instr_word_IE               => instr_word_IE,
      pc_IF                       => pc_IF,
      harc_IF                     => harc_IF,
      served_ie_except_condition  => served_ie_except_condition,
      served_ls_except_condition  => served_ls_except_condition,
      served_except_condition     => served_except_condition,
      served_mret_condition       => served_mret_condition,
      served_irq                  => served_irq,
      taken_branch_pending        => taken_branch_pending,
      incremented_pc              => incremented_pc,
      irq_pending                 => irq_pending,
      PC_offset_ID                => PC_offset_ID,
      set_branch_condition_ID     => set_branch_condition_ID,
      clk_i                       => clk_i,
      rst_ni                      => rst_ni,
      irq_i                       => irq_i,
      fetch_enable_i              => fetch_enable_i,
      boot_addr_i                 => boot_addr_i,
      instr_gnt_i                 => instr_gnt_i
      );

  CSR : CSR_Unit
    generic map (
      THREAD_POOL_SIZE_GLOBAL     => THREAD_POOL_SIZE_GLOBAL_GEN,
      THREAD_POOL_SIZE            => THREAD_POOL_SIZE_GEN,
      MCYCLE_EN                   => MCYCLE_EN,
      MINSTRET_EN                 => MINSTRET_EN,
      MHPMCOUNTER_EN              => MHPMCOUNTER_EN,
      RF_CEIL                     => RF_CEIL,
      count_all                   => count_all
    )
    port map(
      pc_IE                       => pc_IE,
      ie_except_data              => ie_except_data,
      ls_except_data              => ls_except_data,
      served_ie_except_condition  => served_ie_except_condition,
      served_ls_except_condition  => served_ls_except_condition,
      harc_EXEC                   => harc_EXEC,
      harc_to_csr                 => harc_to_csr,
      instr_word_IE               => instr_word_IE,
      served_except_condition     => served_except_condition,
      served_mret_condition       => served_mret_condition,
      served_irq                  => served_irq,
      served_pending_irq          => served_pending_irq,
      pc_except_value_wire        => pc_except_value_wire,
      data_addr_internal          => data_addr_internal,
      jump_instr                  => jump_instr,
      branch_instr                => branch_instr,
      set_branch_condition        => set_branch_condition,
      csr_instr_req               => csr_instr_req,
      misaligned_err              => misaligned_err,
      WFI_Instr                   => WFI_Instr,
      csr_wdata_i                 => csr_wdata_i,
      csr_op_i                    => csr_op_i,
      csr_addr_i                  => csr_addr_i,
      csr_instr_done              => csr_instr_done,
      csr_access_denied_o         => csr_access_denied_o,
      csr_rdata_o                 => csr_rdata_o,
      MHARTID                     => MHARTID,
      MSTATUS                     => MSTATUS,
      MEPC                        => MEPC,
      MCAUSE                      => MCAUSE,
      MIP                         => MIP,
      MTVEC                       => MTVEC,
      PCER                        => PCER,
      fetch_enable_i              => fetch_enable_i,
      clk_i                       => clk_i,
      rst_ni                      => rst_ni,
      core_id_i                   => core_id_i,
      instr_rvalid_i              => instr_rvalid_i,
      instr_rvalid_IE             => instr_rvalid_IE,
      data_we_o                   => data_we_o_int,
      data_req_o                  => data_req_o_int,
      data_gnt_i                  => data_gnt_i,
      irq_i                       => irq_i,
      irq_id_i                    => irq_id_i,
      irq_id_o                    => irq_id_o,
      irq_ack_o                   => irq_ack_o,
      sw_irq                      => sw_irq,
      sw_irq_pending              => sw_irq_pending
      );

  Pipe : Pipeline
    generic map(
      THREAD_POOL_SIZE_GLOBAL => THREAD_POOL_SIZE_GLOBAL_GEN,
      THREAD_POOL_SIZE        => THREAD_POOL_SIZE_GEN,
      lutram_rf               => lutram_rf,
      latch_rf                => latch_rf,
      RV32E                   => RV32E,
      RV32M                   => RV32M,
      superscalar_exec_en     => superscalar_exec_en,
      MCYCLE_EN               => MCYCLE_EN,
      MINSTRET_EN             => MINSTRET_EN,
      MHPMCOUNTER_EN          => MHPMCOUNTER_EN,
      count_all               => count_all,
      debug_en                => debug_en,
      tracer_en               => tracer_en,
      -----------------------------------
      RF_SIZE                 => RF_SIZE,
      RF_CEIL                 => RF_CEIL
      --TPS_CEIL                => TPS_CEIL
      )
    port map(
      pc_IF                      => pc_IF,
      harc_IF                    => harc_IF,
      irq_pending                => irq_pending,
      csr_instr_done             => csr_instr_done,
      csr_access_denied_o        => csr_access_denied_o,
      csr_rdata_o                => csr_rdata_o,
      pc_ID                      => pc_ID,
      pc_IE                      => pc_IE,
      ie_except_data             => ie_except_data,
      ls_except_data             => ls_except_data,
      MHARTID                    => MHARTID,
      MSTATUS                    => MSTATUS,
      PCER                       => PCER,
      served_irq                 => served_irq,
      served_pending_irq         => served_pending_irq,
      misaligned_err             => misaligned_err,
      WFI_Instr                  => WFI_Instr,
      taken_branch               => taken_branch,
      ie_taken_branch            => ie_taken_branch,
      ls_taken_branch            => ls_taken_branch,
      set_branch_condition       => set_branch_condition,
      set_except_condition       => set_except_condition,
      ie_except_condition        => ie_except_condition,
      ls_except_condition        => ls_except_condition,
      set_mret_condition         => set_mret_condition,
      set_wfi_condition          => set_wfi_condition,
      csr_instr_req              => csr_instr_req,
      instr_rvalid_IE            => instr_rvalid_IE,
      csr_addr_i                 => csr_addr_i,
      csr_wdata_i                => csr_wdata_i,
      csr_op_i                   => csr_op_i,
      jump_instr                 => jump_instr,
      jump_instr_lat             => jump_instr_lat,
      branch_instr               => branch_instr,
      branch_instr_lat           => branch_instr_lat,
      harc_ID                    => harc_ID,
      harc_EXEC                  => harc_EXEC,
      harc_to_csr                => harc_to_csr,
      instr_word_IE              => instr_word_IE,
      PC_offset                  => PC_offset,
      absolute_address           => absolute_address,
      ebreak_instr               => ebreak_instr,
      data_addr_internal         => data_addr_internal,
      absolute_jump              => absolute_jump,
      regfile                    => regfile,
      PC_offset_ID               => PC_offset_ID,
      set_branch_condition_ID    => set_branch_condition_ID,
      clk_i                      => clk_i,
      rst_ni                     => rst_ni,
      instr_req_o                => instr_req_o,
      instr_gnt_i                => instr_gnt_i,
      instr_rvalid_i             => instr_rvalid_i,
      instr_rdata_i              => instr_rdata_i,
      data_req_o                 => data_req_o_int,
      data_gnt_i                 => data_gnt_i,
      data_rvalid_i              => data_rvalid_i,
      data_we_o                  => data_we_o_int,
      data_be_o                  => data_be_o,
      data_addr_o                => data_addr_o,
      data_wdata_o               => data_wdata_o,
      data_rdata_i               => data_rdata_i,
      data_err_i                 => data_err_i,
      irq_i                      => irq_i,
      fetch_enable_i             => fetch_enable_i,
      core_busy_o                => core_busy_o,
      core_enable_i              => core_enable_i,
      source_hartid_o            => source_hartid_o,
      sw_irq                     => sw_irq,
      sw_irq_served_i            => sw_irq_served_i, 
      sw_irq_served_o            => sw_irq_served_o,
      sw_irq_pending             => sw_irq_pending,
      RS1_Data_IE                => RS1_Data_IE,
      RS2_Data_IE                => RS2_Data_IE,
      RD_Data_IE                 => RD_Data_IE,
      state_LS                   => open
      );

end Klessydra_M;
--------------------------------------------------------------------------------------------------
-- END of Klessydra M core architecture ----------------------------------------------------------
--------------------------------------------------------------------------------------------------
