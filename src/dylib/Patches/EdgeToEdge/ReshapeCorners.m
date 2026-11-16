#import "EdgeToEdge.h"

// Keeps the same elements, so Dia's path animations still interpolate.
CGPathRef DPReshapeCorners(CGPathRef path, CGFloat extent, CGFloat rightScale, CGFloat leftScale) {
    if (!path) return NULL;
    __block CGRect box = CGRectNull;
    __block int subpath = 0;
    CGPathApplyWithBlock(path, ^(const CGPathElement *element) {
        if (element->type == kCGPathElementMoveToPoint && !CGRectIsNull(box)) subpath++;
        int count = element->type == kCGPathElementAddCurveToPoint ? 3 : element->type == kCGPathElementAddQuadCurveToPoint ? 2
                  : element->type == kCGPathElementCloseSubpath ? 0 : 1;
        for (int i = 0; i < count && subpath == 0; i++) box = CGRectUnion(box, (CGRect){element->points[i], CGSizeZero});
    });
    CGMutablePathRef reshaped = CGPathCreateMutable();
    subpath = 0;
    __block BOOL started = NO;
    CGPoint (^move)(CGPoint) = ^CGPoint(CGPoint p) {
        if (subpath > 0) return p;
        CGFloat cx = p.x - CGRectGetMinX(box) < extent ? CGRectGetMinX(box) : CGRectGetMaxX(box) - p.x < extent ? CGRectGetMaxX(box) : NAN;
        CGFloat cy = p.y - CGRectGetMinY(box) < extent ? CGRectGetMinY(box) : CGRectGetMaxY(box) - p.y < extent ? CGRectGetMaxY(box) : NAN;
        if (isnan(cx) || isnan(cy)) return p;
        CGFloat scale = cx == CGRectGetMinX(box) ? leftScale : rightScale;
        return CGPointMake(cx + (p.x - cx) * scale, cy + (p.y - cy) * scale);
    };
    CGPathApplyWithBlock(path, ^(const CGPathElement *element) {
        const CGPoint *p = element->points;
        switch (element->type) {
            case kCGPathElementMoveToPoint:
                if (started) subpath++;
                started = YES;
                CGPathMoveToPoint(reshaped, NULL, move(p[0]).x, move(p[0]).y);
                break;
            case kCGPathElementAddLineToPoint: CGPathAddLineToPoint(reshaped, NULL, move(p[0]).x, move(p[0]).y); break;
            case kCGPathElementAddQuadCurveToPoint:
                CGPathAddQuadCurveToPoint(reshaped, NULL, move(p[0]).x, move(p[0]).y, move(p[1]).x, move(p[1]).y);
                break;
            case kCGPathElementAddCurveToPoint:
                CGPathAddCurveToPoint(reshaped, NULL, move(p[0]).x, move(p[0]).y, move(p[1]).x, move(p[1]).y, move(p[2]).x, move(p[2]).y);
                break;
            case kCGPathElementCloseSubpath: CGPathCloseSubpath(reshaped); break;
        }
    });
    return (CGPathRef)CFAutorelease(reshaped);
}
