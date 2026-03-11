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
    signal Mem_Ready   : std_logic := '0';
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

    -- Simulación de latencia de SRAM
    constant WAIT_STATES : integer := 4; -- 4 wait states + 1 ciclo acceso = 5 ciclos total

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
            Mem_Ready   => Mem_Ready,
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

    -- Modelo de Memoria con Wait States
    -- Simula una SRAM asíncrona que tarda N ciclos en responder.
    -- El controlador de memoria (simulado aquí) gestiona el handshake Mem_Ready.
    mem_proc: process(clk, reset)
        variable addr_int : integer;
        variable wait_cnt : integer := 0;
    begin
        if reset = '1' then
            Mem_Ready <= '0';
            wait_cnt  := 0;
            MemData_In <= (others => 'Z');
        elsif rising_edge(clk) then
            addr_int := to_integer(unsigned(MemAddress));
            
            -- Lógica de Wait States
            if (Mem_RE = '1' or Mem_WE = '1') then
                if wait_cnt < WAIT_STATES then
                    wait_cnt := wait_cnt + 1;
                    Mem_Ready <= '0';
                else
                    -- Memoria lista
                    Mem_Ready <= '1';
                    
                    -- Escritura síncrona al final del ciclo de espera
                    if Mem_WE = '1' then
                        RAM(addr_int) <= MemData_Out;
                    end if;
                end if;
            else
                -- Bus inactivo
                wait_cnt := 0;
                Mem_Ready <= '0';
            end if;
        end if;
    end process;

    -- Lectura de datos: Conectada al bus cuando RE y Ready están activos
    -- (o asumiendo que el dato es válido tras el tiempo de espera)
    MemData_In <= RAM(to_integer(unsigned(MemAddress))) when (Mem_RE = '1' and Mem_Ready = '1') else (others => 'Z');

    -- Proceso de Estímulo
    stim_proc: process
    begin
        report "=== INICIO SIMULACION PROCESADOR (Test Overflow Flag) ===";
        
        -- Reset del sistema
        reset <= '1';
        wait for clk_period * 5;
        reset <= '0';
        report "--- Reset liberado, iniciando programa ---";

        -- Esperar un tiempo suficiente para que el programa se ejecute y se detenga en un HALT.
        -- Al añadir wait states, cada instrucción tarda más. Aumentamos el tiempo de simulación.
        wait for clk_period * 200;

        report "--- Verificación ---";
        -- Al final, PC debe estar en 0x001F (HALT en 0x001E + 1)
        assert MemAddress = x"001F"
            report "FAIL: El PC final no es correcto. Esperado 0x001F, obtenido: 0x" & to_hstring(MemAddress)
            severity error;
            
        -- 1. Overflow Positivo: 0x7F + 0x01 = 0x80
        assert RAM(16#0100#) = x"80"
            report "FAIL: Suma overflow positivo incorrecta. Esperado 0x80, Leído: 0x" & to_hstring(RAM(16#0100#))
            severity error;

        -- 2. Overflow Negativo: 0x80 + 0xFF = 0x7F
        assert RAM(16#0101#) = x"7F"
            report "FAIL: Suma overflow negativo incorrecta. Esperado 0x7F, Leído: 0x" & to_hstring(RAM(16#0101#))
            severity error;

        -- 3. Sin Overflow: 0x01 + 0x01 = 0x02
        assert RAM(16#0102#) = x"02"
            report "FAIL: Suma sin overflow incorrecta. Esperado 0x02, Leído: 0x" & to_hstring(RAM(16#0102#))
            severity error;

        if (MemAddress = x"001F") and (RAM(16#0100#) = x"80") and (RAM(16#0101#) = x"7F") and (RAM(16#0102#) = x"02") then
            report "PASS: Flag de Overflow (V) verificado correctamente.";
        end if;

        report "=== FIN DE SIMULACION ===";
        std.env.stop; -- Detener la simulación en GHDL
    end process;

end architecture unique;