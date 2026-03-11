# ALU 8-bit

Implementación de una Unidad Aritmético-Lógica de 8 bits en VHDL (VHDL-2008).

## Archivos

| Archivo | Descripción |
|---|---|
| `processor/ALU.vhdl` | Implementación de la ALU |
| `processor/ALU_functions_pkg.vhdl` | Funciones puras para operaciones aritméticas y lógicas |
| `processor/ALU_pkg.vhdl` | Package con las constantes de opcodes |
| `testbenchs/ALU_tb.vhdl` | Testbench manual (casos de prueba seleccionados) |
| `testbenchs/ALU_exhaustive_tb.vhdl` | Testbench exhaustivo (lee vectores desde CSV) |
| `testbenchs/alu_ref.py` | Oráculo Python: genera vectores de test para todas las operaciones |

---

## Interfaz

```vhdl
entity ALU is
    Port (
        RegInA    : in  data_vector;   -- Operando A (R0)
        RegInB    : in  data_vector;   -- Operando B (R0..R7 vía Mux)
        Oper      : in  opcode_vector; -- Código de operación
        Carry_in  : in  STD_LOGIC := '0';              -- Carry/Borrow entrada (ADC, SBB)
        RegOutACC : out data_vector;   -- Resultado (Acumulador)
        RegStatus : out status_vector  -- Flags de estado
    );
end entity ALU;
```

---

## Flags de estado (RegStatus)

`RegStatus[7:0] = ( C, H, V, Z, G, E, R, L )`

| Bit | Flag | Nombre | Descripción |
|:---:|:----:|:---|:---|
| 7 | `C` | Carry/Borrow | Desbordamiento sin signo en sumas; préstamo en restas. Para `MUL`/`MUH`: si el producto > 255. |
| 6 | `H` | Half-Carry/Borrow | Acarreo/préstamo en el nibble bajo (bits 3→4). |
| 5 | `V` | Overflow | Desbordamiento con signo (complemento a 2). |
| 4 | `Z` | Zero | El resultado es `0x00`. En `CMP` refleja `A-B == 0`. |
| 3 | `G` | Greater | `signed(A) > signed(B)`. Calculado en **todas** las operaciones. |
| 2 | `E` | Equal | `A = B`. Calculado en **todas** las operaciones. |
| 1 | `R` | Bit desplazado (right) | Bit 0 de A desplazado en `LSR` y `ASR`. |
| 0 | `L` | Bit desplazado (left) | Bit 7 de A desplazado en `LSL` y `ASL`. |

---

## Operaciones

### Aritméticas

| Mnemónico | Opcode (bin) | Opcode (hex) | Operación | Flags adicionales |
|:---:|:---:|:---:|:---|:---|
| `ADD`  | `00001` | `0x01` | `ACC ← A + B` | C, H, V, Z |
| `ADC`  | `00010` | `0x02` | `ACC ← A + B + Cin` | C, H, V, Z |
| `SUB`  | `00011` | `0x03` | `ACC ← A - B` | C(borrow), H(borrow), V, Z |
| `SBB`  | `00100` | `0x04` | `ACC ← A - B - Cin` | C(borrow), H(borrow), V, Z |
| `NEG`  | `10000` | `0x10` | `ACC ← −A` (complemento a dos: 0−A) | C(borrow), H(borrow), V, Z |
| `INC`  | `01001` | `0x09` | `ACC ← A + 1` | C, H, V, Z |
| `DEC`  | `01010` | `0x0A` | `ACC ← A - 1` | C(borrow), H(borrow), V, Z |
| `INCB` | `11010` | `0x1A` | `ACC ← B + 1` (UC enruta resultado a B) | C, H, V, Z |
| `DECB` | `11011` | `0x1B` | `ACC ← B - 1` (UC enruta resultado a B) | C(borrow), H(borrow), V, Z |
| `MUL`  | `10101` | `0x15` | `ACC ← (A × B)[7:0]` | C si producto > 255, Z |
| `MUH`  | `10110` | `0x16` | `ACC ← (A × B)[15:8]` | C si byte alto ≠ 0, Z |

### Desplazamiento y rotación

| Mnemónico | Opcode (bin) | Opcode (hex) | Operación | Flags adicionales |
|:---:|:---:|:---:|:---|:---|
| `LSL`  | `00101` | `0x05` | `ACC ← A(6:0) & '0'` | L, Z |
| `LSR`  | `00110` | `0x06` | `ACC ← '0' & A(7:1)` | R, Z |
| `ROL`  | `00111` | `0x07` | `ACC ← A(6:0) & A(7)` | Z |
| `ROR`  | `01000` | `0x08` | `ACC ← A(0) & A(7:1)` | Z |
| `ASL`  | `01111` | `0x0F` | `ACC ← A(6:0) & '0'` (aritmético) | V si cambia signo, L, Z |
| `ASR`  | `11000` | `0x18` | `ACC ← A(7) & A(7:1)` (aritmético) | R, Z |
| `SWAP` | `11001` | `0x19` | `ACC ← A(3:0) & A(7:4)` | Z |

> **ASL vs LSL:** producen el mismo resultado en bits, pero ASL activa el flag V cuando el bit de signo cambia (desbordamiento en multiplicación ×2 con signo).

### Lógicas

| Mnemónico | Opcode (bin) | Opcode (hex) | Operación | Flags adicionales |
|:---:|:---:|:---:|:---|:---|
| `AND`  | `01011` | `0x0B` | `ACC ← A AND B` | Z |
| `OR`   | `01100` | `0x0C` | `ACC ← A OR B` | Z |
| `XOR`  | `01101` | `0x0D` | `ACC ← A XOR B` | Z |
| `NOT`  | `01110` | `0x0E` | `ACC ← NOT A` | Z |

### Transferencia y control

| Mnemónico | Opcode (bin) | Opcode (hex) | Operación | Flags adicionales |
|:---:|:---:|:---:|:---|:---|
| `NOP`  | `00000` | `0x00` | Sin operación | — |
| `PA`   | `10001` | `0x11` | `ACC ← A` | Z |
| `PB`   | `10010` | `0x12` | `ACC ← B` | Z |
| `CL`   | `10011` | `0x13` | `ACC ← 0x00` | Z=1 |
| `SET`  | `10100` | `0x14` | `ACC ← 0xFF` | Z=0 |
| `CMP`  | `10111` | `0x17` | Compara A-B, ACC no cambia | C, H, V, Z |

---

## Convención Carry/Borrow en restas

En operaciones de resta (`SUB`, `SBB`, `DEC`, `CMP`), el flag **C** sigue la convención:

- `C = 1` → no hubo borrow (resultado ≥ 0 en aritm. signed extendida a 9 bits)
- `C = 0` → hubo borrow (resultado < 0 en aritm. signed extendida a 9 bits)

Esto es equivalente a `C = NOT borrow`, habitual en arquitecturas como ARM.
