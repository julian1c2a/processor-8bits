# Testbenches

Este directorio contiene los testbenches VHDL y herramientas de soporte para verificar el procesador a nivel de componente (ALU) y de sistema (Processor_Top).

---

## Archivos Principales

| Archivo | Descripción |
|---|---|
| `ALU_tb.vhdl` | Testbench manual con casos de prueba seleccionados |
| `ALU_exhaustive_tb.vhdl` | Testbench exhaustivo genérico (lee vectores desde CSV) |
| `alu_ref.py` | Oráculo Python: genera vectores de test para todas las operaciones |
| `vectors/` | CSVs generados por `alu_ref.py` (no versionados, ver `.gitignore`) |
| `Processor_Top_tb.vhdl` | Testbench de sistema completo con RAM simulada. |

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

## Processor_Top_tb.vhdl — Testbench de Sistema

Este testbench instancia la entidad `Processor_Top` completa y la conecta a una memoria RAM simulada.

### Funcionamiento

1. **RAM Simulada:** Se declara una señal de tipo `array` que modela los 64KB de memoria del procesador.
2. **Carga de Programa:** El programa de prueba se "carga" directamente en la RAM durante la inicialización del testbench (generic `PROGRAM_SEL`).
3. **Ejecución:** Se aplica un pulso de `reset` y se deja que el procesador ejecute el programa cargado.
4. **Verificación:** Al final de la simulación, sentencias `assert` comprueban el contenido de posiciones de memoria específicas que el programa debía modificar.

### Programas de prueba — TB-01 a TB-13: ALL PASS

| # | Nombre | Tiempo PASS | Qué verifica |
|:---:|:---|:---:|:---|
| TB-01 | Instrucciones unarias | @1415 ns | NOT, NEG, INC, DEC, CLR, SET, SWAP sobre registro A |
| TB-02 | ALU registro | @1825 ns | ADD, ADC, SUB, SBB, AND, OR, XOR, CMP, MUL, MUH (operandos en A y B) |
| TB-03 | ALU inmediato | @1345 ns | Variantes con operando `#n` de las operaciones ALU |
| TB-04 | Desplazamientos y rotaciones | @1325 ns | LSL, LSR, ASL, ASR, ROL, ROR |
| TB-05 | Cargas y almacenamientos | @1795 ns | LD/ST en modos: `#n`, `[n]`, `[nn]`, `[B]`, `[nn+B]` |
| TB-06 | Saltos incondicionales | @1585 ns | JP nn, JR rel8, JPN, JP([nn]), JP A:B |
| TB-07 | Saltos condicionales | @2515 ns | BEQ, BNE, BCS, BCC, BVS, BVC, BGT, BLE, BGE, BLT, BHC, BEQ2 |
| TB-08 | CALL / RET | @1025 ns | Llamada a subrutina y retorno (push/pop dirección) |
| TB-09 | PUSH / POP | @1125 ns | PUSH/POP de A, B, F y par A:B; verificación valores en pila |
| TB-10 | Stack Pointer | @935 ns | `LD SP, #nn`; lectura de SP\_L y SP\_H mediante RD SP |
| TB-11 | ADD16 / SUB16 | @1495 ns | Aritmética de 16 bits sobre par A:B (modos `#n` y `#nn`) |
| TB-12 | Interrupciones IRQ/NMI | @1615 ns | Secuencia ESS\_INT, RTI, vectores `0xFFFE` (IRQ) y `0xFFFA` (NMI) |
| TB-13 | Pipeline hazards | @515 ns | Stall RAW (LD A,#n → ADD #0) y flush de salto tomado (JP sobre INC A) |

**Nota TB-12:** El programa inicializa `SP = 0x01FF` con `LD SP, #0x01FF` para evitar que las tres bajadas de SP durante `ESS_INT` (desde `0xFFFE`) solapen los vectores de interrupción en `0xFFFA`–`0xFFFF`.

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
