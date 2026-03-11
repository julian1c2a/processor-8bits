library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.ALU_pkg.ALL;

entity DataPath is
    Port (
        clk       : in std_logic;
        reset     : in std_logic;

        -- Bus de Datos con Memoria/IO
        MemDataIn : in  data_vector; -- Dato leído de memoria/IO
        MemDataOut: out data_vector; -- Dato a escribir en memoria/IO

        -- Señales de Control (vienen de la UC)
        ALU_Op    : in  opcode_vector; -- Operación ALU
        Bus_Op    : in  std_logic_vector(1 downto 0); -- Control mux entrada (ej: 00=Mem, 01=ALU, 10=PC_Low...)
        
        Write_A   : in  std_logic; -- Habilitar escritura en A
        Write_B   : in  std_logic; -- Habilitar escritura en B
        Write_F   : in  std_logic; -- Habilitar actualización de Flags
        
        -- Salidas de Estado hacia la UC
        FlagsOut  : out status_vector -- Para saltos condicionales
    );
end entity DataPath;

architecture unique of DataPath is

    for all : ALU_comp use entity work.ALU(unique);

    -- Registros internos
    signal RegA   : data_vector := (others => '0');
    signal RegB   : data_vector := (others => '0');
    signal RegF   : status_vector := (others => '0'); -- Flags

    -- Señales internas
    signal ALU_Res  : data_vector;
    signal ALU_Stat : status_vector;
    signal Bus_Int  : data_vector; -- Bus interno de escritura (resultado mux)

begin

    -- 1. Instancia de la ALU
    -- Nota: Carry_in necesita lógica especial (puede venir de F(7) o ser 0 o 1)
    -- Por ahora lo conectamos al flag C actual para operaciones aritméticas
    Inst_ALU: ALU_comp 
    Port map (
        RegInA    => RegA,
        RegInB    => RegB,
        Oper      => ALU_Op,
        Carry_in  => RegF(7), -- Carry actual
        RegOutACC => ALU_Res,
        RegStatus => ALU_Stat
    );

    -- 2. Multiplexor de Write-Back (Qué dato escribimos en los registros)
    -- Esto implementa la lógica de selección de fuente
    process(Bus_Op, ALU_Res, MemDataIn)
    begin
        case Bus_Op is
            when b"00" => Bus_Int <= ALU_Res;   -- Resultado ALU
            when b"01" => Bus_Int <= MemDataIn; -- Dato de Memoria/IO
            when others => Bus_Int <= (others => '0');
        end case;
    end process;

    -- 3. Banco de Registros (A, B, Flags)
    process(clk, reset)
    begin
        if reset = '1' then
            RegA <= (others => '0');
            RegB <= (others => '0');
            RegF <= (others => '0');
        elsif rising_edge(clk) then
            -- Escritura A
            if Write_A = '1' then
                RegA <= Bus_Int;
            end if;

            -- Escritura B
            if Write_B = '1' then
                RegB <= Bus_Int;
            end if;

            -- Escritura Flags (Status)
            if Write_F = '1' then
                RegF <= ALU_Stat;
            end if;
        end if;
    end process;

    -- 4. Salidas
    MemDataOut <= RegA; -- Normalmente STORE guarda A (o B, requiere mux salida)
    FlagsOut   <= RegF;

end architecture unique;
