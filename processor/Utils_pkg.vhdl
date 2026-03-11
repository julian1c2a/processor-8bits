library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL; -- Paquete estándar para log2 y ceil

package Utils_pkg is
    -- Calcula log2(n) redondeado hacia arriba (número de bits para direccionar n elementos)
    function ceil_log2(n : natural) return natural;
end package Utils_pkg;

package body Utils_pkg is
    function ceil_log2(n : natural) return natural is
    begin
        if n <= 1 then 
            return 0; 
        else
            -- Conversión estándar: Entero -> Real -> Log2 -> Ceil -> Entero
            return integer(ceil(log2(real(n))));
        end if;
    end function;
end package body Utils_pkg;