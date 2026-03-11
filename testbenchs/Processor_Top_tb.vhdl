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
        -- TEST: ST A, [nn] y LD A, [nn]
        -- 1. Carga A con 0xAA
        -- 2. Guarda A en la dirección 0x0100
        -- 3. Carga A con 0x00 para borrarlo
        -- 4. Carga A desde la dirección 0x0100
        -- 5. HALT. Al final, A debe ser 0xAA, y M[0x0100] debe ser 0xAA.
        
        -- 0x0000: LD A, #0xAA
        16#0000# => x"11", 16#0001# => x"AA",
        
        -- 0x0002: ST A, [0x0100]
        16#0002# => x"31", 16#0003# => x"00", 16#0004# => x"01",
        
        -- 0x0005: LD A, #0x00
        16#0005# => x"11", 16#0006# => x"00",
        
        -- 0x0007: LD A, [0x0100]
        16#0007# => x"13", 16#0008# => x"00", 16#0009# => x"01",

        -- 0x000A: HALT
        16#000A# => x"01",
        
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
        report "=== INICIO SIMULACION PROCESADOR (Test ST/LD) ===";
        
        -- Reset del sistema
        reset <= '1';
        wait for clk_period * 5;
        reset <= '0';
        report "--- Reset liberado, iniciando programa ---";

        -- Esperar un tiempo suficiente para que el programa se ejecute y se detenga en un HALT.
        wait for clk_period * 50;

        report "--- Verificación ---";
        -- Al final de la simulación, el PC debe estar en 0x000B, en un bucle HALT.
        -- (La instrucción HALT está en 0x000A, tras decodificarla PC avanza a 0x000B)
        assert MemAddress = x"000B"
            report "FAIL: El PC final no es correcto. Esperado 0x000B, obtenido: 0x" & to_hstring(MemAddress)
            severity error;
            
        -- Verificación de la escritura en memoria
        assert RAM(16#0100#) = x"AA"
            report "FAIL: La instrucción ST A, [0x0100] no escribió el valor correcto. Esperado 0xAA, Leído: 0x" & to_hstring(RAM(16#0100#))
            severity error;

        if (MemAddress = x"000B") and (RAM(16#0100#) = x"AA") then
            report "PASS: Ciclo ST/LD verificado exitosamente.";
        end if;

        report "=== FIN DE SIMULACION ===";
        std.env.stop; -- Detener la simulación en GHDL
    end process;
            severity note;

        report "=== FIN DE SIMULACION ===";
        std.env.stop; -- Detener la simulación en GHDL
    end process;

end architecture Behavioral;