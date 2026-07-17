library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity delay_ms is
  port (
    CLK           : in    std_logic;
    DELAY_TIME_MS : in    std_logic_vector(11 downto 0);
    DELAY_START   : in    std_logic;
    DELAY_DONE    : out   std_logic
  );
end entity delay_ms;

architecture rtl of delay_ms is

  type state_t is (idle, hold, done);

  constant max_count : unsigned(16 downto 0) := to_unsigned(99999, 17);
  -- This = 100,000 cycles
  -- At 100MHz: 100,000 × 10ns = 1ms ✓

  signal state       : state_t               := idle;
  signal stop_time   : unsigned(11 downto 0) := (others => '0');
  signal ms_counter  : unsigned(11 downto 0) := (others => '0');
  signal clk_counter : unsigned(16 downto 0) := (others => '0');

begin

  DELAY_DONE <= '1' when state = idle and DELAY_START = '0' else
                '0';

  p_fsm : process (CLK) is
  begin

    if rising_edge(CLK) then

      case state is

        when idle =>

          stop_time <= unsigned(DELAY_TIME_MS);
          if (DELAY_START = '1') then
            state <= hold;
          end if;

        when hold =>

          if (ms_counter = stop_time and clk_counter = max_count) then
            if (DELAY_START = '1') then
              state <= done;
            else
              state <= idle;
            end if;
          end if;

        when done =>

          if (DELAY_START = '0') then
            state <= idle;
          end if;

      end case;

    end if;

  end process p_fsm;

  p_delay_cnt : process (CLK) is
  begin

    if rising_edge(CLK) then
      if (state = hold) then
        if (clk_counter = max_count) then
          clk_counter <= (others => '0');
          if (ms_counter = stop_time) then
            ms_counter <= (others => '0');
          else
            ms_counter <= ms_counter + 1;
          end if;
        else
          clk_counter <= clk_counter + 1;
        end if;
      else
        clk_counter <= (others => '0');
        ms_counter  <= (others => '0');
      end if;
    end if;

  end process p_delay_cnt;

end architecture rtl;
