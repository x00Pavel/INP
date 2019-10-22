-- Autor reseni: PAVEL ZADLOUSKI xyadlo00
 -- Sem doplnte definice vnitrnich signalu
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_arith.all;
use IEEE.std_logic_unsigned.all;

entity ledc8x8 is
	port (
		SMCLK : in std_logic; 
		RESET : in std_logic;
		ROW : out std_logic_vector(0 to 7);
		LED : out std_logic_vector(0 to 7)
	);
end ledc8x8;
--------------------------------------------------------------


-------------------------- Architektury ----------------------
architecture main of ledc8x8 is
	signal ce : std_logic := '0';
	-- representing of state to enable or not  
	signal state : std_logic_vector (0 to 1) := "00";
	-- timer for counting half of seconf 
	signal timer : std_logic_vector(22 downto 0) := (others => '0');
	-- set to the first row
	signal row_act : std_logic_vector(0 to 7) := "10000000";
	-- for vector 1111 1111 every LED is turn off
	signal led_act: std_logic_vector(0 to 7) := (others => '1');
begin
	
	
	-- generation of signal ce 
	counter : process (SMCLK, RESET) begin 
		if RESET = '1' then 
			timer <=  (others => '0');
		elsif SMCLK'event and SMCLK = '1' then
			timer <= timer + 1;
		end if;
	end process counter; 
	-- set active signal
	ce <= '1' when timer(7 downto 0) = X"FF" else '0';

	set_state : process (timer, state, ce) begin
		if timer(21 downto 14) = "11100001" and state = "00" and ce = '1' then 	
			state <= "11";
		elsif timer(22 downto 15) = "11100001" then  
			state <= "01";
		end if;
	end process set_state;

	-- generation of signal with vector to be displayed 
	led_activate : process(row_act, state) begin 
			if state = "00" or state = "01" then 
				case row_act is 
					when "10000000" => led_act <= "00011111";
					when "01000000" => led_act <= "01101111"; 
					when "00100000" => led_act <= "00010101"; 
					when "00010000" => led_act <= "01110101";
					when "00001000" => led_act <= "01110101";
					when "00000100" => led_act <= "11111011";
					when "00000010" => led_act <= "11111011";
					when "00000001" => led_act <= "11111011";
					when   others   => led_act <= (others => '1');	
				end case;
			else 
				case row_act is 
					when others => led_act <= (others => '1');
				end case;
			end if;	
	end process led_activate;
	-- set active signal
	LED <= led_act;
	
	-- generation number of addres to be used
	row_activate : process(SMCLK, RESET, ce) begin 
		if RESET = '1' then 
			row_act <= "10000000";
		elsif rising_edge(SMCLK) then
			if ce = '1' then 
				row_act <= row_act(7) & row_act(0 to 6); 							  
			end if;
		end if;
	end process row_activate;
	-- set active signal	
	ROW <= row_act;

end main;

-- ISID: 75579
