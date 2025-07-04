--------------------------------------------------------------------------------------------------------------
--  Debug Control Unit--                                                                          
--                      
--  A.M.                                                                                                       
--                                                                                
--------------------------------------------------------------------------------------------------------------
--                 
--------------------------------------------------------------------------------------------------------------

-- ieee packages ------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_misc.all;
use ieee.numeric_std.all;
use std.textio.all;

-- local packages ------------
use work.riscv_klessydra.all;

-- pipeline  pinout --------------------
entity Debug is
  generic(
    debug_en          : natural;
    THREAD_POOL_SIZE  : natural
  );
  port(
    rst_ni                      : in  std_logic;
    clk_i                       : in  std_logic;
    debug_req_i                 : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
    ebreak_dbg                  : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
    single_stepping             : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
    DEBUG_MODE                  : out std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
    harc_IF                     : in  natural range THREAD_POOL_SIZE-1 downto 0;
    harc_EXEC                   : in  natural range THREAD_POOL_SIZE-1 downto 0;
    ebreak_instr                : in  std_logic;
    halt_req                    : out std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
    halt_req_wire               : out std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
    halt_served                 : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
    reset_state                 : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
    debug_havereset             : out std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
    debug_running               : out std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
    debug_halted                : out std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
    state_waiting_for_halt_serv : out std_logic_vector(THREAD_POOL_SIZE-1 downto 0); 
    dret_instr                  : in  std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
    amo_load                    : in  std_logic;
    amo_load_skip               : in  std_logic;
    amo_store                   : in  std_logic;
    debug_pc_taken_wire         : out std_logic_vector(THREAD_POOL_SIZE-1 downto 0);
    debug_cause                 : out debug_cause_array
    );
end entity;  ------------------------------------------

-------------------------
architecture debug_mode of Debug is

subtype harc_range is natural range THREAD_POOL_SIZE-1 downto 0;

signal DEBUG_MODE_internal                  : std_logic_vector(harc_range);
signal halt_req_internal                    : std_logic_vector(harc_range);
signal debug_cause_internal                 : debug_cause_array;

signal debug_havereset_internal             : std_logic_vector(harc_range);
signal debug_running_internal               : std_logic_vector(harc_range);
signal debug_halted_internal                : std_logic_vector(harc_range);
signal state_waiting_for_halt_serv_internal : std_logic_vector(harc_range); -- This signal is needed to not update the PC during the fetch stage, as if a debug_req arrives while the hart is in a multicycle fetch stage (and not the last cycle of this stage) then the pc will be rewritten with a wrong address.
signal halt_req_wire_internal               : std_logic_vector(harc_range); -- Asynchronous version of halt_req. Required to save the DPC and to jump immediately
signal is_amo                               : std_logic;
signal debug_pc_taken_wire_int              : std_logic_vector(harc_range);
signal debug_pc_taken_reg                   : std_logic_vector(harc_range);

signal state, next_state                    : debug_state_array;

begin

DEBUG_MODE                    <= DEBUG_MODE_internal;
halt_req                      <= halt_req_internal;
debug_cause                   <= debug_cause_internal;
debug_havereset               <= debug_havereset_internal;
debug_running                 <= debug_running_internal;
debug_halted                  <= debug_halted_internal;
state_waiting_for_halt_serv   <= state_waiting_for_halt_serv_internal;
halt_req_wire                 <= halt_req_wire_internal;
is_amo                        <= amo_load or amo_load_skip or amo_store;
debug_pc_taken_wire           <= debug_pc_taken_wire_int or debug_pc_taken_reg;

--Priority Order: trigger (ni) , ebreak_intr , halt_on_reset , halt_req , single step

Debug_state_machine : for h in harc_range generate

state_reg_proc: process(clk_i, rst_ni)
begin
  if rst_ni = '0' then
    state(h) <= (others => '0');
  elsif rising_edge(clk_i) then
    state(h) <= next_state(h);  
  end if;
end process;

next_state_proc: process(debug_req_i, reset_state, ebreak_instr, ebreak_dbg, is_amo, single_stepping, halt_served, dret_instr, state, harc_EXEC)
begin
  case state(h) is 
  when "00" => --reset
  
    if debug_req_i(h) = '1' then
      next_state(h)               <= "10";
      halt_req_wire_internal(h)   <= '1';
      debug_pc_taken_wire_int(h)  <= '1';
    elsif reset_state(h) = '0' then
      next_state(h)               <= "01";
      halt_req_wire_internal(h)   <= '0';
      debug_pc_taken_wire_int(h)  <= '0';
    else 
      next_state(h)               <= "00";
      halt_req_wire_internal(h)   <= '0';
      debug_pc_taken_wire_int(h)  <= '0';
    end if;

  when "01" =>  --running --> Check if based on priority order, 
                            --> 1) ebreak; 2) debug_req 3) single step
                            
    if ebreak_instr = '1' and h = harc_EXEC and ebreak_dbg(h) = '1' then  --ebreak
      next_state(h)               <= "10";
      halt_req_wire_internal(h)   <= '0';
      debug_pc_taken_wire_int(h)  <= '1';

    elsif debug_req_i(h) = '1' then                                      --debug_req
      if not (h = harc_EXEC and is_amo = '1') then          --amo swap not interruptible
        next_state(h)               <= "10";
        halt_req_wire_internal(h)   <= '1';
        debug_pc_taken_wire_int(h)  <= '1';
      else
        next_state(h)               <= "01";
        halt_req_wire_internal(h)   <= '0';
        debug_pc_taken_wire_int(h)  <= '0';
      end if;

    elsif single_stepping(h) = '1' and h = harc_EXEC then                       --single step
      next_state(h)               <= "10";
      halt_req_wire_internal(h)   <= '0';
      debug_pc_taken_wire_int(h)  <= '1';

    else                                                                --no halt, continue to run
      next_state(h)               <= "01";
      halt_req_wire_internal(h)   <= '0';
      debug_pc_taken_wire_int(h)  <= '0';

    end if;

  when "10" => --waiting for halt_served

    if halt_served(h) = '1' then
      next_state(h)               <= "11";
      halt_req_wire_internal(h)   <= '0';
      debug_pc_taken_wire_int(h)  <= '0';
    else 
      next_state(h)               <= "10";
      halt_req_wire_internal(h)   <= '0';
      debug_pc_taken_wire_int(h)  <= '0';
    end if;

  when "11" => --halted --> ebreak or dret. Order is not important since they are mutually exclusive
    if ebreak_instr = '1' and h = harc_EXEC then  --ebreak
      next_state(h)               <= "10";
      halt_req_wire_internal(h)   <= '0';
      debug_pc_taken_wire_int(h)  <= '1';
    elsif dret_instr(h) = '1' then                --dret
      next_state(h)               <= "01";
      halt_req_wire_internal(h)   <= '0';
      debug_pc_taken_wire_int(h)  <= '0';
    else                                          --remains halted
      next_state(h)               <= "11";
      halt_req_wire_internal(h)   <= '0';
      debug_pc_taken_wire_int(h)  <= '0';
    end if;

  when others =>
    next_state(h)               <= "00";
    halt_req_wire_internal(h)   <= '0';
    debug_pc_taken_wire_int(h)  <= '0';
  end case;
  --end if;
end process;


data_path_proc: process(clk_i, rst_ni)

begin

  if rst_ni = '0' then

    DEBUG_MODE_internal(h)                  <= '0';

    debug_havereset_internal(h)             <= '1';
    debug_running_internal(h)               <= '0';
    debug_halted_internal(h)                <= '0';

    halt_req_internal(h)                    <= '0';
    debug_cause_internal(h)                 <= (others => '0');
    state_waiting_for_halt_serv_internal(h) <= '0';
    debug_pc_taken_reg(h)                   <= '0';

  elsif rising_edge(clk_i) then
  
     debug_pc_taken_reg(h) <= debug_pc_taken_wire_int(h);
        
    case state(h) is 
    when "00" => 

      DEBUG_MODE_internal(h)          <= '0';
      state_waiting_for_halt_serv_internal(h) <= '0';

      if debug_req_i(h) = '1' then

        halt_req_internal(h)            <= '1';
        debug_cause_internal(h)         <= RESET_HALT_REQ_CAUSE_CODE;

        debug_havereset_internal(h)     <= '1';
        debug_running_internal(h)       <= '0';
        debug_halted_internal(h)        <= '0';

      elsif reset_state(h) = '0' then

        halt_req_internal(h)            <= '0';
        debug_cause_internal(h)         <= "000";

        debug_havereset_internal(h)     <= '0';
        debug_running_internal(h)       <= '1';
        debug_halted_internal(h)        <= '0';

      else 

        halt_req_internal(h)            <= '0';
        debug_cause_internal(h)         <= "000";

        debug_havereset_internal(h)     <= '1';
        debug_running_internal(h)       <= '0';
        debug_halted_internal(h)        <= '0';

      end if;

    when "01" => --running

      DEBUG_MODE_internal(h)            <= '0';
      debug_havereset_internal(h)       <= '0';
      debug_running_internal(h)         <= '1';
      debug_halted_internal(h)          <= '0';
      state_waiting_for_halt_serv_internal(h) <= '0';

      if ebreak_instr = '1' and h = harc_EXEC and ebreak_dbg(h) = '1' then  --ebreak

        halt_req_internal(h)                    <= '1';
        debug_cause_internal(h)                 <= EBREAK_CAUSE_CODE;
        state_waiting_for_halt_serv_internal(h) <= '1';

      elsif debug_req_i(h) = '1' then                                       --debug_req
        if not (h = harc_EXEC and is_amo = '1') then          --amo swap not interruptible
          halt_req_internal(h)            <= '1';
          debug_cause_internal(h)         <= HALT_REQ_CAUSE_CODE;
          if (h /= harc_IF) then
            state_waiting_for_halt_serv_internal(h) <= '1';
          else
            state_waiting_for_halt_serv_internal(h) <= '0';
          end if;
        end if;


      elsif single_stepping(h) = '1' and h = harc_EXEC then                       --single step
        
        halt_req_internal(h)                    <= '1'; 
        debug_cause_internal(h)                 <= SINGLE_STEP_CAUSE_CODE;
        state_waiting_for_halt_serv_internal(h) <= '1';

      else                                                                --no halt, continue to run

        halt_req_internal(h)            <= '0';
        debug_cause_internal(h)         <= "000";

      end if;

    when "10" => --waiting for halting served

      if (h /= harc_IF) then
        state_waiting_for_halt_serv_internal(h) <= '1';
      else
        state_waiting_for_halt_serv_internal(h) <= '0';
      end if;

      if halt_served(h) = '1' then

        DEBUG_MODE_internal(h)          <= '1';

        debug_halted_internal(h)        <= '1';
        debug_havereset_internal(h)     <= '0';              
        debug_running_internal(h)       <= '0';

        halt_req_internal(h)            <= '0';   --halt has been served
        debug_cause_internal(h)         <= "000";


      else 
        halt_req_internal(h)    <= '1';

      end if;

    when "11" => --halted

      state_waiting_for_halt_serv_internal(h) <= '0';

      if ebreak_instr = '1' and h = harc_EXEC then  --ebreak

        debug_havereset_internal(h)     <= '0';
        debug_running_internal(h)       <= '0';
        debug_halted_internal(h)        <= '1';

        halt_req_internal(h)                    <= '1';
        state_waiting_for_halt_serv_internal(h) <= '1';
        
      elsif dret_instr(h) = '1' then                --dret

        DEBUG_MODE_internal(h)          <= '0';

        debug_running_internal(h)       <= '1';
        debug_halted_internal(h)        <= '0';
        debug_havereset_internal(h)     <= '0';

        halt_req_internal(h)    <= '0';

      end if;
    
    when others => 
      null;
    end case;
  end if;
end process;

end generate Debug_state_machine;
end debug_mode;
--------------------------------------------------------------------------------------------------
-- END of IE architecture ------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------