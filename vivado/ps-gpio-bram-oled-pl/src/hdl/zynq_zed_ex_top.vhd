library ieee;
  use ieee.std_logic_1164.all;

entity zynq_zed_ex_top is
  port (
    DDR_ADDR          : inout std_logic_vector(14 downto 0);
    DDR_BA            : inout std_logic_vector(2 downto 0);
    DDR_CAS_N         : inout std_logic;
    DDR_CK_N          : inout std_logic;
    DDR_CK_P          : inout std_logic;
    DDR_CKE           : inout std_logic;
    DDR_CS_N          : inout std_logic;
    DDR_DM            : inout std_logic_vector(3 downto 0);
    DDR_DQ            : inout std_logic_vector(31 downto 0);
    DDR_DQS_N         : inout std_logic_vector(3 downto 0);
    DDR_DQS_P         : inout std_logic_vector(3 downto 0);
    DDR_ODT           : inout std_logic;
    DDR_RAS_N         : inout std_logic;
    DDR_RESET_N       : inout std_logic;
    DDR_WE_N          : inout std_logic;
    FIXED_IO_DDR_VRN  : inout std_logic;
    FIXED_IO_DDR_VRP  : inout std_logic;
    FIXED_IO_MIO      : inout std_logic_vector(53 downto 0);
    FIXED_IO_PS_CLK   : inout std_logic;
    FIXED_IO_PS_PORB  : inout std_logic;
    FIXED_IO_PS_SRSTB : inout std_logic;
    OLED_DC           : inout std_logic;
    OLED_RES          : inout std_logic;
    OLED_SCLK         : inout std_logic;
    OLED_SDIN         : inout std_logic;
    OLED_VBAT         : inout std_logic;
    OLED_VDD          : inout std_logic;
    BTNS_5BITS_TRI_I  : in    std_logic_vector(4 downto 0);
    LEDS_8BITS_TRI_O  : out   std_logic_vector(7 downto 0);
    SWS_8BITS_TRI_I   : in    std_logic_vector(7 downto 0)
  );
end entity zynq_zed_ex_top;

architecture rtl of zynq_zed_ex_top is

  signal clk       : std_logic;
  signal rst       : std_logic;
  signal rstn      : std_logic;
  signal dbtn_c    : std_logic; -- reset
  signal dbtn_d    : std_logic; -- clear BRAM
  signal dbtn_l    : std_logic; -- start/stop fibonacci
  signal bram_addr : std_logic_vector(31 downto 0);
  signal bram_clk  : std_logic;
  signal bram_din  : std_logic_vector(31 downto 0);
  signal bram_dout : std_logic_vector(31 downto 0);
  signal bram_en   : std_logic;
  signal bram_rst  : std_logic;
  signal bram_we   : std_logic_vector(3 downto 0);

begin

  rst <= not rstn or dbtn_c;

  get_dbtnc : entity work.debouncer
    generic map (
      COUNT_MAX   => 65535,
      COUNT_WIDTH => 16
    )
    port map (
      CLK => clk,
      A   => BTNS_5BITS_TRI_I(0),
      B   => dbtn_c
    );

  get_dbtnd : entity work.debouncer
    generic map (
      COUNT_MAX   => 65535,
      COUNT_WIDTH => 16
    )
    port map (
      CLK => clk,
      A   => BTNS_5BITS_TRI_I(1),
      B   => dbtn_d
    );

  get_dbtnl : entity work.debouncer
    generic map (
      COUNT_MAX   => 65535,
      COUNT_WIDTH => 16
    )
    port map (
      CLK => clk,
      A   => BTNS_5BITS_TRI_I(2),
      B   => dbtn_l
    );

  fibonacci_bram_i : entity work.fibonacci_bram
    port map (
      CLK        => clk,
      RST        => rst,
      START_STOP => dbtn_l,
      CLEAR_BRAM => dbtn_d,
      BRAM_ADDR  => bram_addr,
      BRAM_CLK   => bram_clk,
      BRAM_DIN   => bram_din,
      BRAM_DOUT  => bram_dout,
      BRAM_EN    => bram_en,
      BRAM_RST   => bram_rst,
      BRAM_WE    => bram_we
    );

  zynq_zed_wrapper_i : entity work.zynq_zed_wrapper
    port map (
      BRAM_PORTB_0_ADDR     => bram_addr,
      BRAM_PORTB_0_CLK      => bram_clk,
      BRAM_PORTB_0_DIN      => bram_din,
      BRAM_PORTB_0_DOUT     => bram_dout,
      BRAM_PORTB_0_EN       => bram_en,
      BRAM_PORTB_0_RST      => bram_rst,
      BRAM_PORTB_0_WE       => bram_we,
      FCLK_CLK0             => clk,
      PERIPHERAL_ARESETN(0) => rstn,
      DDR_ADDR              => DDR_ADDR,
      DDR_BA                => DDR_BA,
      DDR_CAS_N             => DDR_CAS_N,
      DDR_CK_N              => DDR_CK_N,
      DDR_CK_P              => DDR_CK_P,
      DDR_CKE               => DDR_CKE,
      DDR_CS_N              => DDR_CS_N,
      DDR_DM                => DDR_DM,
      DDR_DQ                => DDR_DQ,
      DDR_DQS_N             => DDR_DQS_N,
      DDR_DQS_P             => DDR_DQS_P,
      DDR_ODT               => DDR_ODT,
      DDR_RAS_N             => DDR_RAS_N,
      DDR_RESET_N           => DDR_RESET_N,
      DDR_WE_N              => DDR_WE_N,
      FIXED_IO_DDR_VRN      => FIXED_IO_DDR_VRN,
      FIXED_IO_DDR_VRP      => FIXED_IO_DDR_VRP,
      FIXED_IO_MIO          => FIXED_IO_MIO,
      FIXED_IO_PS_CLK       => FIXED_IO_PS_CLK,
      FIXED_IO_PS_PORB      => FIXED_IO_PS_PORB,
      FIXED_IO_PS_SRSTB     => FIXED_IO_PS_SRSTB,
      GPIO_0_0_TRI_IO(0)    => OLED_DC,
      GPIO_0_0_TRI_IO(1)    => OLED_RES,
      GPIO_0_0_TRI_IO(2)    => OLED_SCLK,
      GPIO_0_0_TRI_IO(3)    => OLED_SDIN,
      GPIO_0_0_TRI_IO(4)    => OLED_VBAT,
      GPIO_0_0_TRI_IO(5)    => OLED_VDD,
      BTNS_5BITS_TRI_I      => BTNS_5BITS_TRI_I,
      LEDS_8BITS_TRI_O      => LEDS_8BITS_TRI_O,
      SWS_8BITS_TRI_I       => SWS_8BITS_TRI_I
    );

end architecture rtl;
