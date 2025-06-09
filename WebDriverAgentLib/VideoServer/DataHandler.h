//
//  DataHandler.h
//  WebDriverAgentLib
//
//  Created by xiao on 2024/7/21.
//  Copyright © 2024 Facebook. All rights reserved.
//
 


#import <Foundation/Foundation.h>

@interface DataHandler : NSObject

@property (nonatomic, strong) NSMutableData *cache;
@property (nonatomic, assign) NSUInteger cacheSize;
@property (nonatomic, strong) NSString *filePath;

- (instancetype)initWithFilePath:(NSString *)filePath;
- (void)receiveData:(NSData *)data;
- (void)writeCacheToFile;

@end
