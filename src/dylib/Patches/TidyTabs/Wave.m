#import "TidyTabs.h"

static NSString *const DPWaveName = @"DPTidyWave";
static const CGFloat DPWavelength = 10, DPAmplitude = 2.25, DPWaveWidth = 1.25, DPLineWidth = 1, DPBoxHeight = 9;

// Flat and wavy paths need the same points for the morph to animate.
static CGPathRef DPWavePath(CGFloat width, CGFloat height, CGFloat amplitude) {
    CGMutablePathRef path = CGPathCreateMutable();
    CGFloat mid = height / 2;
    for (CGFloat x = 0; x <= width + DPWavelength; x += 0.5) {
        CGFloat y = mid + amplitude * sin(2 * M_PI * x / DPWavelength);
        if (x == 0) CGPathMoveToPoint(path, NULL, x, y);
        else CGPathAddLineToPoint(path, NULL, x, y);
    }
    return path;
}

static CALayer *DPWaveIn(CALayer *host) {
    for (CALayer *layer in host.sublayers) if ([layer.name isEqualToString:DPWaveName]) return layer;
    return nil;
}

static void DPMorph(CAShapeLayer *shape, CGPathRef to, CGFloat width, void (^done)(void)) {
    CABasicAnimation *morph = [CABasicAnimation animationWithKeyPath:@"path"];
    morph.fromValue = (__bridge id)(shape.presentationLayer.path ?: shape.path);
    morph.toValue = (__bridge id)to;
    CABasicAnimation *thicken = [CABasicAnimation animationWithKeyPath:@"lineWidth"];
    thicken.fromValue = @(shape.presentationLayer.lineWidth ?: shape.lineWidth);
    thicken.toValue = @(width);
    CAAnimationGroup *group = [CAAnimationGroup animation];
    group.animations = @[morph, thicken];
    group.duration = 0.3;
    group.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [CATransaction setCompletionBlock:done];
    shape.path = to;
    shape.lineWidth = width;
    [shape addAnimation:group forKey:@"morph"];
    [CATransaction commit];
}

void DPTidyWave(CALayer *host, CALayer *line, CGColorRef color, BOOL busy) {
    CALayer *box = DPWaveIn(host);
    CAShapeLayer *shape = box.sublayers.firstObject;
    NSRect frame = line.frame;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (busy && NSWidth(frame) > 0) {
        BOOL fresh = !box;
        if (fresh) {
            box = [CALayer layer];
            box.name = DPWaveName;
            box.masksToBounds = YES;
            shape = [CAShapeLayer layer];
            shape.fillColor = nil;
            shape.lineWidth = DPLineWidth;
            shape.lineCap = kCALineCapButt;
            [box addSublayer:shape];
            [host addSublayer:box];
            CABasicAnimation *roll = [CABasicAnimation animationWithKeyPath:@"position.x"];
            roll.fromValue = @0;
            roll.toValue = @(-DPWavelength);
            roll.duration = 0.5;
            roll.repeatCount = HUGE_VALF;
            roll.additive = YES;
            [shape addAnimation:roll forKey:@"roll"];
        }
        box.frame = NSMakeRect(NSMinX(frame), NSMidY(frame) - DPBoxHeight / 2, NSWidth(frame), DPBoxHeight);
        shape.frame = NSMakeRect(0, 0, NSWidth(frame) + DPWavelength, DPBoxHeight);
        shape.strokeColor = color;
        line.opacity = 0;
        CGPathRef wave = DPWavePath(NSWidth(frame), DPBoxHeight, DPAmplitude);
        if (fresh) {
            CGPathRef flat = DPWavePath(NSWidth(frame), DPBoxHeight, 0);
            shape.path = flat;
            CGPathRelease(flat);
            [CATransaction commit];
            DPMorph(shape, wave, DPWaveWidth, nil);
            CGPathRelease(wave);
            return;
        }
        if (![shape animationForKey:@"morph"]) shape.path = wave;
        CGPathRelease(wave);
    } else if (box) {
        CGPathRef flat = DPWavePath(NSWidth(box.frame), NSHeight(box.frame), 0);
        __weak CALayer *weakBox = box, *weakLine = line, *weakHost = host;
        [CATransaction commit];
        box.name = [DPWaveName stringByAppendingString:@"-leaving"];
        DPMorph(shape, flat, DPLineWidth, ^{
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            if (!DPWaveIn(weakHost)) weakLine.opacity = 1;
            [weakBox removeFromSuperlayer];
            [CATransaction commit];
        });
        CGPathRelease(flat);
        return;
    }
    [CATransaction commit];
}
