#include "m4rt.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// ─── Sentinel Nil ──────────────────────────────────────────────────────────

M4Value m4_nil = { .tag = M4_NIL };

// ─── Internal Helpers ──────────────────────────────────────────────────────

static M4Value* alloc_val(void) {
    M4Value *v = (M4Value*)malloc(sizeof(M4Value));
    if (!v) { fprintf(stderr, "m4rt: out of memory\n"); exit(1); }
    return v;
}

// ─── Constructor Wrappers ──────────────────────────────────────────────────

int64_t m4_new_int(int64_t val) {
    M4Value *v = alloc_val();
    v->tag = M4_INT;
    v->i = val;
    return (int64_t)(void*)v;
}

int64_t m4_new_float(double val) {
    M4Value *v = alloc_val();
    v->tag = M4_FLOAT;
    v->f = val;
    return (int64_t)(void*)v;
}

int64_t m4_new_bool(int64_t val) {
    // Use static singletons for true/false
    static M4Value m4_true  = { .tag = M4_BOOL, .i = 1 };
    return val
        ? (int64_t)(void*)&m4_true
        : (int64_t)(void*)&m4_nil;
}

int64_t m4_new_char(uint32_t val) {
    M4Value *v = alloc_val();
    v->tag = M4_CHAR;
    v->c = val;
    return (int64_t)(void*)v;
}

int64_t m4_new_string(int64_t ptr, int64_t len) {
    M4Value *v = alloc_val();
    v->tag = M4_STRING;
    v->s.data = (char*)ptr;
    v->s.len = len;
    v->s.cap = len;
    return (int64_t)(void*)v;
}

// ─── Vec / Struct Constructors ────────────────────────────────────────────

int64_t m4_new_vec(int64_t count) {
    M4Value *v = alloc_val();
    v->tag = M4_VEC;
    v->v.len = 0;
    v->v.cap = count;
    v->v.items = (M4Value**)calloc((size_t)count, sizeof(M4Value*));
    return (int64_t)(void*)v;
}

void m4_vec_set(int64_t obj, int64_t idx, int64_t val) {
    if (!obj) return;
    M4Value *v = (M4Value*)(void*)obj;
    if (v->tag != M4_VEC) return;
    if (idx < 0 || idx >= v->v.cap) return;
    v->v.items[idx] = (M4Value*)(void*)val;
    if (idx >= v->v.len) v->v.len = idx + 1;
}

int64_t m4_new_struct(int64_t type_name) {
    (void)type_name;
    M4Value *v = alloc_val();
    v->tag = M4_STRUCT;
    v->o.count = 0;
    v->o.fields = NULL;
    v->o.names = NULL;
    return (int64_t)(void*)v;
}

void m4_struct_set(int64_t obj, int64_t field_name, int64_t val) {
    if (!obj) return;
    M4Value *v = (M4Value*)(void*)obj;
    if (v->tag != M4_STRUCT) return;
    char *name = (char*)(void*)field_name;
    // Check if field already exists
    for (int64_t i = 0; i < v->o.count; i++) {
        if (strcmp(v->o.names[i], name) == 0) {
            v->o.fields[i] = (M4Value*)(void*)val;
            return;
        }
    }
    // Append new field
    int64_t n = v->o.count + 1;
    v->o.names = (char**)realloc(v->o.names, (size_t)n * sizeof(char*));
    v->o.fields = (M4Value**)realloc(v->o.fields, (size_t)n * sizeof(M4Value*));
    v->o.names[v->o.count] = name;
    v->o.fields[v->o.count] = (M4Value*)(void*)val;
    v->o.count = n;
}

// ─── Query / Access ────────────────────────────────────────────────────────

int64_t m4_len(int64_t val) {
    if (!val) return 0;
    M4Value *v = (M4Value*)(void*)val;
    switch (v->tag) {
        case M4_STRING: return v->s.len;
        case M4_VEC:    return v->v.len;
        default:        return 0;
    }
}

int64_t m4_get(int64_t val, int64_t idx) {
    if (!val) return (int64_t)(void*)&m4_nil;
    M4Value *v = (M4Value*)(void*)val;
    if (v->tag == M4_VEC && idx >= 0 && idx < v->v.len) {
        return (int64_t)(void*)v->v.items[idx];
    }
    return (int64_t)(void*)&m4_nil;
}

int64_t m4_index(int64_t obj, int64_t idx) {
    if (!obj) return (int64_t)(void*)&m4_nil;
    M4Value *v = (M4Value*)(void*)obj;
    // idx is an M4Value* (wrapped by m4_new_int in QBE IR); unwrap to int64_t
    int64_t actual_idx = 0;
    if (idx) {
        M4Value *iv = (M4Value*)(void*)idx;
        if (iv->tag == M4_INT) actual_idx = iv->i;
    }
    // Vec indexing
    if (v->tag == M4_VEC && actual_idx >= 0 && actual_idx < v->v.len) {
        return (int64_t)(void*)v->v.items[actual_idx];
    }
    // String indexing — return char
    if (v->tag == M4_STRING && actual_idx >= 0 && actual_idx < v->s.len) {
        return m4_new_char((unsigned char)v->s.data[actual_idx]);
    }
    return (int64_t)(void*)&m4_nil;
}

int64_t m4_field(int64_t obj, int64_t field_name) {
    if (!obj || !field_name) return (int64_t)(void*)&m4_nil;
    M4Value *v = (M4Value*)(void*)obj;
    if (v->tag != M4_STRUCT) return (int64_t)(void*)&m4_nil;
    char *name = (char*)(void*)field_name;
    for (int64_t i = 0; i < v->o.count; i++) {
        if (strcmp(v->o.names[i], name) == 0) {
            return (int64_t)(void*)v->o.fields[i];
        }
    }
    return (int64_t)(void*)&m4_nil;
}

// ─── Arithmetic ────────────────────────────────────────────────────────────

int64_t m4_add(int64_t a, int64_t b) {
    if (!a || !b) return (int64_t)(void*)&m4_nil;
    M4Value *va = (M4Value*)(void*)a;
    M4Value *vb = (M4Value*)(void*)b;
    if (va->tag == M4_INT && vb->tag == M4_INT)
        return m4_new_int(va->i + vb->i);
    if (va->tag == M4_FLOAT && vb->tag == M4_FLOAT)
        return m4_new_float(va->f + vb->f);
    if (va->tag == M4_INT && vb->tag == M4_FLOAT)
        return m4_new_float((double)va->i + vb->f);
    if (va->tag == M4_FLOAT && vb->tag == M4_INT)
        return m4_new_float(va->f + (double)vb->i);
    // String concatenation
    if (va->tag == M4_STRING && vb->tag == M4_STRING) {
        int64_t total = va->s.len + vb->s.len;
        char *buf = (char*)malloc((size_t)(total + 1));
        memcpy(buf, va->s.data, (size_t)va->s.len);
        memcpy(buf + va->s.len, vb->s.data, (size_t)vb->s.len);
        buf[total] = 0;
        M4Value *v = alloc_val();
        v->tag = M4_STRING;
        v->s.data = buf;
        v->s.len = total;
        v->s.cap = total;
        return (int64_t)(void*)v;
    }
    return (int64_t)(void*)&m4_nil;
}

int64_t m4_sub(int64_t a, int64_t b) {
    if (!a || !b) return (int64_t)(void*)&m4_nil;
    M4Value *va = (M4Value*)(void*)a;
    M4Value *vb = (M4Value*)(void*)b;
    if (va->tag == M4_INT && vb->tag == M4_INT)
        return m4_new_int(va->i - vb->i);
    if (va->tag == M4_FLOAT && vb->tag == M4_FLOAT)
        return m4_new_float(va->f - vb->f);
    if (va->tag == M4_INT && vb->tag == M4_FLOAT)
        return m4_new_float((double)va->i - vb->f);
    if (va->tag == M4_FLOAT && vb->tag == M4_INT)
        return m4_new_float(va->f - (double)vb->i);
    return (int64_t)(void*)&m4_nil;
}

int64_t m4_mul(int64_t a, int64_t b) {
    if (!a || !b) return (int64_t)(void*)&m4_nil;
    M4Value *va = (M4Value*)(void*)a;
    M4Value *vb = (M4Value*)(void*)b;
    if (va->tag == M4_INT && vb->tag == M4_INT)
        return m4_new_int(va->i * vb->i);
    if (va->tag == M4_FLOAT && vb->tag == M4_FLOAT)
        return m4_new_float(va->f * vb->f);
    if (va->tag == M4_INT && vb->tag == M4_FLOAT)
        return m4_new_float((double)va->i * vb->f);
    if (va->tag == M4_FLOAT && vb->tag == M4_INT)
        return m4_new_float(va->f * (double)vb->i);
    return (int64_t)(void*)&m4_nil;
}

int64_t m4_div(int64_t a, int64_t b) {
    if (!a || !b) return (int64_t)(void*)&m4_nil;
    M4Value *va = (M4Value*)(void*)a;
    M4Value *vb = (M4Value*)(void*)b;
    if (va->tag == M4_INT && vb->tag == M4_INT) {
        if (vb->i == 0) return (int64_t)(void*)&m4_nil;
        return m4_new_int(va->i / vb->i);
    }
    if (va->tag == M4_FLOAT && vb->tag == M4_FLOAT) {
        if (vb->f == 0.0) return (int64_t)(void*)&m4_nil;
        return m4_new_float(va->f / vb->f);
    }
    if (va->tag == M4_INT && vb->tag == M4_FLOAT) {
        if (vb->f == 0.0) return (int64_t)(void*)&m4_nil;
        return m4_new_float((double)va->i / vb->f);
    }
    if (va->tag == M4_FLOAT && vb->tag == M4_INT) {
        if (vb->i == 0) return (int64_t)(void*)&m4_nil;
        return m4_new_float(va->f / (double)vb->i);
    }
    return (int64_t)(void*)&m4_nil;
}

int64_t m4_mod(int64_t a, int64_t b) {
    if (!a || !b) return (int64_t)(void*)&m4_nil;
    M4Value *va = (M4Value*)(void*)a;
    M4Value *vb = (M4Value*)(void*)b;
    if (va->tag == M4_INT && vb->tag == M4_INT) {
        if (vb->i == 0) return (int64_t)(void*)&m4_nil;
        return m4_new_int(va->i % vb->i);
    }
    return (int64_t)(void*)&m4_nil;
}

int64_t m4_neg(int64_t a) {
    if (!a) return (int64_t)(void*)&m4_nil;
    M4Value *va = (M4Value*)(void*)a;
    if (va->tag == M4_INT) return m4_new_int(-va->i);
    if (va->tag == M4_FLOAT) return m4_new_float(-va->f);
    return (int64_t)(void*)&m4_nil;
}

int64_t m4_not(int64_t a) {
    if (!a) return m4_new_bool(1);
    M4Value *va = (M4Value*)(void*)a;
    if (va->tag == M4_INT) return m4_new_bool(va->i == 0);
    if (va->tag == M4_BOOL) return m4_new_bool(va->i == 0);
    if (va->tag == M4_FLOAT) return m4_new_bool(va->f == 0.0);
    return m4_new_bool(0);
}

// ─── Logical ────────────────────────────────────────────────────────────────

int64_t m4_and(int64_t a, int64_t b) {
    return m4_is_truthy(a) ? b : m4_new_bool(0);
}

int64_t m4_or(int64_t a, int64_t b) {
    return m4_is_truthy(a) ? a : b;
}

// ─── Comparisons ───────────────────────────────────────────────────────────

static int64_t m4_cmp(int64_t a, int64_t b, int op) {
    if (!a || !b) {
        if (op == 0) return m4_new_bool(a == b);
        return m4_new_bool(0);
    }
    M4Value *va = (M4Value*)(void*)a;
    M4Value *vb = (M4Value*)(void*)b;

    // Type mismatch — compare by tag
    if (va->tag != vb->tag) {
        if (op == 0 || op == 1) return m4_new_bool(va->tag == vb->tag ? 1 : (op == 0 ? 0 : 1));
        return m4_new_bool(0);
    }

    int result = 0;
    switch (va->tag) {
        case M4_INT: {
            int64_t cmp = va->i - vb->i;
            result = (op == 0) ? (cmp == 0) : (op == 1) ? (cmp != 0) : (op == 2) ? (va->i > vb->i) : (op == 3) ? (va->i < vb->i) : (op == 4) ? (va->i >= vb->i) : (va->i <= vb->i);
            break;
        }
        case M4_FLOAT: {
            result = (op == 0) ? (va->f == vb->f) : (op == 1) ? (va->f != vb->f) : (op == 2) ? (va->f > vb->f) : (op == 3) ? (va->f < vb->f) : (op == 4) ? (va->f >= vb->f) : (va->f <= vb->f);
            break;
        }
        case M4_BOOL: {
            result = (op == 0) ? (va->i == vb->i) : (op == 1) ? (va->i != vb->i) : 0;
            break;
        }
        case M4_STRING: {
            int64_t min = va->s.len < vb->s.len ? va->s.len : vb->s.len;
            int scmp = memcmp(va->s.data, vb->s.data, (size_t)min);
            int64_t total = scmp ? scmp : (va->s.len - vb->s.len);
            result = (op == 0) ? (total == 0) : (op == 1) ? (total != 0) : (op == 2) ? (total > 0) : (op == 3) ? (total < 0) : (op == 4) ? (total >= 0) : (total <= 0);
            break;
        }
        default:
            result = (op == 0) ? (va == vb) : 1;
    }
    return m4_new_bool(result);
}

int64_t m4_eq(int64_t a, int64_t b)   { return m4_cmp(a, b, 0); }
int64_t m4_neq(int64_t a, int64_t b)  { return m4_cmp(a, b, 1); }
int64_t m4_gt(int64_t a, int64_t b)   { return m4_cmp(a, b, 2); }
int64_t m4_lt(int64_t a, int64_t b)   { return m4_cmp(a, b, 3); }
int64_t m4_gte(int64_t a, int64_t b)  { return m4_cmp(a, b, 4); }
int64_t m4_lte(int64_t a, int64_t b)  { return m4_cmp(a, b, 5); }

// ─── Predicates ────────────────────────────────────────────────────────────

int64_t m4_is_truthy(int64_t val) {
    if (!val) return 0;
    M4Value *v = (M4Value*)(void*)val;
    switch (v->tag) {
        case M4_NIL:   return 0;
        case M4_BOOL:  return v->i;
        case M4_INT:   return v->i != 0;
        case M4_FLOAT: return v->f != 0.0;
        default:       return 1; // strings, vecs, structs are truthy
    }
}

// ─── Print ─────────────────────────────────────────────────────────────────

static void m4_print_value(int64_t val) {
    if (!val) {
        printf("nil");
        return;
    }
    M4Value *v = (M4Value*)(void*)val;
    switch (v->tag) {
        case M4_NIL:   printf("nil"); break;
        case M4_BOOL:  printf(v->i ? "true" : "false"); break;
        case M4_INT:   printf("%ld", (long)v->i); break;
        case M4_FLOAT: printf("%g", v->f); break;
        case M4_CHAR:  putchar((int)v->c); break;
        case M4_STRING: fwrite(v->s.data, 1, (size_t)v->s.len, stdout); break;
        case M4_VEC:   printf("<vec>"); break;
        case M4_STRUCT: printf("<struct>"); break;
        default:       printf("<value>"); break;
    }
}

int64_t m4_std_println(int64_t val) {
    m4_print_value(val);
    printf("\n");
    return (int64_t)(void*)&m4_nil;
}

int64_t m4_std_print(int64_t val) {
    m4_print_value(val);
    return (int64_t)(void*)&m4_nil;
}

int64_t m4_std_range(int64_t start, int64_t end) {
    // start and end are M4Value* containing ints
    int64_t s = 0, e = 0;
    if (start) { M4Value *vs = (M4Value*)(void*)start; if (vs->tag == M4_INT) s = vs->i; }
    if (end)   { M4Value *ve = (M4Value*)(void*)end;   if (ve->tag == M4_INT) e = ve->i; }

    int64_t count = (e > s) ? (e - s) : 0;
    int64_t vec = m4_new_vec(count);
    for (int64_t i = 0; i < count; i++) {
        int64_t elem = m4_new_int(s + i);
        m4_vec_set(vec, i, elem);
    }
    return vec;
}
