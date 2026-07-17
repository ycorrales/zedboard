library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity SpiCtrl is
    port (
        clk        : in  std_logic;
        send_start : in  std_logic;
        send_data  : in  std_logic_vector(7 downto 0);
        send_ready : out std_logic;
        CS         : out std_logic;
        SDO        : out std_logic;
        SCLK       : out std_logic
    );
end entity SpiCtrl;

architecture rtl of SpiCtrl is
    type state_t is (Idle, Send, HoldCS, Hold);

    constant COUNTER_MID : unsigned(4 downto 0) := to_unsigned(4, 5);
    constant COUNTER_MAX : unsigned(4 downto 0) := to_unsigned(9, 5);
    constant SCLK_DUTY   : unsigned(4 downto 0) := to_unsigned(5, 5);

    signal state          : state_t := Idle;
    signal shift_register : std_logic_vector(7 downto 0) := (others => '0');
    signal shift_counter  : unsigned(3 downto 0) := (others => '0');
    signal counter        : unsigned(4 downto 0) := (others => '0');
    signal temp_sdo       : std_logic := '0';
    signal cs_i           : std_logic;
    signal holdcs_i       : std_logic;
begin
    cs_i       <= '1' when state /= Send and state /= HoldCS else '0';
    holdcs_i   <= '1' when state = HoldCS else '0';
    CS         <= cs_i;
    SCLK       <= '1' when counter < SCLK_DUTY or cs_i = '1' else '0';
    SDO        <= temp_sdo or cs_i or holdcs_i;
    send_ready <= '1' when state = Idle and send_start = '0' else '0';

    process(clk)
    begin
        if rising_edge(clk) then
            case state is
                when Idle =>
                    if send_start = '1' then
                        state <= Send;
                    end if;

                when Send =>
                    if shift_counter = to_unsigned(8, 4) and counter = COUNTER_MID then
                        state <= HoldCS;
                    end if;

                when HoldCS =>
                    if shift_counter = to_unsigned(3, 4) then
                        state <= Hold;
                    end if;

                when Hold =>
                    if send_start = '0' then
                        state <= Idle;
                    end if;
            end case;
        end if;
    end process;

    process(clk)
    begin
        if rising_edge(clk) then
            if state = Send and not (counter = COUNTER_MID and shift_counter = to_unsigned(8, 4)) then
                if counter = COUNTER_MAX then
                    counter <= (others => '0');
                else
                    counter <= counter + 1;
                end if;
            else
                counter <= (others => '0');
            end if;
        end if;
    end process;

    process(clk)
    begin
        if rising_edge(clk) then
            if state = Idle then
                shift_counter  <= (others => '0');
                shift_register <= send_data;
                temp_sdo       <= '1';
            elsif state = Send then
                if counter = COUNTER_MID then
                    temp_sdo       <= shift_register(7);
                    shift_register <= shift_register(6 downto 0) & '0';
                    if shift_counter = to_unsigned(8, 4) then
                        shift_counter <= (others => '0');
                    else
                        shift_counter <= shift_counter + 1;
                    end if;
                end if;
            elsif state = HoldCS then
                shift_counter <= shift_counter + 1;
            end if;
        end if;
    end process;
end architecture rtl;
