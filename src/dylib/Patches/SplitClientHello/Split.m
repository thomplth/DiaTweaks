#include "Split.h"
#include <stdbool.h>
#include <string.h>

// A ClientHello is sent before any keys exist, so its record can be cut in two on the way out, and the handshake
// hashes messages, not records, so the server ends up with the same one.

typedef struct { const uint8_t *at, *end; } DPReader;

static bool DPSkip(DPReader *r, size_t count) {
    if ((size_t)(r->end - r->at) < count) return false;
    r->at += count;
    return true;
}

static bool DPRead(DPReader *r, size_t bytes, size_t *value) {
    if ((size_t)(r->end - r->at) < bytes) return false;
    for (*value = 0; bytes; bytes--) *value = *value << 8 | *r->at++;
    return true;
}

// Skips a length-prefixed field.
static bool DPSkipField(DPReader *r, size_t lengthBytes) {
    size_t length;
    return DPRead(r, lengthBytes, &length) && DPSkip(r, length);
}

// The host name in a ClientHello's body, from its server_name extension.
static const uint8_t *DPServerName(DPReader body, size_t *nameLength) {
    size_t extensionsLength;
    if (!DPSkip(&body, 2 + 32) || !DPSkipField(&body, 1) || !DPSkipField(&body, 2) || !DPSkipField(&body, 1)
        || !DPRead(&body, 2, &extensionsLength) || (size_t)(body.end - body.at) < extensionsLength)
        return NULL;
    DPReader extensions = { body.at, body.at + extensionsLength };
    while (extensions.at < extensions.end) {
        size_t type, length, listLength, nameType;
        if (!DPRead(&extensions, 2, &type) || !DPRead(&extensions, 2, &length) || (size_t)(extensions.end - extensions.at) < length)
            return NULL;
        DPReader extension = { extensions.at, extensions.at + length };
        extensions.at += length;
        if (type != 0) continue;
        if (!DPRead(&extension, 2, &listLength) || !DPRead(&extension, 1, &nameType) || nameType != 0
            || !DPRead(&extension, 2, nameLength) || (size_t)(extension.end - extension.at) < *nameLength)
            return NULL;
        return extension.at;
    }
    return NULL;
}

size_t DPSplitHello(const uint8_t *data, size_t length, uint8_t *out, uint32_t random) {
    // After a HelloRetryRequest, BoringSSL sends a ChangeCipherSpec record ahead of the second ClientHello.
    size_t record = length >= 5 && data[0] == 0x14 && data[1] == 0x03 ? 5 + (size_t)(data[3] << 8 | data[4]) : 0;
    if (length < record + 9 || data[record] != 0x16 || data[record + 1] != 0x03 || data[record + 5] != 0x01) return 0;
    size_t payload = record + 5, recordLength = (size_t)(data[record + 3] << 8 | data[record + 4]);
    size_t messageLength = (size_t)data[payload + 1] << 16 | (size_t)data[payload + 2] << 8 | data[payload + 3];
    if (payload + recordLength > length || 4 + messageLength > recordLength) return 0;

    size_t nameLength;
    const uint8_t *name = DPServerName((DPReader){ data + payload + 4, data + payload + 4 + messageLength }, &nameLength);
    if (!name || nameLength < 2) return 0;

    size_t cut = (size_t)(name - data) + 1 + random % (nameLength - 1), first = cut - payload, second = recordLength - first;
    memcpy(out, data, cut);
    out[record + 3] = (uint8_t)(first >> 8), out[record + 4] = (uint8_t)first;
    memcpy(out + cut, data + record, 3);
    out[cut + 3] = (uint8_t)(second >> 8), out[cut + 4] = (uint8_t)second;
    memcpy(out + cut + 5, data + cut, length - cut);
    return length + 5;
}
