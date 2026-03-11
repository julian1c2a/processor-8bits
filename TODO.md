# TODO - Tareas Pendientes del Procesador

Este archivo lista las funcionalidades de la ISA v0.6 que aún no están implementadas en la Unidad de Control (`ControlUnit.vhdl`).

---

## Prioridad Alta (Funcionalidad Básica Faltante)

- [ ] **Instrucciones de 16 bits (`ADD16`, `SUB16`)**
  - [ ] Opcodes `0xE0` - `0xE3`.
  - [ ] Requiere configurar el `AddressPath` para usar el sumador EA como ALU de 16 bits sobre el par de registros A:B.
  - [ ] La UC debe gestionar la lectura de operandos de 8 o 16 bits y escribir el resultado de 16 bits de vuelta en A (alto) y B (bajo).
  - [ ] Implementar la lógica de flags de 16 bits (C, V, Z).

- [x] **Instrucciones con Carry (`ADC`, `SBB`)**
  - [x] Opcodes `0x91`, `0x93`, `0xA1`, `0xA3`.
  - [x] Implementado en ControlUnit. DataPath ya conectaba Carry_in a RegF(C), y la ALU discrimina internamente si usarlo o no según el opcode.

## Prioridad Media (Completar Sets de Instrucciones)

- [ ] **Operaciones Lógicas Faltantes (`XOR`)**
  - [ ] Opcodes `0x96`, `0xA6`, `0xB6`, `0xBC`.
  - [ ] Añadir la decodificación y configuración de la ALU para `OP_XOR`.

- [ ] **Instrucciones de Pila para B (`PUSH B`, `POP B`)**
  - [ ] Opcodes `0x61`, `0x65`.
  - [ ] La lógica de PUSH/POP ya es genérica, solo falta añadir los opcodes al decodificador y configurar `Out_Sel` y `Write_B`.

- [ ] **Instrucciones de Control de Flags (`SEC`, `CLC`)**
  - [ ] Opcodes `0x02`, `0x03`.
  - [ ] Requiere una forma de que la UC modifique directamente el registro de flags, posiblemente a través de una operación especial en la ALU o una nueva señal de control.

- [ ] **Saltos a Registros (`JP A:B`)**
  - [ ] Opcode `0x74`.
  - [ ] Requiere una nueva ruta de datos para cargar el PC desde el par de registros A:B.

## Prioridad Baja (Optimizaciones y Arquitectura Avanzada v0.6)

Estas características están definidas en la ISA pero requieren cambios estructurales significativos o son optimizaciones sobre la arquitectura actual.

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

- [ ] **Interrupciones (`SEI`, `CLI`, `RTI`)**
  - [ ] Añadir la lógica de interrupción a la FSM, incluyendo el guardado automático de contexto.
