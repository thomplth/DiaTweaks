#import "EdgeToEdge.h"

NSView *DPRoundedContent(NSView *container) {
    return DPFindView(container, ^BOOL(NSView *v) { return v != container && v.layer.masksToBounds && v.layer.cornerRadius > 0; });
}

NSView *DPChatCard(NSView *container) {
    NSView *content = DPRoundedContent(container);
    NSSize size = content.bounds.size;
    BOOL (^isCard)(NSView *) = ^BOOL(NSView *v) {
        return v.layer.masksToBounds && v.layer.cornerRadius > 0 && NSWidth(v.bounds) > size.width / 4 && NSHeight(v.bounds) > size.height / 2;
    };
    for (NSView *root in content.subviews)
        for (NSView *host in root.subviews) {
            if (NSMinX(host.frame) < 2 && NSMinY(host.frame) < 2) continue;
            if (isCard(host)) return host;
            for (NSView *card in host.subviews) if (isCard(card)) return card;
        }
    return nil;
}
