--------------------------------------------------------------------------------
-- Copyright (c) 2026 MICROELECTRÓNICA26.UMA.EII
-- MIT License
--------------------------------------------------------------------------------
-- Entidad: Processor_Top_tb
-- Descripción:
--   Testbench de integración del procesador completo.
--   Simula una memoria RAM asíncrona conectada al bus del procesador.
--   Carga un programa de prueba que verifica saltos condicionales.
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.CONSTANTS_pkg.ALL;
use work.ALU_pkg.ALL;
-- Instanciación directa de la entidad, no se necesita el componente del paquete
-- use work.Processor_Top; 

entity Processor_Top_tb is
end entity Processor_Top_tb;

architecture unique of Processor_Top_tb is

    -- Señales del procesador
    signal clk         : std_logic := '0';
    signal reset       : std_logic := '0';
    signal MemAddress  : address_vector;
    signal MemData_In  : data_vector;
    signal MemData_Out : data_vector;
    signal Mem_WE      : std_logic;
    signal Mem_RE      : std_logic;
    signal IO_WE       : std_logic;
    signal IO_RE       : std_logic;

    -- Memoria RAM simulada (64 KB)
    type ram_type is array (0 to 2**ADDRESS_WIDTH - 1) of data_vector;
    
    -- Inicialización de la memoria con un PROGRAMA DE PRUEBA
    signal RAM : ram_type := (
        -- TEST: CALL y RET
        -- Flujo esperado: 0x0000 -> 0x0002 (CALL) -> 0x0010 (Sub) -> 0x0012 (RET) -> 0x0005 -> 0x0007 (HALT)
        
        -- 0x0000: LD A, #0x10      (A = 16)
        16#0000# => x"11", 16#0001# => x"10",
        
        -- 0x0002: CALL 0x0010      (Llamada a subrutina, guarda ret=0x0005 en stack)
        16#0002# => x"75", 16#0003# => x"10", 16#0004# => x"00",
        
        -- 0x0005: ADD A, #0x02     (A += 2. Si A era 17, ahora 19)
        16#0005# => x"A0", 16#0006# => x"02",
        
        -- 0x0007: HALT             (Fin del programa)
        16#0007# => x"01",
        
        -- --- SUBRUTINA en 0x0010 ---
        -- 0x0010: ADD A, #0x01     (A += 1)
        16#0010# => x"A0", 16#0011# => x"01",

        -- 0x0012: RET              (Retorna a 0x0005)
        16#0012# => x"77",
        
        others => x"00" -- Resto a 0 (NOP)
    );

    constant clk_period : time := 10 ns;

begin

    -- Instancia del Procesador
    uut: entity work.Processor_Top(Structural)
        Port map (
            clk         => clk,
            reset       => reset,
            MemAddress  => MemAddress,
            MemData_In  => MemData_In,
            MemData_Out => MemData_Out,
            Mem_WE      => Mem_WE,
            Mem_RE      => Mem_RE,
            IO_WE       => IO_WE,
            IO_RE       => IO_RE
        );

    -- Generación de Reloj
    clk_process: process
    begin
        clk <= '0';
        wait for clk_period/2;
        clk <= '1';
        wait for clk_period/2;
    end process;

    -- Modelo de Memoria Asíncrona (Simplificado)
    mem_proc: process(MemAddress, Mem_RE, Mem_WE, MemData_Out)
        variable addr_int : integer;
    begin
        addr_int := to_integer(unsigned(MemAddress));
        
        -- Lectura
        if Mem_RE = '1' then
            MemData_In <= RAM(addr_int);
        else
            MemData_In <= (others => 'Z'); -- Alta impedancia si no lee
        end if;

        -- Escritura (Síncrona o Asíncrona según modelo, aquí asíncrona para simplificar TB)
        if Mem_WE = '1' then
            RAM(addr_int) <= MemData_Out;
        end if;
    end process;

    -- Proceso de Estímulo
    stim_proc: process
    begin
        report "=== INICIO SIMULACION PROCESADOR (Test CALL/RET) ===";
        
        -- Reset del sistema
        reset <= '1';
        wait for clk_period * 5;
        reset <= '0';
        report "--- Reset liberado, iniciando programa ---";

        -- Esperar un tiempo suficiente para que el programa se ejecute y se detenga en un HALT.
        wait for clk_period * 50;

        report "--- Verificación ---";
        -- Al final de la simulación, el PC debe estar en 0x0008, en un bucle HALT.
        -- (La instrucción HALT está en 0x0007, tras decodificarla PC avanza a 0x0008)
        assert MemAddress = x"0008"
            report "FAIL: El PC final no es correcto. Esperado 0x0008 (HALT tras retorno), obtenido: 0x" & to_hstring(MemAddress)
            severity error;
            
        -- Verificación del Stack:
        -- CALL guarda la dirección de retorno (0x0005) en el stack.
        -- Stack empieza en 0xFFFE.
        -- PUSH Low (0x05) en 0xFFFC.
        -- PUSH High (0x00) en 0xFFFD.
        -- (AddressPath decrementa SP primero, luego escribe. SP final en subrutina es 0xFFFC).
        
        assert RAM(16#FFFC#) = x"05"
            report "FAIL: Stack Low Byte incorrecto. Esperado 0x05, Leído: 0x" & to_hstring(RAM(16#FFFC#))
            severity error;

        assert RAM(16#FFFD#) = x"00"
            report "FAIL: Stack High Byte incorrecto. Esperado 0x00, Leído: 0x" & to_hstring(RAM(16#FFFD#))
            severity error;

        if (MemAddress = x"0008") and (RAM(16#FFFC#) = x"05") then
            report "PASS: Ciclo CALL/RET verificado exitosamente.";
        end if;

        report "=== FIN DE SIMULACION ===";
        std.env.stop; -- Detener la simulación en GHDL
    end process;
            severity note;

        report "=== FIN DE SIMULACION ===";
        std.env.stop; -- Detener la simulación en GHDL
    end process;

end architecture Behavioral;