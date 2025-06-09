//
//  NSData+HexDump.m
//  WebDriverAgentLib
//
//  Created by xiao on 2024/7/21.
//  Copyright © 2024 Facebook. All rights reserved.
//

#import "NSData+HexDump.h"

@implementation NSData (HexDump)

- (NSString *)hexDump {
    const unsigned char *dataBytes = [self bytes];
    NSUInteger length = [self length];
    NSMutableString *hexString = [NSMutableString stringWithCapacity:(length * 3) + (length / 16 * 80)];
    
    // Print column headers
    [hexString appendString:@"      "]; // Initial padding for address offset
    for (int i = 0; i < 16; i++) {
        [hexString appendFormat:@"%02X ", i];
    }
    [hexString appendString:@"  ASCII\n"];
    
    for (NSUInteger i = 0; i < length; i += 16) {
        [hexString appendFormat:@"%04lx  ", (unsigned long)i]; // Address offset
        
        // Hexadecimal bytes
        for (NSUInteger j = 0; j < 16; j++) {
            if (i + j < length) {
                [hexString appendFormat:@"%02X ", dataBytes[i + j]];
            } else {
                [hexString appendString:@"   "]; // Padding for incomplete lines
            }
        }
        
        [hexString appendString:@" "]; // Space between hex and ASCII
        
        // ASCII representation
        for (NSUInteger j = 0; j < 16; j++) {
            if (i + j < length) {
                char byte = dataBytes[i + j];
                [hexString appendFormat:@"%c", (byte >= 32 && byte <= 126) ? byte : '.'];
            }
        }
        
        [hexString appendString:@"\n"];
    }
    
    return hexString;
}

@end
