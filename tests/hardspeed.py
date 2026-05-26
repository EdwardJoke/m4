def fib(n: int) -> int:
    if n <= 1:
        return n
    else:
        return fib(n - 1) + fib(n - 2)

def main() -> None:
    for n in range(30):
        result: int = fib(n)
        print(result)

main()