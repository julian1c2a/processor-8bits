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

architecture Behavioral of Processor_Top_tb is

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
        -- Programa para probar BEQ
        -- 1. Carga A y B con el mismo valor (5)
        -- 2. Compara A y B (debe activar Z flag)
        -- 3. Salta si es igual (BEQ) a la etiqueta 'target'
        -- 4. Si el salto falla, cae en un HALT de error.
        -- 5. Si el salto funciona, cae en un HALT de éxito en 'target'.
        
        -- Dir 0x0000: LD A, #5
        16#0000# => x"11", 16#0001# => x"05",
        
        -- Dir 0x0002: LD B, #5
        16#0002# => x"21", 16#0003# => x"05",
        
        -- Dir 0x0004: CMP A, B  (A=5, B=5 -> Z flag se pone a 1)
        16#0004# => x"97",
        
        -- Dir 0x0005: BEQ +1 (Branch if Equal. PC estará en 0x0007. 0x0007 + 1 = 0x0008. El salto se toma)
        16#0005# => x"80", 16#0006# => x"01",
        
        -- Dir 0x0007: HALT (Error: el salto no se tomó)
        16#0007# => x"01",
        
        -- target: (at 0x0008)
        -- Dir 0x0008: HALT (Éxito: el procesador se detiene aquí)
        16#0008# => x"01",
        
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
        report "=== INICIO SIMULACION PROCESADOR (Test de Salto Condicional) ===";
        
        -- Reset del sistema
        reset <= '1';
        wait for clk_period * 5;
        reset <= '0';
        report "--- Reset liberado, iniciando programa ---";

        -- Esperar un tiempo suficiente para que el programa se ejecute y se detenga en un HALT.
        wait for clk_period * 50;

        report "--- Verificación ---";
        -- Al final de la simulación, el PC debe estar en 0x0008, en un bucle HALT.
        -- Si está en 0x0007, el salto condicional falló.
        assert MemAddress = x"0008"
            report "FAIL: El salto condicional no se tomó o fue incorrecto. PC final: 0x" & to_hstring(MemAddress)
            severity error;
            
        report "PASS: El salto condicional BEQ se ejecutó correctamente. PC final en 0x0008."
            severity note;

        report "=== FIN DE SIMULACION ===";
        std.env.stop; -- Detener la simulación en GHDL
    end process;

end architecture Behavioral;