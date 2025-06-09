//
//  VideoServer.m
//  WebDriverAgentLib
//
//  Created by xiao on 2024/7/16.
//  Copyright © 2024 Facebook. All rights reserved.
//

@import UniformTypeIdentifiers;

#import "VideoServer.h"
#import "GCDAsyncSocket.h"
#import "FBConfiguration.h"
#import "FBLogger.h"
#import "FBScreenshot.h"
#import "FBImageUtils.h"
#import "XCUIScreen.h"
#import "NSData+HexDump.h"
#import "DataHandler.h"
#import <Photos/Photos.h>
#import <AVFoundation/AVFoundation.h>




static NSString *const SERVER_NAME = @"WDA MJPEG Video Server";
static const char *QUEUE_NAME = "JPEG VideoServer Provider Queue";

static const NSTimeInterval FRAME_TIMEOUT = 1.0;

@interface VideoServer()

@property (nonatomic, readonly) dispatch_queue_t backgroundQueue;

@property (nonatomic) int port;
@property (nonatomic, readonly) long long mainScreenID;

@property (nonatomic, readonly) NSMutableArray<GCDAsyncSocket *> *listeningClients;

@property (nonatomic, retain) H264Encoder *encoder;
@property (nonatomic, retain) VTCompressionH264Encode *encoder2;

@property (nonatomic, retain) DataHandler *dataHandler;

@property (nonatomic, retain) NSMutableData *encodedData;


@end


@implementation VideoServer

- (instancetype) init {
  if ((self = [super init])) {
    compressionQuality = MAX(DLMinCompressionQuality / 100.0,
                                     MIN(DLMaxCompressionQuality / 100.0, FBConfiguration.mjpegServerScreenshotQuality / 100.0));
    
    _listeningClients = [NSMutableArray array];
    dispatch_queue_attr_t queueAttributes = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0);
    _backgroundQueue = dispatch_queue_create(QUEUE_NAME, queueAttributes);
    dispatch_async(_backgroundQueue, ^{
      [self streamScreenshot];
    });

    _mainScreenID = [XCUIScreen.mainScreen displayID];
//    CGSize size = [UIScreen mainScreen].bounds.size;
//    width = 1178, height = 2556
//    _encoder = [[H264Encoder alloc] initWithWidth:1178 height:2556];
//    _encoder.delegate = self;
    [self setupEncoder2];
   
  }
  return self;
}

- (instancetype)initWithPort:(int) port {
  self = [super init];
  if (self) {
    _port = port;
  }
  return self;
}

- (void)setupEncoder2 {
  _encodedData = [NSMutableData data];
  _encoder2 = [[VTCompressionH264Encode alloc] init];
  
  //    width = 1178, height = 2556 better
  
  UIScreen *screen = UIScreen.mainScreen;
  CGFloat scale = screen.scale;
  CGRect bounds = screen.bounds;

//  int32_t width = (int32_t)(bounds.size.width * scale);
//  int32_t height = (int32_t)(bounds.size.height * scale);
  
  _encoder2.width = 1178;
  _encoder2.height = 2556;
  
//  _encoder2.width = width;
//  _encoder2.height = height;
  
  _encoder2.fps = framerate;
  _encoder2.frameInterval = 15;
  _encoder2.delegate = self;
  _encoder2.allowFrameReordering = NO;
  [_encoder2 prepareToEncodeFrames];
  
}


- (void)scheduleNextScreenshotWithInterval:(uint64_t)timerInterval timeStarted:(uint64_t)timeStarted {
//  uint64_t timeElapsed = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) - timeStarted;
//  int64_t nextTickDelta = timerInterval - timeElapsed;
//  if (nextTickDelta > 0) {
//    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, nextTickDelta), self.backgroundQueue, ^{
//      @autoreleasepool {
//        [self streamScreenshot];
//      }
//    });
//  } else {
    // Try to do our best to keep the FPS at a decent level
    dispatch_async(self.backgroundQueue, ^{
      @autoreleasepool {
        [self streamScreenshot];
      }
    });
//  }
}

const CGFloat DLMinScalingFactor = 0.01f;
const CGFloat DLMaxScalingFactor = 1.0f;
const CGFloat DLMinCompressionQuality = 50.0f;
const CGFloat DLMaxCompressionQuality = 50.0;
const NSUInteger framerate = 20;
CGFloat compressionQuality ;

// temp
int count = 0;
- (void)streamScreenshot {
  count ++;
  NSLog(@"in streamScreenshot =======> count %d",count);

 
  uint64_t timerInterval = (uint64_t)((1.0 / 30.0) * NSEC_PER_SEC);
  uint64_t timeStarted = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW);
  // if no client just return
  @synchronized (self.listeningClients) {
    if (0 == self.listeningClients.count) {
      [self scheduleNextScreenshotWithInterval:timerInterval timeStarted:timeStarted];
      return;
    }
  }

  NSError *error;
  
  NSData *screenshotData = [FBScreenshot takeInOriginalResolutionWithScreenID:self.mainScreenID
                                                           compressionQuality:compressionQuality
                                                                          uti:UTTypeJPEG
                                                                      timeout: FRAME_TIMEOUT
                                                                        error:&error];
  if (nil == screenshotData) {
    [FBLogger logFmt:@"%@", error.description];
    [self scheduleNextScreenshotWithInterval:timerInterval timeStarted:timeStarted];
    return;
  }

  CGFloat scalingFactor = 1.0;
  

//  [_encoder encodeJPEGToH264:screenshotData];
  
  UIImage *image = [UIImage imageWithData:screenshotData];
  CVPixelBufferRef pixelBuffer = [self pixelBufferFromImage1:image];
  [_encoder2 encodeByPixelBuffer:pixelBuffer];
  
  // release the pixelVuffer
  CVPixelBufferUnlockBaseAddress(pixelBuffer, 0); // Ensure it is unlocked before releasing
  CVPixelBufferRelease(pixelBuffer);
  [self scheduleNextScreenshotWithInterval:timerInterval timeStarted:timeStarted];
}

- (CVPixelBufferRef)pixelBufferFromImage1:(UIImage *)image {
  
    CIImage *ciimage = [[CIImage alloc] initWithImage:image];
      const void *keys[] = {kCVPixelBufferCGImageCompatibilityKey, kCVPixelBufferCGBitmapContextCompatibilityKey};
      const void *values[] = {kCFBooleanTrue, kCFBooleanTrue};
      CFDictionaryRef cfDic = CFDictionaryCreate(CFAllocatorGetDefault(), keys, values, 2, NULL, NULL);
      CVPixelBufferRef pixelBuff = NULL;
      OSStatus status = CVPixelBufferCreate(kCFAllocatorDefault, (unsigned long)ciimage.extent.size.width, (unsigned long)ciimage.extent.size.height, kCVPixelFormatType_32BGRA, cfDic, &pixelBuff);
      if (status == kCVReturnSuccess) {
//          NSLog(@"success----");
      }
  
      CFRelease(cfDic);
  
      CIContext *cicontext = [CIContext new];
      CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();

      [cicontext render:ciimage toCVPixelBuffer:pixelBuff bounds:ciimage.extent colorSpace:colorSpace];
      CVPixelBufferLockBaseAddress(pixelBuff, 0);
  
      CGColorSpaceRelease(colorSpace); // Release the color space

  
      return pixelBuff;
  }

// this function has some issue
- (CVPixelBufferRef)pixelBufferFromImage:(UIImage *)image {
    CGImageRef cgImage = image.CGImage;
    NSDictionary *options = @{(id)kCVPixelBufferCGImageCompatibilityKey : @YES, (id)kCVPixelBufferCGBitmapContextCompatibilityKey : @YES};
    CVPixelBufferRef pixelBuffer;
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault, CGImageGetWidth(cgImage), CGImageGetHeight(cgImage), kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)(options), &pixelBuffer);
    if (status != kCVReturnSuccess) {
        NSLog(@"Error: Unable to create pixel buffer");
        return NULL;
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    void *pxdata = CVPixelBufferGetBaseAddress(pixelBuffer);
    CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pxdata, CGImageGetWidth(cgImage), CGImageGetHeight(cgImage), 8, 4 * CGImageGetWidth(cgImage), rgbColorSpace, kCGImageAlphaNoneSkipFirst);
    CGContextDrawImage(context, CGRectMake(0, 0, CGImageGetWidth(cgImage), CGImageGetHeight(cgImage)), cgImage);
    
    CGImageRelease(cgImage);
    CGContextRelease(context);
    CGColorSpaceRelease(rgbColorSpace);
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);

    return pixelBuffer;
}


- (void)updatePropertyFromEnv {
  
}

- (void)createPixelBufferFromNSData:(NSData *)data orientation:(int)orientation {
  
  return;
}


- (void)screenShotsAndEncodeVideo {
//scheduleNextScreenshotWithInterval:timeStarted
//
//screenshotCompressionQuality
//
//
//mainScreenID
//
//_kUTTypeJPEG_d8058,_kUTTypeJPEG
//takeInOriginalResolutionWithScreenID

}

#pragma mark - mark - FBTCPSocketDelegate

- (void)didClientConnect:(GCDAsyncSocket *)newClient {
  [FBLogger logFmt:@"Got screenshots broadcast client connection at %@:%d", newClient.connectedHost, newClient.connectedPort];
  // Start broadcast only after there is any data from the client
//  [newClient readDataWithTimeout:-1 tag:0];
  
  if ([self.listeningClients containsObject:newClient]) {
    return;
  }
  
  @synchronized (self.listeningClients) {
    [self.listeningClients addObject:newClient];
  }
  // send init info
//  NSData *da = [self buildHeader1];
//  
//  [FBLogger logFmt:@"will send initInfo to client => %@:", da];
//
//  [newClient  writeData:da withTimeout:-1 tag:0];
  BOOL sendHeader = false;
  
  if(sendHeader) {
    uint32_t codecId = 0x68323634; // 'h264'
    uint32_t width = 1178;
    uint32_t height = 2556;

    NSData *header = [self videoHeaderWithCodec:codecId width:width height:height];
//    [self printHexDump:header];
    NSLog(@"%@",[header hexDump]);
    [newClient  writeData:header withTimeout:-1 tag:0];

  }

  
}

- (void)didClientSendData:(GCDAsyncSocket *)client {
 
//  NSData *da = [self buildHeader1];
//  [FBLogger logFmt:@"will send initInfo2 to client => %@:", da];
//  [client  writeData:da withTimeout:-1 tag:0];
  
  @synchronized (self.listeningClients) {
    if ([self.listeningClients containsObject:client]) {
      return;
    }
  }

  [FBLogger logFmt:@"Starting Video broadcast for the client at %@:%d", client.connectedHost, client.connectedPort];

//  [client writeData:(id)[streamHeader dataUsingEncoding:NSUTF8StringEncoding] withTimeout:-1 tag:0];
  @synchronized (self.listeningClients) {
    [self.listeningClients addObject:client];
  }

}

- (NSData *)buildHeader1 {
  NSString *info2 = @"c2NyY3B5X2luaXRpYWxQaXhlbCA4AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAQ4AAAJYAAAAAAAAAAAAAAAgwAAAAEAAAAZAAAAAAAAAAAAAAQ4AAAJYAAAAUAAAALQAAAAACMAcAAAAAAAPAoC0ALQAAAAAAAAAAAA/wAAAAAAAAAAAAAAAAAAAAMAAAAWYzIuZXh5bm9zLmgyNjQuZW5jb2RlcgAAABZjMi5hbmRyb2lkLmF2Yy5lbmNvZGVyAAAAF09NWC5nb29nbGUuaDI2NC5lbmNvZGVyAAAAAQ==";
  NSData *da = [[NSData alloc] initWithBase64EncodedString:info2 options:NSDataBase64DecodingIgnoreUnknownCharacters];
  return da;
}

- (NSData *)videoHeaderWithCodec:(uint32_t)codecId width:(uint32_t)width height:(uint32_t)height {
    NSMutableData *data = [NSMutableData dataWithCapacity:12];

    // Convert to big-endian before appending
    uint32_t beCodec = CFSwapInt32HostToBig(codecId);
    uint32_t beWidth = CFSwapInt32HostToBig(width);
    uint32_t beHeight = CFSwapInt32HostToBig(height);

    [data appendBytes:&beCodec length:4];
    [data appendBytes:&beWidth length:4];
    [data appendBytes:&beHeight length:4];

    return data;
}


- (void)didClientDisconnect:(GCDAsyncSocket *)client {
  @synchronized (self.listeningClients) {
    [self.listeningClients removeObject:client];
  }
  [FBLogger log:@"Disconnected a client from screenshots broadcast"];
}


# pragma mark - Save Data

- (NSString *)getH264Path {
  NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
  NSString *filePath = [documentsPath stringByAppendingPathComponent:@"video.h264"];
  [FBLogger logFmt:@"H264 file path at %@",filePath];
  return filePath;
}

- (void)saveEncodedDataToDocuments:(NSData *)data {
   
  if (_dataHandler == nil) {
    NSString *filePath = [self getH264Path];
    _dataHandler = [[DataHandler alloc] initWithFilePath:filePath];
  }
  [_dataHandler receiveData:data];
    
//    NSError *error;
//    if (![data writeToFile:filePath options:NSDataWritingAtomic error:&error]) {
//        [FBLogger logFmt:@"Error saving video data to Documents folder: %@", error.localizedDescription];
//    } else {
//        [FBLogger logFmt:@"Video data saved to Documents folder at path: %@", filePath];
//    }
}

- (void)saveVideoToPhotoLibrary:(NSString *)filePath {
    // Request permission to access the Photo Library
    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
        if (status == PHAuthorizationStatusAuthorized) {
            [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                NSURL *videoURL = [NSURL fileURLWithPath:filePath];
                PHAssetCreationRequest *creationRequest = [PHAssetCreationRequest creationRequestForAssetFromVideoAtFileURL:videoURL];
                [creationRequest setCreationDate:[NSDate date]];
            } completionHandler:^(BOOL success, NSError * _Nullable error) {
                if (success) {
                    NSLog(@"Video saved to Photo Library");
                } else {
                    NSLog(@"Error saving video to Photo Library: %@", error.localizedDescription);
                }
            }];
        } else {
            NSLog(@"Photo Library access denied");
        }
    }];
}

- (void)convertH264ToMP4:(NSData *)h264Data completion:(void (^)(NSString *filePath))completion {
    NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *videoPath = [documentsPath stringByAppendingPathComponent:@"video.mp4"];
    
    // Create AVAssetWriter to write H264 data to MP4 file
    AVAssetWriter *assetWriter = [[AVAssetWriter alloc] initWithURL:[NSURL fileURLWithPath:videoPath] fileType:AVFileTypeQuickTimeMovie error:nil];
    AVAssetWriterInput *writerInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:@{AVVideoCodecKey: AVVideoCodecTypeH264}];
    AVAssetWriterInputPixelBufferAdaptor *adaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:writerInput sourcePixelBufferAttributes:nil];
    
    [assetWriter addInput:writerInput];
    [assetWriter startWriting];
    [assetWriter startSessionAtSourceTime:kCMTimeZero];
    
    // Convert NSData to CVPixelBuffer and write frames
    CVPixelBufferRef pixelBuffer;
  
    [self createPixelBufferFromData:h264Data outputBuffer:&pixelBuffer];
    
    CMTime frameTime = CMTimeMake(0, 30);
    [adaptor appendPixelBuffer:pixelBuffer withPresentationTime:frameTime];
    
    [writerInput markAsFinished];
    [assetWriter finishWritingWithCompletionHandler:^{
        if (completion) {
            completion(videoPath);
        }
    }];
}

- (void)createPixelBufferFromData:(NSData *)data outputBuffer:(CVPixelBufferRef *)buffer {
    // Implement conversion from H264 data to CVPixelBuffer
    // This is a placeholder. You may need a more sophisticated approach
  
}


# pragma mark - H264EncoderDelegate
- (void)didReceiveEncodedData:(NSData *)data {
  [FBLogger logFmt:@"we have some data length: %d =========",data.length];
  [FBLogger logFmt:@"\n%@",data.hexDump];
  
//  [self saveEncodedDataToDocuments:data];
}



#pragma mark - VTCompressionH264EncodeDelegate
- (void)dataCallBack:(NSData *)data frameType:(FrameType)frameType {
  NSMutableData *encodedData = [NSMutableData data];
  [encodedData appendBytes:"\x00\x00\x00\x01" length:4];
  [encodedData appendData:data];
  
//  [self saveEncodedDataToDocuments:encodedData];
  
  [self sendClientData:encodedData];

  
  [FBLogger logFmt:@"we have some frameType = %d data length: %d =========",frameType,data.length + 4 ];

}

- (void)spsppsDataCallBack:(NSData *)sps pps:(NSData *)pps { 
  
  [FBLogger logFmt:@"++++++++ get SPS size =%d && PPS ize =%d",[sps length] + 4 ,[pps length] + 4];
  NSMutableData *SPSData = [NSMutableData data];
  [SPSData appendBytes:"\x00\x00\x00\x01" length:4];
  [SPSData appendData:sps];
  
  NSMutableData *PPSData = [NSMutableData data];
  [PPSData appendBytes:"\x00\x00\x00\x01" length:4];
  [PPSData appendData:pps];
  if ([_encodedData length] > 0) {
    [FBLogger log:@"++++++++ need new _encodedData"];
    _encodedData = [NSMutableData data];
  }

  [_encodedData appendData:SPSData];
  [_encodedData appendData:PPSData];
  
//  [self saveEncodedDataToDocuments:_encodedData];
  
//  [self saveEncodedDataToDocuments:SPSData];
//  [self saveEncodedDataToDocuments:PPSData];
  [self sendClientData:SPSData];
  [self sendClientData:PPSData];

}

- (void)sendClientData:(NSData *) chunk {
  @synchronized (self.listeningClients) {
    for (GCDAsyncSocket *client in self.listeningClients) {
      [client writeData:chunk withTimeout:-1 tag:0];
    }
  }
}

@end
