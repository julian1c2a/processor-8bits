library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.STD_LOGIC_TEXTIO.ALL;
use STD.TEXTIO.ALL;
use work.ALU_pkg.ALL;

-- Testbench exhaustivo de la ALU.
--
-- Lee un archivo CSV generado por alu_ref.py con el nombre:
--     testbenchs/vectors/<OP>.csv
-- cuyo path se pasa como generic VECTOR_FILE.
--
-- Formato de cada línea del CSV:
--     A,B,CIN,OPCODE,ACC,STATUS   (todos en decimal)
-- La primera línea es la cabecera y se salta.
--
-- Se instancia una sola entidad genérica; el Makefile crea un ejecutable
-- distinto por operación pasando el generic correspondiente.
--
-- Ejemplo de invocación GHDL:
--   ghdl -e --std=08 ... ALU_exhaustive_tb
--   ./ALU_exhaustive_tb -gVECTOR_FILE=testbenchs/vectors/ADD.csv

entity ALU_exhaustive_tb is
    generic (
        VECTOR_FILE : string := "testbenchs/vectors/ADD.csv"
    );
end entity ALU_exhaustive_tb;

architecture bench of ALU_exhaustive_tb is

    for all : ALU_comp use entity work.ALU(unique);

    signal s_A      : data_vector := (others => '0');
    signal s_B      : data_vector := (others => '0');
    signal s_Op     : opcode_vector := (others => '0');
    signal s_Cin    : STD_LOGIC := '0';
    signal s_ACC    : data_vector;
    signal s_Status : status_vector;

    -- Tiempo de estabilización combinacional
    constant T_PROP : time := 10 ns;

begin

    dut: ALU_comp port map (
        RegInA    => s_A,
        RegInB    => s_B,
        Oper      => s_Op,
        Carry_in  => s_Cin,
        RegOutACC => s_ACC,
        RegStatus => s_Status
    );

    stim: process
        -- ----------------------------------------------------------------
        -- Variables de lectura CSV
        -- ----------------------------------------------------------------
        file     vec_file  : text;
        variable fstatus   : file_open_status;
        variable row       : line;
        variable comma     : character;

        -- Columnas del CSV (leídas como integer)
        variable v_A       : integer;
        variable v_B       : integer;
        variable v_cin     : integer;
        variable v_opcode  : integer; -- no se usa como señal, solo validación
        variable v_acc_exp : integer;
        variable v_stat_exp: integer;

        -- Vectores de comparación
        variable exp_acc   : data_vector;
        variable exp_stat  : status_vector;

        -- Contadores
        variable total     : integer := 0;
        variable errors    : integer := 0;

        -- Cabecera (se descarta)
        variable header    : line;

        -- Buffer para lectura de entero desde línea
        variable ok        : boolean;

        -- ----------------------------------------------------------------
        -- Procedure: lee un entero decimal de la línea hasta ',' o EOL
        -- ----------------------------------------------------------------
        procedure read_int(l: inout line; result: out integer) is
            variable buf : string(1 to 20);
            variable idx : integer := 0;
            variable c   : character;
            variable neg : boolean := false;
            variable val : integer := 0;
            variable peek: character;
            variable valid: boolean;
        begin
            -- Consume optional leading spaces
            loop
                if l'length = 0 then exit; end if;
                read(l, c);
                if c /= ' ' then
                    if c = '-' then neg := true;
                    elsif c >= '0' and c <= '9' then
                        val := character'pos(c) - character'pos('0');
                    end if;
                    exit;
                end if;
            end loop;
            -- Read remaining digits
            loop
                if l'length = 0 then exit; end if;
                read(l, c);
                if c >= '0' and c <= '9' then
                    val := val * 10 + (character'pos(c) - character'pos('0'));
                else
                    exit; -- separator or EOL
                end if;
            end loop;
            if neg then val := -val; end if;
            result := val;
        end procedure;

    begin
        -- Abrir el archivo de vectores
        file_open(fstatus, vec_file, VECTOR_FILE, read_mode);

        if fstatus /= open_ok then
            report "No se puede abrir el archivo de vectores: " & VECTOR_FILE
                severity failure;
        end if;

        report "=== Inicio test exhaustivo: " & VECTOR_FILE;

        -- Saltar cabecera
        readline(vec_file, header);

        -- Iterar sobre todos los vectores
        while not endfile(vec_file) loop
            readline(vec_file, row);

            -- Parsear: A,B,CIN,OPCODE,ACC,STATUS
            read_int(row, v_A);
            read_int(row, v_B);
            read_int(row, v_cin);
            read_int(row, v_opcode);
            read_int(row, v_acc_exp);
            read_int(row, v_stat_exp);

            -- Aplicar estímulos
            s_A   <= std_logic_vector(to_unsigned(v_A,   8));
            s_B   <= std_logic_vector(to_unsigned(v_B,   8));
            s_Op  <= std_logic_vector(to_unsigned(v_opcode, 5));
            s_Cin <= '1' when v_cin = 1 else '0';

            wait for T_PROP;

            -- Construir vectores esperados
            exp_acc  := std_logic_vector(to_unsigned(v_acc_exp,  8));
            exp_stat := std_logic_vector(to_unsigned(v_stat_exp, 8));

            -- Comparar ACC
            if s_ACC /= exp_acc then
                errors := errors + 1;
                report "FAIL ACC | A=" & integer'image(v_A) &
                       " B=" & integer'image(v_B) &
                       " CIN=" & integer'image(v_cin) &
                       " | ACC_exp=0x" & to_hstring(exp_acc) &
                       " ACC_got=0x" & to_hstring(s_ACC)
                    severity error;
            end if;

            -- Comparar Status
            if s_Status /= exp_stat then
                errors := errors + 1;
                report "FAIL STATUS | A=" & integer'image(v_A) &
                       " B=" & integer'image(v_B) &
                       " CIN=" & integer'image(v_cin) &
                       " | STAT_exp=0b" & to_bstring(exp_stat) &
                       " STAT_got=0b" & to_bstring(s_Status)
                    severity error;
            end if;

            total := total + 1;
        end loop;

        file_close(vec_file);

        -- Reporte final
        if errors = 0 then
            report "=== PASS: " & integer'image(total) &
                   " vectores OK - " & VECTOR_FILE
                severity note;
        else
            report "=== FAIL: " & integer'image(errors) &
                   " errores en " & integer'image(total) &
                   " vectores - " & VECTOR_FILE
                severity error;
        end if;

        wait;
    end process;

end architecture bench;
