-- cpu.vhd: Simple 8-bit CPU (BrainF*ck interpreter)
-- Copyright (C) 2019 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): Pavel Zadlouski 
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
	port (
		CLK   : in std_logic; -- hodinovy signal
		RESET : in std_logic; -- asynchronni reset procesoru
		EN    : in std_logic; -- povoleni cinnosti procesoru

		-- synchronni pamet RAM
		DATA_ADDR  : out std_logic_vector(12 downto 0); -- adresa do pameti
		DATA_WDATA : out std_logic_vector(7 downto 0);  -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
		DATA_RDATA : in std_logic_vector(7 downto 0);   -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
		DATA_RDWR  : out std_logic;                     -- cteni (0) / zapis (1)
		DATA_EN    : out std_logic;                     -- povoleni cinnosti

		-- vstupni port
		IN_DATA : in std_logic_vector(7 downto 0); -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
		IN_VLD  : in std_logic;                    -- data platna
		IN_REQ  : out std_logic;                   -- pozadavek na vstup data

		-- vystupni port
		OUT_DATA : out std_logic_vector(7 downto 0); -- zapisovana data
		OUT_BUSY : in std_logic;                     -- LCD je zaneprazdnen (1), nelze zapisovat
		OUT_WE   : out std_logic                     -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'
	);
end cpu;

-- Program i data jsou uloˇzena ve stejn´e pamˇeti maj´ıc´ı kapacitu 8192 8-bitov´ych poloˇzek. 
-- Data jsou uloˇzena od adresy 0x1000 (tj.
--4096 des´ıtkovˇe). Obsah pamˇeti nechˇt je pro jednoduchost inicializov´an na hodnotu nula. Pro pˇr´ıstup do
--pamˇeti se pouˇz´ıv´a ukazatel (ptr), kter´y je moˇzn´e pˇresouvat o pozici doleva ˇci doprava. Pamˇeˇt je ch´ap´ana
-- jako kruhov´y buffer uchov´avaj´ıc´ı 8-bitov´a ˇc´ısla bez znam´enka. Posun doleva z adresy 0x1000 tedy znamen´a
--pˇresun ukazatele na konec pamˇeti odpov´ıdaj´ıc´ı adrese 0x1FFF.

-- Pomocn´apromˇenn´a tmp je uloˇzena v pamˇeti na adrese 0x1000. Ukazatel ptr ukazuje po resetu na adresu 0x1000.

-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is

	-- zde dopiste potrebne deklarace signalu
	signal pc_reg : std_logic_vector(12 downto 0); -- Program Counter
	signal pc_inc : std_logic;                     -- incrementation
	signal pc_dec : std_logic;                     -- decrementation
	-- Addres pointer	
	signal ptr_reg : std_logic_vector(12 downto 0); -- counter of memory pointer
	signal ptr_inc : std_logic;                     -- incrementation
	signal ptr_dec : std_logic;                     -- decrementation

	-- CNT for while loop
	signal cnt_reg : std_logic_vector(7 downto 0);
	signal cnt_inc : std_logic;
	signal cnt_dec : std_logic;

	type fsm_state is (
		begin_st,
		fetch,
		decode,
		ptrInc,                   -- increment pointer 
		ptrDec,                   -- decrement pointers
		valIncR, val_inc_2, valIncW, -- for +
		valDecR, val_dec_2, valDecW, -- for -
		while_1, while_2,         -- for [
		go_ahead_1, go_ahead_2,
		while_1_end, while_2_end, -- fro ]
		go_back_1, go_back_2, go_back_3, 
		printR, printW,
		scanR, scanW,
		to_tmp, to_tmp_1, to_tmp_2,
		from_tmp, from_tmp_2, from_tmp_3,
		EOF,
		comment);
	signal present_st  : fsm_state := fetch; -- default state
	signal next_st     : fsm_state;          -- 
	signal mx_data_sel : std_logic_vector(1 downto 0) := "00";
	signal mx_wdata    : std_logic_vector(7 downto 0);
	signal tmp         : std_logic_vector(7 downto 0) := (others => '0');
begin
	-- Programovy citac pro instrukci 
	progrma_cnt : process (CLK, RESET, pc_inc, pc_dec)
	begin
		if RESET = '1' then
			pc_reg <= (others => '0');
		elsif rising_edge(CLK) then
			if (pc_inc = '1') then
				if(pc_reg = "0111111111111") then 
					pc_reg <= (others => '0');
				else
					pc_reg <= pc_reg + 1;
				end if;
			elsif (pc_dec = '1') then
				if(pc_reg = "0000000000000") then 
					pc_reg <= "0111111111111";
				else		
					pc_reg <= pc_reg - 1;
				end if;
			end if;
		end if;
	end process;

	-- Ukazatel do pamet dat
	mem_ptr : process (CLK, RESET, ptr_inc, ptr_dec)
	begin
		if RESET = '1' then
			ptr_reg <= "1000000000000";
		elsif rising_edge(CLK) then
			if ptr_inc = '1' then
				if ptr_reg = "1111111111111" then
					ptr_reg <= "1000000000000";
				else
					ptr_reg <= ptr_reg + 1;
				end if;
			elsif ptr_dec = '1' then
				if ptr_reg = "1000000000000" then
					ptr_reg <= "1111111111111";
				else
					ptr_reg <= ptr_reg - 1;
				end if;
			end if;
		end if;
	end process;

	cnt_cntr : process (CLK, RESET, cnt_inc, cnt_dec)
	begin
		if RESET = '1' then
			cnt_reg <= (others => '0');
		elsif rising_edge(CLK) then
			if (cnt_inc = '1') then
				cnt_reg <= cnt_reg + 1;
			elsif (cnt_dec = '1') then
				cnt_reg <= cnt_reg - 1;
			end if;
		end if;
	end process;
	present_state : process (RESET, CLK, EN, next_st)
	begin
		if (RESET = '1') then
			present_st <= fetch;
		elsif (rising_edge(CLK) and EN = '1') then
			present_st <= next_st;
		end if;
	end process;

	choose_out : process (RESET, CLK,  mx_data_sel)
	begin
		if (RESET = '1') then
			mx_wdata <= (others => '0');
		else
			case (mx_data_sel) is
				when "00" => mx_wdata   <= IN_DATA;
				when "01" => mx_wdata   <= DATA_RDATA + 1;
				when "10" => mx_wdata   <= DATA_RDATA - 1;
				when "11" => mx_wdata <= tmp;
				when others => mx_wdata <= (others => '0');
			end case;

		end if;
	end process;

	DATA_WDATA <= mx_wdata;
	OUT_DATA <= DATA_RDATA when tmp = (tmp'range => '0') else tmp;
	with  present_st select DATA_ADDR <= 
		pc_reg when fetch,
		pc_reg when go_ahead_1,
		pc_reg when go_back_1,
		"1000000000000" when from_tmp,
		"1000000000000" when to_tmp_1, 
		ptr_reg when others;		

	next_st_logic : process (DATA_RDATA, ptr_reg, cnt_reg, pc_reg, OUT_BUSY, IN_VLD, IN_DATA, present_st)

	begin
		ptr_inc     <= '0';
		ptr_dec     <= '0';
		pc_inc      <= '0';
		pc_dec      <= '0';
		cnt_inc     <= '0';
		cnt_dec     <= '0';
		OUT_WE      <= '0';
		DATA_EN     <= '0';
		DATA_RDWR <= '0';
 		mx_data_sel <= "00";
		case (present_st) is
			when fetch =>     -- read from memory mem[PC]
				--DATA_ADDR <= pc_reg;			
				DATA_EN   <= '1'; -- let processor work
				DATA_RDWR <= '0'; -- let it read
				next_st   <= decode;
			when decode =>
				case(DATA_RDATA) is                   -- choose instruction
				when x"3e" => next_st <= ptrInc;      -- > NOT TESTED
				when x"3c" => next_st <= ptrDec;      -- < NOT TESTED
				when x"2b" => next_st <= valIncR;     -- + NOT TESTED
				when x"2d" => next_st <= valDecR;     -- - NOT TESTED
				when x"5b" => next_st <= while_1;     -- [ 
				when x"5d" => next_st <= while_1_end; -- ]
				when x"2e" => next_st <= printR;      -- . NOT TESTED
				when x"2c" => next_st <= scanR; -- , NOT TESTED
				when x"24" => next_st <= to_tmp; -- $
				when x"21"  => next_st  <= from_tmp; -- !
				when x"00"  => next_st  <= EOF;      -- null
				when others => next_st <= comment;   -- comment
				end case;
			when ptrInc =>
				ptr_inc <= '1'; -- increment pointer
				pc_inc  <= '1'; -- move to the next instruction

				next_st <= fetch; -- next state is process next inctruction

			when ptrDec =>
				ptr_dec <= '1';

				pc_inc <= '1';

				next_st <= fetch;

			when valIncR => -- read from sell 
				DATA_EN   <= '1';
				DATA_RDWR <= '0';

				next_st <= valIncW;

			when valIncW =>
				DATA_EN     <= '1';
				DATA_RDWR   <= '1';
				pc_inc      <= '1';
				next_st <= fetch;
		
				mx_data_sel <= "01";
			when valDecR =>
				DATA_EN   <= '1';
				DATA_RDWR <= '0';

				next_st     <= valDecW;
			when valDecW =>
				DATA_EN   <= '1';
				DATA_RDWR <= '1';
				pc_inc      <= '1';
				mx_data_sel <= "10";
			
				next_st <= fetch;
			when scanR =>
				IN_REQ <= '1';
				mx_data_sel <= "00";
				next_st <= scanW;
			when scanW =>
				if IN_VLD = '1' then 
					IN_REQ     <= '0';
	                    		DATA_EN    <= '1';
       	       		      		DATA_RDWR  <= '1';
       		             		mx_data_sel <= "00";
		    			pc_inc     <= '1';
                   			next_st <= fetch;
				else 
					next_st <= scanW; 
				end if; 
			when printR =>
				DATA_EN   <= '1';
				DATA_RDWR <= '0';
				next_st   <= printW;

			when printW =>
				if (OUT_BUSY = '1') then
					DATA_EN   <= '1';
					DATA_RDWR <= '0';
					next_st   <= printW; -- return to the same state
				else
					OUT_WE  <= '1';
					pc_inc  <= '1';
					tmp <= (others => '0');
					next_st <= fetch;
					
				end if;
			when to_tmp =>
				DATA_EN <= '1';
				DATA_RDWR <= '0';
				next_st <= to_tmp_1;
			when to_tmp_1 =>
				tmp <= DATA_RDATA;
				next_st <= to_tmp_2;
			when to_tmp_2 =>
				mx_data_sel <= "11";
				DATA_EN   <= '1';
				DATA_RDWR <= '1';
				pc_inc  <= '1';
				next_st <= fetch;
			when from_tmp =>
				DATA_EN   <= '1';
				DATA_RDWR <= '0';
				next_st <= from_tmp_2;
			when from_tmp_2 =>
				tmp <= DATA_RDATA;
				next_st <= from_tmp_3;
			when from_tmp_3 =>
				mx_data_sel <= "11";							
				DATA_EN   <= '1';
				DATA_RDWR <= '1';
				pc_inc  <= '1';
				next_st <= fetch;
			when while_1 => -- begining of while loop
			       pc_inc <= '1';			       
			       DATA_EN   <= '1';
			       DATA_RDWR <= '0';
			       next_st   <= while_2;
            		when while_2 =>
                		if (DATA_RDATA /= "00000000") then
                   			next_st <= fetch;
                		else
					cnt_inc <= '1';
                    			next_st <= go_ahead_1;
                                end if;
            when go_ahead_1 =>
               -- DATA_ADDR <= pc_reg;
                DATA_EN   <= '1';
                DATA_RDWR <= '0';
                next_st   <= go_ahead_2;
            when go_ahead_2 =>
		if cnt_reg = "00000000" then 
			next_st <= fetch;
		else 
			if (DATA_RDATA = x"5b") then --[
                		cnt_inc <= '1';
                	elsif (DATA_RDATA = x"5d") then 
				cnt_dec <= '1';	
			end if;
			pc_inc  <= '1';
			next_st <= go_ahead_1;                
		end if;
            when while_1_end =>
               -- DATA_ADDR <= ptr_reg;
                DATA_EN   <= '1';
                DATA_RDWR <= '0';
                next_st   <= while_2_end;
            when while_2_end =>
                if (DATA_RDATA = "00000000") then
                    pc_inc  <= '1';
		    next_st <= fetch;
                else
                    cnt_inc <= '1';
                    pc_dec  <= '1';
                    next_st <= go_back_1;
                end if;
            when go_back_1 =>
               -- DATA_ADDR <= pc_reg;
                DATA_EN   <= '1';
                DATA_RDWR <= '0';
                next_st   <= go_back_2;
            when go_back_2 =>
		if cnt_reg = "00000000" then 
			next_st <= fetch;	
		else
			if (DATA_RDATA = x"5d") then--]
                 		cnt_inc <= '1';
                    	elsif (DATA_RDATA = x"5b") then -- [
               		    	     	cnt_dec <= '1';
                    	end if;
               	         next_st <= go_back_3;
            	    end if;
		when go_back_3 => 
			if cnt_reg = "00000000" then 
				pc_inc <= '1';
			else 
				pc_dec <= '1';
			end if;		
			next_st <= go_back_1; 	
	    when comment =>
				pc_inc <= '1';
				next_st <= fetch;
			when EOF  =>
				next_st <= EOF;
			when others =>
				pc_dec  <= '0';
				pc_inc  <= '1';
				next_st <= fetch;
		end case;

	end process; -- next_st_logic
end behavioral;
