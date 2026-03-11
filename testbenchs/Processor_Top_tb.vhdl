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
        -- TEST: Rotación y Desplazamiento (Shift/Rotate)
        -- 1. LSL:  0x01 -> 0x02.  Guardar en 0x0100.
        -- 2. LSR:  0x80 -> 0x40.  Guardar en 0x0101.
        -- 3. ASR:  0x80 -> 0xC0.  Guardar en 0x0102.
        -- 4. ROL:  0x80 -> 0x01.  Guardar en 0x0103.
        -- 5. ROR:  0x01 -> 0x80.  Guardar en 0x0104.
        
        -- 0x0000: LD A, #0x01
        16#0000# => x"11", 16#0001# => x"01",
        -- 0x0002: LSL A (0xC8)
        16#0002# => x"C8",
        -- 0x0003: ST A, [0x0100]
        16#0003# => x"31", 16#0004# => x"00", 16#0005# => x"01",

        -- 0x0006: LD A, #0x80
        16#0006# => x"11", 16#0007# => x"80",
        -- 0x0008: LSR A (0xC9)
        16#0008# => x"C9",
        -- 0x0009: ST A, [0x0101]
        16#0009# => x"31", 16#000A# => x"01", 16#000B# => x"01",

        -- 0x000C: LD A, #0x80
        16#000C# => x"11", 16#000D# => x"80",
        -- 0x000E: ASR A (0xCB)
        16#000E# => x"CB",
        -- 0x000F: ST A, [0x0102]
        16#000F# => x"31", 16#0010# => x"02", 16#0011# => x"01",

        -- 0x0012: LD A, #0x80
        16#0012# => x"11", 16#0013# => x"80",
        -- 0x0014: ROL A (0xCC)
        16#0014# => x"CC",
        -- 0x0015: ST A, [0x0103]
        16#0015# => x"31", 16#0016# => x"03", 16#0017# => x"01",

        -- 0x0018: LD A, #0x01
        16#0018# => x"11", 16#0019# => x"01",
        -- 0x001A: ROR A (0xCD)
        16#001A# => x"CD",
        -- 0x001B: ST A, [0x0104]
        16#001B# => x"31", 16#001C# => x"04", 16#001D# => x"01",

        -- 0x001E: HALT
        16#001E# => x"01",
        
        
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
        report "=== INICIO SIMULACION PROCESADOR (Test Rotacion/Desplazamiento) ===";
        
        -- Reset del sistema
        reset <= '1';
        wait for clk_period * 5;
        reset <= '0';
        report "--- Reset liberado, iniciando programa ---";

        -- Esperar un tiempo suficiente para que el programa se ejecute y se detenga en un HALT.
        wait for clk_period * 50;

        report "--- Verificación ---";
        -- Al final, PC debe estar en 0x001F (HALT en 0x001E + 1)
        assert MemAddress = x"001F"
            report "FAIL: El PC final no es correcto. Esperado 0x001F, obtenido: 0x" & to_hstring(MemAddress)
            severity error;
            
        -- LSL: 0x01 << 1 = 0x02
        assert RAM(16#0100#) = x"02"
            report "FAIL: LSL incorrecto. Esperado 0x02, Leído: 0x" & to_hstring(RAM(16#0100#))
            severity error;

        -- LSR: 0x80 >> 1 = 0x40
        assert RAM(16#0101#) = x"40"
            report "FAIL: LSR incorrecto. Esperado 0x40, Leído: 0x" & to_hstring(RAM(16#0101#))
            severity error;

        -- ASR: 0x80 (signed -128) >> 1 = 0xC0 (signed -64)
        assert RAM(16#0102#) = x"C0"
            report "FAIL: ASR incorrecto. Esperado 0xC0, Leído: 0x" & to_hstring(RAM(16#0102#))
            severity error;

        -- ROL: 0x80 rot 1 = 0x01
        assert RAM(16#0103#) = x"01"
            report "FAIL: ROL incorrecto. Esperado 0x01, Leído: 0x" & to_hstring(RAM(16#0103#))
            severity error;

        -- ROR: 0x01 rot 1 = 0x80
        assert RAM(16#0104#) = x"80"
            report "FAIL: ROR incorrecto. Esperado 0x80, Leído: 0x" & to_hstring(RAM(16#0104#))
            severity error;

        if (MemAddress = x"001F") and (RAM(16#0100#) = x"02") and (RAM(16#0101#) = x"40") and (RAM(16#0102#) = x"C0") and (RAM(16#0103#) = x"01") and (RAM(16#0104#) = x"80") then
            report "PASS: Operaciones de Shift/Rotate verificadas.";
        end if;

        report "=== FIN DE SIMULACION ===";
        std.env.stop; -- Detener la simulación en GHDL
    end process;

end architecture unique;