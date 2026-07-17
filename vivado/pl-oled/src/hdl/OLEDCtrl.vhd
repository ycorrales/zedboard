library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity OLEDCtrl is
    port (
        clk               : in  std_logic;
        write_start       : in  std_logic;
        write_ascii_data  : in  std_logic_vector(7 downto 0);
        write_base_addr   : in  std_logic_vector(8 downto 0);
        write_ready       : out std_logic;
        update_start      : in  std_logic;
        update_clear      : in  std_logic;
        update_ready      : out std_logic;
        disp_on_start     : in  std_logic;
        disp_on_ready     : out std_logic;
        disp_off_start    : in  std_logic;
        disp_off_ready    : out std_logic;
        toggle_disp_start : in  std_logic;
        toggle_disp_ready : out std_logic;
        SDIN              : out std_logic;
        SCLK              : out std_logic;
        DC                : out std_logic;
        RES               : out std_logic;
        VBAT              : out std_logic;
        VDD               : out std_logic
    );
end entity OLEDCtrl;

architecture rtl of OLEDCtrl is
    type state_t is (
        Idle,
        Startup,
        StartupFetch,
        ActiveWait,
        ActiveUpdatePage,
        ActiveUpdateScreen,
        ActiveSendByte,
        ActiveUpdateWait,
        ActiveToggleDispWait,
        ActiveWrite,
        ActiveWriteTran,
        ActiveWriteWait,
        BringdownDispOff,
        BringdownVbatOff,
        BringdownVddOff,
        UtilitySpiStart,
        UtilitySpiWait,
        UtilityDelayStart,
        UtilityDelayWait
    );

    signal state              : state_t := Idle;
    signal after_state        : state_t := Idle;
    signal after_page_state   : state_t := Idle;
    signal after_char_state   : state_t := Idle;
    signal after_update_state : state_t := Idle;
    signal disp_is_full       : std_logic := '0';
    signal clear_screen       : std_logic := '0';

    signal update_page_count : unsigned(2 downto 0) := (others => '0');
    signal temp_page         : unsigned(1 downto 0) := (others => '0');
    signal temp_index        : unsigned(6 downto 0) := (others => '0');

    signal oled_dc   : std_logic := '1';
    signal oled_res  : std_logic := '1';
    signal oled_vdd  : std_logic := '1';
    signal oled_vbat : std_logic := '1';

    signal temp_spi_start : std_logic := '0';
    signal temp_spi_data  : std_logic_vector(7 downto 0) := (others => '0');
    signal temp_spi_done  : std_logic;
    signal temp_spi_cs    : std_logic;

    signal temp_delay_start : std_logic := '0';
    signal temp_delay_ms    : std_logic_vector(11 downto 0) := (others => '0');
    signal temp_delay_done  : std_logic;

    signal temp_write_ascii     : std_logic_vector(7 downto 0) := (others => '0');
    signal temp_write_base_addr : unsigned(8 downto 0) := (others => '0');

    signal char_lib_addr   : std_logic_vector(9 downto 0);
    signal pbuf_read_addr  : std_logic_vector(8 downto 0);
    signal pbuf_read_data  : std_logic_vector(7 downto 0);
    signal pbuf_write_en   : std_logic_vector(0 downto 0);
    signal pbuf_write_data : std_logic_vector(7 downto 0);
    signal pbuf_write_addr : std_logic_vector(8 downto 0);

    signal write_byte_count : unsigned(2 downto 0) := (others => '0');

    signal init_operation  : std_logic_vector(15 downto 0);
    signal startup_count   : unsigned(4 downto 0) := (others => '0');
    signal iop_state_select : std_logic := '0';
    signal iop_res_set      : std_logic := '0';
    signal iop_res_val      : std_logic := '0';
    signal iop_vbat_set     : std_logic := '0';
    signal iop_vbat_val     : std_logic := '0';
    signal iop_vdd_set      : std_logic := '0';
    signal iop_vdd_val      : std_logic := '0';
    signal iop_data         : std_logic_vector(7 downto 0) := (others => '0');

    component charLib is
        port (
            clka  : in  std_logic;
            addra : in  std_logic_vector(9 downto 0);
            douta : out std_logic_vector(7 downto 0)
        );
    end component;

    component pixel_buffer is
        port (
            clka  : in  std_logic;
            wea   : in  std_logic_vector(0 downto 0);
            addra : in  std_logic_vector(8 downto 0);
            dina  : in  std_logic_vector(7 downto 0);
            clkb  : in  std_logic;
            addrb : in  std_logic_vector(8 downto 0);
            doutb : out std_logic_vector(7 downto 0)
        );
    end component;

    component init_sequence_rom is
        port (
            clka  : in  std_logic;
            addra : in  std_logic_vector(4 downto 0);
            douta : out std_logic_vector(15 downto 0)
        );
    end component;
begin
    DC   <= oled_dc;
    RES  <= oled_res;
    VDD  <= oled_vdd;
    VBAT <= oled_vbat;

    SPI_CTRL : entity work.SpiCtrl
        port map (
            clk        => clk,
            send_start => temp_spi_start,
            send_data  => temp_spi_data,
            send_ready => temp_spi_done,
            CS         => temp_spi_cs,
            SDO        => SDIN,
            SCLK       => SCLK
        );

    MS_DELAY : entity work.delay_ms
        port map (
            clk           => clk,
            delay_start   => temp_delay_start,
            delay_time_ms => temp_delay_ms,
            delay_done    => temp_delay_done
        );

    pbuf_read_addr  <= std_logic_vector(temp_page & temp_index);
    char_lib_addr   <= temp_write_ascii(6 downto 0) & std_logic_vector(write_byte_count);
    pbuf_write_en(0) <= '1' when state = ActiveWrite else '0';
    pbuf_write_addr <= std_logic_vector(temp_write_base_addr + resize(write_byte_count, 9));

    U_CHAR_LIB : charLib
        port map (
            clka  => clk,
            addra => char_lib_addr,
            douta => pbuf_write_data
        );

    U_PIXEL_BUFFER : pixel_buffer
        port map (
            clka  => clk,
            wea   => pbuf_write_en,
            addra => pbuf_write_addr,
            dina  => pbuf_write_data,
            clkb  => clk,
            addrb => pbuf_read_addr,
            doutb => pbuf_read_data
        );

    U_INIT_SEQ : init_sequence_rom
        port map (
            clka  => clk,
            addra => std_logic_vector(startup_count),
            douta => init_operation
        );

    disp_on_ready     <= '1' when state = Idle and disp_on_start = '0' else '0';
    update_ready      <= '1' when state = ActiveWait and update_start = '0' else '0';
    write_ready       <= '1' when state = ActiveWait and write_start = '0' else '0';
    disp_off_ready    <= '1' when state = ActiveWait and disp_off_start = '0' else '0';
    toggle_disp_ready <= '1' when state = ActiveWait and toggle_disp_start = '0' else '0';

    process(clk)
    begin
        if rising_edge(clk) then
            case state is
                when Idle =>
                    if disp_on_start = '1' then
                        startup_count <= (others => '0');
                        state <= StartupFetch;
                    end if;
                    disp_is_full <= '0';

                when Startup =>
                    oled_dc <= '0';

                    if iop_vdd_set = '1' then
                        oled_vdd <= iop_vdd_val;
                    end if;
                    if iop_res_set = '1' then
                        oled_res <= iop_res_val;
                    end if;
                    if iop_vbat_set = '1' then
                        oled_vbat <= iop_vbat_val;
                    end if;

                    if iop_state_select = '0' then
                        temp_delay_ms    <= "0000" & iop_data;
                        state            <= UtilityDelayStart;
                    else
                        temp_spi_data  <= iop_data;
                        state          <= UtilitySpiStart;
                    end if;

                    if startup_count = to_unsigned(26, 5) then
                        after_state        <= ActiveUpdatePage;
                        after_update_state <= ActiveWait;
                        after_char_state   <= ActiveUpdateScreen;
                        after_page_state   <= ActiveUpdateScreen;
                        update_page_count  <= (others => '0');
                        temp_page          <= (others => '0');
                        temp_index         <= (others => '0');
                        clear_screen       <= '1';
                    else
                        after_state   <= StartupFetch;
                        startup_count <= startup_count + 1;
                    end if;

                when StartupFetch =>
                    state            <= Startup;
                    iop_state_select <= init_operation(14);
                    iop_res_set      <= init_operation(13);
                    iop_res_val      <= init_operation(12);
                    iop_vdd_set      <= init_operation(11);
                    iop_vdd_val      <= init_operation(10);
                    iop_vbat_set     <= init_operation(9);
                    iop_vbat_val     <= init_operation(8);
                    iop_data         <= init_operation(7 downto 0);

                when ActiveWait =>
                    if disp_off_start = '1' then
                        state <= BringdownDispOff;
                    elsif update_start = '1' then
                        after_update_state <= ActiveUpdateWait;
                        after_char_state   <= ActiveUpdateScreen;
                        after_page_state   <= ActiveUpdateScreen;
                        state              <= ActiveUpdatePage;
                        update_page_count  <= (others => '0');
                        temp_page          <= (others => '0');
                        temp_index         <= (others => '0');
                        clear_screen       <= update_clear;
                    elsif write_start = '1' then
                        state                <= ActiveWriteTran;
                        write_byte_count     <= (others => '0');
                        temp_write_ascii     <= write_ascii_data;
                        temp_write_base_addr <= unsigned(write_base_addr);
                    elsif toggle_disp_start = '1' then
                        oled_dc          <= '0';
                        disp_is_full     <= not disp_is_full;
                        temp_spi_data    <= x"A4" or ("0000000" & (not disp_is_full));
                        after_state      <= ActiveToggleDispWait;
                        state            <= UtilitySpiStart;
                    end if;

                when ActiveWrite =>
                    if write_byte_count = to_unsigned(7, 3) then
                        state <= ActiveWriteWait;
                    else
                        state <= ActiveWriteTran;
                    end if;
                    write_byte_count <= write_byte_count + 1;

                when ActiveWriteTran =>
                    state <= ActiveWrite;

                when ActiveWriteWait =>
                    if write_start = '0' then
                        state <= ActiveWait;
                    else
                        state <= ActiveWriteWait;
                    end if;
                    write_byte_count <= (others => '0');

                when ActiveUpdatePage =>
                    case update_page_count is
                        when "000" => temp_spi_data <= x"B0" or ("000000" & std_logic_vector(temp_page));
                        when "001" => temp_spi_data <= x"00";
                        when "010" => temp_spi_data <= x"10";
                        when others => null;
                    end case;

                    if update_page_count < to_unsigned(3, 3) then
                        oled_dc        <= '0';
                        after_state    <= ActiveUpdatePage;
                        state          <= UtilitySpiStart;
                    else
                        state <= after_page_state;
                    end if;
                    update_page_count <= update_page_count + 1;

                when ActiveSendByte =>
                    oled_dc <= '1';
                    if clear_screen = '1' then
                        temp_spi_data <= (others => '0');
                    else
                        temp_spi_data <= pbuf_read_data;
                    end if;
                    after_state    <= after_char_state;
                    state          <= UtilitySpiStart;

                when ActiveUpdateScreen =>
                    if temp_index = to_unsigned(127, 7) then
                        temp_index        <= (others => '0');
                        temp_page         <= temp_page + 1;
                        update_page_count <= (others => '0');
                        after_char_state  <= ActiveUpdatePage;
                        if temp_page = to_unsigned(3, 2) then
                            after_page_state <= after_update_state;
                        else
                            after_page_state <= ActiveUpdateScreen;
                        end if;
                    else
                        temp_index       <= temp_index + 1;
                        after_char_state <= ActiveUpdateScreen;
                    end if;
                    state <= ActiveSendByte;

                when ActiveUpdateWait =>
                    if update_start = '0' then
                        state <= ActiveWait;
                    end if;

                when ActiveToggleDispWait =>
                    if toggle_disp_start = '0' then
                        state <= ActiveWait;
                    end if;

                when BringdownDispOff =>
                    oled_dc        <= '0';
                    temp_spi_data  <= x"AE";
                    after_state    <= BringdownVbatOff;
                    state          <= UtilitySpiStart;

                when BringdownVbatOff =>
                    oled_vbat        <= '1';
                    temp_delay_ms    <= std_logic_vector(to_unsigned(100, 12));
                    after_state      <= BringdownVddOff;
                    state            <= UtilityDelayStart;

                when BringdownVddOff =>
                    oled_vdd <= '1';
                    if disp_on_start = '0' then
                        state <= Idle;
                    end if;

                when UtilitySpiStart =>
                    temp_spi_start <= '1';
                    state          <= UtilitySpiWait;

                when UtilitySpiWait =>
                    temp_spi_start <= '0';
                    if temp_spi_done = '1' then
                        state <= after_state;
                    end if;

                when UtilityDelayStart =>
                    temp_delay_start <= '1';
                    state            <= UtilityDelayWait;

                when UtilityDelayWait =>
                    temp_delay_start <= '0';
                    if temp_delay_done = '1' then
                        state <= after_state;
                    end if;
            end case;
        end if;
    end process;
end architecture rtl;
