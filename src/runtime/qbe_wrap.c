#include "qbe_wrap.h"
#include "all.h"
#include <stdio.h>
#include <string.h>

/* ─── QBE Globals ──────────────────────────────────────────────────────── */
/* These are normally defined in main.c. Since we don't compile main.c,
   we must provide them here. */

Target T;
char debug['Z' + 1];

/* ─── Target Extern Declarations ───────────────────────────────────────── */
/* Defined in the arch-specific targ.c files. Exactly one will be linked. */

extern Target T_amd64_sysv;
extern Target T_amd64_apple;
extern Target T_amd64_win;
extern Target T_arm64;
extern Target T_arm64_apple;
extern Target T_rv64;

static Target *tlist[] = {
    &T_amd64_sysv,
    &T_amd64_apple,
    &T_amd64_win,
    &T_arm64,
    &T_arm64_apple,
    &T_rv64,
    0
};

/* ─── State ────────────────────────────────────────────────────────────── */

static FILE *wrap_outf;
static enum {
    OptFast,
    OptSmall,
} opt = OptFast;

static void
wrap_dbgfile(char *fn)
{
    emitdbgfile(fn, wrap_outf);
}

static void
wrap_data(Dat *d)
{
    if (debug['M'])  /* if debug is set, skip */
        return;
    emitdat(d, wrap_outf);
    if (d->type == DEnd) {
        fputs("/* end data */\n\n", wrap_outf);
        freeall();
    }
}

static void
wrap_func(Fn *fn)
{
    uint n;

    /* Full QBE compilation pipeline (mirrors main.c's func()) */
    T.abi0(fn);
    fillcfg(fn);
    filluse(fn);
    promote(fn);
    filluse(fn);
    ssa(fn);
    filluse(fn);
    ssacheck(fn);
    fillalias(fn);
    loadopt(fn);
    filluse(fn);
    fillalias(fn);
    coalesce(fn);
    filluse(fn);
    filldom(fn);
    ssacheck(fn);
    gvn(fn);
    fillcfg(fn);
    simplcfg(fn);
    filluse(fn);
    filldom(fn);
    gcm(fn);
    filluse(fn);
    ssacheck(fn);
    if (opt == OptSmall)
        for (n = 0; n < 2; n++) {
            gvn(fn);
            fillcfg(fn);
            simplcfg(fn);
            filluse(fn);
            filldom(fn);
            gcm(fn);
            filluse(fn);
            ssacheck(fn);
        }
    if (T.cansel) {
        ifconvert(fn);
        fillcfg(fn);
        filluse(fn);
        filldom(fn);
        ssacheck(fn);
    }
    T.abi1(fn);
    simpl(fn);
    fillcfg(fn);
    filluse(fn);
    T.isel(fn);
    fillcfg(fn);
    filllive(fn);
    fillloop(fn);
    fillcost(fn);
    spill(fn);
    rega(fn);
    fillcfg(fn);
    simpljmp(fn);
    fillcfg(fn);

    /* Link blocks in RPO order */
    for (n = 0;; n++) {
        if (n == fn->nblk - 1) {
            fn->rpo[n]->link = 0;
            break;
        } else {
            fn->rpo[n]->link = fn->rpo[n + 1];
        }
    }

    T.emitfn(fn, wrap_outf);
    fprintf(wrap_outf, "/* end function %s */\n\n", fn->name);
    freeall();
}

/* ─── Public API ───────────────────────────────────────────────────────── */

int
qbe_compile_ssa(const char *input_path, const char *output_path, const char *target, const char *qbe_opt)
{
    Target **t;
    FILE *inf;

    /* Select target */
    if (target) {
        for (t = tlist; *t; t++) {
            if (strcmp(target, (*t)->name) == 0) {
                T = **t;
                break;
            }
        }
        if (!*t) {
            fprintf(stderr, "qbe_wrap: unknown target '%s'\n", target);
            return 1;
        }
    }
    /* If no target specified, T keeps its default (zero-initialized).
       We'll fall back to the native target in qbe_build.zig. */

    /* Zero out debug flags first */
    memset(debug, 0, sizeof(debug));

    /* Apply QBE optimization flags */
    if (qbe_opt) {
        if (strcmp(qbe_opt, "fast") == 0) {
            opt = OptFast;
        } else if (strcmp(qbe_opt, "small") == 0) {
            opt = OptSmall;
        } else {
            fprintf(stderr, "qbe_wrap: unknown optimization level '%s'\n", qbe_opt);
            return 1;
        }
    }

    /* Open input */
    inf = fopen(input_path, "r");
    if (!inf) {
        fprintf(stderr, "qbe_wrap: cannot open '%s'\n", input_path);
        return 1;
    }

    /* Open output */
    wrap_outf = fopen(output_path, "w");
    if (!wrap_outf) {
        fprintf(stderr, "qbe_wrap: cannot open '%s'\n", output_path);
        fclose(inf);
        return 1;
    }

    /* Run QBE: parse → optimize → emit assembly */
    parse(inf, (char*)input_path, wrap_dbgfile, wrap_data, wrap_func);
    fclose(inf);

    /* Finish output */
    T.emitfin(wrap_outf);
    fclose(wrap_outf);

    return 0;
}
