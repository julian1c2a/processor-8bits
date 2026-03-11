# Processor Top Level

La entidad `Processor_Top` integra los subsistemas principales para formar el núcleo completo del procesador. Implementa la arquitectura de **Doble Datapath** descrita en la ISA v0.6.

## Estructura del Sistema

El diseño separa limpiamente el flujo de datos (8 bits) del flujo de control/direcciones (16 bits), orquestados por una Unidad de Control central.

### Jerarquía

* **Processor_Top**
  * `ControlUnit` (Cerebro): Genera señales de control basadas en instrucciones y flags.
  * `AddressPath` (Direcciones 16-bit): Gestiona PC, SP y direccionamiento.
  * `DataPath` (Datos 8-bit): Gestiona ALU y registros generales.

## Interconexión Interna

1. **Bus de Control (`CtrlBus`):** Un registro (record) masivo que transporta todas las micro-órdenes desde la UC hacia los dataregions. Definido en `ControlUnit_pkg`.
2. **Flags (`s_Flags`):** Feedback desde el DataPath (ALU) hacia la UC para la toma de decisiones (saltos condicionales).
3. **Índice B (`s_DataPath_IndexB`):** Conexión directa desde el registro B del DataPath hacia el sumador EA del AddressPath para permitir direccionamiento indexado (`[nn+B]`).
4. **PC (`s_AddressPath_PC`):** Conexión desde el PC del AddressPath hacia el DataPath para permitir guardar la dirección de retorno en la pila (`PUSH PC` durante `CALL`).

## Interfaz Externa

| Puerto | Tipo | Descripción |
|---|---|---|
| `clk`, `reset` | Entrada | Reloj del sistema y reinicio global (activo alto). |
| `MemAddress` | Salida (16b) | Dirección de memoria física. |
| `MemData_In` | Entrada (8b) | Bus de lectura de memoria. |
| `MemData_Out` | Salida (8b) | Bus de escritura de memoria. |
| `Mem_WE` / `RE` | Salida (1b) | Control de escritura/lectura de memoria. |
| `IO_WE` / `RE` | Salida (1b) | Control para espacio de I/O (puertos). |

## Mapa de Memoria (Resumen)

* `0x0000 - 0xFFFF`: Espacio de direccionamiento de 64KB.
* I/O mapeado independientemente (instrucciones `IN`/`OUT`).
* Stack: Crecimiento descendente, inicializado típicamente en `0xFFFE`.
* Vector de Reset: `0x0000`.
