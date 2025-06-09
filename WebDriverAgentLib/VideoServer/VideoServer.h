//
//  VideoServer.h
//  WebDriverAgentLib
//
//  Created by xiao on 2024/7/16.
//  Copyright © 2024 Facebook. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "FBTCPSocket.h"
#import "H264Encoder.h"
#import "VTCompressionH264Encode.h"


NS_ASSUME_NONNULL_BEGIN


@interface VideoServer : NSObject <FBTCPSocketDelegate,H264EncoderDelegate,VTCompressionH264EncodeDelegate>

- (instancetype)init;

@end

NS_ASSUME_NONNULL_END
