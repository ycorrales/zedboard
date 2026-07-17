library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity fibonacci_bram is
  port (
    CLK        : in    std_logic;
    RST        : in    std_logic;
    START_STOP : in    std_logic;
    CLEAR_BRAM : in    std_logic;
    BRAM_ADDR  : out   std_logic_vector(31 downto 0);
    BRAM_CLK   : out   std_logic;
    BRAM_DIN   : out   std_logic_vector(31 downto 0);
    BRAM_DOUT  : in    std_logic_vector(31 downto 0);
    BRAM_EN    : out   std_logic;
    BRAM_RST   : out   std_logic;
    BRAM_WE    : out   std_logic_vector(3 downto 0)
  );
end entity fibonacci_bram;

architecture rtl of fibonacci_bram is

  constant bram_depth  : natural  := 2048;
  constant seq_bits    : positive := 32;
  constant clk_mhz     : natural  := 100;
  constant counter_max : natural  := clk_mhz * 500000;

  signal seq_num         : std_logic_vector(seq_bits - 1 downto 0);
  signal seq_valid       : std_logic;
  signal address         : unsigned(31 downto 0);
  signal counter         : unsigned(31 downto 0);
  signal get_next_number : std_logic;
  signal fib_rst         : std_logic;
  signal dummy           : std_logic_vector(31 downto 0);

  signal start_stop_p : std_logic;
  signal running_s    : std_logic;

  signal clear_bram_p : std_logic;
  signal clear_busy   : std_logic;

begin

  -- dummy assignment to remove unused warning
  dummy <= BRAM_DOUT;

  get_next_number <= '1' when counter = to_unsigned(1, counter'length) else
                     '0';
  fib_rst         <= '1' when address = to_unsigned(bram_depth - 1, address'length) else
                     RST;

  u_start_stop_p : entity work.edge_detect
    port map (
      CLK => CLK,
      P_I => START_STOP,
      P_O => start_stop_p
    );

  u_clear_bram_p : entity work.edge_detect
    port map (
      CLK => CLK,
      P_I => CLEAR_BRAM,
      P_O => clear_bram_p
    );

  toogle_block : entity work.toggle_block
    port map (
      CLK           => CLK,
      RESET         => RST,
      TRIGGER_PULSE => start_stop_p,
      TOGGLE_OUTPUT => running_s
    );

  fibonacci_i : entity work.fibonacci
    generic map (
      SEQ_BITS => SEQ_BITS
    )
    port map (
      CLK             => CLK,
      RST             => fib_rst,
      GET_NEXT_NUMBER => get_next_number,
      SEQ             => seq_num,
      SEQ_VALID       => seq_valid
    );

  p_addr_incr : process (CLK) is
  begin

    if rising_edge(CLK) then
      if (RST = '1') then
        clear_busy <= '0';
        address    <= (others => '0');
      elsif (clear_bram_p = '1' and clear_busy = '0') then
        address    <= (others => '0');
        clear_busy <= '1';
      elsif (clear_busy = '1') then
        clear_busy <= '1';

        -- Increment address until BRAM depth is reached (e.g., 1023)
        if (address < to_unsigned(bram_depth - 1, address'length)) then
          address <= address + 1;
        else
          clear_busy <= '0';                                          -- Done clearing
          address    <= (others => '0');
        end if;
      elsif (seq_valid = '1') then
        if (address < to_unsigned(bram_depth - 1, address'length)) then
          address <= address + 1;
        else
          address <= (others => '0');
        end if;
      end if;
    end if;

  end process p_addr_incr;

  p_cnt : process (CLK) is
  begin

    if rising_edge(CLK) then
      if (RST = '1' or counter = to_unsigned(counter_max - 1, counter'length) or running_s = '0' or clear_busy = '1') then
        counter <= (others => '0');
      else
        counter <= counter + 1;
      end if;
    end if;

  end process p_cnt;

  BRAM_ADDR <= std_logic_vector(address sll 2);
  BRAM_CLK  <= CLK;
  BRAM_DIN  <= seq_num when clear_busy = '0' else
               (others => '0');
  BRAM_EN   <= '1';
  BRAM_RST  <= RST;
  BRAM_WE   <= (others => seq_valid) when clear_busy = '0' else
               (others => '1');

end architecture rtl;
