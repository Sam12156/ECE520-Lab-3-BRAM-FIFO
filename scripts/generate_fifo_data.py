import random
import sys
import pathlib

WIDTH = 16
DEPTH = 32

def main():
    n_random = int(sys.argv[1]) if len(sys.argv) > 1 else 200
    random.seed(42)
    mask = (1 << WIDTH) - 1


    words = []
    words += [mask] * DEPTH                                     # all 1s
    words += [0] * DEPTH                                        # all 0s
    words += [0xAAAA & mask if i % 2 == 0 else 0x5555 & mask
              for i in range(DEPTH)]                            # alternating bits
    words += [random.randint(0, mask) for _ in range(n_random)] # random

    script_dir = pathlib.Path(__file__).resolve().parent
    out_path = script_dir.parent / "sim" / "input_data.txt"
    digits = (WIDTH + 3) // 4
    with open(out_path, "w") as f:
        for w in words:
            f.write(f"{w:0{digits}x}\n")
    print(f"Wrote {len(words)} words to {out_path}")

if __name__ == "__main__":
    main()
