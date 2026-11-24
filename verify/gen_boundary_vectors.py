#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen_boundary_vectors.py
=======================
为 DES 等价类 / 边界值定向回归生成向量，输出到 verify/vectors_bnd/：

  bkeys.mem    密钥   (16 hex, one per line)
  bins.mem     明文
  bexps.mem    期望密文 (ECB, encrypt)
  blabels.txt  每行一个标签，说明该向量测什么

参考实现：pycryptodome (Crypto.Cipher.DES)。
本机 D:\\anaconda3\\python.exe 为 0 字节坏文件，但 anaconda 的
Lib/site-packages 是 cp312 的；若当前解释器 import Crypto 失败，
脚本会自动把该目录加入 sys.path（codex runtime Python 3.12 实测可用）。

自检（任何一项失败 -> 非零退出，不写文件）：
  1) FIPS 标准向量 133457799BBCDFF1 / 0123456789ABCDEF -> 85E813540F0AB405
  2) 弱密钥 E(E(P)) == P（0101...、FEFE...）
  3) 半弱对 E(K2, E(K1, P)) == P（01FE... / FE01...）
  4) 补性质 E(~K, ~P) == ~E(K, P)
  5) 与 OpenSSL CLI (legacy provider) 逐条交叉验证（可用时）
  6) 与既有 vectors/exps.mem 28 条 golden 交叉验证（只读）
"""
from __future__ import print_function
import os
import sys
import subprocess
import shutil

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "vectors_bnd")


def _import_des():
    try:
        from Crypto.Cipher import DES  # noqa
        return DES
    except ImportError:
        # 复用 anaconda 的 cp312 site-packages（anaconda 的 python.exe 坏了，
        # 但库本身与 codex runtime 的 Python 3.12 同 ABI）
        alt = r"D:\anaconda3\Lib\site-packages"
        if os.path.isdir(os.path.join(alt, "Crypto")):
            sys.path.append(alt)
        from Crypto.Cipher import DES  # noqa
        return DES


DES = _import_des()
import Crypto  # noqa: E402


def enc(key_hex, pt_hex):
    c = DES.new(bytes.fromhex(key_hex), DES.MODE_ECB)
    return c.encrypt(bytes.fromhex(pt_hex)).hex().upper()


def dec(key_hex, ct_hex):
    c = DES.new(bytes.fromhex(key_hex), DES.MODE_ECB)
    return c.decrypt(bytes.fromhex(ct_hex)).hex().upper()


def invert64(h):
    return "%016X" % (int(h, 16) ^ 0xFFFFFFFFFFFFFFFF)


# ---------------------------------------------------------------------------
# 向量表：15 个等价类/边界，其中第 13/14/15 类各两行 -> 18 行
# (key, plaintext, label)
# ---------------------------------------------------------------------------
V = [
    # 1 全零
    ("0000000000000000", "0000000000000000", "B01 全零密钥+全零明文（最小端边界）"),
    # 2 全一
    ("FFFFFFFFFFFFFFFF", "FFFFFFFFFFFFFFFF", "B02 全1密钥+全1明文（最大端边界）"),
    # 3 弱密钥 E(E(P))=P
    ("0101010101010101", "0123456789ABCDEF", "B03 弱密钥0101..：E(E(P))=P性质"),
    # 4 弱密钥
    ("FEFEFEFEFEFEFEFE", "0123456789ABCDEF", "B04 弱密钥FEFE..：E(E(P))=P性质"),
    # 5 半弱密钥（与 FE01.. 成对）
    ("01FE01FE01FE01FE", "0123456789ABCDEF", "B05 半弱密钥：与FE01..互为半弱对"),
    # 6
    ("5555555555555555", "AAAAAAAAAAAAAAAA", "B06 0101交替模式：K=55..,P=AA.."),
    # 7
    ("AAAAAAAAAAAAAAAA", "5555555555555555", "B07 0101交替模式交叉：K/P互换"),
    # 8 单比特游走密钥
    ("0000000000000001", "0000000000000000", "B08 单比特游走密钥LSB=1+全零明文"),
    # 9 单比特游走明文
    ("133457799BBCDFF1", "8000000000000000", "B09 单比特游走明文MSB=1"),
    # 10
    ("133457799BBCDFF1", "0000000000000000", "B10 标准密钥+全零明文"),
    # 11
    ("133457799BBCDFF1", "FFFFFFFFFFFFFFFF", "B11 标准密钥+全1明文"),
    # 12 标准向量
    ("133457799BBCDFF1", "0123456789ABCDEF", "B12 FIPS标准向量复核"),
    # 13 同明文两行（ECB 确定性 / 流水线串扰）
    ("133457799BBCDFF1", "0123456789ABCDEF", "B13 ECB确定性：同明文块第1次"),
    ("133457799BBCDFF1", "0123456789ABCDEF", "B14 ECB确定性：同明文块第2次(串扰)"),
    # 14 明文互补对（同密钥）
    ("133457799BBCDFF1", "0123456789ABCDEF", "B15 明文互补对基准P"),
    ("133457799BBCDFF1", "FEDCBA9876543210", "B16 明文互补对P=~P0"),
    # 15 密钥+明文同时互补
    ("133457799BBCDFF1", "0123456789ABCDEF", "B17 补性质基准E(K,P)"),
    (invert64("133457799BBCDFF1"), invert64("0123456789ABCDEF"),
     "B18 补性质E(~K,~P)应=~E(K,P)"),
]

IDX_STD = 11
IDX_WEAK = [2, 3]
IDX_SEMI = 4
IDX_COMP_A = 16
IDX_COMP_B = 17


def fail(msg):
    print("SELF-CHECK FAILED: " + msg)
    sys.exit(1)


def openssl_enc(key_hex, pt_hex):
    """OpenSSL CLI 交叉验证；不可用/不支持时返回 None。"""
    exe = shutil.which("openssl")
    if not exe:
        return None
    cmd = [exe, "enc", "-des-ecb", "-K", key_hex, "-nopad",
           "-provider", "legacy", "-provider", "default"]
    try:
        r = subprocess.run(cmd, input=bytes.fromhex(pt_hex),
                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                           timeout=15)
    except Exception:
        return None
    if r.returncode != 0 or len(r.stdout) != 8:
        return None
    return r.stdout.hex().upper()


def main():
    print("reference : pycryptodome Crypto %s (%s)" % (Crypto.__version__, DES.__file__))

    # ---- 1) FIPS 标准向量 ----
    std = enc("133457799BBCDFF1", "0123456789ABCDEF")
    print("FIPS vector: 133457799BBCDFF1 / 0123456789ABCDEF -> %s (expect 85E813540F0AB405)" % std)
    if std != "85E813540F0AB405":
        fail("FIPS vector mismatch")

    # ---- 2) 弱密钥 E(E(P))==P ----
    for i in IDX_WEAK:
        k, p, _ = V[i]
        c1 = enc(k, p)
        c2 = enc(k, c1)
        print("weak key %s: E(E(P))=%s %s" % (k, c2, "OK" if c2 == p else "FAIL"))
        if c2 != p:
            fail("weak key E(E(P))!=P for " + k)

    # ---- 3) 半弱对 ----
    k1 = V[IDX_SEMI][0]
    k2 = "FE01FE01FE01FE01"
    p = V[IDX_SEMI][1]
    prop = enc(k2, enc(k1, p))
    print("semi-weak %s/%s: E(K2,E(K1,P))=%s %s" % (k1, k2, prop, "OK" if prop == p else "FAIL"))
    if prop != p:
        fail("semi-weak pair property failed")

    # ---- 4) 计算全部并做补性质 ----
    rows = []
    for k, p, label in V:
        rows.append((k, p, enc(k, p), label))

    if rows[IDX_COMP_B][2] != invert64(rows[IDX_COMP_A][2]):
        fail("complement property E(~K,~P)!=~E(K,P)")
    print("complement : E(~K,~P)=%s, ~E(K,P)=%s OK"
          % (rows[IDX_COMP_B][2], invert64(rows[IDX_COMP_A][2])))

    # ECB 确定性
    if not (rows[11][2] == rows[12][2] == rows[13][2]):
        fail("ECB determinism rows differ")

    # ---- 5) OpenSSL 交叉验证 ----
    n_ssl = 0
    for k, p, c, label in rows:
        ref = openssl_enc(k, p)
        if ref is None:
            continue
        if ref != c:
            fail("OpenSSL mismatch: K=%s P=%s ours=%s ossl=%s" % (k, p, c, ref))
        n_ssl += 1
    print("openssl    : %d/%d rows cross-checked" % (n_ssl, len(rows)))

    # ---- 6) 与既有 28 条 golden 交叉验证（只读）----
    vec = os.path.join(HERE, "vectors")
    try:
        with open(os.path.join(vec, "keys.mem")) as f:
            old_k = [x.strip() for x in f if x.strip()]
        with open(os.path.join(vec, "ins.mem")) as f:
            old_p = [x.strip() for x in f if x.strip()]
        with open(os.path.join(vec, "exps.mem")) as f:
            old_c = [x.strip() for x in f if x.strip()]
        n_ok = 0
        for k, p, c in zip(old_k, old_p, old_c):
            if enc(k, p) == c.upper():
                n_ok += 1
        print("existing   : %d/%d vectors in vectors/exps.mem reproduced" % (n_ok, len(old_c)))
        if n_ok != len(old_c):
            fail("existing golden vectors not reproduced")
    except IOError as e:
        print("existing   : skipped (%s)" % e)

    # ---- 写文件 ----
    if not os.path.isdir(OUT):
        os.makedirs(OUT)

    def write(name, lines):
        path = os.path.join(OUT, name)
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            for line in lines:
                f.write(line + "\n")
        print("wrote %s (%d lines)" % (path, len(lines)))

    write("bkeys.mem", [r[0] for r in rows])
    write("bins.mem", [r[1] for r in rows])
    write("bexps.mem", [r[2] for r in rows])
    write("blabels.txt", [r[3] for r in rows])

    print("")
    print("| # | label | key | plaintext | ciphertext |")
    print("|---|---|---|---|---|")
    for n, (k, p, c, label) in enumerate(rows):
        print("| %d | %s | %s | %s | %s |" % (n, label, k, p, c))


if __name__ == "__main__":
    main()
