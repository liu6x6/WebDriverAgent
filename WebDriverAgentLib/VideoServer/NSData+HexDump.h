//
//  NSData+HexDump.h
//  WebDriverAgentLib
//
//  Created by xiao on 2024/7/21.
//  Copyright © 2024 Facebook. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSData (HexDump)

- (NSString *)hexDump;

@end

NS_ASSUME_NONNULL_END
