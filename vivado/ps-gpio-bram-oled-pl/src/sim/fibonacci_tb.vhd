library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity tb_fibonacci is
end entity tb_fibonacci;

architecture tb of tb_fibonacci is

  constant seq_bits   : positive := 8;
  constant clk_period : time     := 10 ns;

  signal clk             : std_logic := '0';
  signal rst             : std_logic := '0';
  signal get_next_number : std_logic := '0';
  signal seq             : std_logic_vector(seq_bits - 1 downto 0);
  signal seq_valid       : std_logic;

begin

  -- Instantiate the fibonacci entity
  dut : entity work.fibonacci
    generic map (
      SEQ_BITS => SEQ_BITS
    )
    port map (
      CLK             => clk,
      RST             => rst,
      GET_NEXT_NUMBER => get_next_number,
      SEQ             => seq,
      SEQ_VALID       => seq_valid
    );

  -- Clock generation
  clk <= not clk after clk_period / 2;

  -- Stimulus process
  p_stim : process is
  begin

    report "Starting Fibonacci Testbench...";

    -- Reset
    rst <= '1';
    wait for 2 * clk_period;
    rst <= '0';
    wait for clk_period;

    report "Testing Fibonacci sequence generation...";

    -- Generate 20 Fibonacci numbers
    for i in 0 to 19 loop

      get_next_number <= '1';
      wait for clk_period;
      get_next_number <= '0';

      if (seq_valid = '1') then
        report "Fib[" & integer'image(i) & "] = " & integer'image(to_integer(unsigned(seq)));
      else
        report "Fib[" & integer'image(i) & "] = " & integer'image(to_integer(unsigned(seq))) & " (OVERFLOW - RESET)";
      end if;

      wait for clk_period;

    end loop;

    report "Testing reset during operation...";

    -- Reset signal test
    for i in 0 to 4 loop

      get_next_number <= '1';
      wait for clk_period;
      get_next_number <= '0';
      wait for clk_period;

    end loop;

    -- Apply reset mid-sequence
    rst <= '1';
    wait for clk_period;
    rst <= '0';
    wait for clk_period;

    report "Sequence after reset:";

    for i in 0 to 4 loop

      get_next_number <= '1';
      wait for clk_period;
      get_next_number <= '0';
      report "Fib[" & integer'image(i) & "] = " & integer'image(to_integer(unsigned(seq)));
      wait for clk_period;

    end loop;

    report "Testing with GET_NEXT_NUMBER held low...";
    get_next_number <= '0';
    wait for 5 * clk_period;
    report "Sequence should not change while GET_NEXT_NUMBER = 0";

    report "Testbench completed!";
    wait;

  end process p_stim;

end architecture tb;
