#import "StdPatch/StdPatch.h"

// moves: per row, @[frame now, frame as Dia laid it out].
CGFloat DPTabListDiaY(NSArray<NSArray<NSValue *> *> *moves, CGFloat y);
id<NSDraggingInfo> DPDraggingInfoAt(id<NSDraggingInfo> info, NSPoint location);
