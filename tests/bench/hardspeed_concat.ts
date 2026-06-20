function buildStr(n: number): string {
    let s = "";
    for (let i = 0; i < n; i++) {
        s = s + "a";
    }
    return s;
}

for (const n of [500, 2000, 5000]) {
    const start = performance.now();
    const s = buildStr(n);
    const elapsed = (performance.now() - start) / 1000;
    console.log(`n=${n}: done (len=${s.length}) [${elapsed.toFixed(4)}s]`);
}
