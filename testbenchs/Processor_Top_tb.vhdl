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
        -- TEST: Direccionamiento Indexado [nn+B]
        -- 1. Carga B con 0x05
        -- 2. Carga A desde [0x0200 + B] -> Lee de 0x0205 (Dato 0x55)
        -- 3. Guarda A en [0x0300 + B]   -> Escribe en 0x0305
        -- 4. HALT
        
        -- 0x0000: LD B, #0x05
        16#0000# => x"21", 16#0001# => x"05",
        
        -- 0x0002: LD A, [0x0200 + B] (Opcode 0x15)
        16#0002# => x"15", 16#0003# => x"00", 16#0004# => x"02",
        
        -- 0x0005: ST A, [0x0300 + B] (Opcode 0x33)
        16#0005# => x"33", 16#0006# => x"00", 16#0007# => x"03",
        
        -- 0x0008: HALT
        16#0008# => x"01",
        
        -- Datos iniciales
        16#0205# => x"55", 
        
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
        report "=== INICIO SIMULACION PROCESADOR (Test Indexado [nn+B]) ===";
        
        -- Reset del sistema
        reset <= '1';
        wait for clk_period * 5;
        reset <= '0';
        report "--- Reset liberado, iniciando programa ---";

        -- Esperar un tiempo suficiente para que el programa se ejecute y se detenga en un HALT.
        wait for clk_period * 50;

        report "--- Verificación ---";
        -- Al final de la simulación, el PC debe estar en 0x0009, en un bucle HALT.
        -- (La instrucción HALT está en 0x0008, tras decodificarla PC avanza a 0x0009)
        assert MemAddress = x"0009"
            report "FAIL: El PC final no es correcto. Esperado 0x0009, obtenido: 0x" & to_hstring(MemAddress)
            severity error;
            
        -- Verificación de la escritura en memoria en dirección indexada (0x0300 + 0x05 = 0x0305)
        assert RAM(16#0305#) = x"55"
            report "FAIL: Escritura indexada incorrecta en 0x0305. Esperado 0x55, Leído: 0x" & to_hstring(RAM(16#0305#))
            severity error;

        if (MemAddress = x"0009") and (RAM(16#0305#) = x"55") then
            report "PASS: Direccionamiento Indexado verificado exitosamente.";
        end if;

        report "=== FIN DE SIMULACION ===";
        std.env.stop; -- Detener la simulación en GHDL
    end process;
            severity note;

        report "=== FIN DE SIMULACION ===";
        std.env.stop; -- Detener la simulación en GHDL
    end process;

end architecture Behavioral;