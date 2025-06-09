//
//  H264Encoder.m
//  WebDriverAgentLib
//
//  Created by xiao on 2024/7/16.
//  Copyright © 2024 Facebook. All rights reserved.
//

#import "H264Encoder.h"

#import <VideoToolbox/VideoToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

@interface H264Encoder ()

@property (nonatomic, assign) VTCompressionSessionRef compressionSession;
@property (nonatomic, assign) int frameCount;
@property (nonatomic, strong) NSMutableData *encodedData;

@end

@implementation H264Encoder

- (instancetype)initWithWidth:(int)width height:(int)height {
    self = [super init];
    if (self) {
        self.frameCount = 0;
        self.encodedData = [NSMutableData data];
        [self setupCompressionSessionWithWidth:width height:height];
    }
    return self;
}

- (void)setupCompressionSessionWithWidth:(int)width height:(int)height {
    OSStatus status = VTCompressionSessionCreate(NULL, width, height, kCMVideoCodecType_H264, NULL, NULL, NULL, compressionOutputCallback, (__bridge void *)(self), &_compressionSession);
    if (status != noErr) {
        NSLog(@"Error: Unable to create a H264 compression session");
        return;
    }

    VTSessionSetProperty(self.compressionSession, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
    VTSessionSetProperty(self.compressionSession, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Main_AutoLevel);
  
  //关闭B帧
    VTSessionSetProperty(self.compressionSession, kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse);
  
  // 设置关键帧（GOPsize)间隔
    int frameInterval = 0;
    CFNumberRef  frameIntervalRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &frameInterval);
    VTSessionSetProperty(_compressionSession, kVTCompressionPropertyKey_MaxKeyFrameInterval, frameIntervalRef);
    CFRelease(frameIntervalRef);
  
  // 设置期望帧率
    int _fps = 10;
    CFNumberRef  fpsRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &_fps);
    VTSessionSetProperty(self.compressionSession, kVTCompressionPropertyKey_ExpectedFrameRate, fpsRef);
    CFRelease(fpsRef);
  
    //设置码率，上限，单位是bps
    int bitRate = 0;
    CFNumberRef bitRateRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &bitRate);
    VTSessionSetProperty(self.compressionSession, kVTCompressionPropertyKey_AverageBitRate, bitRateRef); // 1 Mbps
    CFRelease(bitRateRef);
  
  //设置码率，均值，单位是byte
    int dataRateLimit =0;
    CFNumberRef dataRateLimitRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &dataRateLimit);
    VTSessionSetProperty(self.compressionSession, kVTCompressionPropertyKey_DataRateLimits, dataRateLimitRef); // 1 Mbps
    CFRelease(dataRateLimitRef);
  
    VTCompressionSessionPrepareToEncodeFrames(self.compressionSession);
}

void compressionOutputCallback(
    void *outputCallbackRefCon,
    void *sourceFrameRefCon,
    OSStatus status,
    VTEncodeInfoFlags infoFlags,
    CMSampleBufferRef sampleBuffer) {
    H264Encoder *encoder = (__bridge H264Encoder *)outputCallbackRefCon;
    if (status != noErr) {
        NSLog(@"Error: Encoding failed with status %d", status);
        return;
    }

    if (!CMSampleBufferDataIsReady(sampleBuffer)) {
        NSLog(@"Error: Sample buffer data is not ready");
        return;
    }

    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true);
    if (attachments) {
        CFDictionaryRef dict = CFArrayGetValueAtIndex(attachments, 0);
        bool keyFrame = !CFDictionaryContainsKey(dict, kCMSampleAttachmentKey_NotSync);
        if (keyFrame) {
            CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);
            const uint8_t *sps, *pps;
            size_t spsSize, ppsSize;
            size_t parmCount;
            CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 0, &sps, &spsSize, &parmCount, 0);
            CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 1, &pps, &ppsSize, &parmCount, 0);

            [encoder.encodedData appendBytes:"\x00\x00\x00\x01" length:4];
            [encoder.encodedData appendBytes:sps length:spsSize];
            [encoder.encodedData appendBytes:"\x00\x00\x00\x01" length:4];
            [encoder.encodedData appendBytes:pps length:ppsSize];
        }
    }

    CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    size_t length, totalLength;
    char *dataPointer;
    CMBlockBufferGetDataPointer(dataBuffer, 0, &length, &totalLength, &dataPointer);

    const int headerLength = 4;
    while (totalLength > 0) {
        uint32_t nalLength = 0;
        memcpy(&nalLength, dataPointer, headerLength);
        nalLength = CFSwapInt32BigToHost(nalLength);

        [encoder.encodedData appendBytes:"\x00\x00\x00\x01" length:4];
        [encoder.encodedData appendBytes:dataPointer + headerLength length:nalLength];

        dataPointer += headerLength + nalLength;
        totalLength -= headerLength + nalLength;
    }

    if ([encoder.delegate respondsToSelector:@selector(didReceiveEncodedData:)]) {
        [encoder.delegate didReceiveEncodedData:[encoder.encodedData copy]];
    }

    [encoder.encodedData setLength:0];
}

- (void)encodeJPEGToH264:(NSData *)jpegData {
    UIImage *image = [UIImage imageWithData:jpegData];
    CVPixelBufferRef pixelBuffer = [self pixelBufferFromImage:image];
  
    CMTime presentationTimeStamp = CMTimeMake(self.frameCount++, 1000);
    VTEncodeInfoFlags flags;

    OSStatus status = VTCompressionSessionEncodeFrame(self.compressionSession, pixelBuffer, presentationTimeStamp, kCMTimeInvalid, NULL, NULL, &flags);
    if (status != noErr) {
        NSLog(@"Error: Failed to encode frame");
    }

    CVPixelBufferRelease(pixelBuffer);
}

- (CVPixelBufferRef)pixelBufferFromImage:(UIImage *)image {
    CGImageRef cgImage = image.CGImage;
    NSDictionary *options = @{(id)kCVPixelBufferCGImageCompatibilityKey : @YES, (id)kCVPixelBufferCGBitmapContextCompatibilityKey : @YES};
    CVPixelBufferRef pixelBuffer;
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault, CGImageGetWidth(cgImage), CGImageGetHeight(cgImage), kCVPixelFormatType_32ARGB, (__bridge CFDictionaryRef)(options), &pixelBuffer);
    if (status != kCVReturnSuccess) {
        NSLog(@"Error: Unable to create pixel buffer");
        return NULL;
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    void *pxdata = CVPixelBufferGetBaseAddress(pixelBuffer);
    CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pxdata, CGImageGetWidth(cgImage), CGImageGetHeight(cgImage), 8, 4 * CGImageGetWidth(cgImage), rgbColorSpace, kCGImageAlphaNoneSkipFirst);
    CGContextDrawImage(context, CGRectMake(0, 0, CGImageGetWidth(cgImage), CGImageGetHeight(cgImage)), cgImage);
    CGContextRelease(context);
    CGColorSpaceRelease(rgbColorSpace);
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);

    return pixelBuffer;
}

- (void)endEncoding {
    VTCompressionSessionCompleteFrames(self.compressionSession, kCMTimeInvalid);
    VTCompressionSessionInvalidate(self.compressionSession);
    CFRelease(self.compressionSession);
    self.compressionSession = NULL;
}

@end
