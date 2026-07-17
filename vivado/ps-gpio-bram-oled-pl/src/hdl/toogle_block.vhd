library ieee;
  use ieee.std_logic_1164.all;

entity toggle_block is
  port (
    CLK           : in    std_logic;
    RESET         : in    std_logic;
    TRIGGER_PULSE : in    std_logic;
    TOGGLE_OUTPUT : out   std_logic
  );
end entity toggle_block;

architecture behavioral of toggle_block is

  -- Internal signal to track the state
  signal toggle_reg : std_logic := '0';

begin

  p_toogle : process (CLK, RESET) is
  begin

    if (RESET = '1') then
      toggle_reg <= '0';
    elsif rising_edge(CLK) then
      if (TRIGGER_PULSE = '1') then
        toggle_reg <= not toggle_reg; -- Flips the bit (0->1 or 1->0)
      end if;
    end if;

  end process p_toogle;

  -- Assign internal state to the top-level entity output
  TOGGLE_OUTPUT <= toggle_reg;

end architecture behavioral;
