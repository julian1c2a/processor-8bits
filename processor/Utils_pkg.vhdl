-- =========================================================================
-- Paquete: Utils_pkg
-- Descripción:
--   Funciones matemáticas de utilidad general usadas en tiempo de elaboración
--   (generics, constantes derivadas). No genera lógica sintetizable por sí solo.
--
-- NOTA DE SÍNTESIS:
--   La dependencia de IEEE.MATH_REAL (log2, ceil) implica que este paquete
--   solo es válido durante la elaboración estática del diseño. Las funciones
--   aquí definidas se evalúan en tiempo de compilación/síntesis, NO en hardware.
--   Los simuladores también aceptan IEEE.MATH_REAL en runtime de simulación.
-- =========================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL; -- Paquete estándar para log2 y ceil
                        -- Requerido SOLO en elaboración; no produce lógica RTL

package Utils_pkg is

    -- =========================================================================
    -- Función: ceil_log2
    -- =========================================================================
    -- Calcula log2(n) redondeado hacia arriba (número de bits para direccionar n elementos).
    --
    -- Uso principal: dimensionar el selector de índice del banco de registros.
    --   Ejemplo: ceil_log2(8) = 3  → se necesitan 3 bits para seleccionar entre 8 registros.
    --   Ejemplo: ceil_log2(1) = 0  → un solo elemento no requiere bits de selección.
    --
    -- El caso base (n <= 1 retorna 0) es correcto porque:
    --   - n=0: no tiene sentido direccionar 0 elementos; devolver 0 evita log2(0)=-inf.
    --   - n=1: con un único elemento no hace falta ningún bit selector (2^0 = 1).
    function ceil_log2(n : natural) return natural;

end package Utils_pkg;

package body Utils_pkg is

    function ceil_log2(n : natural) return natural is
    begin
        if n <= 1 then
            -- Caso base: 0 o 1 elemento no requieren bits de selección.
            -- Evita además llamar a log2(0) que es matemáticamente indefinido (-∞).
            return 0;
        else
            -- Conversión estándar: Entero -> Real -> Log2 -> Ceil -> Entero
            -- Se convierte a Real porque log2() de MATH_REAL solo acepta tipo real.
            -- ceil() garantiza el redondeo hacia arriba para potencias no exactas de 2.
            -- Ejemplo: n=5 → log2(5.0)≈2.32 → ceil→3.0 → integer→3 bits.
            return integer(ceil(log2(real(n))));
        end if;
    end function;

end package body Utils_pkg;
