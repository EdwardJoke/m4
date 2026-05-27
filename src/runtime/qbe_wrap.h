#ifndef QBE_WRAP_H
#define QBE_WRAP_H

#ifdef __cplusplus
extern "C" {
#endif

/* Compile a QBE .ssa file to assembly.
 *   input_path  — path to the .ssa file
 *   output_path — path for the resulting .s assembly file
 *   target      — target architecture name: "amd64_apple", "amd64_sysv",
 *                 "amd64_win", "arm64", "arm64_apple", "rv64"
 * Returns 0 on success, nonzero on error.
 */
int qbe_compile_ssa(const char *input_path, const char *output_path, const char *target);

#ifdef __cplusplus
}
#endif

#endif /* QBE_WRAP_H */
