"""Read a GGUF header without loading weights: report the metadata, the tensor
type histogram and the expert tensor layout.

Why this exists: before spending an afternoon on an engine, it is worth knowing
whether the file's quantization types and tensor names are ones that engine
implements. This walks the header only - no tensors are read, no memory beyond
the file's own metadata is used - so it runs in a second on a 68 GB model.

  python -I inspect-gguf.py model-00001-of-00002.gguf

Written against GGUF v3. It stops with a message rather than mis-parsing if it
meets a value type it does not know.
"""
import struct
import sys

GGUF_VALUE_TYPES = {
    0: "uint8", 1: "int8", 2: "uint16", 3: "int16", 4: "uint32", 5: "int32",
    6: "float32", 7: "bool", 8: "string", 9: "array", 10: "uint64",
    11: "int64", 12: "float64",
}

# ggml_type ids. The names matter here: a type the target engine does not
# implement is the difference between "loads" and "garbage output".
GGML_TYPES = {
    0: "F32", 1: "F16", 2: "Q4_0", 3: "Q4_1", 6: "Q5_0", 7: "Q5_1",
    8: "Q8_0", 9: "Q8_1", 10: "Q2_K", 11: "Q3_K", 12: "Q4_K", 13: "Q5_K",
    14: "Q6_K", 15: "Q8_K", 16: "IQ2_XXS", 17: "IQ2_XS", 18: "IQ3_XXS",
    19: "IQ1_S", 20: "IQ4_NL", 21: "IQ3_S", 22: "IQ2_S", 23: "IQ4_XS",
    24: "I8", 25: "I16", 26: "I32", 27: "I64", 28: "F64", 29: "IQ1_M",
    30: "BF16", 34: "TQ1_0", 35: "TQ2_0", 38: "MXFP4", 39: "NVFP4",
    40: "NVFP4", 41: "Q1_0", 42: "Q2_0",
}

# The metadata keys worth printing; the rest of the file's keys are skipped.
INTERESTING_KEYS = (
    "general.architecture", "general.name", "general.size_label",
    "tokenizer.ggml.model", "tokenizer.ggml.pre",
)


class Reader:
    def __init__(self, fh):
        self.fh = fh

    def read(self, n):
        b = self.fh.read(n)
        if len(b) != n:
            raise EOFError(f"wanted {n} bytes, got {len(b)}")
        return b

    def u32(self):
        return struct.unpack("<I", self.read(4))[0]

    def u64(self):
        return struct.unpack("<Q", self.read(8))[0]

    def string(self):
        n = self.u64()
        if n > 1 << 20:
            raise ValueError(f"string length {n} is implausible - header is misaligned")
        return self.read(n).decode("utf-8", "replace")

    def value(self, t):
        if t in (0, 1):
            return self.read(1)[0]
        if t in (2, 3):
            return struct.unpack("<H", self.read(2))[0]
        if t == 4:
            return self.u32()
        if t == 5:
            return struct.unpack("<i", self.read(4))[0]
        if t == 6:
            return struct.unpack("<f", self.read(4))[0]
        if t == 7:
            return bool(self.read(1)[0])
        if t == 8:
            return self.string()
        if t == 9:
            et = self.u32()
            n = self.u64()
            if n > 1 << 24:
                raise ValueError(f"array length {n} is implausible - header is misaligned")
            if et == 8:
                vals = [self.string() for _ in range(n)]
            else:
                vals = [self.value(et) for _ in range(n)]
            # long arrays are summarised: the tokenizer list has 248k entries
            return vals if len(vals) <= 16 else f"<array of {n}>"
        if t == 10:
            return self.u64()
        if t == 11:
            return struct.unpack("<q", self.read(8))[0]
        if t == 12:
            return struct.unpack("<d", self.read(8))[0]
        raise ValueError(f"unknown GGUF value type {t} ({GGUF_VALUE_TYPES.get(t, '?')})")


def main(path):
    with open(path, "rb") as fh:
        r = Reader(fh)
        if r.read(4) != b"GGUF":
            print(f"{path}: not a GGUF file")
            return 1
        version = r.u32()
        n_tensors = r.u64()
        n_kv = r.u64()

        print(f"file      {path}")
        print(f"version   {version}   tensors {n_tensors}   metadata keys {n_kv}")

        print("\n--- metadata (selected keys) ---")
        for _ in range(n_kv):
            key = r.string()
            t = r.u32()
            val = r.value(t)
            if key in INTERESTING_KEYS or key.split(".")[-1] in (
                    "block_count", "context_length", "embedding_length",
                    "expert_count", "expert_used_count"):
                text = str(val)
                print(f"  {key:<44} {text[:80]}")

        tensors = []
        for _ in range(n_tensors):
            name = r.string()
            nd = r.u32()
            dims = [r.u64() for _ in range(nd)]
            tt = r.u32()
            r.u64()  # data offset, unused here
            tensors.append((name, dims, tt))

    hist = {}
    for _, _, tt in tensors:
        hist[tt] = hist.get(tt, 0) + 1

    print("\n--- tensor types ---")
    total = sum(hist.values())
    for tt, count in sorted(hist.items()):
        name = GGML_TYPES.get(tt, f"id {tt} (unknown)")
        print(f"  {name:<12} {count:>5}  ({count * 100 / total:.1f}%)")

    print("\n--- expert tensors (first 9) ---")
    experts = [t for t in tensors if "exps" in t[0] or "shexp" in t[0]]
    for name, dims, tt in experts[:9]:
        print(f"  {name:<48} {dims} {GGML_TYPES.get(tt, tt)}")

    print("\n--- MTP / draft head ---")
    mtp = [n for n, _, _ in tensors
           if any(k in n.lower() for k in ("nextn", "mtp", "eagle", "draft"))]
    # A model with no NextN tensors cannot do MTP speculative decoding on any
    # engine, however good that engine's MTP support is.
    print("  " + (", ".join(mtp) if mtp else "NONE - this file has no NextN/MTP head"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
