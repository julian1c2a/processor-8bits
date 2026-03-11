--------------------------------------------------------------------------------
-- Entidad: DataPath
-- Descripción:
--   Implementa el camino de datos de 8 bits del procesador.
--   Contiene:
--     - Banco de Registros Unificado (8x8): R0 actúa como Acumulador (A).
--     - ALU: Realiza operaciones aritmético-lógicas.
--     - MDR: Registro de datos de memoria para sincronización.
--     - Lógica de Flags: Gestión de estado con escritura enmascarada.
--
--   Características clave:
--     - Permite usar cualquier registro (R0..R7) como operando B de la ALU.
--     - Doble puerto de escritura lógico (Write_A para R0, Write_B para R_Sel).
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.CONSTANTS_pkg.ALL;
use work.ALU_pkg.ALL;
use work.DataPath_pkg.ALL;

entity DataPath is
    Port (
        clk       : in std_logic;
        reset     : in std_logic;

        -- Bus de Datos con Memoria/IO
        MemDataIn : in  data_vector; -- Dato leído de memoria/IO
        MemDataOut: out data_vector; -- Dato a escribir en memoria/IO
        IndexB_Out: out data_vector; -- Salida de RegB para el AddressPath

        -- Señales de Control (vienen de la UC)
        ALU_Op    : in  opcode_vector; -- Operación ALU
        Bus_Op    : in  std_logic_vector(1 downto 0); -- Control mux entrada (ej: 00=Mem, 01=ALU, 10=PC_Low...)
        
        Write_A   : in  std_logic; -- Habilitar escritura en A
        Write_B   : in  std_logic; -- Habilitar escritura en B
        Reg_Sel   : in  std_logic_vector(MSB_REG_SEL downto 0); -- Selección registro operando B
        Write_F   : in  std_logic; -- Habilitar actualización de Flags
        Flag_Mask : in  status_vector; -- Máscara para actualización parcial de flags (1=update)
        MDR_WE    : in  std_logic; -- Habilitar escritura en MDR (Memory Data Register)
        Out_Sel   : in  std_logic; -- 0=RegA, 1=RegB para MemDataOut
        
        -- Salidas de Estado hacia la UC
        FlagsOut  : out status_vector -- Para saltos condicionales
    );
end entity DataPath;

architecture unique of DataPath is

    for all : ALU_comp use entity work.ALU(unique);

    -- -------------------------------------------------------------------------
    -- Banco de Registros (Register File)
    -- -------------------------------------------------------------------------
    -- Se define como un array de vectores.
    -- Inicialización a 0 para simulación limpia.
    signal Registers : register_file_t := (others => (others => '0'));

    -- Alias semánticos: R0 es siempre el Acumulador (A), R1 es el registro B por defecto
    alias RegA is Registers(0);
    alias RegB is Registers(1);

    -- Registros internos
    signal RegF   : status_vector := (others => '0'); -- Flags
    signal MDR    : data_vector := (others => '0');   -- Memory Data Register

    -- Señales internas
    signal ALU_Res  : data_vector;
    signal ALU_Stat : status_vector;
    signal Bus_Int  : data_vector; -- Bus interno de escritura (resultado mux)
    signal ALU_OpB  : data_vector; -- Operando B seleccionado

begin

    -- =========================================================================
    -- 1. Instancia de la ALU
    -- =========================================================================
    -- 1. Instancia de la ALU
    -- Nota: Carry_in necesita lógica especial (puede venir de F(7) o ser 0 o 1)
    -- Por ahora lo conectamos al flag C actual para operaciones aritméticas
    Inst_ALU: ALU_comp 
    Port map (
        RegInA    => RegA,
        RegInB    => ALU_OpB, -- Entrada B multiplexada
        Oper      => ALU_Op,
        Carry_in  => RegF(idx_fC), -- Carry actual
        RegOutACC => ALU_Res,
        RegStatus => ALU_Stat
    );

    -- MUX Entrada B ALU:
    -- Permite flexibilidad total: ALU puede operar A con cualquier Rn.
    ALU_OpB <= Registers(to_register_index(Reg_Sel));

    -- =========================================================================
    -- 2. Lógica de Write-Back (Escritura en Registros)
    -- =========================================================================
    
    -- MUX Write-Back: Selecciona la fuente de datos a escribir en el banco de registros.
    -- Esto implementa la lógica de selección de fuente
    process(Bus_Op, ALU_Res, MDR)
    begin
        case Bus_Op is
            when ACC_ALU_elected  => Bus_Int <= ALU_Res;   -- Resultado ALU
            when MEM_MDR_elected => Bus_Int <= MDR;       -- Dato de Memoria/IO (vía MDR)
            when others => Bus_Int <= (others => '0');
        end case;
    end process;

    -- Proceso secuencial: Actualización de registros en flanco de reloj
    process(clk, reset)
    begin
        if reset = '1' then
            Registers <= (others => (others => '0'));
            RegF <= (others => '0');
            MDR  <= (others => '0');
        elsif rising_edge(clk) then
            
            -- Escritura en Acumulador (A / R0)
            -- Prioridad o independencia: Write_A siempre afecta a R0.
            if Write_A = '1' then
                RegA <= Bus_Int;
            end if;

            -- Escritura en Registro General (R0..R7 seleccionado por Reg_Sel)
            -- Permite escribir resultados en registros auxiliares.
            if Write_B = '1' then
                Registers(to_register_index(Reg_Sel)) <= Bus_Int;
            end if;

            -- Gestión de Flags (Registro F)
            -- Usa 'Flag_Mask' para permitir actualizaciones parciales (ej. instrucciones
            -- que solo afectan a Z pero no a C).
            if Write_F = '1' then
                -- Actualización con máscara: (Old and NOT Mask) OR (New and Mask)
                RegF <= apply_flag_mask(RegF, ALU_Stat, Flag_Mask);
            end if;

            -- Escritura MDR (Captura de dato de memoria)
            -- Buffer de entrada para desacoplar el tiempo de acceso a memoria.
            if MDR_WE = '1' then
                MDR <= MemDataIn;
            end if;
        end if;
    end process;

    -- =========================================================================
    -- 3. Salidas del DataPath
    -- =========================================================================
    -- Selección de dato a escribir en memoria (ST A o ST B)
    MemDataOut <= RegA when Out_Sel = '0' else RegB;
    
    FlagsOut   <= RegF;
    IndexB_Out <= RegB;

end architecture unique;
