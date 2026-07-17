library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity top is
  port (
    CLK       : in    std_logic;
    BTNR      : in    std_logic; -- // CPU Reset Button turns the display on and off
    BTNC      : in    std_logic; -- // Center DPad Button turns every pixel on the display on or resets to previous state
    BTND      : in    std_logic; -- // Upper DPad Button updates the delay to the contents of the local memory
    BTNU      : in    std_logic; -- // Bottom DPad Button clears the display
    OLED_SDIN : out   std_logic;
    OLED_SCLK : out   std_logic;
    OLED_DC   : out   std_logic;
    OLED_RES  : out   std_logic;
    OLED_VBAT : out   std_logic;
    OLED_VDD  : out   std_logic;
    LED       : out   std_logic_vector(7 downto 0)
  );
end entity top;

architecture rtl of top is

  type state_t is (idle, init, active, done, fulldisp, write, writewait, autoupdate, updatewait);

  constant str1 : string(1 to 16) := " I am the       ";
  constant str2 : string(1 to 16) := " Zedboard OLED  ";
  constant str3 : string(1 to 16) := " Display Demo!  ";
  constant str4 : string(1 to 16) := "                ";

  signal state : state_t   := init;
  signal once  : std_logic := '0';

  signal update_start      : std_logic                    := '0';
  signal disp_on_start     : std_logic                    := '1';
  signal disp_off_start    : std_logic                    := '0';
  signal toggle_disp_start : std_logic                    := '0';
  signal write_start       : std_logic                    := '0';
  signal update_clear      : std_logic                    := '0';
  signal write_base_addr   : unsigned(8 downto 0)         := (others => '0');
  signal write_ascii_data  : std_logic_vector(7 downto 0) := (others => '0');

  signal disp_on_ready     : std_logic;
  signal disp_off_ready    : std_logic;
  signal toggle_disp_ready : std_logic;
  signal update_ready      : std_logic;
  signal write_ready       : std_logic;

  signal rst   : std_logic;
  signal dbtnc : std_logic;
  signal dbtnu : std_logic;
  signal dbtnd : std_logic;

  signal init_done  : std_logic;
  signal init_ready : std_logic;

  function char_at (
    row : natural;
    idx : natural
  ) return std_logic_vector is

    variable ch : character;

  begin

    case row is

      when 0 =>

        ch := STR1(idx + 1);

      when 1 =>

        ch := STR2(idx + 1);

      when 2 =>

        ch := STR3(idx + 1);

      when others =>

        ch := STR4(idx + 1);

    end case;

    return std_logic_vector(to_unsigned(character'pos(ch), 8));

  end function char_at;

begin

  m_oledctrl : entity work.oledctrl
    port map (
      CLK               => CLK,
      WRITE_START       => write_start,
      WRITE_ASCII_DATA  => write_ascii_data,
      WRITE_BASE_ADDR   => std_logic_vector(write_base_addr),
      WRITE_READY       => write_ready,
      UPDATE_START      => update_start,
      UPDATE_READY      => update_ready,
      UPDATE_CLEAR      => update_clear,
      DISP_ON_START     => disp_on_start,
      DISP_ON_READY     => disp_on_ready,
      DISP_OFF_START    => disp_off_start,
      DISP_OFF_READY    => disp_off_ready,
      TOGGLE_DISP_START => toggle_disp_start,
      TOGGLE_DISP_READY => toggle_disp_ready,
      SDIN              => OLED_SDIN,
      SCLK              => OLED_SCLK,
      DC                => OLED_DC,
      RES               => OLED_RES,
      VBAT              => OLED_VBAT,
      VDD               => OLED_VDD
    );

  get_dbtnc : entity work.debouncer
    generic map (
      COUNT_MAX   => 65535,
      COUNT_WIDTH => 16
    )
    port map (
      CLK => CLK,
      A   => BTNC,
      B   => dbtnc
    );

  get_dbtnu : entity work.debouncer
    generic map (
      COUNT_MAX   => 65535,
      COUNT_WIDTH => 16
    )
    port map (
      CLK => CLK,
      A   => BTNU,
      B   => dbtnu
    );

  get_dbtnd : entity work.debouncer
    generic map (
      COUNT_MAX   => 65535,
      COUNT_WIDTH => 16
    )
    port map (
      CLK => CLK,
      A   => BTND,
      B   => dbtnd
    );

  get_rst : entity work.debouncer
    generic map (
      COUNT_MAX   => 65535,
      COUNT_WIDTH => 16
    )
    port map (
      CLK => CLK,
      A   => BTNR,
      B   => rst
    );

  p_write_addrs : process (write_base_addr) is

    variable row      : natural;
    variable char_idx : natural;

  begin

    row              := to_integer(write_base_addr(8 downto 7));
    char_idx         := to_integer(write_base_addr(6 downto 3));
    write_ascii_data <= char_at(row, char_idx);

  end process p_write_addrs;

  LED        <= (0 => update_ready, others => '0');
  init_done  <= disp_off_ready or toggle_disp_ready or write_ready or update_ready;
  init_ready <= disp_on_ready;

  p_fsm : process (CLK) is
  begin

    if rising_edge(CLK) then
      -- Default pulse states to prevent persistent signal assertions
      disp_on_start     <= '0';
      disp_off_start    <= '0';
      write_start       <= '0';
      update_start      <= '0';
      toggle_disp_start <= '0';

      case state is

        when idle =>

          if (rst = '1' and init_ready = '1') then
            disp_on_start <= '1';
            state         <= init;
          end if;
          once <= '0';

        when init =>

          disp_on_start <= '0';
          if (rst = '0' and init_done = '1') then
            state <= active;
          end if;

        when active =>

          if (rst = '1' and disp_off_ready = '1') then
            disp_off_start <= '1';
            state          <= done;
          elsif (once = '0' and write_ready = '1') then
            write_start     <= '1';
            write_base_addr <= (others => '0');
            state           <= writewait;
          elsif (once = '1' and dbtnu = '1') then
            update_start <= '1';
            update_clear <= '0';
            state        <= updatewait;
          elsif (once = '1' and dbtnd = '1') then
            update_start <= '1';
            update_clear <= '1';
            state        <= updatewait;
          elsif (dbtnc = '1' and toggle_disp_ready = '1') then
            toggle_disp_start <= '1';
            state             <= fulldisp;
          end if;

        when write =>

          write_start     <= '1';
          write_base_addr <= write_base_addr + 8;
          state           <= writewait;

        when writewait =>

          write_start <= '0';
          if (write_ready = '1') then
            if (write_base_addr = to_unsigned(16#1F8#, 9)) then
              once  <= '1';
              state <= autoupdate;
            else
              state <= write;
            end if;
          end if;

        when autoupdate =>

          update_start <= '1';
          update_clear <= '0';
          state        <= updatewait;

        when updatewait =>

          update_start <= '0';
          if (update_ready = '1' and dbtnu = '0' and dbtnd = '0') then
            state <= active;
          end if;

        when done =>

          disp_off_start <= '0';
          if (rst = '0' and init_ready = '1') then
            state <= idle;
          end if;

        when fulldisp =>

          toggle_disp_start <= '0';
          if (dbtnc = '0' and init_done = '1') then
            state <= active;
          end if;

      end case;

    end if;

  end process p_fsm;

end architecture rtl;
