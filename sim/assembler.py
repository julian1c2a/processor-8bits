# MIT License — Copyright (c) 2026 MICROELECTRÓNICA26.UMA.EII
"""
sim/assembler.py — Ensamblador de una pasada/dos pasadas para ISA v0.7.

Uso básico (REPL, una línea):
    asm = Assembler()
    result = asm.assemble_line("LD A, #0x42", current_pc=0x0200)

Uso programático (dos pasadas con etiquetas):
    asm = Assembler()
    asm.reset(org=0x0200)
    asm.feed("start:  LD A, #0x01")
    asm.feed("        BEQ start")
    binary, listing = asm.link()
"""

from __future__ import annotations
import re
from dataclasses import dataclass, field


# ---------------------------------------------------------------------------
# Tipos resultado
# ---------------------------------------------------------------------------

@dataclass
class AsmLine:
    addr:      int
    label:     str | None
    mnemonic:  str
    encoded:   list              # enteros 0-255
    text:      str               # línea original
    size:      int
    error:     str | None = None

    # Para ramas/BSR que necesitan resolución de etiqueta
    _patch_offset: int | None   = None   # offset dentro de `encoded` a parchear
    _patch_label:  str | None   = None   # nombre de la etiqueta
    _patch_type:   str | None   = None   # 'rel8'

@dataclass
class AsmResult:
    bytes:    list              # lista de int [0,255]
    size:     int
    mnemonic: str
    opcode:   int
    error:    str | None = None


# ---------------------------------------------------------------------------
# Helpers de parseo
# ---------------------------------------------------------------------------

_NUM_RE = re.compile(r'^([+-]?)(0x[0-9a-fA-F]+|0b[01]+|0o[0-7]+|\d+)$', re.IGNORECASE)

def parse_int(s: str) -> int | None:
    """Convierte string a entero; acepta 0x, 0b, 0o, decimal, signos."""
    s = s.strip()
    m = _NUM_RE.match(s)
    s = s.lower()   # normalizar para la conversión
    if m:
        sign_str, val_str = m.group(1), s[len(m.group(1)):]
        if   val_str.startswith('0x'): v = int(val_str, 16)
        elif val_str.startswith('0b'): v = int(val_str, 2)
        elif val_str.startswith('0o'): v = int(val_str, 8)
        else:                          v = int(val_str, 10)
        return -v if sign_str == '-' else v
    return None


def is_label_name(s: str) -> bool:
    return bool(re.match(r'^[a-zA-Z_][a-zA-Z0-9_]*$', s))


# ---------------------------------------------------------------------------
# Tabla de instrucciones
# ---------------------------------------------------------------------------
# Cada entrada: (mnemonic_key: str, operand_form: str, opcode: int)
# mnemonic_key  incluye el registro destino fijo si es parte del mnemónico.
# operand_form  uno de: ''  A  B  F  AB  IMM8  IMM16  ZP  ABS  INDB
#               IDX_ABS  IDX_ZP  REL8  PG8  INDIR  IMM8_A  INDB_A
# ---------------------------------------------------------------------------

_TABLE: list[tuple[str, str, int]] = [
    # Sistema
    ('NOP',        '',        0x00),
    ('HALT',       '',        0x01),
    ('SEC',        '',        0x02),
    ('CLC',        '',        0x03),
    ('SEI',        '',        0x04),
    ('CLI',        '',        0x05),
    ('RTI',        '',        0x06),
    # LD A
    ('LD A',       'B',       0x10),
    ('LD A',       'IMM8',    0x11),
    ('LD A',       'ZP',      0x12),
    ('LD A',       'ABS',     0x13),
    ('LD A',       'INDB',    0x14),
    ('LD A',       'IDX_ABS', 0x15),
    ('LD A',       'IDX_ZP',  0x16),
    # LD B
    ('LD B',       'A',       0x20),
    ('LD B',       'IMM8',    0x21),
    ('LD B',       'ZP',      0x22),
    ('LD B',       'ABS',     0x23),
    ('LD B',       'INDB',    0x24),
    ('LD B',       'IDX_ABS', 0x25),
    # ST A
    ('ST A',       'ZP',      0x30),
    ('ST A',       'ABS',     0x31),
    ('ST A',       'INDB',    0x32),
    ('ST A',       'IDX_ABS', 0x33),
    ('ST A',       'IDX_ZP',  0x34),
    # ST B
    ('ST B',       'ZP',      0x40),
    ('ST B',       'ABS',     0x41),
    ('ST B',       'IDX_ABS', 0x42),
    # SP
    ('LD SP',      'IMM16',   0x50),
    ('LD SP',      'AB',      0x51),
    ('ST SP_L',    'A',       0x52),
    ('ST SP_H',    'A',       0x53),
    # Alias mnemonicos alternativos aceptados
    ('RD SP_L',    '',        0x52),
    ('RD SP_H',    '',        0x53),
    # PUSH / POP
    ('PUSH',       'A',       0x60),
    ('PUSH',       'B',       0x61),
    ('PUSH',       'F',       0x62),
    ('PUSH',       'AB',      0x63),
    ('POP',        'A',       0x64),
    ('POP',        'B',       0x65),
    ('POP',        'F',       0x66),
    ('POP',        'AB',      0x67),
    # Saltos
    ('JP',         'ABS',     0x70),
    ('JR',         'REL8',    0x71),
    ('JPN',        'PG8',     0x72),
    ('JP',         'INDIR',   0x73),
    ('JP A:B',     '',        0x74),
    ('CALL',       'ABS',     0x75),
    ('CALL',       'INDIR',   0x76),
    ('RET',        '',        0x77),
    # Ramas condicionales
    ('BEQ',        'REL8',    0x80),
    ('BNE',        'REL8',    0x81),
    ('BCS',        'REL8',    0x82),
    ('BCC',        'REL8',    0x83),
    ('BVS',        'REL8',    0x84),
    ('BVC',        'REL8',    0x85),
    ('BGT',        'REL8',    0x86),
    ('BLE',        'REL8',    0x87),
    ('BGE',        'REL8',    0x88),
    ('BLT',        'REL8',    0x89),
    ('BHC',        'REL8',    0x8A),
    ('BEQ2',       'REL8',    0x8B),
    # ALU reg A op B
    ('ADD',        '',        0x90),
    ('ADC',        '',        0x91),
    ('SUB',        '',        0x92),
    ('SBB',        '',        0x93),
    ('AND',        '',        0x94),
    ('OR',         '',        0x95),
    ('XOR',        '',        0x96),
    ('CMP',        '',        0x97),
    ('MUL',        '',        0x98),
    ('MUH',        '',        0x99),
    # ALU imm A op #n
    ('ADD',        'IMM8',    0xA0),
    ('ADC',        'IMM8',    0xA1),
    ('SUB',        'IMM8',    0xA2),
    ('SBB',        'IMM8',    0xA3),
    ('AND',        'IMM8',    0xA4),
    ('OR',         'IMM8',    0xA5),
    ('XOR',        'IMM8',    0xA6),
    ('CMP',        'IMM8',    0xA7),
    # ALU mem ZP
    ('ADD',        'ZP',      0xB0),
    ('SUB',        'ZP',      0xB2),
    ('AND',        'ZP',      0xB4),
    ('OR',         'ZP',      0xB5),
    ('XOR',        'ZP',      0xB6),
    ('CMP',        'ZP',      0xB7),
    # ALU mem ABS
    ('ADD',        'ABS',     0xB1),
    ('SUB',        'ABS',     0xB3),
    # ALU mem indexado ABS+B
    ('ADD',        'IDX_ABS', 0xB8),
    ('SUB',        'IDX_ABS', 0xB9),
    ('AND',        'IDX_ABS', 0xBA),
    ('OR',         'IDX_ABS', 0xBB),
    ('XOR',        'IDX_ABS', 0xBC),
    ('CMP',        'IDX_ABS', 0xBD),
    # Unarias
    ('NOT A',      '',        0xC0),
    ('NEG A',      '',        0xC1),
    ('INC A',      '',        0xC2),
    ('DEC A',      '',        0xC3),
    ('INC B',      '',        0xC4),
    ('DEC B',      '',        0xC5),
    ('CLR A',      '',        0xC6),
    ('SET A',      '',        0xC7),
    ('LSL A',      '',        0xC8),
    ('LSR A',      '',        0xC9),
    ('ASL A',      '',        0xCA),
    ('ASR A',      '',        0xCB),
    ('ROL A',      '',        0xCC),
    ('ROR A',      '',        0xCD),
    ('SWAP A',     '',        0xCE),
    # E/S
    ('IN A',       'IMM8',    0xD0),
    ('IN A',       'INDB',    0xD1),
    ('OUT',        'IMM8_A',  0xD2),   # OUT #n, A
    ('OUT',        'INDB_A',  0xD3),   # OUT [B], A
    # ADD16 / SUB16
    ('ADD16',      'IMM8',    0xE0),
    ('ADD16',      'IMM16',   0xE1),
    ('SUB16',      'IMM8',    0xE2),
    ('SUB16',      'IMM16',   0xE3),
    # BSR / RET LR / CALL LR
    ('BSR',        'REL8',    0xF0),
    ('RET LR',     '',        0xF1),
    ('CALL LR',    'ABS',     0xF2),
]

# Construir dict para búsqueda rápida
_LOOKUP: dict[tuple[str,str], int] = {
    (mk.upper(), form): opc for mk, form, opc in _TABLE
}
# Añadir REL8_DIRECT: mismo opcode que REL8 para todas las ramas
for (_mk, _form), _opc in list(_LOOKUP.items()):
    if _form == 'REL8':
        _LOOKUP[(_mk, 'REL8_DIRECT')] = _opc


# ---------------------------------------------------------------------------
# Clase Assembler
# ---------------------------------------------------------------------------

class Assembler:
    def __init__(self):
        self.reset()

    def reset(self, org: int = 0x0000):
        self._pc:     int  = org
        self._org:    int  = org
        self._lines:  list = []        # lista de AsmLine
        self._labels: dict = {}        # name → addr
        self._errors: list = []

    # ------------------------------------------------------------------
    # Interfaz pública
    # ------------------------------------------------------------------

    def assemble_line(self, text: str, current_pc: int) -> AsmResult:
        """Ensambla una sola línea (modo REPL, sin etiquetas forward)."""
        line = self._parse_line(text.strip(), current_pc)
        if line.error:
            return AsmResult(bytes=[], size=0, mnemonic='',
                             opcode=0, error=line.error)
        if line._patch_label:
            return AsmResult(bytes=[], size=0, mnemonic=line.mnemonic,
                             opcode=line.encoded[0] if line.encoded else 0,
                             error='Etiqueta forward no permitida en modo REPL')
        opc = line.encoded[0] if line.encoded else 0
        return AsmResult(bytes=line.encoded, size=line.size,
                         mnemonic=line.mnemonic, opcode=opc, error=None)

    def feed(self, text: str) -> AsmLine | None:
        """Añade una línea al buffer del programa."""
        al = self._parse_line(text.strip(), self._pc)
        if al is None:
            return None
        if al.label:
            self._labels[al.label] = al.addr
        self._lines.append(al)
        self._pc = (self._pc + al.size) & 0xFFFF
        return al

    def link(self) -> tuple[list, list]:
        """Segunda pasada: resuelve etiquetas. Devuelve (bytes, listing)."""
        binary = []
        errors = []
        for al in self._lines:
            if al._patch_label:
                target = self._labels.get(al._patch_label)
                if target is None:
                    al.error = f"Etiqueta no definida: '{al._patch_label}'"
                    errors.append(al)
                else:
                    patch_pc = al.addr + 2   # PC después de la instrucción
                    rel8 = target - patch_pc
                    if not (-128 <= rel8 <= 127):
                        al.error = (f"Salto fuera de rango: {rel8} "
                                    f"(target={target:#06x}, PC={patch_pc:#06x})")
                        errors.append(al)
                    else:
                        al.encoded[al._patch_offset] = rel8 & 0xFF
            binary.extend(al.encoded)
        return binary, list(self._lines)

    @property
    def pc(self) -> int:
        return self._pc

    @property
    def org(self) -> int:
        return self._org

    @property
    def labels(self) -> dict:
        return dict(self._labels)

    @property
    def lines(self) -> list:
        return list(self._lines)

    # ------------------------------------------------------------------
    # Parser interno
    # ------------------------------------------------------------------

    def _parse_line(self, text: str, pc: int) -> AsmLine:
        original = text
        # Eliminar comentario
        for comment_char in (';', '//'):
            idx = text.find(comment_char)
            if idx >= 0:
                text = text[:idx]
        text = text.strip()

        al = AsmLine(addr=pc, label=None, mnemonic='', encoded=[],
                     text=original, size=0)

        if not text:
            return al         # línea vacía / comentario puro

        # Línea de directiva
        if text.upper().startswith('.ORG'):
            parts = text.split()
            if len(parts) >= 2:
                v = parse_int(parts[1])
                if v is None:
                    al.error = f'Valor inválido para .ORG: {parts[1]}'
                else:
                    self._pc = v & 0xFFFF
                    self._org = self._pc
                    al.addr = self._pc
            return al

        if text.upper().startswith('.BYTE'):
            vals = text.split(None, 1)
            if len(vals) < 2:
                al.error = '.BYTE sin valores'; return al
            bs = []
            for tok in vals[1].split(','):
                v = parse_int(tok.strip())
                if v is None:
                    al.error = f'Valor inválido: {tok.strip()}'; return al
                bs.append(v & 0xFF)
            al.encoded = bs; al.size = len(bs); return al

        if text.upper().startswith('.WORD'):
            vals = text.split(None, 1)
            if len(vals) < 2:
                al.error = '.WORD sin valores'; return al
            ws = []
            for tok in vals[1].split(','):
                v = parse_int(tok.strip())
                if v is None:
                    al.error = f'Valor inválido: {tok.strip()}'; return al
                ws += [v & 0xFF, (v >> 8) & 0xFF]
            al.encoded = ws; al.size = len(ws); return al

        # Extracción de etiqueta al inicio
        lm = re.match(r'^([a-zA-Z_][a-zA-Z0-9_]*):\s*(.*)', text)
        if lm:
            al.label = lm.group(1)
            text = lm.group(2).strip()
            self._labels[al.label] = pc
            if not text:
                return al   # etiqueta sola, sin instrucción

        err = self._encode(text, pc, al)
        if err:
            al.error = err
        return al

    def _encode(self, text: str, pc: int, al: AsmLine) -> str | None:
        """Determina opcode + bytes extra y rellena al.encoded."""
        text = text.strip()
        if not text:
            return None

        # Normalizar espacios alrededor de ,
        text = re.sub(r'\s*,\s*', ', ', text)
        # Normalizar + sólo dentro de corchetes (para [nn+B])
        text = re.sub(r'\[([^\]]*)\]',
                      lambda m: '[' + re.sub(r'\s*\+\s*', '+', m.group(1)) + ']',
                      text)
        text = re.sub(r'\s+', ' ', text)

        upper = text.upper()

        # Identificar la clave del mnemónico (comparación case-insensitive)
        # pero conservar el caso original para el operando (importante para labels)
        mnemonic_key, _ = self._split_mnemonic(upper)
        if mnemonic_key is None:
            return f'Mnemónico desconocido: {text}'
        # operand_str preserva el caso original (necesario para names de etiquetas)
        operand_str = text[len(mnemonic_key):].lstrip(' ,').strip()

        al.mnemonic = text   # texto original para mostrar

        form, val, label_name = self._classify_operand(operand_str, mnemonic_key)

        # Caso especial ADD16/SUB16: auto-selección IMM8 ↔ IMM16
        if mnemonic_key in ('ADD16', 'SUB16') and form in ('IMM8', 'IMM16'):
            form = self._add16_select(val)
            if form is None:
                return f'Valor fuera de rango para ADD16/SUB16: {operand_str}'

        key = (mnemonic_key, form)
        opc = _LOOKUP.get(key)
        if opc is None:
            return (f'Forma de operando "{form}" no válida '
                    f'para "{mnemonic_key}" ({text})')

        # Codificar bytes extra según form
        extra, patch_ofs, patch_lbl, patch_type = self._encode_operand(
            form, val, label_name, pc, opc)
        if isinstance(extra, str):
            return extra   # es un mensaje de error

        al.encoded = [opc] + extra
        al.size    = len(al.encoded)
        if patch_lbl:
            al._patch_offset = 1 + patch_ofs
            al._patch_label  = patch_lbl
            al._patch_type   = patch_type
        return None

    # ------------------------------------------------------------------
    # Identificar split mnemónico / operando
    # ------------------------------------------------------------------

    # Claves ordenadas de mayor a menor longitud para match greedy
    _MNEMONIC_KEYS = sorted(
        {mk.upper() for mk, _, _ in _TABLE},
        key=len, reverse=True
    )

    def _split_mnemonic(self, upper: str) -> tuple[str | None, str]:
        for key in self._MNEMONIC_KEYS:
            if upper == key or upper.startswith(key + ' ') or upper.startswith(key + ','):
                operand = upper[len(key):].lstrip(' ,').strip()
                return key, operand
        return None, upper

    # ------------------------------------------------------------------
    # Clasificar operando → form
    # ------------------------------------------------------------------

    def _classify_operand(self, op: str, mkey: str) -> tuple[str, int | None, str | None]:
        """
        Devuelve (form, value_int_or_None, label_name_or_None).
        value_int es None si se usa label_name.
        """
        op = op.strip()
        op_upper = op.upper()

        if not op:
            return '', None, None

        # Registros sueltos (case-insensitive)
        if op_upper == 'A':  return 'A',  None, None
        if op_upper == 'B':  return 'B',  None, None
        if op_upper == 'F':  return 'F',  None, None
        if op_upper in ('A:B', 'AB'):  return 'AB', None, None

        # Forma  #n  (inmediato)
        if op.startswith('#'):
            v = parse_int(op[1:])
            if v is None:
                return '?', None, None
            v &= 0xFFFF
            if 0 <= v <= 0xFF:
                return 'IMM8', v, None
            return 'IMM16', v, None

        # Forma  ([nn])  indirecto absoluto
        m = re.match(r'^\(\[\s*(.+?)\s*\]\)$', op)
        if m:
            v = parse_int(m.group(1))
            if v is None: return '?', None, None
            return 'INDIR', v & 0xFFFF, None

        # Forma  [B]  (case-insensitive)
        if op_upper == '[B]':
            return 'INDB', None, None

        # Forma  [nn+B]  o  [n+B]  (case-insensitive para B)
        m = re.match(r'^\[\s*(.+?)\s*\+\s*[Bb]\s*\]$', op)
        if m:
            v = parse_int(m.group(1))
            if v is None: return '?', None, None
            v &= 0xFFFF
            if v <= 0xFF: return 'IDX_ZP',  v, None
            return 'IDX_ABS', v, None

        # Forma  [n]  o  [nn]
        m = re.match(r'^\[\s*(.+?)\s*\]$', op)
        if m:
            v = parse_int(m.group(1))
            if v is None: return '?', None, None
            v &= 0xFFFF
            if v <= 0xFF: return 'ZP',  v, None
            return 'ABS', v, None

        # Forma  #n, A  (OUT) o [B], A  (case-insensitive para A final)
        m_out = re.match(r'^(.+?),\s*[Aa]$', op)
        if m_out:
            inner = m_out.group(1).strip()
            if inner.startswith('#'):
                v = parse_int(inner[1:])
                if v is not None: return 'IMM8_A', v & 0xFF, None
            if inner.upper() == '[B]':
                return 'INDB_A', None, None

        # Offset directo con signo: +n o -n (para ramas/BSR/JR)
        # Distingue offset directo de dirección absoluta
        if op.startswith('+') or op.startswith('-'):
            v = parse_int(op)
            if v is not None:
                if mkey in ('BEQ','BNE','BCS','BCC','BVS','BVC',
                            'BGT','BLE','BGE','BLT','BHC','BEQ2','BSR','JR'):
                    return 'REL8_DIRECT', v, None

        # Número sin '#' → puede ser ABS, REL8 (como addr), PG8, etc.
        v = parse_int(op)
        if v is not None:
            v_ = v & 0xFFFF
            if mkey in ('BEQ','BNE','BCS','BCC','BVS','BVC',
                        'BGT','BLE','BGE','BLT','BHC','BEQ2','BSR','JR'):
                return 'REL8', v_, None
            if mkey == 'JPN':
                return 'PG8', v_ & 0xFF, None
            if mkey in ('ADD16','SUB16'):
                if 0 <= v_ <= 0xFF: return 'IMM8', v_, None
                return 'IMM16', v_, None
            if v_ <= 0xFF: return 'ZP', v_, None
            return 'ABS', v_, None

        # Etiqueta (preservar case original)
        if is_label_name(op):
            if mkey in ('BEQ','BNE','BCS','BCC','BVS','BVC',
                        'BGT','BLE','BGE','BLT','BHC','BEQ2','BSR','JR'):
                return 'REL8', None, op
            if mkey in ('JP','CALL','CALL LR'):
                return 'ABS', None, op

        return '?', None, None

    # ------------------------------------------------------------------
    # Codificar bytes extra
    # ------------------------------------------------------------------

    def _encode_operand(self, form, val, label_name, pc, opc):
        """
        Devuelve (extra_bytes_list, patch_offset, patch_label, patch_type).
        Si hay error, devuelve (error_str, ...)
        """
        def rel8_bytes(target, label):
            if label:
                return [0x00], 0, label, 'rel8'
            rel = target - (pc + 2)
            if not (-128 <= rel <= 127):
                return (f'Salto fuera de rango rel8: '
                        f'{rel} (target={target:#06x}, PC+2={pc+2:#06x})',
                        None, None, None)
            return [rel & 0xFF], None, None, None

        if form == '':        return [], None, None, None
        if form in ('A','B','F','AB'): return [], None, None, None
        if form == 'IMM8':    return [val & 0xFF], None, None, None
        if form == 'IMM16':   return [val & 0xFF, (val>>8)&0xFF], None, None, None
        if form == 'ZP':      return [val & 0xFF], None, None, None
        if form == 'ABS':
            if label_name:
                return [0x00, 0x00], 0, label_name, 'abs16'
            return [val & 0xFF, (val>>8)&0xFF], None, None, None
        if form == 'INDB':    return [], None, None, None
        if form == 'IDX_ZP':  return [val & 0xFF], None, None, None
        if form == 'IDX_ABS': return [val & 0xFF, (val>>8)&0xFF], None, None, None
        if form == 'INDIR':   return [val & 0xFF, (val>>8)&0xFF], None, None, None
        if form == 'REL8':    return rel8_bytes(val, label_name)
        if form == 'REL8_DIRECT':
            # offset directo ya calculado por el usuario (rel8 = val)
            if val is None: return ('REL8_DIRECT sin valor', None, None, None)
            rel = val if val < 128 else val - 256
            if not (-128 <= rel <= 127):
                return (f'Offset fuera de rango: {rel}', None, None, None)
            return [rel & 0xFF], None, None, None
        if form == 'PG8':     return [val & 0xFF], None, None, None
        if form == 'IMM8_A':  return [val & 0xFF], None, None, None
        if form == 'INDB_A':  return [], None, None, None
        return (f'Forma "{form}" sin implementar', None, None, None)

    # ------------------------------------------------------------------
    # Auto-selección ADD16 / SUB16
    # ------------------------------------------------------------------

    def _add16_select(self, val) -> str | None:
        if val is None:
            return None
        v = val & 0xFFFF
        # Si cabe en byte con signo → IMM8; si no → IMM16
        s = v if v < 0x8000 else v - 0x10000
        if -128 <= s <= 127:
            return 'IMM8'
        if 0 <= v <= 0xFFFF:
            return 'IMM16'
        return None
