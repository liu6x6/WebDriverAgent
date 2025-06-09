//
//  VTCompressionH264.m
//  Pods
//
//  Created by Dcell on 2017/7/6.
//
//

#import "VTCompressionH264Encode.h"

@interface VTCompressionH264Encode()
@property(strong,nonatomic) NSLock *lock;
@end

@implementation VTCompressionH264Encode{
    int  frameCount;
    VTCompressionSessionRef encodingSession;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.lock = [[NSLock alloc] init];
        self.allowFrameReordering = NO;
    }
    return self;
}

-(void)prepareToEncodeFrames{
    [self.lock lock];
    
    // Create the compression session
    OSStatus status = VTCompressionSessionCreate(NULL, self.width, self.height, kCMVideoCodecType_H264, NULL, NULL, NULL, outputCallback, (__bridge void *)(self),  &encodingSession);
    if (status != 0)
    {
        [self.lock unlock];
        NSLog(@"H264: Unable to create a H264 session");
        return ;
    }
    
    // Set the properties
    VTSessionSetProperty(encodingSession, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
    VTSessionSetProperty(encodingSession, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Main_AutoLevel);
    
    //关闭B帧
    const CFBooleanRef allowFrameReordering =  self.allowFrameReordering ? kCFBooleanTrue : kCFBooleanFalse;
    VTSessionSetProperty(encodingSession, kVTCompressionPropertyKey_AllowFrameReordering, allowFrameReordering);
    
    // 设置关键帧（GOPsize)间隔
    CFNumberRef  frameIntervalRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &_frameInterval);
    VTSessionSetProperty(encodingSession, kVTCompressionPropertyKey_MaxKeyFrameInterval, frameIntervalRef);
    CFRelease(frameIntervalRef);
  
    // 设置期望帧率
    CFNumberRef  fpsRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &_fps);
    VTSessionSetProperty(encodingSession, kVTCompressionPropertyKey_ExpectedFrameRate, fpsRef);
    CFRelease(fpsRef);

    //设置码率，上限，单位是bps
    CFNumberRef bitRateRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &_bitRate);
    VTSessionSetProperty(encodingSession, kVTCompressionPropertyKey_AverageBitRate, bitRateRef);
    CFRelease(bitRateRef);

    //设置码率，均值，单位是byte
    CFNumberRef dataRateLimitRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &_dataRateLimit);
    VTSessionSetProperty(encodingSession, kVTCompressionPropertyKey_DataRateLimits, dataRateLimitRef);
    CFRelease(dataRateLimitRef);

    // Tell the encoder to start encoding
    VTCompressionSessionPrepareToEncodeFrames(encodingSession);
    
    [self.lock unlock];
}

void outputCallback(void *outputCallbackRefCon, void *sourceFrameRefCon, OSStatus status, VTEncodeInfoFlags infoFlags,
                     CMSampleBufferRef sampleBuffer )
{
    if (status != 0) return;
    
    if (!CMSampleBufferDataIsReady(sampleBuffer))
    {
        NSLog(@"didCompressH264 data is not ready ");
        return;
    }
    VTCompressionH264Encode* encoder = (__bridge VTCompressionH264Encode*)outputCallbackRefCon;
    // Check if we have got a key frame first
    bool keyframe = !CFDictionaryContainsKey( (CFArrayGetValueAtIndex(CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true), 0)), kCMSampleAttachmentKey_NotSync);
    
    if (keyframe)
    {
        CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);
        // CFDictionaryRef extensionDict = CMFormatDescriptionGetExtensions(format);
        // Get the extensions
        // From the extensions get the dictionary with key "SampleDescriptionExtensionAtoms"
        // From the dict, get the value for the key "avcC"
        
        size_t sparameterSetSize, sparameterSetCount;
        const uint8_t *sparameterSet;
        OSStatus statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 0, &sparameterSet, &sparameterSetSize, &sparameterSetCount, 0 );
        if (statusCode == noErr)
        {
            // Found sps and now check for pps
            size_t pparameterSetSize, pparameterSetCount;
            const uint8_t *pparameterSet;
            OSStatus statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 1, &pparameterSet, &pparameterSetSize, &pparameterSetCount, 0 );
            if (statusCode == noErr)
            {
                NSData *sps = [NSData dataWithBytes:sparameterSet length:sparameterSetSize];
                NSData *pps = [NSData dataWithBytes:pparameterSet length:pparameterSetSize];
                [encoder.delegate spsppsDataCallBack:sps pps:pps];
            }
        }
    }
    
    CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    size_t length, totalLength;
    char *dataPointer;
    OSStatus statusCodeRet = CMBlockBufferGetDataPointer(dataBuffer, 0, &length, &totalLength, &dataPointer);
    if (statusCodeRet == noErr) {
        
        size_t bufferOffset = 0;
        static const int AVCCHeaderLength = 4;
        while (bufferOffset < totalLength - AVCCHeaderLength) {
            
            // Read the NAL unit length
            uint32_t NALUnitLength = 0;
            memcpy(&NALUnitLength, dataPointer + bufferOffset, AVCCHeaderLength);
            
            // Convert the length value from Big-endian to Little-endian
            NALUnitLength = CFSwapInt32BigToHost(NALUnitLength);
            
            NSData* data = [[NSData alloc] initWithBytes:(dataPointer + bufferOffset + AVCCHeaderLength) length:NALUnitLength];
            //[encoder->_delegate gotEncodedData:data isKeyFrame:keyframe];
            FrameType frameType =  FrameType_PFreme;
            unsigned char* pFrameHead = (unsigned char*)data.bytes;
            if ((pFrameHead[0] & 0x1F) == 5) {
                //i frame
                frameType = FrameType_IFreme;
            }
            [encoder.delegate dataCallBack:data frameType:frameType];
            
            // Move to the next NAL unit in the block buffer
            bufferOffset += AVCCHeaderLength + NALUnitLength;
        }
        
    }
    
}


- (void)encodeByPixelBuffer:(CVPixelBufferRef)cVPixelBufferRef {
        
    [self.lock lock];
    if(encodingSession == NULL){
        [self.lock unlock];
        return;
    }
    frameCount++;
    // Get the CV Image buffer
    CVImageBufferRef imageBuffer = cVPixelBufferRef;
    // Create properties
    CMTime presentationTimeStamp = CMTimeMake(frameCount, 1000);
    //CMTime duration = CMTimeMake(1, DURATION);
    VTEncodeInfoFlags flags;
    
    // Pass it to the encoder
    OSStatus statusCode = VTCompressionSessionEncodeFrame(encodingSession,
                                                          imageBuffer,
                                                          presentationTimeStamp,
                                                          kCMTimeInvalid,
                                                          NULL, NULL, &flags);
    // Check for error
    if (statusCode != noErr) {
        NSLog(@"VTCompressionSessionEncodeFrame error:%d ",statusCode);
    }
    [self.lock unlock];
}

-(void)encodeBySampleBuffer:(CMSampleBufferRef)sampleBuffer{
    // Get the CV Image buffer
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    [self encodeByPixelBuffer:imageBuffer];
}


-(void)invalidate{
    // Mark the completion
    [self.lock lock];
    if (encodingSession != NULL) {
        VTCompressionSessionCompleteFrames(encodingSession, kCMTimeInvalid);
        
        // End the session
        VTCompressionSessionInvalidate(encodingSession);
        CFRelease(encodingSession);
        encodingSession = NULL;
    }
    frameCount = 0;
    [self.lock unlock];
}

@end
