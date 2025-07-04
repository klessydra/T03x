--------------------------------------------------------------------------------------------------------------
--  PC -- (Program Counters and hart interleavers)                                                          --
--  Author(s): Abdallah Cheikh abdallah.cheikh@uniroma1.it (abdallah93.as@gmail.com)                        --
--                                                                                                          --
--  Date Modified: 17-11-2019                                                                               --
--------------------------------------------------------------------------------------------------------------
--  Program Counter Managing Units -- synchronous process, sinle cycle.                                     --
--  Note: in the present version, gives priority to branching over trapping, except LSU and DSP traps       -- 
--  i.e. branch instructions are not interruptible. This can be changed but may be unsafe.                  --
--  Implements as many PC units as the  number of harts supported                                           --
--  This entity also implements the hardware context counters that interleve the harts in the core.         --
--------------------------------------------------------------------------------------------------------------


-- ieee packages ------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_misc.all;
use ieee.numeric_std.all;
use std.textio.all;

-- local packages ------------
use work.riscv_klessydra.all;

entity Program_Counter is
  generic (
    debug_en                          : natural;
    THREAD_POOL_SIZE                  : natural
  );
  port (
    absolute_jump                     : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
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
    ------------------------------------------------------------------------------
    gnt_waiting                       : in  std_logic;
    fetch_busy_dbg                    : in  std_logic;
    DEBUG_MODE                        : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
    DPC                               : in  harc_vec_array;
    halt_req                          : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
    debug_pc_taken_wire               : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
    halt_served                       : out std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
    reset_state                       : out std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
    dm_halt_addr_i                    : in  std_logic_vector(31 downto 0);
    dm_exception_addr_i               : in  std_logic_vector(31 downto 0);
    taken_branch_addr_out             : out std_logic_vector(31 downto 0);
    dret_instr                        : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0); 
    state_waiting_for_halt_serv       : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0); 
    ------------------------------------------------------------------------------
    harc_ID                           : in  natural range THREAD_POOL_SIZE-1 downto 0;
    harc_EXEC                         : in  natural range THREAD_POOL_SIZE-1 downto 0;
    instr_rvalid_IE                   : in  std_logic;
    pc_ID                             : in  std_logic_vector(31 downto 0);
    pc_IE                             : in  std_logic_vector(31 downto 0);
    MSTATUS                           : in  MSTATUS_array;
    MIP, MEPC, MCAUSE, MTVEC          : in  harc_vec_array;
    instr_word_IE                     : in  std_logic_vector(31 downto 0);
    pc_IF                             : out std_logic_vector(31 downto 0);
    harc_IF                           : out natural range THREAD_POOL_SIZE-1 downto 0;
    served_ie_except_condition        : out std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
    served_ls_except_condition        : out std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
    served_except_condition           : out std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
    served_mret_condition             : out std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
    served_irq                        : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
    taken_branch_pending              : out std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
    incremented_pc                    : out harc_vec_array;
    irq_pending                       : out std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
    PC_offset_ID                      : in  std_logic_vector(31 downto 0);
    set_branch_condition_ID           : in  std_logic;
    clk_i                             : in  std_logic;
    rst_ni                            : in  std_logic;
    irq_i                             : in  std_logic;
    fetch_enable_i                    : in  std_logic;
    boot_addr_i                       : in  std_logic_vector(31 downto 0);
    instr_gnt_i                       : in  std_logic
    );
end entity;


architecture PC of Program_counter is

  subtype harc_range is natural range THREAD_POOL_SIZE-1 downto 0;

  -- pc updater signals
  signal pc_update_enable                      : std_logic_vector(harc_range);
  signal taken_branch_replicated               : std_logic_vector(harc_range);
  signal ls_except_condition_replicated        : std_logic_vector(harc_range);
  signal ie_except_condition_replicated        : std_logic_vector(harc_range);
  signal set_except_condition_replicated       : std_logic_vector(harc_range);
  signal set_trap_condition_replicated         : std_logic_vector(harc_range);
  signal set_mret_condition_replicated         : std_logic_vector(harc_range);
  signal set_branch_condition_ID_replicated    : std_logic_vector(harc_range);
  signal set_branch_condition_replicated       : std_logic_vector(harc_range);
  signal set_wfi_condition_replicated          : std_logic_vector(harc_range);
  signal relative_to_PC                        : harc_vec_array;
  signal pc                                    : harc_vec_array;
  signal pc_wire                               : harc_vec_array;
  signal harc_IF_internal                      : harc_range;
  signal harc_IF_internal_wire                 : harc_range;
  signal mret_condition_pending_internal       : std_logic_vector(harc_range);
  signal incremented_pc_internal               : harc_vec_array;
  signal trap_addr                             : harc_vec_array;
  signal mepc_addr_internal                    : harc_vec_array;
  signal taken_branch_addr_internal            : harc_vec_array;
  signal taken_branch_pc_pending_internal      : harc_vec_array;
  signal taken_branch_pending_internal         : std_logic_vector(harc_range);
  signal irq_pending_internal                  : std_logic_vector(harc_range);
  signal halt_served_internal                  : std_logic_vector(THREAD_POOL_SIZE-1 downto 0);

  signal taken_branch_pc_pending_internal_lat  : harc_vec_array;
  signal taken_branch_pending_internal_lat     : std_logic_vector(harc_range);
  signal served_ie_except_condition_lat        : std_logic_vector(harc_range);
  signal served_ls_except_condition_lat        : std_logic_vector(harc_range);
  signal served_except_condition_lat           : std_logic_vector(harc_range);
  signal served_mret_condition_lat             : std_logic_vector(harc_range);

  signal halt_en                               : std_logic_vector(harc_range);
  signal harc_is_in_fetch                      : std_logic_vector(THREAD_POOL_SIZE-1 downto 0);

  -- Internal signals (VHDL1993)
  signal served_ie_except_condition_int        : std_logic_vector(harc_range);
  signal served_ls_except_condition_int        : std_logic_vector(harc_range);
  signal served_except_condition_int           : std_logic_vector(harc_range);
  signal served_mret_condition_int             : std_logic_vector(harc_range);

  signal reset_state_internal                  : std_logic_vector(harc_range);
  ------------------------------------------------------------------------------------------------------------
  -- Subroutine implementing pc updating combinational logic, that is replicated for the threads supported  --
  ------------------------------------------------------------------------------------------------------------
  procedure pc_update_no_dbg(
    signal fetch_enable_i                : in    std_logic;
    signal MTVEC                         : in    std_logic_vector(31 downto 0);
    signal instr_gnt_i, taken_branch     : in    std_logic;
    signal set_branch_condition_ID       : in    std_logic;
    signal set_wfi_condition             : in    std_logic;
    signal taken_branch_pending          : inout std_logic;
    signal taken_branch_pending_lat      : in    std_logic;
    signal irq_pending                   : in    std_logic;
    signal ie_except_condition           : in    std_logic;
    signal ls_except_condition           : in    std_logic;
    signal set_except_condition          : in    std_logic;
    signal set_mret_condition            : in    std_logic;
    signal pc                            : inout std_logic_vector(31 downto 0);
    signal taken_branch_addr             : in    std_logic_vector(31 downto 0);
    signal taken_branch_pc_pending       : inout std_logic_vector(31 downto 0);
    signal taken_branch_pc_pending_lat   : in    std_logic_vector(31 downto 0);
    signal incremented_pc                : in    std_logic_vector(31 downto 0);
    signal pc_update_enable              : in    std_logic;
    signal served_ie_except_condition    : out   std_logic;
    signal served_ls_except_condition    : out   std_logic;
    signal served_except_condition       : out   std_logic;
    signal served_mret_condition         : out   std_logic) is
  begin
    if pc_update_enable          = '1' then
      if taken_branch            = '1' or
         set_branch_condition_ID = '1' then
        pc                          <= taken_branch_addr;
        taken_branch_pending        <= '0';
        served_ie_except_condition  <= ie_except_condition;
        served_ls_except_condition  <= ls_except_condition;
        served_except_condition     <= set_except_condition;
        served_mret_condition       <= set_mret_condition;
      elsif taken_branch_pending_lat = '1' then
        pc                          <= taken_branch_pc_pending_lat;
        taken_branch_pending        <= '0';
        served_ie_except_condition  <= ie_except_condition;
        served_ls_except_condition  <= ls_except_condition;
        served_except_condition     <= set_except_condition;
        served_mret_condition       <= set_mret_condition;
      else
        pc                          <= incremented_pc;
        served_except_condition     <= '0';
        served_ie_except_condition  <= '0';
        served_ls_except_condition  <= '0';
        served_mret_condition       <= '0';
      end if;
      -- end of pc value update ---    
    else                                -- sets registers to record pending requests
      served_except_condition <= set_except_condition;
      served_mret_condition   <= set_mret_condition and fetch_enable_i;
      if taken_branch            = '1' or 
         set_branch_condition_ID = '1' then 
        taken_branch_pending <= '1';
        taken_branch_pc_pending <= taken_branch_addr;
      end if;
      if ls_except_condition = '1' then
        served_ls_except_condition <= '1';
      elsif ie_except_condition = '1' then
        served_ie_except_condition <= '1';
      end if;
    end if;
  end pc_update_no_dbg;

  procedure pc_update_dbg(
    signal fetch_enable_i                : in    std_logic;
    signal MTVEC                         : in    std_logic_vector(31 downto 0);
    signal instr_gnt_i, taken_branch     : in    std_logic;
    signal set_branch_condition_ID       : in    std_logic;
    signal set_wfi_condition             : in    std_logic;
    signal taken_branch_pending          : inout std_logic;
    signal taken_branch_pending_lat      : in    std_logic;
    signal irq_pending                   : in    std_logic;
    signal ie_except_condition           : in    std_logic;
    signal ls_except_condition           : in    std_logic;
    signal set_except_condition          : in    std_logic;
    signal set_mret_condition            : in    std_logic;
    signal halt_req                      : in    std_logic;
    signal dm_halt_addr_i                : in    std_logic_vector(31 downto 0);
    signal dret_instr                    : in    std_logic;
    signal DPC                           : in    std_logic_vector(31 downto 0);
    signal harc_is_in_fetch              : in    std_logic;
    signal pc                            : inout std_logic_vector(31 downto 0);
    signal taken_branch_addr             : in    std_logic_vector(31 downto 0);
    signal taken_branch_pc_pending       : inout std_logic_vector(31 downto 0);
    signal taken_branch_pc_pending_lat   : in    std_logic_vector(31 downto 0);
    signal incremented_pc                : in    std_logic_vector(31 downto 0);
    signal pc_update_enable              : in    std_logic;
    signal served_ie_except_condition    : out   std_logic;
    signal served_ls_except_condition    : out   std_logic;
    signal served_except_condition       : out   std_logic;
    signal served_mret_condition         : out   std_logic) is
  begin
    if halt_req = '1' and harc_is_in_fetch = '0' then                                                         
        pc                          <= dm_halt_addr_i; 
        served_except_condition     <= '0';
        served_ie_except_condition  <= '0';
        served_ls_except_condition  <= '0';
        served_mret_condition       <= '0';
        taken_branch_pending        <= '0'; --QUI

    elsif dret_instr = '1' then      --pc <= dpc
      pc                          <= dpc;
      served_except_condition     <= '0';
      served_ie_except_condition  <= '0';
      served_ls_except_condition  <= '0';
      served_mret_condition       <= '0';
      
    elsif pc_update_enable  = '1' then 
      if taken_branch            = '1' or
         set_branch_condition_ID = '1' then
        pc                          <= taken_branch_addr;
        taken_branch_pending        <= '0';
        served_ie_except_condition  <= ie_except_condition;
        served_ls_except_condition  <= ls_except_condition;
        served_except_condition     <= set_except_condition;
        served_mret_condition       <= set_mret_condition;
      elsif taken_branch_pending_lat = '1' then
        pc                          <= taken_branch_pc_pending_lat;
        taken_branch_pending        <= '0';
        served_ie_except_condition  <= ie_except_condition;
        served_ls_except_condition  <= ls_except_condition;
        served_except_condition     <= set_except_condition;
        served_mret_condition       <= set_mret_condition;
      else
        pc                          <= incremented_pc;
        served_except_condition     <= '0';
        served_ie_except_condition  <= '0';
        served_ls_except_condition  <= '0';
        served_mret_condition       <= '0';
      end if;
      -- end of pc value update ---    
    else                                -- sets registers to record pending requests
      served_except_condition <= set_except_condition;
      served_mret_condition   <= set_mret_condition and fetch_enable_i;
      if taken_branch            = '1' or 
         set_branch_condition_ID = '1' then 
        taken_branch_pending <= '1';
        taken_branch_pc_pending <= taken_branch_addr;
      end if;
      if ls_except_condition = '1' then
        served_ls_except_condition <= '1';
      elsif ie_except_condition = '1' then
        served_ie_except_condition <= '1';
      end if;
    end if;
  end pc_update_dbg;
  --------------------------------------------------------------------------------------

begin

  harc_IF                  <= harc_IF_internal;
  incremented_pc           <= incremented_pc_internal;
  taken_branch_pending     <= taken_branch_pending_internal;
  irq_pending              <= irq_pending_internal;

  debug_sig_gen: if debug_en = 1 generate
    halt_served              <= halt_served_internal;
    reset_state              <= reset_state_internal;
  
    taken_branch_addr_out <= taken_branch_addr_internal(harc_EXEC);
    
    harc_is_in_state_gen: for i in harc_range generate
    begin
        harc_is_in_fetch(i) <= '1' when harc_IF_internal = i else '0';
    end generate harc_is_in_state_gen;

  end generate debug_sig_gen;

  -- Connecting internal signals to ports
  served_ie_except_condition <= served_ie_except_condition_int;
  served_ls_except_condition <= served_ls_except_condition_int;
  served_except_condition <= served_except_condition_int;
  served_mret_condition <= served_mret_condition_int;

  debug_hw_ctx_nen: if debug_en = 0 generate
    hardware_context_counter : process(clk_i, rst_ni)
    begin
      if rst_ni = '0' then
        harc_IF_internal <= THREAD_POOL_SIZE-1;
      elsif rising_edge(clk_i) then
        if instr_gnt_i = '1' then
          if harc_IF_internal > 0 then
            harc_IF_internal <= harc_IF_internal-1;
          else 
            harc_IF_internal <= THREAD_POOL_SIZE-1;
          end if;
        end if;
      end if;
    end process hardware_context_counter;
  end generate debug_hw_ctx_nen;

  debug_hw_ctx_en: if debug_en = 1 generate
    hardware_context_counter : process(clk_i, rst_ni)
    begin
      if rst_ni = '0' then
        harc_IF_internal <= THREAD_POOL_SIZE-1;
      elsif rising_edge(clk_i) then
        if ( (instr_gnt_i = '1' or gnt_waiting = '1') and fetch_busy_dbg = '0' and to_integer(unsigned(debug_pc_taken_wire)) = 0) then
          if harc_IF_internal > 0 then
            harc_IF_internal <= harc_IF_internal-1;
          else 
            harc_IF_internal <= THREAD_POOL_SIZE-1;
          end if;
        end if;
      end if;
    end process hardware_context_counter;
  end generate debug_hw_ctx_en;

  pc_IF <= pc(harc_IF_internal);

  ----------------------------------------------------------------------------------------------
  -- this part of logic and registers is replicated as many times as the supported threads:   --
  pc_update_logic : for h in harc_range generate

    mepc_addr_internal(h) <= MEPC(h) when MCAUSE(h)(30) = '0' else std_logic_vector(unsigned(MEPC(h)) + 4);  -- MCAUSE(30) = '0' indicates that we weren't executing a WFI instruction

    incremented_pc_internal(h) <= std_logic_vector(unsigned(pc(h))+4);
    irq_pending_internal(h)    <= ((MIP(h)(11) or MIP(h)(7) or MIP(h)(3)) and MSTATUS(h)(0)); -- prevents servicing interrupts during trap routines

    taken_branch_replicated(h) <= '1' when ls_taken_branch  = '1' and (harc_EXEC = h)
	                                   else '1' when ie_taken_branch  = '1' and (harc_EXEC = h)
                                     else '0';
    ls_except_condition_replicated(h)  <= '1' when ls_except_condition = '1' and (harc_EXEC = h)
                                     else '0';
    ie_except_condition_replicated(h)  <= '1' when ie_except_condition = '1' and (harc_EXEC = h)
                                     else '0';
    set_except_condition_replicated(h) <= '1' when ls_except_condition_replicated(h) = '1' or ie_except_condition_replicated(h) = '1'
                                     else '0'; -- replicated so that only one hart serves the exception and not more
    -- the abscence of the replicated singals below will create a problem with set_branch_condition_ID_replicated
    set_branch_condition_replicated(h) <= '1' when set_branch_condition = '1' and (harc_EXEC = h)
                                     else '0';
    set_wfi_condition_replicated(h)    <= '1' when set_wfi_condition = '1' and (harc_EXEC = h)
                                     else '0';
    set_mret_condition_replicated(h)   <= '1' when set_mret_condition = '1' and (harc_EXEC = h)
                                     else '0'; -- replicated so that only one hart serves the mret and not more
    set_branch_condition_ID_replicated(h) <= '1' when set_branch_condition_ID = '1' and (harc_ID = h)
                                     else '0';
    set_trap_condition_replicated(h) <= set_except_condition_replicated(h) or served_irq(h);

    -- latch on the branch address, possibly useless but may be needed in future situations, served_irq has the highest priority, interrupt request are checked before executing any instructions in the IE_Stage

    debug_pc_asin_nen: if debug_en = 0 generate
      taken_branch_addr_internal(h) <=
        absolute_address      when absolute_jump(h)                      = '1' else  -- sets a jump or a branch address
        PC_offset             when set_branch_condition_replicated(h)    = '1' or set_wfi_condition_replicated(h) = '1'  else  -- sets a jump or a branch address
        MTVEC(h)              when set_trap_condition_replicated(h)      = '1' else  -- sets MTVEC address for traps
        mepc_addr_internal(h) when set_mret_condition_replicated(h)      = '1' else  -- sets return address from trap subroutine
        PC_offset_ID;
        --PC_offset_ID          when set_branch_condition_ID_replicated(h) = '1';
  
      pc_update_enable(h) <= '1' when instr_gnt_i = '1'
                                  and (harc_IF_internal = h
                                  or  taken_branch_replicated(h) = '1'
                                  or  taken_branch_pending_internal_lat(h) = '1'
                                  or  set_branch_condition_ID_replicated(h) = '1')
                             else '0';

      pc_updater_comb : process(
                                pc(h), taken_branch_pc_pending_internal_lat(h), taken_branch_pending_internal_lat(h), served_ie_except_condition_lat(h),
                                served_ls_except_condition_lat(h), served_except_condition_lat(h), served_mret_condition_lat(h), reset_state_internal(h),
                                fetch_enable_i, MTVEC(h), instr_gnt_i, taken_branch_replicated(h), set_branch_condition_ID_replicated(h),
                                set_wfi_condition, taken_branch_pending_internal(h), irq_pending_internal(h),
                                ie_except_condition_replicated(h), ls_except_condition_replicated(h), set_except_condition_replicated(h), set_mret_condition_replicated(h), 
                                pc_wire(h), taken_branch_addr_internal(h), taken_branch_pc_pending_internal(h),
                                incremented_pc_internal(h), pc_update_enable(h)
                               ) --VHDL1993
      begin
        pc_wire(h)                          <= pc(h);
        taken_branch_pc_pending_internal(h) <= taken_branch_pc_pending_internal_lat(h);
        taken_branch_pending_internal(h)    <= taken_branch_pending_internal_lat(h);
        served_ie_except_condition_int(h)       <= served_ie_except_condition_lat(h);
        served_ls_except_condition_int(h)       <= served_ls_except_condition_lat(h);
        served_except_condition_int(h)          <= served_except_condition_lat(h);
        served_mret_condition_int(h)            <= served_mret_condition_lat(h);
        if (reset_state_internal(h) = '0') then
          pc_update_no_dbg(
            fetch_enable_i,
            MTVEC(h),
            instr_gnt_i,
            taken_branch_replicated(h),
            set_branch_condition_ID_replicated(h),
            set_wfi_condition,
            taken_branch_pending_internal(h), 
            taken_branch_pending_internal_lat(h),
            irq_pending_internal(h),
            ie_except_condition_replicated(h),
            ls_except_condition_replicated(h), 
            set_except_condition_replicated(h), 
            set_mret_condition_replicated(h), 
            pc_wire(h),
            taken_branch_addr_internal(h), 
            taken_branch_pc_pending_internal(h),
            taken_branch_pc_pending_internal_lat(h), 
            incremented_pc_internal(h), 
            pc_update_enable(h), 
            served_ie_except_condition_int(h), 
            served_ls_except_condition_int(h),
            served_except_condition_int(h), 
            served_mret_condition_int(h)
          );
        end if;
      end process;
    end generate debug_pc_asin_nen;

    debug_pc_asin_en: if debug_en = 1 generate
      taken_branch_addr_internal(h) <=
      dm_exception_addr_i     when DEBUG_MODE(h) = '1' and set_trap_condition_replicated(h)   = '1' else
        absolute_address      when absolute_jump(h)                      = '1' else  -- sets a jump or a branch address
        PC_offset             when set_branch_condition_replicated(h)    = '1' or set_wfi_condition_replicated(h) = '1'  else  -- sets a jump or a branch address
        MTVEC(h)              when set_trap_condition_replicated(h)      = '1' else  -- sets MTVEC address for traps
        mepc_addr_internal(h) when set_mret_condition_replicated(h)      = '1' else  -- sets return address from trap subroutine
        PC_offset_ID;
        --PC_offset_ID          when set_branch_condition_ID_replicated(h) = '1';
  
      pc_update_enable(h) <= '1' when ((instr_gnt_i = '1' or gnt_waiting = '1')
                                and (harc_IF_internal = h
                                or  taken_branch_replicated(h) = '1'
                                or  taken_branch_pending_internal_lat(h) = '1'
                                or  set_branch_condition_ID_replicated(h) = '1')
                                and fetch_busy_dbg = '0'
                                and unsigned(debug_pc_taken_wire) = 0)
                           else '0';

      --halt_served_internal(h) <= '1' when halt_req(h) = '1'    --the signal PC_update_enable could be used to replace this one with additional conditions and removing state_waiting_for_halt_serv probably.
      --                          and (harc_IF_internal = h
      --                          or  taken_branch_replicated(h) = '1'
      --                          or  taken_branch_pending_internal_lat(h) = '1'
      --                          or  set_branch_condition_ID_replicated(h) = '1')
      --                          and state_waiting_for_halt_serv(h) = '1'
      --                          and fetch_enable_i = '1'
      --                     else '0';

      halt_served_internal(h) <= '1' when halt_req(h) = '1'    --the signal PC_update_enable could be used to replace this one with additional conditions and removing state_waiting_for_halt_serv probably.
                                and harc_IF_internal = h
                                and state_waiting_for_halt_serv(h) = '1'
                                and fetch_enable_i = '1'
                           else '0';

      pc_updater_comb : process(
                                pc(h), taken_branch_pc_pending_internal_lat(h), taken_branch_pending_internal_lat(h), served_ie_except_condition_lat(h),
                                served_ls_except_condition_lat(h), served_except_condition_lat(h), served_mret_condition_lat(h), reset_state_internal(h),
                                fetch_enable_i, MTVEC(h), instr_gnt_i, taken_branch_replicated(h), set_branch_condition_ID_replicated(h),
                                set_wfi_condition, taken_branch_pending_internal(h), irq_pending_internal(h),
                                ie_except_condition_replicated(h), ls_except_condition_replicated(h), set_except_condition_replicated(h), set_mret_condition_replicated(h), 
                                pc_wire(h), taken_branch_addr_internal(h), taken_branch_pc_pending_internal(h),
                                incremented_pc_internal(h), pc_update_enable(h), halt_req(h), dm_halt_addr_i, dret_instr(h), DPC(h)
                               ) --VHDL1993
      begin
        pc_wire(h)                          <= pc(h);
        taken_branch_pc_pending_internal(h) <= taken_branch_pc_pending_internal_lat(h);
        taken_branch_pending_internal(h)    <= taken_branch_pending_internal_lat(h);
        served_ie_except_condition_int(h)       <= served_ie_except_condition_lat(h);
        served_ls_except_condition_int(h)       <= served_ls_except_condition_lat(h);
        served_except_condition_int(h)          <= served_except_condition_lat(h);
        served_mret_condition_int(h)            <= served_mret_condition_lat(h);
        if (reset_state_internal(h) = '0') or (halt_req(h) = '1') then
          pc_update_dbg(
            fetch_enable_i,
            MTVEC(h),
            instr_gnt_i,
            taken_branch_replicated(h),
            set_branch_condition_ID_replicated(h),
            set_wfi_condition,
            taken_branch_pending_internal(h), 
            taken_branch_pending_internal_lat(h),
            irq_pending_internal(h),
            ie_except_condition_replicated(h),
            ls_except_condition_replicated(h), 
            set_except_condition_replicated(h), 
            set_mret_condition_replicated(h), 
            halt_req(h),
            dm_halt_addr_i,
            dret_instr(h),
            DPC(h),
            harc_is_in_fetch(h),
            pc_wire(h),
            taken_branch_addr_internal(h), 
            taken_branch_pc_pending_internal(h),
            taken_branch_pc_pending_internal_lat(h), 
            incremented_pc_internal(h), 
            pc_update_enable(h), 
            served_ie_except_condition_int(h), 
            served_ls_except_condition_int(h),
            served_except_condition_int(h), 
            served_mret_condition_int(h)
          );
        end if;
      end process;
    end generate debug_pc_asin_en;

    pc_update_sync : process (clk_i, rst_ni)
    begin
      if rst_ni = '0' then 
        reset_state_internal                 <= (others => '1');
        taken_branch_pending_internal_lat(h) <= '0';
        served_ie_except_condition_lat(h)    <= '0';
        served_ls_except_condition_lat(h)    <= '0';
        served_except_condition_lat(h)       <= '0';
        served_mret_condition_lat(h)         <= '0';
        -- The S1 core in the hetergeneous cluster does not have a reset state and takes only the state of the hart that is doing the context switch
        pc(h) <= (31 downto 8 => '0') & std_logic_vector(to_unsigned(128,8)); -- Put address 0x0000_0080 which is the pointer to the reset handler
        --pc(h) <= x"80000080"; --for uvm purposes
      elsif rising_edge(clk_i) then
        if fetch_enable_i = '1' then
          reset_state_internal(harc_IF_internal) <= '0';
        end if;
        pc(h)                                   <= pc_wire(h);
        taken_branch_pc_pending_internal_lat(h) <= taken_branch_pc_pending_internal(h);
        taken_branch_pending_internal_lat(h)    <= taken_branch_pending_internal(h);
        served_ie_except_condition_lat(h)       <= served_ie_except_condition_int(h);
        served_ls_except_condition_lat(h)       <= served_ls_except_condition_int(h);
        served_except_condition_lat(h)          <= served_except_condition_int(h);
        served_mret_condition_lat(h)            <= served_mret_condition_int(h);
      end if;
    end process;
  end generate pc_update_logic;
  -- end of replicated logic --   

--------------------------------------------------------------------- end of PC Managing Units ---
--------------------------------------------------------------------------------------------------  

end PC;
--------------------------------------------------------------------------------------------------
-- END of Program Counter architecture -----------------------------------------------------------
--------------------------------------------------------------------------------------------------
