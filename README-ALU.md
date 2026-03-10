# ALU 8-bit Operations

This document describes the operations supported by the 8-bit Arithmetic Logic Unit (ALU), based on the implementation in `ALU.vhdl`.

**Note:** The VHDL file is nearly complete. The documentation below reflects what is currently implemented.

## Operands

The ALU operates on two 8-bit registers:

-   **Register A**: `RegInA`
-   **Register B**: `RegInB`

The result of the operations is stored in the `ACC` (Accumulator) register.

---

## Operations

### Core & Comparison Operations

| Operation | Description | Affected Flags (as per `ALU.vhdl`) | Opcode (HEX) |
| :--- | :--- | :--- | :--- |
| `NOP` | No Operation. ACC defaults to `0x00`. | - | `00` |
| `CMP` | Compare `A` with `B` (calculates `A-B`), updates flags but does not alter `ACC`. | `C`, `H`, `V`, `Z` | `17` |

### Arithmetic Operations

| Operation | Description | Affected Flags (as per `ALU.vhdl`) | Opcode (HEX) |
| :--- | :--- | :--- | :--- |
| `ADD` | `ACC <= A + B` | `C`, `H`, `V`, `Z` | `1` |
| `ADC` | `ACC <= A + B + Carry_in` | `C`, `H`, `V`, `Z` | `2` |
| `SUB` | `ACC <= A - B` | `C` (borrow), `H` (borrow), `V`, `Z` | `3` |
| `SBB` | `ACC <= A - B - Carry_in`| `C` (borrow), `H` (borrow), `V`, `Z` | `4` |
| `LSL` | `ACC <= A(6:0) & '0'` | `L`, `Z` | `5` |
| `LSR` | `ACC <= '0' & A(7:1)` | `R`, `Z` | `6` |
| `ROL` | `ACC <= A(6:0) & A(7)` | `Z` | `7` |
| `ROR` | `ACC <= A(0) & A(7:1)` | `Z` | `8` |
| `INC` | `ACC <= A + 1` | `C`, `H`, `V`, `Z` | `9` |
| `DEC` | `ACC <= A - 1` | `C` (borrow), `H` (borrow), `V`, `Z` | `A` |
| `MUL` | `ACC <= (A * B)(7:0)` | `C`, `Z` | `15` |
| `MUH` | `ACC <= (A * B)(15:8)` | `C`, `Z` | `16` |
| `ASR` | `ACC <= A(7) & A(7:1)` | `R`, `Z` | `18` |
| `SWAP`| `ACC <= A(3:0) & A(7:4)` | `Z` | `19` |

### Logical & Transfer Operations

| Operation | Description | Affected Flags (as per `ALU.vhdl`) | Opcode (HEX) |
| :--- | :--- | :--- | :--- |
| `AND` | `ACC <= A AND B` | `Z` | `B` |
| `OR`  | `ACC <= A OR B`  | `Z` | `C` |
| `XOR` | `ACC <= A XOR B` | `Z` | `D` |
| `NOT` | `ACC <= NOT A`   | `Z` | `E` |
| `PA`  | `ACC <= A`       | `Z` | `11` |
| `PB`  | `ACC <= B`       | `Z` | `12` |
| `CL`  | `ACC <= 0x00`    | `Z` | `13` |
| `SET` | `ACC <= 0xFF`    | `Z` | `14` |

### Unimplemented Operations

The following operations are defined but not yet implemented.

| Operation | Description | Opcode (HEX) |
| :--- | :--- | :--- |
| `GT`  | `ACC <= 0x00 if A > B, else 0x01` | `F` |
| `EQ`  | `ACC <= 0x00 if A = B, else 0x01` | `10`|

---

## Status Flags (RegStatus)

The `RegStatus` is an 8-bit register that holds the status flags. Its behavior is determined by the VHDL implementation.

`RegStatus[7:0] = (C, H, V, Z, G, E, R, L)`

| Bit | Flag | Name | VHDL Implementation Details |
|:---:|:----:|:---|:---|
| 7 | `C` | Carry | Set on carry/borrow for arithmetic (`ADD`,`SUB`,`INC`,`DEC`,`CMP`). For `MUL`/`MUH`, set if result > 255. |
| 6 | `H` | Half-Carry | Set on half-carry/borrow for `ADD`, `SUB`, `INC`, `DEC`, `CMP`. |
| 5 | `V` | Overflow | Set on signed overflow for `ADD`, `SUB`, `INC`, `DEC`, `CMP`. |
| 4 | `Z` | Zero | Set if the result is `0x00`. Affected by all operations except `NOP`. For `CMP`, reflects `A-B==0`. |
| 3 | `G` | Greater Than| Set if `signed(A) > signed(B)`. **Note:** Checked on *every cycle* regardless of the operation. |
| 2 | `E` | Equal | Set if `A = B`. **Note:** Checked on *every cycle* regardless of the operation. |
| 1 | `R` | LSR/ASR Bit | Set to the value of `A[0]` during an `LSR` or `ASR` operation. |
| 0 | `L` | LSL Bit | Set to the value of `A[7]` during an `LSL` operation. |
