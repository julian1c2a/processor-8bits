# VHDL 8-bit Processor

Implementación de un procesador de 8 bits con una arquitectura de conjunto de instrucciones (ISA) personalizada, diseñado en VHDL (estándar 2008).

El diseño sigue las mejores prácticas de la industria, incluyendo una arquitectura de doble datapath, pipeline, y un sistema de paquetes VHDL modular y parametrizable para facilitar el mantenimiento y la escalabilidad.

## Características de la Arquitectura (ISA v0.7)

* **Arquitectura Acumulador:** El registro `A` (R0) actúa como operando principal y destino.
* **Banco de Registros:** 8 registros de 8 bits de propósito general (R0-R7).
* **Doble Datapath:**
  * **Data Path (8 bits):** Gestiona la ALU y el banco de registros.
  * **Address Path (16 bits):** Gestiona el PC, SP y el cálculo de direcciones efectivas.
* **Pipeline de 4 Etapas:** `FETCH | DECODE | EXEC | WB` con detección de hazards RAW y stalls. Forwarding planificado para v0.8.
* **Especulación de Dirección:** Optimización para accesos a BRAM (memoria interna de la FPGA).
* **Stack de 16 bits:** Operaciones `PUSH`/`POP` de palabra completa para mayor eficiencia.
* **Frecuencia Objetivo:** 450 MHz en dispositivos Artix-7 (Nexys 7 100T).

---

## Estado Actual de la Implementación

La implementación VHDL actual (v0.7) incluye la infraestructura hardware completa (DataPath, AddressPath, ALU) y una Unidad de Control con **pipeline de 4 etapas** que cubre toda la ISA:

* **Carga/Almacenamiento:** Registros (A, B), Inmediato (#n), Absoluto ([nn]), Página Cero ([n]), Indexado ([nn+B]) e Indirecto ([B]).
* **Operaciones ALU:** Aritméticas (ADD, SUB, ADC, SBB), Lógicas (AND, OR, XOR, NOT), Comparación (CMP), Incremento/Decremento (INC, DEC, INC B, DEC B), Negación (NEG), Desplazamientos y Rotaciones, Multiplicación.
* **Flujo de Control:** Saltos incondicionales (JP nn, JR rel8, JPN, JP A:B, JP([nn])) y toda la familia de saltos condicionales (BEQ, BNE, BCS, BCC, BVS, BVC, BGT, BLE, BGE, BLT, BHC, BEQ2).
* **Pila (Stack):** PUSH/POP de registros (A, B, F) y pares (A:B).
* **Subrutinas:** `CALL nn`, `CALL([nn])`, `RET`.
* **Interrupciones:** `IRQ`, `NMI`, `RTI`, `SEI`, `CLI`.
* **E/S:** `IN`/`OUT` con direccionamiento inmediato e indirecto.
* **Aritmética 16 bits:** `ADD16`/`SUB16` con operando inmediato de 8 o 16 bits.
* **Pipeline:** Registros IF/ID e ID/EX explícitos (`Pipeline_pkg.vhdl`), solapamiento FETCH+EXEC para instrucciones de 1 ciclo, stalls RAW, flush en saltos.

Las optimizaciones avanzadas (forwarding, TDP stack, BSR/RET LR, RAS) están planificadas para v0.8+

---

## Documentación de la Arquitectura

La documentación técnica detallada de cada subsistema se encuentra en los siguientes archivos:

* **ISA - Conjunto de Instrucciones:** La especificación completa del procesador, incluyendo modos de direccionamiento, mapa de memoria y opcodes.

### Módulos Hardware

1. **Processor Top Level:** Describe la integración de los componentes principales.
2. **Data Path (8-bit):** Explica el funcionamiento del banco de registros, la ALU y el bus de datos.
3. **Address Path (16-bit):** Detalla la gestión del PC, SP y el sumador de direcciones.
4. **ALU (Unidad Aritmético-Lógica):** Especificación de las operaciones y flags de la ALU.

---

## Estructura del Proyecto

```
├── processor/          # Código fuente VHDL de los componentes del procesador
│   ├── Processor_Top.vhdl
│   ├── ControlUnit.vhdl
│   ├── DataPath.vhdl
│   ├── AddressPath.vhdl
│   ├── ALU.vhdl
│   └── *.pkg.vhdl      # Paquetes de definiciones y constantes
│
├── testbenchs/         # Testbenches y herramientas de simulación
│   ├── ALU_exhaustive_tb.vhdl
│   ├── Processor_Top_tb.vhdl
│   ├── alu_ref.py      # Oráculo de referencia en Python
│   └── vectors/        # Vectores de prueba generados (no versionados)
│
└── *.md                # Documentación en formato Markdown
```

## Verificación y Pruebas

El proyecto utiliza un sistema de verificación exhaustivo para la ALU (con oráculo en Python) y un testbench de sistema (`Processor_Top_tb.vhdl`) que carga y ejecuta programas de prueba para validar la integración de los componentes y la lógica de control.

### Estado de Verificación — ISA v0.7

| # | Testbench | Tiempo PASS | Qué verifica |
|:---:|:---|:---:|:---|
| TB-01 | Instrucciones unarias | @1415 ns | NOT, NEG, INC, DEC, CLR, SET, SWAP |
| TB-02 | ALU registro | @1825 ns | ADD, ADC, SUB, SBB, AND, OR, XOR, CMP, MUL, MUH |
| TB-03 | ALU inmediato | @1345 ns | Variantes `#n` de las operaciones ALU |
| TB-04 | Desplazamientos/rotaciones | @1325 ns | LSL, LSR, ASL, ASR, ROL, ROR |
| TB-05 | Cargas y almacenamientos | @1795 ns | LD/ST modos: `#n`, `[n]`, `[nn]`, `[B]`, `[nn+B]` |
| TB-06 | Saltos incondicionales | @1585 ns | JP nn, JR rel8, JPN, JP([nn]), JP A:B |
| TB-07 | Saltos condicionales | @2515 ns | BEQ, BNE, BCS, BCC, BVS, BVC, BGT, BLE, BGE, BLT, BHC, BEQ2 |
| TB-08 | CALL / RET | @1025 ns | Llamadas a subrutina y retorno |
| TB-09 | PUSH / POP | @1125 ns | PUSH/POP de A, B, F y par A:B |
| TB-10 | Stack Pointer | @935 ns | LD SP, RD SP\_L/H |
| TB-11 | ADD16 / SUB16 | @1495 ns | Aritmética de 16 bits sobre el par A:B |
| TB-12 | Interrupciones IRQ/NMI | @1615 ns | Secuencia ESS\_INT, RTI, vectores 0xFFFE/0xFFFA |
| TB-13 | Pipeline hazards | @515 ns | Stall RAW (LD A→ADD) y flush de salto tomado (JP) |

**ALU exhaustiva:** 28/28 operaciones PASS · ~2 millones de vectores (oráculo Python).

* **Detalles de los Testbenches:** ver [`testbenchs/README-TB.md`](testbenchs/README-TB.md)

---

## Licencia

Este proyecto se distribuye bajo la licencia MIT. Ver el archivo `LICENSE` para más detalles.

Copyright (c) 2026 MICROELECTRÓNICA26.UMA.EII

---
