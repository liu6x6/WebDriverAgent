//
//  H264Encoder.h
//  WebDriverAgentLib
//
//  Created by xiao on 2024/7/16.
//  Copyright © 2024 Facebook. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <Foundation/Foundation.h>

@protocol H264EncoderDelegate <NSObject>

- (void)didReceiveEncodedData:(NSData *)data;

@end



NS_ASSUME_NONNULL_BEGIN

@interface H264Encoder : NSObject


@property (nonatomic, weak) id<H264EncoderDelegate> delegate;

- (instancetype)initWithWidth:(int)width height:(int)height;
- (void)encodeJPEGToH264:(NSData *)jpegData;
- (void)endEncoding;

@end

NS_ASSUME_NONNULL_END
