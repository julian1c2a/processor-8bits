--------------------------------------------------------------------------------
-- File: ALU_tb.vhdl
-- Description:
--   Testbench manual de la ALU con verificación de resultados.
--   Comprueba 7 casos representativos de las operaciones ADD y SUB:
--     - ADD simple, ADD con Half-Carry, ADD con Carry, ADD con Overflow
--     - SUB simple, SUB con resultado cero, SUB con Borrow
--   Cada caso usa la procedure check_case para contrastar la salida del
--   acumulador y el registro de flags con los valores esperados.
--
--   Encoding del registro de status (8 bits, orden MSB→LSB):
--     bit 7 = C  (Carry / no-Borrow)
--     bit 6 = H  (Half-carry)
--     bit 5 = V  (oVerflow)
--     bit 4 = Z  (Zero)
--     bit 3 = G  (Greater, con signo)
--     bit 2 = E  (Equal)
--     bit 1 = L  (Less, con signo)
--     bit 0 = R  (reservado)
--
-- Usage:
--   ghdl -a --std=08 --workdir=build processor/Utils_pkg.vhdl \
--         processor/CONSTANTS_pkg.vhdl processor/ALU_pkg.vhdl \
--         processor/ALU_functions_pkg.vhdl processor/ALU.vhdl \
--         testbenchs/ALU_tb.vhdl
--   ghdl -e --std=08 --workdir=build ALU_tb
--   ghdl -r --std=08 --workdir=build ALU_tb
--
-- Dependencies: ALU_pkg, ALU.vhdl
--------------------------------------------------------------------------------
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
    for all : ALU_comp use entity work.ALU(unique);

    -- 2. Señales para conectar a los puertos del componente
    signal s_RegInA    : data_vector := (others => '0');
    signal s_RegInB    : data_vector := (others => '0');
    signal s_Oper      : opcode_vector := (others => '0');
    signal s_Carry_in  : STD_LOGIC := '0';
    signal s_RegOutACC : data_vector;
    signal s_RegStatus : status_vector;

    -- Constante para el ciclo de reloj
    constant clk_period : time := 10 ns;

begin

    -- 3. Instanciar el componente a probar (DUT: Device Under Test)
    uut: ALU_comp Port map (
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
            constant expected_acc   : in data_vector;
            constant expected_flags : in status_vector
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
        -- Resultado no supera los límites de 8 bits; ningún flag activo.
        s_RegInA <= std_logic_vector(to_signed(5, 8));
        s_RegInB <= std_logic_vector(to_signed(10, 8));
        s_Oper   <= OP_ADD;
        -- Flags esperados = 0x00: C=0, H=0, V=0, Z=0, G=0, E=0, L=0, R=0
        check_case("CASO 1: ADD | 5 + 10", x"0F", x"00");

        -- Caso 2: ADD con Half-Carry (15 + 1 = 16 = 0x10)
        -- Nibble bajo: 0xF + 0x1 genera carry hacia bit 4  → H=1.
        -- Con signo: 15 y 1 son positivos, resultado 16 > 0            → G=1.
        -- No hay carry global ni overflow.
        s_RegInA <= x"0F"; -- 15
        s_RegInB <= x"01"; -- 1
        s_Oper   <= OP_ADD;
        -- Flags esperados = 0x48: H=1 (bit 6), G=1 (bit 3)  →  0100_1000
        check_case("CASO 2: ADD con Half-Carry | 15 + 1", x"10", x"48");

        -- Caso 3: ADD con Carry (255 + 1 = 256, resultado = 0 en 8 bits)
        -- Carry global: suma desborda los 8 bits sin signo          → C=1.
        -- Half-carry:   0xF + 0x1 de los nibbles bajos              → H=1.
        -- Zero:         resultado truncado = 0x00                   → Z=1.
        s_RegInA <= x"FF"; -- 255 (o -1 en C2)
        s_RegInB <= x"01"; -- 1
        s_Oper   <= OP_ADD;
        -- Flags esperados = 0xD0: C=1 (bit 7), H=1 (bit 6), Z=1 (bit 4)  →  1101_0000
        check_case("CASO 3: ADD con Carry | 255 + 1", x"00", x"D0");

        -- Caso 4: ADD con Overflow (127 + 1 = 128 = -128 en C2)
        -- El resultado cambia de signo positivo a negativo           → V=1.
        -- Half-carry: 0xF + 0x1                                     → H=1.
        -- Con signo: el resultado como -128 es menor que los operandos → G=1
        --   (la ALU compara el resultado sin signo; G refleja "A > B" sin signo).
        s_RegInA <= "01111111"; -- 127
        s_RegInB <= "00000001"; -- 1
        s_Oper   <= OP_ADD;
        -- Flags esperados = 0x68: H=1 (bit 6), V=1 (bit 5), G=1 (bit 3)  →  0110_1000
        check_case("CASO 4: ADD con Overflow | 127 + 1", x"80", x"68");

        -- Caso 5: SUB simple (10 - 5 = 5)
        -- En SUB, C = no-Borrow (Carry activo significa que NO hubo borrow).
        -- C=1: 10 ≥ 5, no borrow                                    → C=1.
        -- H=1: nibble bajo 10 ≥ nibble bajo 5, no half-borrow       → H=1.
        -- G=1: con signo, 10 > 5                                    → G=1.
        s_RegInA <= std_logic_vector(to_signed(10, 8));
        s_RegInB <= std_logic_vector(to_signed(5, 8));
        s_Oper   <= OP_SUB;
        -- Flags esperados = 0xC8: C=1 (bit 7), H=1 (bit 6), G=1 (bit 3)  →  1100_1000
        check_case("CASO 5: SUB | 10 - 5", x"05", x"C8");

        -- Caso 6: SUB con resultado cero (10 - 10 = 0)
        -- C=1: no borrow (10 ≥ 10)                                  → C=1.
        -- H=1: no half-borrow                                       → H=1.
        -- Z=1: resultado = 0                                        → Z=1.
        -- E=1: los operandos son iguales (CMP semántica)            → E=1.
        s_RegInA <= std_logic_vector(to_signed(10, 8));
        s_RegInB <= std_logic_vector(to_signed(10, 8));
        s_Oper   <= OP_SUB;
        -- Flags esperados = 0xD4: C=1, H=1, Z=1, E=1  →  1101_0100
        check_case("CASO 6: SUB con Flag Zero | 10 - 10", x"00", x"D4");

        -- Caso 7: SUB con Borrow (5 - 10 = -5 = 0xFB en C2)
        -- C=0: 5 < 10, hay borrow -> C inactivo                     → C=0.
        -- H=0: nibble bajo 5 < nibble bajo 10, hay half-borrow      → H=0.
        -- Ningún otro flag se activa: resultado no es 0, no overflow con signo.
        s_RegInA <= std_logic_vector(to_signed(5, 8));
        s_RegInB <= std_logic_vector(to_signed(10, 8));
        s_Oper   <= OP_SUB;
        -- Flags esperados = 0x00: todos los flags inactivos  →  0000_0000
        check_case("CASO 7: SUB con Borrow | 5 - 10", x"FB", x"00");

        report "-------------------- FIN SIMULACION (todos los casos OK) --------------------";
        wait; -- Detener la simulación
    end process;

end architecture;
