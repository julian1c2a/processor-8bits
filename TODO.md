# TODO - Tareas Pendientes del Procesador

Este archivo lista las funcionalidades de la ISA v0.6 que aún no están implementadas en la Unidad de Control (`ControlUnit.vhdl`).

---

## Prioridad Alta (Funcionalidad Básica Faltante)

- [x] **Instrucciones de 16 bits (`ADD16`, `SUB16`)**
  - [x] Opcodes `0xE1` (#nn) y `0xE3` (#nn) implementados.
  - [x] Variantes inmediatas cortas `0xE0` (#n) y `0xE2` (#n) implementadas.
  - [x] Reutilización del AddressPath y lógica de flags completada.

- [x] **Instrucciones con Carry (`ADC`, `SBB`)**
  - [x] Opcodes `0x91`, `0x93`, `0xA1`, `0xA3`.
  - [x] Implementado en ControlUnit. DataPath ya conectaba Carry_in a RegF(C), y la ALU discrimina internamente si usarlo o no según el opcode.

## Prioridad Media (Completar Sets de Instrucciones Faltantes)

Muchas instrucciones están definidas en la ISA pero aún no tienen entrada en el `case` del decodificador de la UC.

- [x] **Operaciones Lógicas (`XOR`)**
  - [x] Opcodes `0x96`, `0xA6` implementados.

- [ ] **Instrucciones de Pila para B (`PUSH B`, `POP B`)**
  - [ ] Opcodes `0x61`, `0x65`.
    - [ ] Falta añadir los opcodes al decodificador y configurar `Out_Sel` (para PUSH) y `Write_B` (para POP) en los estados de ejecución existentes.

- [ ] **Operaciones Unarias Faltantes**
  - [ ] `INC B` (0xC4), `DEC B` (0xC5).
  - [ ] `CLR A` (0xC6), `SET A` (0xC7), `SWAP A` (0xCE).
  - [ ] Requieren añadir opcodes y configurar el `ALU_Op` correcto en el estado `S_EXEC_ALU_UNARY`.

- [ ] **Instrucciones de Control de Flags (`SEC`, `CLC`)**
  - [ ] Opcodes `0x02`, `0x03`.
  - [ ] Requiere una forma de que la UC modifique directamente el registro de flags, posiblemente a través de una operación especial en la ALU o una nueva señal de control.

- [ ] **Manipulación del Stack Pointer (`LD SP`, `ST SP`)**
  - [ ] Opcodes `0x50`-`0x53`.
  - [ ] Requiere cargar el SP desde un inmediato o desde A:B, y guardar el SP en A.

- [ ] **Saltos a Registros (`JP A:B`)**
  - [ ] Opcode `0x74`.
  - [ ] Requiere una nueva ruta de datos para cargar el PC desde el par de registros A:B.

- [ ] **Saltos y Llamadas Indirectas (`JP ([nn])`, `CALL ([nn])`)**
  - [ ] Opcodes `0x73`, `0x76`.
  - [ ] Requiere leer una dirección de memoria y luego usarla como destino.

- [ ] **Salto Relativo Incondicional (`JR rel8`)**
  - [ ] Opcode `0x71`.
  - [ ] Similar a `BEQ` pero sin comprobar condición (siempre tomado).

## Prioridad Baja (Optimizaciones y Arquitectura Avanzada v0.6)

Estas características están definidas en la ISA pero requieren cambios estructurales significativos o son optimizaciones sobre la arquitectura actual.

- [x] **Interrupciones Básicas (`IRQ`, `NMI`)**
  - [x] Lógica de prioridad, registro `I`, secuencia de entrada (Push PC/F) y vectores implementada.
  - [x] Instrucciones `SEI`, `CLI`, `RTI` implementadas.

- [ ] **Pipeline de 2 Etapas (`DECODE | EXEC+WB`)**
  - [ ] Reestructurar la `ControlUnit` y el `DataPath` para incluir registros de pipeline.
  - [ ] Implementar lógica de **forwarding** para evitar stalls.

- [ ] **Especulación de Dirección BRAM**
  - [ ] Modificar la FSM para emitir direcciones a la BRAM durante la etapa de decodificación.

- [ ] **BRAM True Dual-Port (TDP)**
  - [ ] Separar el acceso a la pila (Stack) a un puerto de memoria dedicado para paralelizar `PUSH`/`POP` con otras operaciones.

- [ ] **Link Register (LR) y `BSR`/`RET LR`**
  - [ ] Añadir el registro LR al `AddressPath`.
  - [ ] Implementar la lógica para `BSR` (Branch to Subroutine) y `RET LR`.

- [ ] **Return Address Stack (RAS)**
  - [ ] Implementar la pila hardware de 4 niveles para la predicción de saltos de `RET`.
