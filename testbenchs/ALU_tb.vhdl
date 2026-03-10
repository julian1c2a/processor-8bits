library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.STD_LOGIC_TEXTIO.ALL;
use STD.TEXTIO.ALL;
use work.ALU_pkg.ALL;

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

    -- Constante para el ciclo de reloj
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
        -- Procedure para verificar los resultados de un caso de prueba
        procedure check_case(
            constant case_name      : in string;
            constant expected_acc   : in STD_LOGIC_VECTOR(7 downto 0);
            constant expected_flags : in STD_LOGIC_VECTOR(7 downto 0)
        ) is
            variable acc_ok   : boolean;
            variable flags_ok : boolean;
        begin
            -- Espera un ciclo para que la salida se estabilice
            wait for clk_period;

            acc_ok   := s_RegOutACC = expected_acc;
            flags_ok := s_RegStatus = expected_flags;

            -- Verificar la salida del acumulador (ACC)
            assert acc_ok
                report "ERROR en " & case_name & ": ACC" &
                       " | Esperado: 0x" & to_hstring(expected_acc) &
                       " | Obtenido: 0x" & to_hstring(s_RegOutACC)
                severity error;

            -- Verificar los flags de estado
            assert flags_ok
                report "ERROR en " & case_name & ": Flags" &
                       " | Esperado: 0b" & to_bstring(expected_flags) &
                       " | Obtenido: 0b" & to_bstring(s_RegStatus)
                severity error;

            -- Si las aserciones pasan, reportar éxito
            if acc_ok and flags_ok then
                report "[OK] " & case_name &
                    " | A: 0x" & to_hstring(s_RegInA) &
                    " | B: 0x" & to_hstring(s_RegInB) &
                    " => ACC: 0x" & to_hstring(s_RegOutACC) &
                    " | Flags(CHVZGELR): " & to_bstring(s_RegStatus)
                    severity note;
            end if;
        end procedure;

    begin
        report "-------------------- INICIO SIMULACION ALU (con verificacion) --------------------";

        -- Caso 1: ADD simple (5 + 10 = 15)
        s_RegInA <= std_logic_vector(to_signed(5, 8));
        s_RegInB <= std_logic_vector(to_signed(10, 8));
        s_Oper   <= OP_ADD;
        -- Flags esperados: G=0, E=0 -> ...00
        check_case("CASO 1: ADD | 5 + 10", x"0F", x"00");

        -- Caso 2: ADD con Half-Carry (15 + 1 = 16)
        s_RegInA <= x"0F"; -- 15
        s_RegInB <= x"01"; -- 1
        s_Oper   <= OP_ADD;
        -- Flags esperados: H=1, G=1, E=0 -> .1.10.
        check_case("CASO 2: ADD con Half-Carry | 15 + 1", x"10", x"48");

        -- Caso 3: ADD con Carry (255 + 1 = 0, con Carry)
        s_RegInA <= x"FF"; -- 255 (o -1 en C2)
        s_RegInB <= x"01"; -- 1
        s_Oper   <= OP_ADD;
        -- Flags esperados: C=1, H=1, Z=1 -> 11.1....
        check_case("CASO 3: ADD con Carry | 255 + 1", x"00", x"D0");

        -- Caso 4: ADD con Overflow (127 + 1 = -128)
        s_RegInA <= "01111111"; -- 127
        s_RegInB <= "00000001"; -- 1
        s_Oper   <= OP_ADD;
        -- Flags esperados: H=1, V=1, G=1 -> .11.1...
        check_case("CASO 4: ADD con Overflow | 127 + 1", x"80", x"68");

        -- Caso 5: SUB simple (10 - 5 = 5)
        s_RegInA <= std_logic_vector(to_signed(10, 8));
        s_RegInB <= std_logic_vector(to_signed(5, 8));
        s_Oper   <= OP_SUB;
        -- Flags esperados: C=1 (no borrow), H=1 (no borrow), G=1 -> 11..1...
        check_case("CASO 5: SUB | 10 - 5", x"05", x"C8");

        -- Caso 6: SUB con resultado cero (10 - 10 = 0)
        s_RegInA <= std_logic_vector(to_signed(10, 8));
        s_RegInB <= std_logic_vector(to_signed(10, 8));
        s_Oper   <= OP_SUB;
        -- Flags esperados: C=1, H=1, Z=1, E=1 -> 11.1.1..
        check_case("CASO 6: SUB con Flag Zero | 10 - 10", x"00", x"D4");

        -- Caso 7: SUB con Borrow (5 - 10 = -5)
        s_RegInA <= std_logic_vector(to_signed(5, 8));
        s_RegInB <= std_logic_vector(to_signed(10, 8));
        s_Oper   <= OP_SUB;
        -- Flags esperados: C=0 (borrow), H=0 (borrow) -> 00.....
        check_case("CASO 7: SUB con Borrow | 5 - 10", x"FB", x"00");

        report "-------------------- FIN SIMULACION (todos los casos OK) --------------------";
        wait; -- Detener la simulación
    end process;

end architecture;
