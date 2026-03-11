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
        -- TEST: Página Cero [n] e Indirecto [B]
        -- 1. LD A, [0x10]      ; Carga 0xAA desde dir 0x0010 (Pág Cero)
        -- 2. ST A, [0x20]      ; Guarda 0xAA en dir 0x0020 (Pág Cero)
        -- 3. LD B, #0x20       ; B = 0x20
        -- 4. LD A, [B]         ; Carga desde [0x00:B] = 0x0020 -> A = 0xAA
        -- 5. INC A             ; A = 0xAB
        -- 6. LD B, #0x30       ; B = 0x30
        -- 7. ST A, [B]         ; Guarda 0xAB en [0x0030]
        -- 8. HALT
        
        -- 0x0000: LD A, [0x10]
        16#0000# => x"12", 16#0001# => x"10",
        
        -- 0x0002: ST A, [0x20]
        16#0002# => x"30", 16#0003# => x"20",
        
        -- 0x0004: LD B, #0x20
        16#0004# => x"21", 16#0005# => x"20",
        
        -- 0x0006: LD A, [B]
        16#0006# => x"14",
        
        -- 0x0007: INC A (0xC2)
        16#0007# => x"C2",
        
        -- 0x0008: LD B, #0x30
        16#0008# => x"21", 16#0009# => x"30",
        
        -- 0x000A: ST A, [B]
        16#000A# => x"32",
        
        -- 0x000B: HALT
        16#000B# => x"01",

        -- Dato inicial
        16#0010# => x"AA",
        
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
        report "=== INICIO SIMULACION PROCESADOR (Test Página Cero/Indirecto) ===";
        
        -- Reset del sistema
        reset <= '1';
        wait for clk_period * 5;
        reset <= '0';
        report "--- Reset liberado, iniciando programa ---";

        -- Esperar un tiempo suficiente para que el programa se ejecute y se detenga en un HALT.
        wait for clk_period * 50;

        report "--- Verificación ---";
        -- Al final, PC debe estar en 0x000C (HALT en 0x000B + 1)
        assert MemAddress = x"000C"
            report "FAIL: El PC final no es correcto. Esperado 0x000C, obtenido: 0x" & to_hstring(MemAddress)
            severity error;
            
        -- Verificación de escritura en 0x0020 (ST A, [0x20]) -> 0xAA
        -- Verificación de escritura en 0x0030 (ST A, [B])    -> 0xAB
        assert RAM(16#0030#) = x"AB"
            report "FAIL: Escritura indirecta incorrecta en 0x0030. Esperado 0xAB, Leído: 0x" & to_hstring(RAM(16#0030#))
            severity error;

        if (MemAddress = x"000C") and (RAM(16#0030#) = x"AB") then
            report "PASS: Direccionamiento PZ e Indirecto verificados.";
        end if;

        report "=== FIN DE SIMULACION ===";
        std.env.stop; -- Detener la simulación en GHDL
    end process;
            severity note;

        report "=== FIN DE SIMULACION ===";
        std.env.stop; -- Detener la simulación en GHDL
    end process;

end architecture Behavioral;