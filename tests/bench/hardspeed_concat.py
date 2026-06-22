import time

def build_str(n: int) -> str:
    s = ""
    for i in range(n):
        s = s + "a"
    return s

for n in [500, 2000, 5000]:
    start = time.time()
    s = build_str(n)
    elapsed = time.time() - start
    print(f"n={n}: done (len={len(s)}) [{elapsed:.4f}s]")
