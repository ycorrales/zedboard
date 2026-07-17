library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity fibonacci is
  generic (
    SEQ_BITS : positive := 32
  );
  port (
    CLK             : in    std_logic;
    RST             : in    std_logic;
    GET_NEXT_NUMBER : in    std_logic;
    SEQ             : out   std_logic_vector(SEQ_BITS - 1 downto 0);
    SEQ_VALID       : out   std_logic
  );
end entity fibonacci;

architecture rtl of fibonacci is

  signal seq_0             : unsigned(SEQ'range);
  signal seq_1             : unsigned(SEQ'range);
  signal seq_valid_i       : std_logic;
  signal overflow_detected : std_logic := '0';

begin

  p_fib : process (CLK) is

    variable fib_v : unsigned(SEQ_BITS downto 0);

  begin

    if rising_edge(CLK) then
      seq_valid_i <= '0';

      if (RST = '1') then
        seq_0 <= to_unsigned(0, SEQ_BITS);
        seq_1 <= to_unsigned(1, SEQ_BITS);
      elsif (GET_NEXT_NUMBER = '1') then
        if (overflow_detected = '1') then
          seq_0             <= to_unsigned(1, SEQ_BITS);
          seq_1             <= to_unsigned(0, SEQ_BITS);
          overflow_detected <= '0';
        else
          fib_v       := ('0' & seq_0) + ('0' & seq_1);
          seq_valid_i <= '1';

          if (fib_v(SEQ_BITS) = '1') then
            seq_1 <= seq_0;
            -- fib_v would overflow, so DON'T update yet
            -- Just set flag to reset on next call
            overflow_detected <= '1';
          else
            seq_1 <= seq_0;
            seq_0 <= fib_v(SEQ_BITS - 1 downto 0);
          end if;
        end if;
      end if;
    end if;

  end process p_fib;

  SEQ       <= std_logic_vector(seq_1);
  SEQ_VALID <= seq_valid_i;

end architecture rtl;
