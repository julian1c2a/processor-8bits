-- ALU_run_tb.vhdl
-- Testbench interactivo: lee vectores de entrada desde un CSV (sin valores
-- esperados) y reporta el resultado real de la ALU. Pensado para ser lanzado
-- desde alu_sim.py, que actúa de consola de usuario.
--
-- Formato del CSV (sin cabecera de STATUS):
--   A,B,CIN,OPCODE
--   (todos decimales, sin espacios)
--
-- Uso directo con GHDL:
--   ALU_run_tb.exe -gVECTOR_FILE=testbenchs/vectors/_sim_run.csv
-- ---------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;

use work.ALU_pkg.all;

entity ALU_run_tb is
    generic (
        VECTOR_FILE : string := "testbenchs/vectors/_sim_run.csv"
    );
end entity ALU_run_tb;

architecture sim of ALU_run_tb is

    -- Señales del DUT
    signal s_A      : STD_LOGIC_VECTOR(7 downto 0) := (others => '0');
    signal s_B      : STD_LOGIC_VECTOR(7 downto 0) := (others => '0');
    signal s_Op     : STD_LOGIC_VECTOR(4 downto 0) := (others => '0');
    signal s_Cin    : STD_LOGIC := '0';
    signal s_ACC    : STD_LOGIC_VECTOR(7 downto 0);
    signal s_Status : STD_LOGIC_VECTOR(7 downto 0);

    -- Tiempo de propagación combinacional
    constant T_PROP : time := 10 ns;

    -- -----------------------------------------------------------------------
    -- Parsea un entero decimal (positivo) de una línea CSV con comas.
    -- Salta cualquier carácter no numérico hasta encontrar el primer dígito;
    -- lee dígitos hasta que ya no haya más o aparezca un delimitador.
    -- -----------------------------------------------------------------------
    procedure read_int (
        variable lin : inout line;
        variable val : out   integer
    ) is
        variable c       : character;
        variable ok      : boolean;
        variable n       : integer := 0;
        variable started : boolean := false;
    begin
        loop
            read(lin, c, ok);
            exit when not ok;
            if c >= '0' and c <= '9' then
                n       := n * 10 + (character'pos(c) - character'pos('0'));
                started := true;
            elsif started then
                exit;   -- primer carácter no numérico tras haber leído dígitos
            end if;
            -- Si aún no empezamos (p.ej. espacios/comas iniciales) seguimos
        end loop;
        val := n;
    end procedure;

    -- -----------------------------------------------------------------------
    -- Convierte un STD_LOGIC_VECTOR(7 downto 0) a cadena hexadecimal "XX".
    -- -----------------------------------------------------------------------
    function to_hex_byte (v : STD_LOGIC_VECTOR(7 downto 0)) return string is
        constant HEX : string := "0123456789ABCDEF";
        variable hi  : integer := to_integer(unsigned(v(7 downto 4)));
        variable lo  : integer := to_integer(unsigned(v(3 downto 0)));
    begin
        return HEX(hi + 1) & HEX(lo + 1);
    end function;

    -- -----------------------------------------------------------------------
    -- Convierte un STD_LOGIC_VECTOR(7 downto 0) a cadena binaria "XXXXXXXX"
    -- (MSB primero).
    -- -----------------------------------------------------------------------
    function to_bin_byte (v : STD_LOGIC_VECTOR(7 downto 0)) return string is
        variable s : string(1 to 8);
    begin
        for i in 7 downto 0 loop
            if v(i) = '1' then
                s(8 - i) := '1';
            else
                s(8 - i) := '0';
            end if;
        end loop;
        return s;
    end function;

    -- Extrae el carácter '0'/'1' de std_logic'image (que devuelve "'0'" o "'1'")
    function sl_char (b : std_logic) return string is
    begin
        return std_logic'image(b)(2 to 2);
    end function;

begin

    -- Instancia del DUT
    DUT: entity work.ALU
        port map (
            RegInA    => s_A,
            RegInB    => s_B,
            Oper      => s_Op,
            Carry_in  => s_Cin,
            RegOutACC => s_ACC,
            RegStatus => s_Status
        );

    -- -----------------------------------------------------------------------
    -- Proceso principal: lee el CSV, aplica estímulos y reporta resultados
    -- -----------------------------------------------------------------------
    process
        file     f           : text;
        variable lin         : line;
        variable v_A, v_B    : integer;
        variable v_Cin, v_Op : integer;
    begin
        file_open(f, VECTOR_FILE, read_mode);

        -- Saltar cabecera
        readline(f, lin);

        while not endfile(f) loop
            readline(f, lin);

            -- Saltar líneas vacías
            if lin'length = 0 then
                next;
            end if;

            -- Leer los cuatro campos
            read_int(lin, v_A);
            read_int(lin, v_B);
            read_int(lin, v_Cin);
            read_int(lin, v_Op);

            -- Aplicar entradas al DUT
            s_A   <= std_logic_vector(to_unsigned(v_A,  8));
            s_B   <= std_logic_vector(to_unsigned(v_B,  8));
            s_Cin <= '1' when v_Cin /= 0 else '0';
            s_Op  <= std_logic_vector(to_unsigned(v_Op, 5));

            -- Esperar propagación combinacional
            wait for T_PROP;

            -- Reportar resultado en formato parseble por alu_sim.py
            report
                "RESULT:"
                & " ACC=0x"    & to_hex_byte(s_ACC)
                & " ("         & integer'image(to_integer(unsigned(s_ACC))) & "d)"
                & " bin="      & to_bin_byte(s_ACC)
                & " STATUS=0x" & to_hex_byte(s_Status)
                & " bin="      & to_bin_byte(s_Status)
                & " C=" & sl_char(s_Status(7))
                & " H=" & sl_char(s_Status(6))
                & " V=" & sl_char(s_Status(5))
                & " Z=" & sl_char(s_Status(4))
                & " G=" & sl_char(s_Status(3))
                & " E=" & sl_char(s_Status(2))
                & " R=" & sl_char(s_Status(1))
                & " L=" & sl_char(s_Status(0))
                severity note;
        end loop;

        file_close(f);
        wait;
    end process;

end architecture sim;
