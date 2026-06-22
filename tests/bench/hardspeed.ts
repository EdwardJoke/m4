function fib(n: number): number {
    if (n <= 1) {
        return n;
    } else {
        return fib(n - 1) + fib(n - 2);
    }
}

function main(): void {
    for (let n = 0; n < 30; n++) {
        const result: number = fib(n);
        console.log(result);
    }
}

main();