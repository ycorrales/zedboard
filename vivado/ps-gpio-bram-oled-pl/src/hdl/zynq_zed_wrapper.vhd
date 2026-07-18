-- Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
-- Copyright 2022-2024 Advanced Micro Devices, Inc. All Rights Reserved.
----------------------------------------------------------------------------------
-- Tool Version: Vivado v.2024.1 (lin64) Build 5076996 Wed May 22 18:36:09 MDT 2024
-- Date        : Sat Jul 18 12:48:23 2026
-- Host        : localhost.localdomain running 64-bit unknown
-- Command     : generate_target zynq_zed_wrapper.bd
-- Design      : zynq_zed_wrapper
-- Purpose     : IP block netlist
----------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;

library unisim;
  use unisim.vcomponents.all;

entity zynq_zed_wrapper is
  port (
    BRAM_PORTB_0_ADDR  : in    std_logic_vector( 31 downto 0);
    BRAM_PORTB_0_CLK   : in    std_logic;
    BRAM_PORTB_0_DIN   : in    std_logic_vector( 31 downto 0);
    BRAM_PORTB_0_DOUT  : out   std_logic_vector( 31 downto 0);
    BRAM_PORTB_0_EN    : in    std_logic;
    BRAM_PORTB_0_RST   : in    std_logic;
    BRAM_PORTB_0_WE    : in    std_logic_vector( 3 downto 0);
    BTNS_5BITS_TRI_I   : in    std_logic_vector( 4 downto 0);
    DDR_ADDR           : inout std_logic_vector( 14 downto 0);
    DDR_BA             : inout std_logic_vector( 2 downto 0);
    DDR_CAS_N          : inout std_logic;
    DDR_CK_N           : inout std_logic;
    DDR_CK_P           : inout std_logic;
    DDR_CKE            : inout std_logic;
    DDR_CS_N           : inout std_logic;
    DDR_DM             : inout std_logic_vector( 3 downto 0);
    DDR_DQ             : inout std_logic_vector( 31 downto 0);
    DDR_DQS_N          : inout std_logic_vector( 3 downto 0);
    DDR_DQS_P          : inout std_logic_vector( 3 downto 0);
    DDR_ODT            : inout std_logic;
    DDR_RAS_N          : inout std_logic;
    DDR_RESET_N        : inout std_logic;
    DDR_WE_N           : inout std_logic;
    FCLK_CLK0          : out   std_logic;
    FIXED_IO_DDR_VRN   : inout std_logic;
    FIXED_IO_DDR_VRP   : inout std_logic;
    FIXED_IO_MIO       : inout std_logic_vector( 53 downto 0);
    FIXED_IO_PS_CLK    : inout std_logic;
    FIXED_IO_PS_PORB   : inout std_logic;
    FIXED_IO_PS_SRSTB  : inout std_logic;
    GPIO_0_0_TRI_IO    : inout std_logic_vector( 5 downto 0);
    LEDS_8BITS_TRI_O   : out   std_logic_vector( 7 downto 0);
    SWS_8BITS_TRI_I    : in    std_logic_vector( 7 downto 0);
    PERIPHERAL_ARESETN : out   std_logic_vector( 0 to 0)
  );
end entity zynq_zed_wrapper;

architecture structure of zynq_zed_wrapper is

  component zynq_zed is
    port (
      LEDS_8BITS_TRI_O   : out   std_logic_vector( 7 downto 0);
      SWS_8BITS_TRI_I    : in    std_logic_vector( 7 downto 0);
      DDR_CAS_N          : inout std_logic;
      DDR_CKE            : inout std_logic;
      DDR_CK_N           : inout std_logic;
      DDR_CK_P           : inout std_logic;
      DDR_CS_N           : inout std_logic;
      DDR_RESET_N        : inout std_logic;
      DDR_ODT            : inout std_logic;
      DDR_RAS_N          : inout std_logic;
      DDR_WE_N           : inout std_logic;
      DDR_BA             : inout std_logic_vector( 2 downto 0);
      DDR_ADDR           : inout std_logic_vector( 14 downto 0);
      DDR_DM             : inout std_logic_vector( 3 downto 0);
      DDR_DQ             : inout std_logic_vector( 31 downto 0);
      DDR_DQS_N          : inout std_logic_vector( 3 downto 0);
      DDR_DQS_P          : inout std_logic_vector( 3 downto 0);
      FIXED_IO_MIO       : inout std_logic_vector( 53 downto 0);
      FIXED_IO_DDR_VRN   : inout std_logic;
      FIXED_IO_DDR_VRP   : inout std_logic;
      FIXED_IO_PS_SRSTB  : inout std_logic;
      FIXED_IO_PS_CLK    : inout std_logic;
      FIXED_IO_PS_PORB   : inout std_logic;
      BRAM_PORTB_0_ADDR  : in    std_logic_vector( 31 downto 0);
      BRAM_PORTB_0_CLK   : in    std_logic;
      BRAM_PORTB_0_DIN   : in    std_logic_vector( 31 downto 0);
      BRAM_PORTB_0_DOUT  : out   std_logic_vector( 31 downto 0);
      BRAM_PORTB_0_EN    : in    std_logic;
      BRAM_PORTB_0_RST   : in    std_logic;
      BRAM_PORTB_0_WE    : in    std_logic_vector( 3 downto 0);
      GPIO_0_0_TRI_I     : in    std_logic_vector( 5 downto 0);
      GPIO_0_0_TRI_O     : out   std_logic_vector( 5 downto 0);
      GPIO_0_0_TRI_T     : out   std_logic_vector( 5 downto 0);
      BTNS_5BITS_TRI_I   : in    std_logic_vector( 4 downto 0);
      FCLK_CLK0          : out   std_logic;
      PERIPHERAL_ARESETN : out   std_logic_vector( 0 to 0)
    );
  end component zynq_zed;

  component iobuf is
    port (
      I  : in    std_logic;
      O  : out   std_logic;
      T  : in    std_logic;
      IO : inout std_logic
    );
  end component iobuf;

  signal gpio_0_0_tri_i_0  : std_logic_vector( 0 to 0);
  signal gpio_0_0_tri_i_1  : std_logic_vector( 1 to 1);
  signal gpio_0_0_tri_i_2  : std_logic_vector( 2 to 2);
  signal gpio_0_0_tri_i_3  : std_logic_vector( 3 to 3);
  signal gpio_0_0_tri_i_4  : std_logic_vector( 4 to 4);
  signal gpio_0_0_tri_i_5  : std_logic_vector( 5 to 5);
  signal gpio_0_0_tri_io_0 : std_logic_vector( 0 to 0);
  signal gpio_0_0_tri_io_1 : std_logic_vector( 1 to 1);
  signal gpio_0_0_tri_io_2 : std_logic_vector( 2 to 2);
  signal gpio_0_0_tri_io_3 : std_logic_vector( 3 to 3);
  signal gpio_0_0_tri_io_4 : std_logic_vector( 4 to 4);
  signal gpio_0_0_tri_io_5 : std_logic_vector( 5 to 5);
  signal gpio_0_0_tri_o_0  : std_logic_vector( 0 to 0);
  signal gpio_0_0_tri_o_1  : std_logic_vector( 1 to 1);
  signal gpio_0_0_tri_o_2  : std_logic_vector( 2 to 2);
  signal gpio_0_0_tri_o_3  : std_logic_vector( 3 to 3);
  signal gpio_0_0_tri_o_4  : std_logic_vector( 4 to 4);
  signal gpio_0_0_tri_o_5  : std_logic_vector( 5 to 5);
  signal gpio_0_0_tri_t_0  : std_logic_vector( 0 to 0);
  signal gpio_0_0_tri_t_1  : std_logic_vector( 1 to 1);
  signal gpio_0_0_tri_t_2  : std_logic_vector( 2 to 2);
  signal gpio_0_0_tri_t_3  : std_logic_vector( 3 to 3);
  signal gpio_0_0_tri_t_4  : std_logic_vector( 4 to 4);
  signal gpio_0_0_tri_t_5  : std_logic_vector( 5 to 5);

begin

  gpio_0_0_tri_iobuf_0 : component iobuf
    port map (
      I  => gpio_0_0_tri_o_0(0),
      IO => GPIO_0_0_TRI_IO(0),
      O  => gpio_0_0_tri_i_0(0),
      T  => gpio_0_0_tri_t_0(0)
    );

  gpio_0_0_tri_iobuf_1 : component iobuf
    port map (
      I  => gpio_0_0_tri_o_1(1),
      IO => GPIO_0_0_TRI_IO(1),
      O  => gpio_0_0_tri_i_1(1),
      T  => gpio_0_0_tri_t_1(1)
    );

  gpio_0_0_tri_iobuf_2 : component iobuf
    port map (
      I  => gpio_0_0_tri_o_2(2),
      IO => GPIO_0_0_TRI_IO(2),
      O  => gpio_0_0_tri_i_2(2),
      T  => gpio_0_0_tri_t_2(2)
    );

  gpio_0_0_tri_iobuf_3 : component iobuf
    port map (
      I  => gpio_0_0_tri_o_3(3),
      IO => GPIO_0_0_TRI_IO(3),
      O  => gpio_0_0_tri_i_3(3),
      T  => gpio_0_0_tri_t_3(3)
    );

  gpio_0_0_tri_iobuf_4 : component iobuf
    port map (
      I  => gpio_0_0_tri_o_4(4),
      IO => GPIO_0_0_TRI_IO(4),
      O  => gpio_0_0_tri_i_4(4),
      T  => gpio_0_0_tri_t_4(4)
    );

  gpio_0_0_tri_iobuf_5 : component iobuf
    port map (
      I  => gpio_0_0_tri_o_5(5),
      IO => GPIO_0_0_TRI_IO(5),
      O  => gpio_0_0_tri_i_5(5),
      T  => gpio_0_0_tri_t_5(5)
    );

  zynq_zed_i : component zynq_zed
    port map (
      BRAM_PORTB_0_ADDR(31 downto 0) => BRAM_PORTB_0_ADDR(31 downto 0),
      BRAM_PORTB_0_CLK               => BRAM_PORTB_0_CLK,
      BRAM_PORTB_0_DIN(31 downto 0)  => BRAM_PORTB_0_DIN(31 downto 0),
      BRAM_PORTB_0_DOUT(31 downto 0) => BRAM_PORTB_0_DOUT(31 downto 0),
      BRAM_PORTB_0_EN                => BRAM_PORTB_0_EN,
      BRAM_PORTB_0_RST               => BRAM_PORTB_0_RST,
      BRAM_PORTB_0_WE(3 downto 0)    => BRAM_PORTB_0_WE(3 downto 0),
      BTNS_5BITS_TRI_I(4 downto 0)   => BTNS_5BITS_TRI_I(4 downto 0),
      DDR_ADDR(14 downto 0)          => DDR_ADDR(14 downto 0),
      DDR_BA(2 downto 0)             => DDR_BA(2 downto 0),
      DDR_CAS_N                      => DDR_CAS_N,
      DDR_CK_N                       => DDR_CK_N,
      DDR_CK_P                       => DDR_CK_P,
      DDR_CKE                        => DDR_CKE,
      DDR_CS_N                       => DDR_CS_N,
      DDR_DM(3 downto 0)             => DDR_DM(3 downto 0),
      DDR_DQ(31 downto 0)            => DDR_DQ(31 downto 0),
      DDR_DQS_N(3 downto 0)          => DDR_DQS_N(3 downto 0),
      DDR_DQS_P(3 downto 0)          => DDR_DQS_P(3 downto 0),
      DDR_ODT                        => DDR_ODT,
      DDR_RAS_N                      => DDR_RAS_N,
      DDR_RESET_N                    => DDR_RESET_N,
      DDR_WE_N                       => DDR_WE_N,
      FCLK_CLK0                      => FCLK_CLK0,
      FIXED_IO_DDR_VRN               => FIXED_IO_DDR_VRN,
      FIXED_IO_DDR_VRP               => FIXED_IO_DDR_VRP,
      FIXED_IO_MIO(53 downto 0)      => FIXED_IO_MIO(53 downto 0),
      FIXED_IO_PS_CLK                => FIXED_IO_PS_CLK,
      FIXED_IO_PS_PORB               => FIXED_IO_PS_PORB,
      FIXED_IO_PS_SRSTB              => FIXED_IO_PS_SRSTB,
      GPIO_0_0_TRI_I(5)              => gpio_0_0_tri_i_5(5),
      GPIO_0_0_TRI_I(4)              => gpio_0_0_tri_i_4(4),
      GPIO_0_0_TRI_I(3)              => gpio_0_0_tri_i_3(3),
      GPIO_0_0_TRI_I(2)              => gpio_0_0_tri_i_2(2),
      GPIO_0_0_TRI_I(1)              => gpio_0_0_tri_i_1(1),
      GPIO_0_0_TRI_I(0)              => gpio_0_0_tri_i_0(0),
      GPIO_0_0_TRI_O(5)              => gpio_0_0_tri_o_5(5),
      GPIO_0_0_TRI_O(4)              => gpio_0_0_tri_o_4(4),
      GPIO_0_0_TRI_O(3)              => gpio_0_0_tri_o_3(3),
      GPIO_0_0_TRI_O(2)              => gpio_0_0_tri_o_2(2),
      GPIO_0_0_TRI_O(1)              => gpio_0_0_tri_o_1(1),
      GPIO_0_0_TRI_O(0)              => gpio_0_0_tri_o_0(0),
      GPIO_0_0_TRI_T(5)              => gpio_0_0_tri_t_5(5),
      GPIO_0_0_TRI_T(4)              => gpio_0_0_tri_t_4(4),
      GPIO_0_0_TRI_T(3)              => gpio_0_0_tri_t_3(3),
      GPIO_0_0_TRI_T(2)              => gpio_0_0_tri_t_2(2),
      GPIO_0_0_TRI_T(1)              => gpio_0_0_tri_t_1(1),
      GPIO_0_0_TRI_T(0)              => gpio_0_0_tri_t_0(0),
      LEDS_8BITS_TRI_O(7 downto 0)   => LEDS_8BITS_TRI_O(7 downto 0),
      SWS_8BITS_TRI_I(7 downto 0)    => SWS_8BITS_TRI_I(7 downto 0),
      PERIPHERAL_ARESETN(0)          => PERIPHERAL_ARESETN(0)
    );

end architecture structure;
