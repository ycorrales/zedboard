library ieee;
  use ieee.std_logic_1164.all;

entity edge_detect is
  port (
    CLK : in    std_logic;
    P_I : in    std_logic;
    P_O : out   std_logic
  );
end entity edge_detect;

architecture rtl of edge_detect is

  signal p_reg0 : std_logic;
  signal p_reg1 : std_logic;

begin

  p_start_stop_pulse : process (CLK) is
  begin

    if (rising_edge(CLK)) then
      p_reg0 <= P_I;
      p_reg1 <= p_reg0;
    end if;

  end process p_start_stop_pulse;

  P_O <= p_reg0 and (not P_I);

end architecture rtl;

