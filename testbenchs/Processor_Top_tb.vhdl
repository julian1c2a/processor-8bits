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
        -- TEST: Unary Ops (INC, DEC, NOT, NEG)
        -- 1. INC A: 0xFE -> 0xFF.      Store at 0x0100
        -- 2. INC A: 0xFF -> 0x00.      Store at 0x0101
        -- 3. DEC A: 0x01 -> 0x00.      Store at 0x0102
        -- 4. DEC A: 0x00 -> 0xFF.      Store at 0x0103
        -- 5. NOT A: 0xAA -> 0x55.      Store at 0x0104
        -- 6. NEG A: 0x01 -> 0xFF (-1). Store at 0x0105
        
        -- 0x0000: LD A, #0xFE
        16#0000# => x"11", 16#0001# => x"FE",
        -- 0x0002: INC A (0xC2) -> 0xFF
        16#0002# => x"C2",
        -- 0x0003: ST A, [0x0100]
        16#0003# => x"31", 16#0004# => x"00", 16#0005# => x"01",

        -- 0x0006: INC A (0xC2) -> 0x00
        16#0006# => x"C2",
        -- 0x0007: ST A, [0x0101]
        16#0007# => x"31", 16#0008# => x"01", 16#0009# => x"01",

        -- 0x000A: LD A, #0x01
        16#000A# => x"11", 16#000B# => x"01",
        -- 0x000C: DEC A (0xC3) -> 0x00
        16#000C# => x"C3",
        -- 0x000D: ST A, [0x0102]
        16#000D# => x"31", 16#000E# => x"02", 16#000F# => x"01",

        -- 0x0010: DEC A (0xC3) -> 0xFF
        16#0010# => x"C3",
        -- 0x0011: ST A, [0x0103]
        16#0011# => x"31", 16#0012# => x"03", 16#0013# => x"01",

        -- 0x0014: LD A, #0xAA
        16#0014# => x"11", 16#0015# => x"AA",
        -- 0x0016: NOT A (0xC0) -> 0x55
        16#0016# => x"C0",
        -- 0x0017: ST A, [0x0104]
        16#0017# => x"31", 16#0018# => x"04", 16#0019# => x"01",

        -- 0x001A: LD A, #0x01
        16#001A# => x"11", 16#001B# => x"01",
        -- 0x001C: NEG A (0xC1) -> 0xFF
        16#001C# => x"C1",
        -- 0x001D: ST A, [0x0105]
        16#001D# => x"31", 16#001E# => x"05", 16#001F# => x"01",
        
        -- 0x0020: HALT
        16#0020# => x"01",
        
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
        report "=== INICIO SIMULACION PROCESADOR (Test ADD16/SUB16) ===";
        
        -- Reset del sistema
        reset <= '1';
        wait for clk_period * 5;
        reset <= '0';
        report "--- Reset liberado, iniciando programa ---";

        -- Esperar un tiempo suficiente para que el programa se ejecute y se detenga en un HALT.
        wait for clk_period * 60;

        report "--- Verificación ---";
        -- Al final, PC debe estar en 0x0016 (HALT en 0x0015 + 1)
        assert MemAddress = x"0016"
            report "FAIL: El PC final no es correcto. Esperado 0x0016, obtenido: 0x" & to_hstring(MemAddress)
            severity error;
            
        -- 1. ADD16: 0x00FF + 1 = 0x0100
        assert RAM(16#0100#) = x"01"
            report "FAIL: ADD16 High incorrecto. Esperado 0x01, Leído: 0x" & to_hstring(RAM(16#0100#))
            severity error;
        assert RAM(16#0101#) = x"00"
            report "FAIL: ADD16 Low incorrecto. Esperado 0x00, Leído: 0x" & to_hstring(RAM(16#0101#))
            severity error;

        -- 2. SUB16: 0x0100 - 1 = 0x00FF
        assert RAM(16#0102#) = x"00"
            report "FAIL: SUB16 High incorrecto. Esperado 0x00, Leído: 0x" & to_hstring(RAM(16#0102#))
            severity error;
        assert RAM(16#0103#) = x"FF"
            report "FAIL: SUB16 Low incorrecto. Esperado 0xFF, Leído: 0x" & to_hstring(RAM(16#0103#))
            severity error;

        if (MemAddress = x"0016") and (RAM(16#0100#) = x"01") and (RAM(16#0103#) = x"FF") then
            report "PASS: Instrucciones ADD16/SUB16 verificadas correctamente.";
        end if;

        report "=== FIN DE SIMULACION ===";
        std.env.stop; -- Detener la simulación en GHDL
    end process;

end architecture unique;