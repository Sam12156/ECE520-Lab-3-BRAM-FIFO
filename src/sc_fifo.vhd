-- Single-clock FIFO backed by inferred block RAM.
-- data_out is registered: data addressed by the read pointer appears
-- READ_LATENCY clocks after an accepted read, together with valid.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity sc_fifo is
    generic (
        WIDTH                  : integer := 16;
        DEPTH                  : integer := 32;   -- must be a power of two
        ALMOST_EMPTY_THRESHOLD : integer := 1;
        ALMOST_FULL_THRESHOLD  : integer := 31;
        READ_LATENCY           : integer range 1 to 8 := 1
    );
    port (
        clk          : in  std_logic;
        srst         : in  std_logic;
        data_in      : in  std_logic_vector(WIDTH-1 downto 0);
        write_enable : in  std_logic;
        read_enable  : in  std_logic;
        data_count   : out std_logic_vector(integer(ceil(log2(real(DEPTH + 1)))) - 1 downto 0);
        valid        : out std_logic;
        data_out     : out std_logic_vector(WIDTH-1 downto 0);
        almost_full  : out std_logic;
        almost_empty : out std_logic;
        full         : out std_logic;
        empty        : out std_logic
    );
end sc_fifo;

architecture rtl of sc_fifo is

    constant ADDR_WIDTH  : integer := integer(ceil(log2(real(DEPTH))));
    constant COUNT_WIDTH : integer := integer(ceil(log2(real(DEPTH + 1))));

    type mem_t is array (0 to DEPTH-1) of std_logic_vector(WIDTH-1 downto 0);
    signal mem : mem_t;
    attribute ram_style : string;
    attribute ram_style of mem : signal is "block";

    -- Stage 0 is the BRAM's own read register; later stages are extra pipeline
    type pipe_t is array (0 to READ_LATENCY-1) of std_logic_vector(WIDTH-1 downto 0);
    signal data_pipe  : pipe_t := (others => (others => '0'));
    signal valid_pipe : std_logic_vector(0 to READ_LATENCY-1) := (others => '0');

    signal wr_ptr : unsigned(ADDR_WIDTH-1 downto 0)  := (others => '0');
    signal rd_ptr : unsigned(ADDR_WIDTH-1 downto 0)  := (others => '0');
    signal count  : unsigned(COUNT_WIDTH-1 downto 0) := (others => '0');

    signal full_i  : std_logic;
    signal empty_i : std_logic;

    -- Writes are ignored when full and reads when empty
    signal do_write : std_logic;
    signal do_read  : std_logic;

begin

    assert 2**ADDR_WIDTH = DEPTH
        report "sc_fifo: DEPTH must be a power of two" severity failure;

    do_write <= write_enable and not full_i;
    do_read  <= read_enable and not empty_i;

    -- Memory write port, registered read port and output pipeline.
    -- The memory array itself is never reset so it maps onto BRAM.
    mem_proc : process (clk)
    begin
        if rising_edge(clk) then
            if do_write = '1' then
                mem(to_integer(wr_ptr)) <= data_in;
            end if;

            if srst = '1' then
                data_pipe  <= (others => (others => '0'));
                valid_pipe <= (others => '0');
            else
                if do_read = '1' then
                    data_pipe(0) <= mem(to_integer(rd_ptr));
                end if;
                valid_pipe(0) <= do_read;

                for i in 1 to READ_LATENCY-1 loop
                    data_pipe(i)  <= data_pipe(i-1);
                    valid_pipe(i) <= valid_pipe(i-1);
                end loop;
            end if;
        end if;
    end process;

    -- Pointers and occupancy count
    ctrl_proc : process (clk)
    begin
        if rising_edge(clk) then
            if srst = '1' then
                wr_ptr <= (others => '0');
                rd_ptr <= (others => '0');
                count  <= (others => '0');
            else
                if do_write = '1' then
                    wr_ptr <= wr_ptr + 1;
                end if;
                if do_read = '1' then
                    rd_ptr <= rd_ptr + 1;
                end if;

                if do_write = '1' and do_read = '0' then
                    count <= count + 1;
                elsif do_write = '0' and do_read = '1' then
                    count <= count - 1;
                end if;
            end if;
        end if;
    end process;

    full_i  <= '1' when count = DEPTH else '0';
    empty_i <= '1' when count = 0     else '0';

    full         <= full_i;
    empty        <= empty_i;
    almost_full  <= '1' when count >= ALMOST_FULL_THRESHOLD  else '0';
    almost_empty <= '1' when count <= ALMOST_EMPTY_THRESHOLD else '0';
    data_count   <= std_logic_vector(count);
    data_out     <= data_pipe(READ_LATENCY-1);
    valid        <= valid_pipe(READ_LATENCY-1);

end rtl;
