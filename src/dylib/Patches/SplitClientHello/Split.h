#include <stddef.h>
#include <stdint.h>

// If `data` starts with a plaintext TLS ClientHello record, after at most one ChangeCipherSpec record, and its server
// name is at least two bytes long, writes `data` to `out` with that record cut in two after byte
// `1 + random % (name length - 1)` of the name, and returns the new length, `length + 5`. Otherwise returns 0.
// `out` must hold `length + 5` bytes.
size_t DPSplitHello(const uint8_t *data, size_t length, uint8_t *out, uint32_t random);
