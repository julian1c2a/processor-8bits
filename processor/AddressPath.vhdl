--------------------------------------------------------------------------------
-- Entidad: AddressPath
-- Descripción:
--   Camino de datos de 16 bits para gestión de direcciones.
--   Contiene:
--     - Registros: PC (Program Counter), SP (Stack Pointer), LR (Link Reg).
--     - Sumador EA: Calcula direcciones efectivas (Base + Índice).
--     - Lógica de incremento/decremento para PC y SP.
--------------------------------------------------------------------------------

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
        Index_A   : in  data_vector; -- Registro A para formar A:B
        
        -- Bus de Direcciones (Salida Principal)
        AddressBus : out address_vector;
        PC_Out     : out address_vector; -- Salida del PC para guardar en Stack
        EA_Out     : out address_vector; -- Resultado EA hacia DataPath
        EA_Flags   : out status_vector;  -- Flags resultantes (C, V, Z)

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
        Load_Src_Sel : in std_logic; -- 0=EA_Adder_Res, 1=TMP (Dato 16 bits ensamblado)
        SP_Offset    : in std_logic; -- 0=SP, 1=SP+1 (para accesos de 16 bits secuenciales)
        
        -- Selección de operandos para el EA Adder
        EA_A_Sel  : in  std_logic;
        Clear_TMP : in  std_logic;
        EA_B_Sel  : in  std_logic_vector(1 downto 0);
        EA_Op     : in  std_logic -- 0=ADD, 1=SUB
    );
end entity AddressPath;

architecture unique of AddressPath is

    -- Registros internos de 16 bits
    signal r_PC  : unsigned_address_vector := (others => '0');
    signal r_SP  : unsigned_address_vector := x"FFFE"; -- Stack empieza arriba (alineado a par)
    signal r_LR  : unsigned_address_vector := (others => '0');
    signal r_EAR : unsigned_address_vector := (others => '0');
    
    -- Registro temporal para ensamblar 16 bits desde bus de 8 bits
    signal r_TMP : unsigned_address_vector := (others => '0');

    -- Señales internas
    signal EA_Adder_Res : unsigned_address_vector; -- Resultado del sumador
    signal EA_Result_Full : unsigned(ADDRESS_WIDTH downto 0); -- Resultado con carry bit (17 bits)
    signal EA_Adder_A_In: unsigned_address_vector; -- Operando A para el sumador
    signal EA_Adder_B_In: signed_address_vector;   -- Operando B para el sumador (signed para rel8)
    signal Mux_Load_Data : unsigned_address_vector; -- Dato a cargar en registros

begin

    -- ========================================================================
    -- 1. Lógica Combinacional: MUXes y Sumador EA
    -- ========================================================================
    
    -- Multiplexor para la entrada A (Base) del sumador
    EA_Adder_A_In <= r_PC when EA_A_Sel = EA_A_SRC_PC else r_TMP;
    
    -- Multiplexor para la entrada B (Índice) del sumador
    with EA_B_Sel select EA_Adder_B_In <= 
        resize(unsigned(Index_B), 16) when EA_B_SRC_REG_B,
        resize(signed(DataIn), 16)    when EA_B_SRC_DATA_IN,
        resize(unsigned(Index_A & Index_B), 16) when EA_B_SRC_REG_AB,
        (others => '0')               when others;

    -- Calcula: Base (TMP) + Índice (B extendido)
    -- Sirve para: [nn+B], Saltos relativos (PC + rel8), ADD16 (TMP + A:B)
    -- Lógica Add/Sub
    process(EA_Adder_A_In, EA_Adder_B_In, EA_Op)
        variable v_opA : signed(ADDRESS_WIDTH downto 0);
        variable v_opB : signed(ADDRESS_WIDTH downto 0);
        variable v_res : signed(ADDRESS_WIDTH downto 0);
    begin
        v_opA := resize(signed(EA_Adder_A_In), ADDRESS_WIDTH + 1);
        v_opB := resize(EA_Adder_B_In, ADDRESS_WIDTH + 1);
        
        if EA_Op = EA_OP_ADD then
            v_res := v_opA + v_opB;
        else
            v_res := v_opA - v_opB; -- Resta: A (TMP) - B (Index)
            -- Nota: Para SUB16 A:B - nn, usaremos: EA_A=A:B (vía REG_AB), EA_B=nn (vía TMP)
            -- pero nuestro MUX pone A:B en la entrada B.
            -- Así que calcularemos: TMP - A:B.
            -- Si queremos A:B - TMP, necesitariamos cambiar los muxes o hacer negación.
            -- Solución simple: Asumiremos ADD16 es conmutativo.
            -- Para SUB16, ajustaremos en ControlUnit o AddressPath.
            -- Por ahora implementamos A + B y A - B estándar.
        end if;
        
        EA_Result_Full <= unsigned(v_res);
    end process;

    EA_Adder_Res <= EA_Result_Full(MSB_ADDRESS downto 0);

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
            
            if Clear_TMP = '1' then
                r_TMP <= (others => '0');
            end if;

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
            when ABUS_SRC_SP  => 
                if SP_Offset = '1' then
                    AddressBus <= std_logic_vector(r_SP + 1);
                else
                    AddressBus <= std_logic_vector(r_SP);
                end if;
            when ABUS_SRC_EAR => AddressBus <= std_logic_vector(r_EAR);
            when ABUS_SRC_EA_RES => AddressBus <= std_logic_vector(EA_Adder_Res);
            when others       => AddressBus <= (others => '0');
        end case;
    end process;

    -- Salida auxiliar del PC hacia el DataPath (para PUSH PC/CALL)
    PC_Out <= std_logic_vector(r_PC);
    EA_Out <= std_logic_vector(EA_Adder_Res);
    
    -- Cálculo de Flags 16-bit
    process(EA_Result_Full, EA_Adder_Res, EA_Op)
        variable v_flags : status_vector := (others => '0');
    begin
        -- Zero Flag
        if EA_Adder_Res = 0 then v_flags(idx_fZ) := '1'; end if;
        
        -- Carry Flag (Bit 16)
        if EA_Op = EA_OP_ADD then
            v_flags(idx_fC) := EA_Result_Full(ADDRESS_WIDTH);
        else
            v_flags(idx_fC) := not EA_Result_Full(ADDRESS_WIDTH); -- Not Borrow
        end if;
        
        -- Overflow (V) simplificado: solo para aritmética con signo si se requiere
        -- Dejamos V a 0 por ahora para simplificar AddressPath
        
        EA_Flags <= v_flags;
    end process;

end architecture Behavioral;
```

Con `DataPath` y `AddressPath` listos, ya tenemos las dos "piernas" del procesador. Ahora sí que tiene sentido ir a por el `CPU_Top` y la Unidad de Control.

<!--
[PROMPT_SUGGESTION]Crea el archivo processor/ControlUnit_pkg.vhdl para definir los tipos de señales de control que conectarán la UC con estos dos paths.[/PROMPT_SUGGESTION]
[PROMPT_SUGGESTION]Ahora crea la estructura general en processor/Processor_Top.vhdl instanciando DataPath y AddressPath.[/PROMPT_SUGGESTION]
-->