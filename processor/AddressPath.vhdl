library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.CONSTANTS_pkg.ALL;
use work.ALU_pkg.ALL; -- Para tipos de datos base
use work.AddressPath_pkg.ALL;

entity AddressPath is
    Port (
        clk       : in std_logic;
        reset     : in std_logic;

        -- Buses de Datos
        DataIn    : in  data_vector; -- Entrada desde Memoria/DataPath (8 bits)
        Index_B   : in  data_vector; -- Índice desde DataPath (Registro B)
        
        -- Bus de Direcciones (Salida Principal)
        AddressBus : out address_vector;

        -- Señales de Control (vienen de UC)
        PC_Op     : in  std_logic_vector(1 downto 0); -- Control PC (Inc, Load...)
        SP_Op     : in  std_logic_vector(1 downto 0); -- Control SP (Inc, Dec, Load...)
        ABUS_Sel  : in  std_logic_vector(1 downto 0); -- Quién controla el AddressBus
        
        -- Cargas de registros específicos
        Load_LR   : in  std_logic; -- Cargar Link Register
        Load_EAR  : in  std_logic; -- Cargar Effective Address Register
        Load_TMP_L: in  std_logic; -- Cargar parte baja de TMP (desde DataIn)
        Load_TMP_H: in  std_logic; -- Cargar parte alta de TMP (desde DataIn)
        
        -- Selección de fuente para cargar PC/SP/LR (Calculado vs Dato directo)
        Load_Src_Sel : in std_logic -- 0=EA_Adder_Res, 1=TMP (Dato 16 bits ensamblado)
    );
end entity AddressPath;

architecture Behavioral of AddressPath is

    -- Registros internos de 16 bits
    signal r_PC  : unsigned_address_vector := (others => '0');
    signal r_SP  : unsigned_address_vector := x"FFFE"; -- Stack empieza arriba (alineado a par)
    signal r_LR  : unsigned_address_vector := (others => '0');
    signal r_EAR : unsigned_address_vector := (others => '0');
    
    -- Registro temporal para ensamblar 16 bits desde bus de 8 bits
    signal r_TMP : unsigned_address_vector := (others => '0');

    -- Señales internas
    signal EA_Adder_Res : unsigned_address_vector; -- Resultado del sumador
    signal Mux_Load_Data : unsigned_address_vector; -- Dato a cargar en registros

begin

    -- ========================================================================
    -- 1. Lógica Combinacional: EA Adder (Sumador de Direcciones)
    -- ========================================================================
    -- Calcula: Base (TMP) + Índice (B extendido)
    -- Sirve para: [nn+B], Saltos relativos (PC + rel8), etc.
    -- Nota: Para saltos relativos, TMP tendría el PC actual y DataIn el rel8.
    --       Para simplificar, aquí asumimos Base = TMP, Index = Index_B.
    --       (La arquitectura exacta de entradas del sumador puede refinarse según microcódigo)
    EA_Adder_Res <= r_TMP + resize(unsigned(Index_B), 16);

    -- ========================================================================
    -- 2. Multiplexor de Fuente de Carga
    -- ========================================================================
    -- Elige si cargamos el resultado de una suma (ej. Salto Relativo)
    -- o un dato directo ensamblado en TMP (ej. JP nn)
    Mux_Load_Data <= EA_Adder_Res when Load_Src_Sel = LOAD_SRC_ALU_RES else
                     r_TMP;

    -- ========================================================================
    -- 3. Registros y Lógica Secuencial
    -- ========================================================================
    process(clk, reset)
    begin
        if reset = '1' then
            r_PC  <= (others => '0');
            r_SP  <= x"FFFE";
            r_LR  <= (others => '0');
            r_EAR <= (others => '0');
            r_TMP <= (others => '0');
        elsif rising_edge(clk) then
            
            -- --- Gestión de TMP (Ensamblador de 16 bits) ---
            if Load_TMP_L = '1' then
                r_TMP(7 downto 0) <= unsigned(DataIn);
            end if;
            if Load_TMP_H = '1' then
                r_TMP(15 downto 8) <= unsigned(DataIn);
            end if;

            -- --- Gestión del PC (Program Counter) ---
            case PC_Op is
                when PC_OP_NOP  => null; -- Hold
                when PC_OP_INC  => r_PC <= r_PC + 1;
                when PC_OP_LOAD => r_PC <= Mux_Load_Data; -- Salto absoluto o relativo
                when others => null;
            end case;

            -- --- Gestión del SP (Stack Pointer) ---
            -- Nota: SP siempre par (bit 0 forzado a 0 implícitamente por aritmética +2/-2)
            case SP_Op is
                when SP_OP_NOP  => null;
                when SP_OP_INC  => r_SP <= r_SP + 2; -- POP
                when SP_OP_DEC  => r_SP <= r_SP - 2; -- PUSH
                when SP_OP_LOAD => r_SP <= Mux_Load_Data;
                    -- Forzar alineación par si cargamos valor arbitrario?
                    -- r_SP(0) <= '0'; (se aplicaría en siguiente ciclo o combinacional)
                when others => null;
            end case;

            -- --- Gestión de LR (Link Register) ---
            if Load_LR = '1' then
                -- Normalmente se carga con PC actual (para CALL/BSR)
                -- Aquí asumimos que Mux_Load_Data puede traer el PC si TMP se carga con PC
                -- O podemos añadir una ruta directa PC -> LR si la ISA lo requiere frecuentemente.
                r_LR <= r_PC; 
            end if;

            -- --- Gestión de EAR (Effective Address Register) ---
            if Load_EAR = '1' then
                r_EAR <= EA_Adder_Res;
            end if;

        end if;
    end process;

    -- ========================================================================
    -- 4. Salida al Bus de Direcciones (Multiplexor de Salida)
    -- ========================================================================
    process(ABUS_Sel, r_PC, r_SP, r_EAR, r_LR)
    begin
        case ABUS_Sel is
            when ABUS_SRC_PC  => AddressBus <= std_logic_vector(r_PC);
            when ABUS_SRC_SP  => AddressBus <= std_logic_vector(r_SP);
            when ABUS_SRC_EAR => AddressBus <= std_logic_vector(r_EAR);
            when ABUS_SRC_LR  => AddressBus <= std_logic_vector(r_LR);
            when others       => AddressBus <= (others => '0');
        end case;
    end process;

end architecture Behavioral;
```

Con `DataPath` y `AddressPath` listos, ya tenemos las dos "piernas" del procesador. Ahora sí que tiene sentido ir a por el `CPU_Top` y la Unidad de Control.

<!--
[PROMPT_SUGGESTION]Crea el archivo processor/ControlUnit_pkg.vhdl para definir los tipos de señales de control que conectarán la UC con estos dos paths.[/PROMPT_SUGGESTION]
[PROMPT_SUGGESTION]Ahora crea la estructura general en processor/Processor_Top.vhdl instanciando DataPath y AddressPath.[/PROMPT_SUGGESTION]
-->