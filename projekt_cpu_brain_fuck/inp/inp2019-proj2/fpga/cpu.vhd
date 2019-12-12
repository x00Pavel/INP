-- cpu.vhd: Simple 8-bit CPU (BrainF*ck interpreter)
-- Copyright (C) 2019 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): DOPLNIT
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
   CLK   : in std_logic;  -- hodinovy signal
   RESET : in std_logic;  -- asynchronni reset procesoru
   EN    : in std_logic;  -- povoleni cinnosti procesoru
 
   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(12 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_RDWR  : out std_logic;                    -- cteni (0) / zapis (1)
   DATA_EN    : out std_logic;                    -- povoleni cinnosti
   
   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna
   IN_REQ    : out std_logic;                     -- pozadavek na vstup data
   
   -- vystupni port
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
   OUT_WE   : out std_logic                       -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'
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
	signal pc_reg: std_logic_vector(12 downto 0) -- Program Counter
	signal pc_inc: std_logic; -- incrementation
	signal pc_dec: std_logic; -- decrementation


	-- Addres pointer	
	signal ptr_reg: std_logic_vector(12 downto 0); -- counter of memory pointer
	signal ptr_inc: std_logic; -- incrementation
	signal ptr_dec: std_logic; -- decrementation
	
	-- CNT for while loop
	signal cnt_reg: std_logic_vector(7 downto 0);
	signal cnt_inc: std_logic;
	signal cnt_dec: std_logic;
	
	type fsm_state is (
		begin_st,
		fetch,
		decode, 
		ptrInc, -- increment pointer 
		ptrDec,-- decrement pointers
		valInc1, valInc2, valInc3, -- for +
		valDec1, valDec2, valDec3, -- for -
		while1, while2, while3, while_en,   -- for [
                while1_end, while2_end, while3_end, -- fro ]
		
		printR,
		print,scan,
		scanR,
		Eof,
		comment);
	

	signal present_st : fsm_state := begin_st; -- default state
	signal next_st : fsm_state; -- 
	-- Vectro for choosing value to write in data.
	-- 00 -> write from stdin
	-- 01 -> increment value of pointer and write its value
	-- 10 -> decrement value of pointer and write its value
	signal mx_data_sel : std_logic_vector(1 downto 0) := "00";
begin

 -- zde dopiste vlastni VHDL kod


 -- pri tvorbe kodu reflektujte rady ze cviceni INP, zejmena mejte na pameti, ze 
 --   - nelze z vice procesu ovladat stejny signal,
 --   - je vhodne mit jeden proces pro popis jedne hardwarove komponenty, protoze pak
 --   - u synchronnich komponent obsahuje sensitivity list pouze CLK a RESET a 
 --   - u kombinacnich komponent obsahuje sensitivity list vsechny ctene signaly.

	-- Programovy citac pro instrukci 
	process program_cnt(CLK, RESET, pc_inc, pc_dec) 
	begin 
		if RESET = '1' then
			pc_reg <= (others => '0');
		elsif rising_edge(CLK) then
			if pc_inc = '1' then
				pc_reg <= pc_reg + 1;
			elsif pc_dev = '1' then
				pc_reg <= pc_reg - 1;
			end if;
		end if;
	end process;
	
 	DATA_ADDR <= pc_reg;

	-- Ukazatel do pamet dat
	process mem_ptr(CLK, RESET, ptr_inc, ptr_dec)
	begin
		if RESET = '1' then 
			ptr_reg <= x"1000"
		elsif rising_edge(CLK) then
			if ptr_inc = '1' then 
				if ptr_reg = x"1FFF" then 
					ptr_reg <= x"1000";
				else
					ptr_reg <= ptr_reg + 1;
				end if;
			elsif ptr_dec = '1' then 
				if ptr_reg = x"1000" then 
					ptr_reg <= x"1FFF";
				else 				
					ptr_reg <= ptr_reg - 1;
				end if;
			end if;		 
	end process

	-- MX1 pro rozliseni pameti dat a programu 
--	process mx_prog_or_data()
--	begin
		
--	end process
	-- MX2 pro vyber pameti dat 
	process mx_data_addr(CLK, RESET, mx_data_sel)
	begin
		if RESET = '1' then 
			mx_wdata <= (others => '0');
		elsif rising_edge(CLK) then 
			case mx_data_sel is -- mx_data_wdata_sel
				when "00" => 
					mx_wdata <= IN_DATA; -- write value from stdin
				when "01" =>
					mx_wdata <= DATA_RDATA + 1; -- write value to incremented pointer
				when "10" =>
					mx_wdata <= DATA_RDATA + 1; -- write value to decremented pointer
			end case;		
		end if;
	end process;

	DATA_WDATA <= mx_wdata;

	-- for WHILE loop
	process cnt_cntr (CLK, RESET, cnt_inc, cnt_dec)
	begin
		if RESET = '1' then
			cnt_reg <= (others => '0');
		elsif rising_edge(CLK) then
			if cnt_inc = '1' then
				cnt_reg <= cnt_reg + 1;
			elsif cnt_dec = '1' then
				cnt_reg <= cnt_reg - 1;
			end if;
		end if;
	end process;
	-- MX3 pro rizeni zapisove hodnoty 
	OUT_DATA <= DATA_RDATA;
	-- FSM 
	process present_state (RESET, CLK)
	begin
		if (RESET='1') then
			present_st <= begin_st;
		elsif rising_edge(CLK) then
			if (CE = '1') then
				present_st <= next_st;
			end if;
		end if;
	end process;

	

end behavioral;
 
