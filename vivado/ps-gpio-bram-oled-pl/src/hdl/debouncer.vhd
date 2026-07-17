library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity debouncer is
  generic (
    COUNT_MAX   : natural := 15;
    COUNT_WIDTH : natural := 4
  );
  port (
    CLK : in    std_logic;
    A   : in    std_logic;
    B   : out   std_logic
  );
end entity debouncer;

architecture rtl of debouncer is

  constant idle : std_logic := '0';
  constant tran : std_logic := '1';
  constant off  : std_logic := '0';
  constant on_s : std_logic := '1';

  signal state : std_logic_vector(1 downto 0)       := off & idle;
  signal count : unsigned(COUNT_WIDTH - 1 downto 0) := (others => '0');

begin

  B <= state(1);

  p_cnt : process (CLK) is
  begin

    if rising_edge(CLK) then
      if (state(0) = '0') then
        count <= (others => '0');
      else
        count <= count + 1;
      end if;
    end if;

  end process p_cnt;

  p_fsm : process (CLK) is
  begin

    if rising_edge(CLK) then

      case state is

        when off & idle =>

          if (A = '1') then
            state <= off & tran;
          end if;

        when off & tran =>

          if (A = '0') then
            state <= off & idle;
          elsif (count = to_unsigned(COUNT_MAX, COUNT_WIDTH)) then
            state <= on_s & idle;
          end if;

        when on_s & tran =>

          if (A = '1') then
            state <= on_s & idle;
          elsif (count = to_unsigned(COUNT_MAX, COUNT_WIDTH)) then
            state <= off & idle;
          end if;

        when on_s & idle =>

          if (A = '0') then
            state <= on_s & tran;
          end if;

        when others =>

          state <= off & idle;

      end case;

    end if;

  end process p_fsm;

end architecture rtl;
