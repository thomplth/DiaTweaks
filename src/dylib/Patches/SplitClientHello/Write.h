#include <stdbool.h>
#include <stdint.h>
#include <sys/socket.h>

// On macOS 13.3 up to 26.1, Chromium also reads sendto's second return register to catch a kernel bug: anything but 0
// there after a send that worked fails the connection. So sendto's replacement returns this pair, and gives 0 there
// itself for a split send.
typedef struct { ssize_t sent; uintptr_t secondary; } DPSendResult;
typedef DPSendResult (*DPSendFunction)(int fd, const void *buffer, size_t length, int flags, const struct sockaddr *address,
                                       socklen_t addressLength);

// If `data` starts with a ClientHello that DPSplitHello can split, and `fd` is a stream socket with room for all of the
// split, sends it all with `send` and returns YES, with what sendto should return for `data` in `result`. Otherwise
// sends nothing and returns NO.
bool DPSendSplit(int fd, const uint8_t *data, size_t length, int flags, uint32_t random, DPSendFunction send,
                 bool checkSecondary, DPSendResult *result);
