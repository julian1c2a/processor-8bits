library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.STD_LOGIC_TEXTIO.ALL;
use STD.TEXTIO.ALL;

-- Entidad del testbench (es una entidad vacía)
entity ALU_tb is
end entity ALU_tb;

architecture unique of ALU_tb is

    -- 1. Declarar el componente que vamos a probar (nuestra ALU)
    component ALU is
        Port (
            RegInA    : in  STD_LOGIC_VECTOR(7 downto 0);
            RegInB    : in  STD_LOGIC_VECTOR(7 downto 0);
            Oper      : in  STD_LOGIC_VECTOR(4 downto 0);
            Carry_in  : in  STD_LOGIC := '0';
            RegOutACC : out STD_LOGIC_VECTOR(7 downto 0);
            RegStatus : out STD_LOGIC_VECTOR(7 downto 0)
        );
    end component ALU;

    -- 2. Señales para conectar a los puertos del componente
    signal s_RegInA    : STD_LOGIC_VECTOR(7 downto 0) := (others => '0');
    signal s_RegInB    : STD_LOGIC_VECTOR(7 downto 0) := (others => '0');
    signal s_Oper      : STD_LOGIC_VECTOR(4 downto 0) := (others => '0');
    signal s_Carry_in  : STD_LOGIC := '0';
    signal s_RegOutACC : STD_LOGIC_VECTOR(7 downto 0);
    signal s_RegStatus : STD_LOGIC_VECTOR(7 downto 0);

    -- Constante para el ciclo de reloj (aunque la ALU es combinacional, es buena práctica)
    constant clk_period : time := 10 ns;

begin

    -- 3. Instanciar el componente a probar (DUT: Device Under Test)
    uut: ALU Port map (
        RegInA    => s_RegInA,
        RegInB    => s_RegInB,
        Oper      => s_Oper,
        Carry_in  => s_Carry_in,
        RegOutACC => s_RegOutACC,
        RegStatus => s_RegStatus
    );

    -- 4. Proceso de estímulo: aquí definimos los casos de prueba
    stim_proc: process
        -- La procedure ahora usa to_hstring para evitar la ambigüedad con 'write'.
        procedure print_results(case_name : in string) is
        begin
            report case_name &
                "  A: 0x" & to_hstring(s_RegInA) &
                " | B: 0x" & to_hstring(s_RegInB) &
                " => ACC: 0x" & to_hstring(s_RegOutACC) &
                " | Flags(CHVZGELR): " & to_hstring(s_RegStatus);
        end procedure;
    begin
        report "-------------------- INICIO SIMULACION ALU --------------------";

        -- Caso 1: ADD simple (5 + 10 = 15)
        s_RegInA <= std_logic_vector(to_signed(5, 8));
        s_RegInB <= std_logic_vector(to_signed(10, 8));
        s_Oper   <= b"00001";
        wait for clk_period;
        print_results("CASO 1: ADD | 5 + 10");

        -- Caso 2: ADD con Half-Carry (15 + 1 = 16)
        s_RegInA <= x"0F"; -- 15
        s_RegInB <= x"01"; -- 1
        s_Oper   <= b"00001";
        wait for clk_period;
        print_results("CASO 2: ADD con Half-Carry | 15 + 1");

        -- Caso 3: ADD con Carry (255 + 1 = 0, con Carry)
        s_RegInA <= x"FF"; -- 255
        s_RegInB <= x"01"; -- 1
        s_Oper   <= b"00001";
        wait for clk_period;
        print_results("CASO 3: ADD con Carry | 255 + 1");

        -- Caso 4: ADD con Overflow (127 + 1 = -128)
        s_RegInA <= std_logic_vector(to_signed(127, 8)); -- 0x7F
        s_RegInB <= std_logic_vector(to_signed(1, 8));   -- 0x01
        s_Oper   <= b"00001";
        wait for clk_period;
        print_results("CASO 4: ADD con Overflow | 127 + 1");
        
        -- Caso 5: SUB simple (10 - 5 = 5)
        s_RegInA <= std_logic_vector(to_signed(10, 8));
        s_RegInB <= std_logic_vector(to_signed(5, 8));
        s_Oper   <= b"00011";
        wait for clk_period;
        print_results("CASO 5: SUB | 10 - 5");

        -- Caso 6: SUB con resultado cero (10 - 10 = 0)
        s_RegInA <= std_logic_vector(to_signed(10, 8));
        s_RegInB <= std_logic_vector(to_signed(10, 8));
        s_Oper   <= b"00011";
        wait for clk_period;
        print_results("CASO 6: SUB con Flag Zero | 10 - 10");

        -- Caso 7: SUB con Borrow (5 - 10 = -5)
        s_RegInA <= std_logic_vector(to_signed(5, 8));
        s_RegInB <= std_logic_vector(to_signed(10, 8));
        s_Oper   <= b"00011";
        wait for clk_period;
        print_results("CASO 7: SUB con Borrow | 5 - 10");

        report "-------------------- FIN SIMULACION --------------------";
        wait; -- Detener la simulación
    end process;

end architecture;
