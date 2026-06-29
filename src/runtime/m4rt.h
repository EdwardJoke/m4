#ifndef M4RT_H
#define M4RT_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// ─── M4Value Type ──────────────────────────────────────────────────────────
// All values in the m4 runtime are represented as M4Value*, passed as
// int64_t (QBE 'l' type) across the FFI boundary.

typedef enum {
    M4_NIL = 0,
    M4_BOOL,
    M4_INT,
    M4_FLOAT,
    M4_CHAR,
    M4_STRING,
    M4_VEC,
    M4_STRUCT,
} M4Tag;

typedef struct M4Value {
    M4Tag tag;
    union {
        int64_t i;
        double f;
        uint32_t c;
        struct { char *data; int64_t len; int64_t cap; } s;
        struct { struct M4Value **items; int64_t len; int64_t cap; } v;
        struct { struct M4Value **fields; char **names; int64_t count; } o;
    };
} M4Value;

// Sentinel nil value — address is used as the canonical "nil" M4Value*
extern M4Value m4_nil;

// ─── Constructor Wrappers ──────────────────────────────────────────────────
// m4_new_int returns the raw l value directly (unboxed).
// m4_box_int wraps an unboxed int into a heap-allocated M4Value*.
// m4_new_bool, m4_new_char, nil-as-null produce boxed M4Value* with the
// correct tag — the QBE backend emits them directly as boxed rather than
// erasing the kind through m4_box_int.

int64_t m4_new_int(int64_t val);
int64_t m4_box_int(int64_t val);
int64_t m4_new_float(double val);
int64_t m4_new_bool(int64_t val);
int64_t m4_new_char(uint32_t val);
int64_t m4_new_string(int64_t ptr, int64_t len);

// ─── Vec / Struct Constructors ────────────────────────────────────────────

int64_t m4_new_vec(int64_t count);
void   m4_vec_set(int64_t obj, int64_t idx, int64_t val);
int64_t m4_new_struct(int64_t type_name);
void   m4_struct_set(int64_t obj, int64_t field_name, int64_t val);

// ─── Query / Access ────────────────────────────────────────────────────────

int64_t m4_len(int64_t val);
int64_t m4_get(int64_t val, int64_t idx);
int64_t m4_index(int64_t obj, int64_t idx);
int64_t m4_field(int64_t obj, int64_t field_name);

// ─── Arithmetic (return M4Value*) ──────────────────────────────────────────

int64_t m4_add(int64_t a, int64_t b);
int64_t m4_sub(int64_t a, int64_t b);
int64_t m4_mul(int64_t a, int64_t b);
int64_t m4_div(int64_t a, int64_t b);
int64_t m4_mod(int64_t a, int64_t b);
int64_t m4_neg(int64_t a);
int64_t m4_not(int64_t a);
int64_t m4_and(int64_t a, int64_t b);
int64_t m4_or(int64_t a, int64_t b);

// ─── Unboxed Arithmetic Entry Points ───────────────────────────────────────
// These take raw l values (no M4Value* indirection) and return raw l results.
// div_u and mod_u return boxed M4Value* (or &m4_nil on divide-by-zero) so
// nil semantics are preserved for the QBE backend.

int64_t m4_add_u(int64_t a, int64_t b);
int64_t m4_sub_u(int64_t a, int64_t b);
int64_t m4_mul_u(int64_t a, int64_t b);
int64_t m4_div_u(int64_t a, int64_t b);
int64_t m4_mod_u(int64_t a, int64_t b);
int64_t m4_neg_u(int64_t a);
int64_t m4_not_u(int64_t a);

// ─── Comparison (return M4Value*) ──────────────────────────────────────────

int64_t m4_eq(int64_t a, int64_t b);
int64_t m4_neq(int64_t a, int64_t b);
int64_t m4_lt(int64_t a, int64_t b);
int64_t m4_gt(int64_t a, int64_t b);
int64_t m4_lte(int64_t a, int64_t b);
int64_t m4_gte(int64_t a, int64_t b);

// ─── Predicates (return 0/1 as int64_t) ────────────────────────────────────

int64_t m4_is_truthy(int64_t val);

// ─── Memory Management ───────────────────────────────────────────────────

/// Free an M4Value and all its owned heap data (strings, vecs, structs).
/// Accepts only boxed (heap-allocated) M4Value pointers — NOT unboxed ints.
void m4_free_value(M4Value *val);

// ─── Stdlib Functions ──────────────────────────────────────────────────────

int64_t m4_std_println(int64_t val);
int64_t m4_std_print(int64_t val);
int64_t m4_std_range(int64_t start, int64_t end);

#ifdef __cplusplus
}
#endif

#endif /* M4RT_H */
