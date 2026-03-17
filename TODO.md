# TODO - Tareas Pendientes del Procesador

Este archivo lista el estado de implementación de la ISA v0.8 en la Unidad de Control (`ControlUnit.vhdl`).

---

## Completado en v0.7

- [x] **Interrupciones Básicas (`IRQ`, `NMI`)**
  - [x] Lógica de prioridad, registro `I`, secuencia de entrada (Push PC/F) y vectores.
  - [x] Instrucciones `SEI`, `CLI`, `RTI`.

- [x] **Pipeline de 4 Etapas (`FETCH | DECODE | EXEC | WB`)**
  - [x] Registros de pipeline IF/ID e ID/EX (`Pipeline_pkg.vhdl`).
  - [x] Solapamiento FETCH+EXEC para instrucciones ALU de 1 ciclo.
  - [x] Detección de hazards RAW con stalls.
  - [x] Flush de pipeline en saltos tomados y ramas.
  - [x] Sub-FSM DECODE (`dss`) para instrucciones multi-byte (1/2/3 bytes).
  - [x] Sub-FSM EXEC (`ess`) para instrucciones multi-ciclo (CALL, RET, PUSH, POP…).

- [x] **Testbenches de sistema (`Processor_Top_tb.vhdl`) — TB-01 a TB-13: ALL PASS (v0.7)**
  - [x] TB-01 @1415ns — Instrucciones unarias (NOT, NEG, INC, DEC, CLR, SET, SWAP).
  - [x] TB-02 @1825ns — ALU registro (ADD, ADC, SUB, SBB, AND, OR, XOR, CMP, MUL, MUH).
  - [x] TB-03 @1345ns — ALU inmediato.
  - [x] TB-04 @1325ns — Desplazamientos y rotaciones (LSL, LSR, ASL, ASR, ROL, ROR).
  - [x] TB-05 @1795ns — Cargas y almacenamientos (modos: #n, [n], [nn], [B], [nn+B]).
  - [x] TB-06 @1585ns — Saltos incondicionales (JP nn, JR, JPN, JP([nn]), JP A:B).
  - [x] TB-07 @2515ns — Saltos condicionales (BEQ..BEQ2).
  - [x] TB-08 @1025ns — CALL/RET.
  - [x] TB-09 @1125ns — PUSH/POP (A, B, F, A:B).
  - [x] TB-10 @935ns  — Stack Pointer (LD SP, RD SP_L/H).
  - [x] TB-11 @1495ns — ADD16/SUB16.
  - [x] TB-12 @1615ns — Interrupciones IRQ y NMI con RTI.
  - [x] TB-13 @515ns  — Pipeline hazards: stall RAW (LD A→ADD #0) y flush (JP sobre INC A).

---

## Completado en v0.8

- [x] **Infraestructura de Forwarding / Bypassing**
  - [x] Puerto `Fwd_A_En` / `Fwd_A_Data` añadido a `DataPath` y `DataPath_pkg`.
  - [x] Campo `Fwd_A_En` añadido a `control_bus_t` e `INIT_CTRL_BUS` en `ControlUnit_pkg`.
  - [x] Señal `s_fwd_a_data` cableada en `Processor_Top` (alimentada desde `RegA`).
  - [x] Mux de forwarding integrado en el DataPath; transparente por defecto (`Fwd_A_En='0'`).

- [x] **Solapamiento DECODE+EX para instrucciones de 1B/1 ciclo**
  - [x] Función helper `is_1byte_single_f()` identificando los 32 opcodes elegibles.
  - [x] Condición DECODE ampliada: acepta avanzar cuando `r_ID_EX.is_single='1'`.
  - [x] Variable `v_did_decode_1byte` para trigger de captura anticipada del opcode siguiente.
  - [x] Captura directa de `InstrIn` en `r_IF_ID` tras decodificar instrucción 1B/1ciclo.
  - [x] `comb_proc` ampliado: pre-fetch solapado en prioridades 2 y 4.
  - [x] Throughput de **1 ciclo/instrucción** en cadenas consecutivas de ALU registro/unario.

- [x] **Testbenches — TB-01 a TB-13: ALL PASS (v0.8)**
  - [x] TB-01 @1285ns — Instrucciones unarias (−130 ns respecto a v0.7).
  - [x] TB-02 @1705ns — ALU registro (−120 ns).
  - [x] TB-03 @1325ns — ALU inmediato (sin cambio).
  - [x] TB-04 @1195ns — Desplazamientos y rotaciones (−130 ns).
  - [x] TB-05 @1755ns — Cargas y almacenamientos (sin cambio significativo).
  - [x] TB-06 @1465ns — Saltos incondicionales (sin cambio significativo).
  - [x] TB-07 @2205ns — Saltos condicionales (−310 ns).
  - [x] TB-08 @995ns  — CALL/RET (sin cambio significativo).
  - [x] TB-09 @1105ns — PUSH/POP (sin cambio significativo).
  - [x] TB-10 @935ns  — Stack Pointer (sin cambio).
  - [x] TB-11 @1495ns — ADD16/SUB16 (sin cambio).
  - [x] TB-12 @1615ns — Interrupciones IRQ y NMI con RTI (sin cambio).
  - [x] TB-13 @515ns  — Pipeline hazards (sin cambio).

- [x] **Simulador Python actualizado a v0.8**
  - [x] Constante `_1BYTE_SINGLE_OPCODES` en `sim/cpu.py` (32 opcodes, espejo de `is_1byte_single_f`).
  - [x] Estado `_prev_1byte_single` y acumulador `total_cycles` en `CPU`.
  - [x] Modelo de ciclos: primera instrucción 1B/1ciclo = 2 ciclos; cada siguiente en cadena = 1 ciclo.
  - [x] `show_regs()` en `sim/display.py` muestra `∑ N ciclos` acumulados.
  - [x] `_cmd_run()` en `sim/cli.py` imprime resumen de ciclos del programa al finalizar.

- [x] **Documentación**
  - [x] `processor/ControlUnit.md` — documento técnico completo de la Control Unit.
  - [x] Archivos `.pyc` eliminados del historial del repositorio; `.gitignore` ya los excluye.

---

## Completado en v0.9

- [x] **Direct-decode desde InstrIn — eliminación de burbuja post-2-byte-single**
  - [x] Función `build_1byte_id_ex_f()` para decodificar los 32 opcodes 1B/1ciclo en un solo paso.
  - [x] Refactor DSS_OPCODE: 12 `when` individuales reemplazados por un `when` compuesto + llamada a la función.
  - [x] Bloque "direct-decode from InstrIn": cuando EX ejecuta una instrucción `is_single` y `r_IF_ID` está vacío (situación post-2-byte), y el opcode en `InstrIn` es `is_1byte_single`, se decodifica directamente en `r_ID_EX` sin pasar por el latch `r_IF_ID`. Eliminación de **1 ciclo de burbuja** en cada secuencia 2B/1ciclo → 1B/1ciclo.
  - [x] Instrucciones cubiertas como "2-byte single" que activan la optimización: `LD A,#n` (0x11), `LD B,#n` (0x21), ALU inmediato `0xA0..0xA7`.

- [x] **Testbenches — TB-01 a TB-13: ALL PASS (v0.9)**
  - [x] TB-01 @1285ns — Instrucciones unarias (=v0.8, sin secuencias 2B→1B en este test).
  - [x] TB-02 @1705ns — ALU registro (=v0.8).
  - [x] TB-03 @1325ns — ALU inmediato (=v0.8).
  - [x] TB-04 @1195ns — Desplazamientos y rotaciones (=v0.8).
  - [x] TB-05 @1755ns — Cargas y almacenamientos (=v0.8).
  - [x] TB-06 @1465ns — Saltos incondicionales (=v0.8).
  - [x] TB-07 @2205ns — Saltos condicionales (=v0.8).
  - [x] TB-08 @995ns  — CALL/RET (=v0.8).
  - [x] TB-09 @1105ns — PUSH/POP (=v0.8).
  - [x] TB-10 @935ns  — Stack Pointer (=v0.8).
  - [x] TB-11 @1495ns — ADD16/SUB16 (=v0.8).
  - [x] TB-12 @1615ns — Interrupciones IRQ y NMI con RTI (=v0.8).
  - [x] TB-13 @515ns  — Pipeline hazards (=v0.8).

- [x] **Simulador Python actualizado a v0.9**
  - [x] Constante `_2BYTE_SINGLE_OPCODES` en `sim/cpu.py`: `0x11`, `0x21`, `0xA0..0xA7`.
  - [x] Estado `_prev_2byte_single` en `CPU.soft_reset()`.
  - [x] Modelo de ciclos extendido: instrucción 1B/1ciclo tras 2B/1ciclo también cuesta 1 ciclo.

---

## Completado en v0.10

- [x] **Forwarding activo EX→EX**
  - [x] Detección de dependencia RAW A en el bloque DECODE: `r_ID_EX.writes_a = '1'` AND `reads_a_f(I2) = '1'` → `Fwd_A_En='1'` en el ctrl del nuevo r_ID_EX.
  - [x] Ruta de solapamiento DECODE+EX (DSS_OPCODE compound when): usa variable `v_new_id_ex := build_1byte_id_ex_f(opcode)`, aplica la condición de forwarding, asigna a r_ID_EX.
  - [x] Ruta direct-decode (bloque post-FETCH): misma detección para la optimización v0.9.
  - [x] `Fwd_A_Data` ya estaba conectado a `s_DataPath_RegA = RegA` (valor correcto tras el flanco de reloj); el mux `ALU_OpA = Fwd_A_Data if Fwd_A_En='1' else RegA` opera con el valor actualizado en ambos casos → transparente para los tests existentes.
  - [x] TB-01..13 ALL PASS (timestamps idénticos a v0.9).

- [x] **Suite de tests Python (sim/tests/) — 323 tests, ALL PASS**
  - [x] `sim/tests/__init__.py` — marcador de paquete.
  - [x] `sim/tests/test_cpu_alu.py` — 12 clases, tests unitarios de cada operación ALU via `CPU.step()`.
  - [x] `sim/tests/test_assembler.py` — tests de `assemble_line()` y ciclo `feed()`/`link()` para toda la ISA.
  - [x] `sim/tests/test_programs.py` — porta los 13 programas de `Processor_Top_tb.vhdl` al simulador Python; verifica las mismas condiciones PASS que el VHDL.
  - [x] 1 expected failure documentado: `OUT #n, A` (bug conocido en el parser del ensamblador).

- [x] **Bugs corregidos en el simulador Python**
  - [x] `sim/alu.py` — `ref_ROL`/`ref_ROR`: rotación circular → rotación a través de carry (C flag correcto).
  - [x] `sim/cpu.py` — ROL/ROR: pasan `get_C()` como `cin` a la ALU.
  - [x] `sim/cpu.py` — `_handle_interrupt`: lee el vector de interrupción **antes** del `push16`, evitando sobreescribir el vector NMI (0xFFFA) cuando SP=0xFFFE.

---

## Pendiente — Optimizaciones Avanzadas (v0.11+)

- [ ] **Stall RAW restante: LD A,[n] → ADD**
  - [ ] Permitir FETCH durante los últimos ciclos de ESS para reducir la latencia post-multi-ciclo.
  - [ ] Actualmente: fin de ESS → FETCH (1 ciclo) → DECODE (1 ciclo) → EXEC. Potencial: solapar FETCH con el último ciclo de ESS.

- [ ] **Especulación de Dirección BRAM**
  - [ ] Emitir la dirección al bus en el último ciclo de DECODE para modos `[n]`, `[B]`, stack.
  - [ ] Ganancia estimada: −1 ciclo en `LD/ST [n]`, `PUSH`/`POP`.

- [ ] **BRAM True Dual-Port (TDP)**
  - [ ] Port B exclusivo para la pila (stack) — permite solapar push/pop con fetch.
  - [ ] `CALL nn` baja de 6 a 4 ciclos, `RET` de 3 a 2 ciclos.

- [ ] **Link Register (LR) y `BSR`/`RET LR`**
  - [ ] LR ya existe en `AddressPath`. Falta cablear `Load_LR` desde la UC pipeline.
  - [ ] Instrucción `BSR rel8` (opcode `0xF0`): 2 bytes, 4 ciclos.
  - [ ] Instrucción `RET LR` (opcode `0xF1`): 1 byte, 1 ciclo.

- [ ] **Return Address Stack (RAS)**
  - [ ] Pila hardware de 4 entradas para predicción especulativa de `RET`.

- [ ] **PUSH LR / POP LR**
  - [ ] Opcodes provisionales `0x68`/`0x69`. Actualizar §7.3, §8, §9 y §11 de ISA.md.
