# Testbenches

Este directorio contiene los testbenches VHDL y el oráculo Python para verificar la ALU.

---

## Archivos

| Archivo | Descripción |
|---|---|
| `ALU_tb.vhdl` | Testbench manual con casos de prueba seleccionados |
| `ALU_exhaustive_tb.vhdl` | Testbench exhaustivo genérico (lee vectores desde CSV) |
| `alu_ref.py` | Oráculo Python: genera vectores de test para todas las operaciones |
| `vectors/` | CSVs generados por `alu_ref.py` (no versionados, ver `.gitignore`) |

---

## ALU_tb.vhdl — Testbench manual

Testbench con casos de prueba a mano para ADD y SUB. Verifica:

- Resultado del acumulador (ACC)
- Flags: Carry, Half-Carry, Overflow, Zero, Greater, Equal

Usa la `procedure check_case` para comparar resultados esperados vs. obtenidos con mensajes descriptivos.

---

## ALU_exhaustive_tb.vhdl — Testbench exhaustivo

Testbench genérico que cubre **todas las combinaciones posibles** de entradas para cada operación.

- Recibe el archivo CSV a leer mediante el generic `VECTOR_FILE`.
- Lee línea a línea: `A, B, CIN, OPCODE, ACC_esperado, STATUS_esperado`.
- Compara la salida del DUT con los valores del oráculo.
- Reporta el número total de vectores y errores al finalizar.

Cobertura por operación:

| Tipo | Entradas iteradas | Vectores por operación |
|---|---|---|
| Binaria (dos operandos) | A ∈ [0,255], B ∈ [0,255] | 65 536 |
| Con carry (ADC, SBB) | A ∈ [0,255], B ∈ [0,255], Cin ∈ {0,1} | 131 072 |

Total: **~2.0 millones de vectores** para las 28 operaciones.

### Uso

```sh
# Compilar (desde MSYS2 MinGW64 con mingw32-make, o desde PowerShell)
mingw32-make compile

# Generar vectores CSV
python testbenchs/alu_ref.py

# Construir ejecutable exhaustivo
mingw32-make build/build_tests/ALU_exhaustive_tb.exe

# Ejecutar una operación concreta
./build/build_tests/ALU_exhaustive_tb.exe -gVECTOR_FILE=testbenchs/vectors/ADD.csv

# Ejecutar todas las operaciones (desde Makefile)
mingw32-make test-exhaustive
```

---

## alu_ref.py — Oráculo Python

Modela la ALU en Python puro (sin ambigüedad de tipos VHDL) y genera los CSVs de test.

**Por qué Python y no VHDL:** usar el mismo lenguaje para el modelo y el DUT podría copiar errores en ambos lados. Python actúa como referencia independiente.

Los modelos de referencia usan aritmética de precisión arbitraria de Python truncada explícitamente a 8 o 9 bits, espejando la lógica `signed(8 downto 0)` de la ALU VHDL.

### Uso

```sh
# Generar todas las operaciones
python testbenchs/alu_ref.py

# Generar solo algunas
python testbenchs/alu_ref.py ADD SUB ADC
```

Los CSVs se escriben en `testbenchs/vectors/<OP>.csv` con el formato:

```
A,B,CIN,OPCODE,ACC,STATUS
```

todos los valores en decimal.

---

## Operaciones verificadas (28/28 PASS)

| # | Operación | Vectores | Resultado |
|:---:|:---:|---:|:---:|
| 1 | NOP | 65 536 | PASS |
| 2 | ADD | 65 536 | PASS |
| 3 | ADC | 131 072 | PASS |
| 4 | SUB | 65 536 | PASS |
| 5 | SBB | 131 072 | PASS |
| 6 | LSL | 65 536 | PASS |
| 7 | LSR | 65 536 | PASS |
| 8 | ROL | 65 536 | PASS |
| 9 | ROR | 65 536 | PASS |
| 10 | INC | 65 536 | PASS |
| 11 | DEC | 65 536 | PASS |
| 12 | AND | 65 536 | PASS |
| 13 | IOR | 65 536 | PASS |
| 14 | XOR | 65 536 | PASS |
| 15 | NOT | 65 536 | PASS |
| 16 | ASL | 65 536 | PASS |
| 17 | PSA | 65 536 | PASS |
| 18 | PSB | 65 536 | PASS |
| 19 | CLR | 65 536 | PASS |
| 20 | SET | 65 536 | PASS |
| 21 | MUL | 65 536 | PASS |
| 22 | MUH | 65 536 | PASS |
| 23 | CMP | 65 536 | PASS |
| 24 | ASR | 65 536 | PASS |
| 25 | SWP | 65 536 | PASS |
| 26 | NEG | 65 536 | PASS |
| 27 | INB | 65 536 | PASS |
| 28 | DEB | 65 536 | PASS |
