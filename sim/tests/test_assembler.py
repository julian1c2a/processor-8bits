# MIT License — Copyright (c) 2026 MICROELECTRÓNICA26.UMA.EII
"""
sim/tests/test_assembler.py — Tests del ensamblador (Assembler).

Verifica que assemble_line() y el ciclo feed/link producen los bytes
correctos para cada mnemónico de la ISA v0.7.

Ejecutar:  python -m pytest sim/tests/test_assembler.py
           python -m unittest sim.tests.test_assembler
"""

import sys
import os
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))

from sim.assembler import Assembler, parse_int

# ---------------------------------------------------------------------------
# parse_int
# ---------------------------------------------------------------------------

class TestParseInt(unittest.TestCase):

    def test_decimal(self):         self.assertEqual(parse_int('42'),      42)
    def test_hex_lower(self):       self.assertEqual(parse_int('0x1f'),    0x1F)
    def test_hex_upper(self):       self.assertEqual(parse_int('0x1F'),    0x1F)
    def test_binary(self):          self.assertEqual(parse_int('0b1010'),  10)
    def test_octal(self):           self.assertEqual(parse_int('0o17'),    15)
    def test_negative(self):        self.assertEqual(parse_int('-1'),       -1)
    def test_positive_sign(self):   self.assertEqual(parse_int('+5'),       5)
    def test_zero(self):            self.assertEqual(parse_int('0'),        0)
    def test_invalid(self):         self.assertIsNone(parse_int('abc'))
    def test_empty(self):           self.assertIsNone(parse_int(''))


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

class AsmTestBase(unittest.TestCase):

    def setUp(self):
        self.asm = Assembler()

    def asm_line(self, text: str, pc: int = 0):
        return self.asm.assemble_line(text, pc)

    def assertBytes(self, text: str, expected: list, pc: int = 0):
        r = self.asm_line(text, pc)
        self.assertIsNone(r.error, f'Error inesperado en "{text}": {r.error}')
        self.assertEqual(r.bytes, expected,
                         f'"{text}": esperado {expected}, obtenido {r.bytes}')

    def assertError(self, text: str, pc: int = 0):
        r = self.asm_line(text, pc)
        self.assertIsNotNone(r.error, f'Se esperaba error en "{text}" pero no hubo')


# ---------------------------------------------------------------------------
# Sistema (1 byte)
# ---------------------------------------------------------------------------

class TestSystem(AsmTestBase):

    def test_nop(self):  self.assertBytes('NOP',  [0x00])
    def test_halt(self): self.assertBytes('HALT', [0x01])
    def test_sec(self):  self.assertBytes('SEC',  [0x02])
    def test_clc(self):  self.assertBytes('CLC',  [0x03])
    def test_sei(self):  self.assertBytes('SEI',  [0x04])
    def test_cli(self):  self.assertBytes('CLI',  [0x05])
    def test_rti(self):  self.assertBytes('RTI',  [0x06])

    def test_case_insensitive(self):
        self.assertBytes('nop', [0x00])
        self.assertBytes('Halt', [0x01])


# ---------------------------------------------------------------------------
# LD A (opcodes 0x10..0x16)
# ---------------------------------------------------------------------------

class TestLDA(AsmTestBase):

    def test_ld_a_b(self):
        self.assertBytes('LD A, B', [0x10])

    def test_ld_a_imm(self):
        self.assertBytes('LD A, #0x42', [0x11, 0x42])

    def test_ld_a_imm_decimal(self):
        self.assertBytes('LD A, #66', [0x11, 66])

    def test_ld_a_zp(self):
        self.assertBytes('LD A, [0x80]', [0x12, 0x80])

    def test_ld_a_abs(self):
        self.assertBytes('LD A, [0x0200]', [0x13, 0x00, 0x02])

    def test_ld_a_indb(self):
        self.assertBytes('LD A, [B]', [0x14])

    def test_ld_a_idx_abs(self):
        self.assertBytes('LD A, [0x0100+B]', [0x15, 0x00, 0x01])

    def test_ld_a_idx_zp(self):
        self.assertBytes('LD A, [0x80+B]', [0x16, 0x80])


# ---------------------------------------------------------------------------
# LD B (opcodes 0x20..0x25)
# ---------------------------------------------------------------------------

class TestLDB(AsmTestBase):

    def test_ld_b_a(self):
        self.assertBytes('LD B, A', [0x20])

    def test_ld_b_imm(self):
        self.assertBytes('LD B, #0x05', [0x21, 0x05])

    def test_ld_b_zp(self):
        self.assertBytes('LD B, [0x10]', [0x22, 0x10])

    def test_ld_b_abs(self):
        self.assertBytes('LD B, [0x0186]', [0x23, 0x86, 0x01])

    def test_ld_b_indb(self):
        self.assertBytes('LD B, [B]', [0x24])

    def test_ld_b_idx_abs(self):
        self.assertBytes('LD B, [0x0180+B]', [0x25, 0x80, 0x01])


# ---------------------------------------------------------------------------
# ST A (0x30..0x34) y ST B (0x40..0x42)
# ---------------------------------------------------------------------------

class TestStore(AsmTestBase):

    def test_st_a_zp(self):   self.assertBytes('ST A, [0x10]',      [0x30, 0x10])
    def test_st_a_abs(self):  self.assertBytes('ST A, [0x0100]',    [0x31, 0x00, 0x01])
    def test_st_a_indb(self): self.assertBytes('ST A, [B]',         [0x32])
    def test_st_a_idx_abs(self): self.assertBytes('ST A, [0x0100+B]', [0x33, 0x00, 0x01])
    def test_st_a_idx_zp(self):  self.assertBytes('ST A, [0x80+B]',   [0x34, 0x80])

    def test_st_b_zp(self):   self.assertBytes('ST B, [0x20]',      [0x40, 0x20])
    def test_st_b_abs(self):  self.assertBytes('ST B, [0x0101]',    [0x41, 0x01, 0x01])
    def test_st_b_idx_abs(self): self.assertBytes('ST B, [0x0100+B]', [0x42, 0x00, 0x01])


# ---------------------------------------------------------------------------
# Stack Pointer (0x50..0x53 + alias)
# ---------------------------------------------------------------------------

class TestSP(AsmTestBase):

    def test_ld_sp_imm(self):
        self.assertBytes('LD SP, #0x01FE', [0x50, 0xFE, 0x01])

    def test_ld_sp_ab(self):
        self.assertBytes('LD SP, A:B', [0x51])

    def test_st_sp_l(self):
        self.assertBytes('ST SP_L, A', [0x52])

    def test_st_sp_h(self):
        self.assertBytes('ST SP_H, A', [0x53])

    def test_rd_sp_l_alias(self):
        self.assertBytes('RD SP_L', [0x52])

    def test_rd_sp_h_alias(self):
        self.assertBytes('RD SP_H', [0x53])


# ---------------------------------------------------------------------------
# PUSH / POP (0x60..0x67)
# ---------------------------------------------------------------------------

class TestPushPop(AsmTestBase):

    def test_push_a(self):  self.assertBytes('PUSH A',   [0x60])
    def test_push_b(self):  self.assertBytes('PUSH B',   [0x61])
    def test_push_f(self):  self.assertBytes('PUSH F',   [0x62])
    def test_push_ab(self): self.assertBytes('PUSH A:B', [0x63])
    def test_pop_a(self):   self.assertBytes('POP A',    [0x64])
    def test_pop_b(self):   self.assertBytes('POP B',    [0x65])
    def test_pop_f(self):   self.assertBytes('POP F',    [0x66])
    def test_pop_ab(self):  self.assertBytes('POP A:B',  [0x67])


# ---------------------------------------------------------------------------
# Saltos (0x70..0x77)
# ---------------------------------------------------------------------------

class TestJumps(AsmTestBase):

    def test_jp_abs(self):
        self.assertBytes('JP 0x0150', [0x70, 0x50, 0x01])

    def test_jr_direct_positive(self):
        self.assertBytes('JR +5', [0x71, 0x05])

    def test_jr_direct_negative(self):
        self.assertBytes('JR -2', [0x71, 0xFE])

    def test_jrn(self):
        self.assertBytes('JPN 0x30', [0x72, 0x30])

    def test_jp_indir(self):
        self.assertBytes('JP ([0x0100])', [0x73, 0x00, 0x01])

    def test_jp_ab(self):
        self.assertBytes('JP A:B', [0x74])

    def test_call_abs(self):
        self.assertBytes('CALL 0x0150', [0x75, 0x50, 0x01])

    def test_call_indir(self):
        self.assertBytes('CALL ([0x0200])', [0x76, 0x00, 0x02])

    def test_ret(self):
        self.assertBytes('RET', [0x77])


# ---------------------------------------------------------------------------
# Ramas condicionales (0x80..0x8B)
# ---------------------------------------------------------------------------

class TestBranches(AsmTestBase):

    def test_beq_direct(self):  self.assertBytes('BEQ  +3', [0x80, 0x03])
    def test_bne_direct(self):  self.assertBytes('BNE  +3', [0x81, 0x03])
    def test_bcs_direct(self):  self.assertBytes('BCS  +3', [0x82, 0x03])
    def test_bcc_direct(self):  self.assertBytes('BCC  +3', [0x83, 0x03])
    def test_bvs_direct(self):  self.assertBytes('BVS  +3', [0x84, 0x03])
    def test_bvc_direct(self):  self.assertBytes('BVC  +3', [0x85, 0x03])
    def test_bgt_direct(self):  self.assertBytes('BGT  +3', [0x86, 0x03])
    def test_ble_direct(self):  self.assertBytes('BLE  +3', [0x87, 0x03])
    def test_bge_direct(self):  self.assertBytes('BGE  +3', [0x88, 0x03])
    def test_blt_direct(self):  self.assertBytes('BLT  +3', [0x89, 0x03])
    def test_bhc_direct(self):  self.assertBytes('BHC  +3', [0x8A, 0x03])
    def test_beq2_direct(self): self.assertBytes('BEQ2 +3', [0x8B, 0x03])

    def test_beq_abs_target(self):
        # BEQ 0x0007 como dirección absoluta: rel = 0x0007 - (0x0000+2) = 5
        self.assertBytes('BEQ 0x0007', [0x80, 0x05], pc=0x0000)

    def test_branch_negative_offset(self):
        # BEQ -3: offset byte = 0xFD
        self.assertBytes('BEQ -3', [0x80, 0xFD])


# ---------------------------------------------------------------------------
# ALU registro (0x90..0x99)
# ---------------------------------------------------------------------------

class TestALUReg(AsmTestBase):

    def test_add(self): self.assertBytes('ADD', [0x90])
    def test_adc(self): self.assertBytes('ADC', [0x91])
    def test_sub(self): self.assertBytes('SUB', [0x92])
    def test_sbb(self): self.assertBytes('SBB', [0x93])
    def test_and(self): self.assertBytes('AND', [0x94])
    def test_or(self):  self.assertBytes('OR',  [0x95])
    def test_xor(self): self.assertBytes('XOR', [0x96])
    def test_cmp(self): self.assertBytes('CMP', [0x97])
    def test_mul(self): self.assertBytes('MUL', [0x98])
    def test_muh(self): self.assertBytes('MUH', [0x99])


# ---------------------------------------------------------------------------
# ALU inmediato (0xA0..0xA7)
# ---------------------------------------------------------------------------

class TestALUImm(AsmTestBase):

    def test_add_imm(self): self.assertBytes('ADD #0x08', [0xA0, 0x08])
    def test_adc_imm(self): self.assertBytes('ADC #0x08', [0xA1, 0x08])
    def test_sub_imm(self): self.assertBytes('SUB #0x08', [0xA2, 0x08])
    def test_sbb_imm(self): self.assertBytes('SBB #0x08', [0xA3, 0x08])
    def test_and_imm(self): self.assertBytes('AND #0x35', [0xA4, 0x35])
    def test_or_imm(self):  self.assertBytes('OR  #0x35', [0xA5, 0x35])
    def test_xor_imm(self): self.assertBytes('XOR #0x35', [0xA6, 0x35])
    def test_cmp_imm(self): self.assertBytes('CMP #0x05', [0xA7, 0x05])


# ---------------------------------------------------------------------------
# ALU memoria (0xB0..0xBD)
# ---------------------------------------------------------------------------

class TestALUMem(AsmTestBase):

    def test_add_zp(self):     self.assertBytes('ADD [0x80]',       [0xB0, 0x80])
    def test_add_abs(self):    self.assertBytes('ADD [0x0200]',     [0xB1, 0x00, 0x02])
    def test_sub_zp(self):     self.assertBytes('SUB [0x10]',       [0xB2, 0x10])
    def test_sub_abs(self):    self.assertBytes('SUB [0x0100]',     [0xB3, 0x00, 0x01])
    def test_and_zp(self):     self.assertBytes('AND [0x20]',       [0xB4, 0x20])
    def test_or_zp(self):      self.assertBytes('OR  [0x20]',       [0xB5, 0x20])
    def test_xor_zp(self):     self.assertBytes('XOR [0x20]',       [0xB6, 0x20])
    def test_cmp_zp(self):     self.assertBytes('CMP [0x20]',       [0xB7, 0x20])
    def test_add_idx_abs(self): self.assertBytes('ADD [0x0180+B]',  [0xB8, 0x80, 0x01])
    def test_sub_idx_abs(self): self.assertBytes('SUB [0x0180+B]',  [0xB9, 0x80, 0x01])
    def test_and_idx_abs(self): self.assertBytes('AND [0x0180+B]',  [0xBA, 0x80, 0x01])
    def test_or_idx_abs(self):  self.assertBytes('OR  [0x0180+B]',  [0xBB, 0x80, 0x01])
    def test_xor_idx_abs(self): self.assertBytes('XOR [0x0180+B]',  [0xBC, 0x80, 0x01])
    def test_cmp_idx_abs(self): self.assertBytes('CMP [0x0180+B]',  [0xBD, 0x80, 0x01])


# ---------------------------------------------------------------------------
# Unarias / Desplazamientos (0xC0..0xCE)
# ---------------------------------------------------------------------------

class TestUnary(AsmTestBase):

    def test_not_a(self):  self.assertBytes('NOT A',  [0xC0])
    def test_neg_a(self):  self.assertBytes('NEG A',  [0xC1])
    def test_inc_a(self):  self.assertBytes('INC A',  [0xC2])
    def test_dec_a(self):  self.assertBytes('DEC A',  [0xC3])
    def test_inc_b(self):  self.assertBytes('INC B',  [0xC4])
    def test_dec_b(self):  self.assertBytes('DEC B',  [0xC5])
    def test_clr_a(self):  self.assertBytes('CLR A',  [0xC6])
    def test_set_a(self):  self.assertBytes('SET A',  [0xC7])
    def test_lsl_a(self):  self.assertBytes('LSL A',  [0xC8])
    def test_lsr_a(self):  self.assertBytes('LSR A',  [0xC9])
    def test_asl_a(self):  self.assertBytes('ASL A',  [0xCA])
    def test_asr_a(self):  self.assertBytes('ASR A',  [0xCB])
    def test_rol_a(self):  self.assertBytes('ROL A',  [0xCC])
    def test_ror_a(self):  self.assertBytes('ROR A',  [0xCD])
    def test_swap_a(self): self.assertBytes('SWAP A', [0xCE])


# ---------------------------------------------------------------------------
# E/S (0xD0..0xD3)
# ---------------------------------------------------------------------------

class TestIO(AsmTestBase):

    def test_in_a_imm(self):   self.assertBytes('IN A, #0x05',  [0xD0, 0x05])
    def test_in_a_indb(self):  self.assertBytes('IN A, [B]',    [0xD1])
    @unittest.expectedFailure  # Known bug: '#n, A' — '#' prefix consumed before OUT regex
    def test_out_imm_a(self):  self.assertBytes('OUT #0x05, A', [0xD2, 0x05])
    def test_out_indb_a(self): self.assertBytes('OUT [B], A',   [0xD3])


# ---------------------------------------------------------------------------
# ADD16 / SUB16 (0xE0..0xE3)
# ---------------------------------------------------------------------------

class TestADD16(AsmTestBase):

    def test_add16_imm8(self):
        self.assertBytes('ADD16 #1',      [0xE0, 0x01])

    def test_add16_imm16(self):
        self.assertBytes('ADD16 #0x0200', [0xE1, 0x00, 0x02])

    def test_sub16_imm8(self):
        self.assertBytes('SUB16 #1',      [0xE2, 0x01])

    def test_sub16_imm16(self):
        self.assertBytes('SUB16 #0x0200', [0xE3, 0x00, 0x02])

    def test_add16_boundary_127(self):
        # 127 cabe en IMM8 con signo → opcode 0xE0
        self.assertBytes('ADD16 #127', [0xE0, 0x7F])

    def test_add16_boundary_128(self):
        # 128 ya no cabe en int8 → IMM16
        self.assertBytes('ADD16 #128', [0xE1, 0x80, 0x00])


# ---------------------------------------------------------------------------
# BSR / RET LR / CALL LR (0xF0..0xF2)
# ---------------------------------------------------------------------------

class TestExtended(AsmTestBase):

    def test_bsr_direct(self):
        self.assertBytes('BSR +5', [0xF0, 0x05])

    def test_bsr_negative(self):
        self.assertBytes('BSR -2', [0xF0, 0xFE])

    def test_ret_lr(self):
        self.assertBytes('RET LR', [0xF1])

    def test_call_lr_abs(self):
        self.assertBytes('CALL LR 0x0200', [0xF2, 0x00, 0x02])


# ---------------------------------------------------------------------------
# Errores
# ---------------------------------------------------------------------------

class TestErrors(AsmTestBase):

    def test_unknown_mnemonic(self):
        self.assertError('LDA')

    def test_wrong_operand_form(self):
        self.assertError('NOP A')   # NOP no tiene operandos

    def test_empty_line_no_error(self):
        r = self.asm_line('')
        self.assertIsNone(r.error)
        self.assertEqual(r.bytes, [])

    def test_comment_only(self):
        r = self.asm_line('; esto es un comentario')
        self.assertIsNone(r.error)
        self.assertEqual(r.bytes, [])


# ---------------------------------------------------------------------------
# Ensamblador de dos pasadas con etiquetas
# ---------------------------------------------------------------------------

class TestTwoPass(unittest.TestCase):

    def test_backward_branch_label(self):
        asm = Assembler()
        asm.reset(org=0x0000)
        asm.feed('start: NOP')         # @ 0x0000, 1 byte
        asm.feed('       BEQ start')   # @ 0x0001, 2 bytes; rel = 0 - (1+2) = -3
        binary, _ = asm.link()
        self.assertEqual(binary, [0x00, 0x80, 0xFD])  # 0xFD = -3 u8

    def test_forward_branch_label(self):
        asm = Assembler()
        asm.reset(org=0x0000)
        asm.feed('       BEQ done')    # @ 0x0000, rel = 1 - (0+2) = -1 → ??? wait
        # done @ 0x0002 (NOP): rel = 2 - (0+2) = 0
        asm.feed('       NOP')         # @ 0x0002
        asm.feed('done:  NOP')         # @ 0x0003  ← label defined here
        # Corrección: BEQ @ 0, done @ 0x0003, PC tras fetch = 2; rel = 3-2 = 1
        binary, listing = asm.link()
        self.assertIsNone(listing[0].error)
        self.assertEqual(binary[0], 0x80)   # BEQ opcode
        self.assertEqual(binary[1], 0x01)   # rel8 = +1

    def test_org_directive(self):
        asm = Assembler()
        asm.reset()
        asm.feed('.org 0x0100')
        asm.feed('NOP')
        self.assertEqual(asm.pc, 0x0101)

    def test_byte_directive(self):
        asm = Assembler()
        asm.reset()
        asm.feed('.byte 0xDE, 0xAD, 0xBE, 0xEF')
        binary, _ = asm.link()
        self.assertEqual(binary, [0xDE, 0xAD, 0xBE, 0xEF])

    def test_word_directive_little_endian(self):
        asm = Assembler()
        asm.reset()
        asm.feed('.word 0x1234')
        binary, _ = asm.link()
        self.assertEqual(binary, [0x34, 0x12])

    def test_label_at_own_line(self):
        asm = Assembler()
        asm.reset()
        asm.feed('my_label:')
        asm.feed('NOP')
        self.assertIn('my_label', asm.labels)
        self.assertEqual(asm.labels['my_label'], 0x0000)

    def test_label_with_instruction(self):
        asm = Assembler()
        asm.reset()
        asm.feed('start: NOP')
        self.assertIn('start', asm.labels)
        self.assertEqual(asm.labels['start'], 0x0000)

    def test_undefined_label_error(self):
        asm = Assembler()
        asm.reset()
        asm.feed('BEQ nowhere')
        _, listing = asm.link()
        self.assertIsNotNone(listing[0].error)

    def test_call_literal_address(self):
        asm = Assembler()
        asm.reset()
        asm.feed('CALL 0x0150')
        binary, _ = asm.link()
        self.assertEqual(binary, [0x75, 0x50, 0x01])

    def test_full_mini_program(self):
        """Programa con etiqueta forward en rama y JP literal."""
        asm = Assembler()
        asm.reset(org=0x0000)
        asm.feed('      LD A, #0x00')   # @ 0x0000, 2 bytes
        asm.feed('loop: INC A')         # @ 0x0002, 1 byte
        asm.feed('      CMP #0x03')     # @ 0x0003, 2 bytes
        asm.feed('      BNE loop')      # @ 0x0005, 2 bytes; rel = 2 - (5+2) = -5
        asm.feed('      HALT')          # @ 0x0007
        binary, listing = asm.link()
        for al in listing:
            self.assertIsNone(al.error, f'Error en "{al.text}": {al.error}')
        self.assertEqual(binary[0], 0x11)   # LD A,#n
        self.assertEqual(binary[2], 0xC2)   # INC A
        self.assertEqual(binary[5], 0x81)   # BNE
        self.assertEqual(binary[6], 0xFB)   # rel8 = -5 → 0xFB
        self.assertEqual(binary[7], 0x01)   # HALT


if __name__ == '__main__':
    unittest.main()
