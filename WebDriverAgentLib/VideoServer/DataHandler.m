//
//  DataHandler.m
//  WebDriverAgentLib
//
//  Created by xiao on 2024/7/21.
//  Copyright © 2024 Facebook. All rights reserved.
//

#import "DataHandler.h"
#import "FBLogger.h"

 

@implementation DataHandler

- (instancetype)initWithFilePath:(NSString *)filePath {
    self = [super init];
    if (self) {
        _cacheSize = 1 * 1024 * 1024; // 1 MB
        _cache = [[NSMutableData alloc] init];
        _filePath = filePath;
    }
    return self;
}

- (void)receiveData:(NSData *)data {
    [self.cache appendData:data];
    
    if ([self.cache length] >= self.cacheSize) {
        [self writeCacheToFile];
        self.cache = [[NSMutableData alloc] init]; // Reset the cache
    }
}

- (void)writeCacheToFile {
    
  [FBLogger logFmt:@"Write Data to file: %@",self.filePath];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:self.filePath]) {
        [fileManager createFileAtPath:self.filePath contents:nil attributes:nil];
    }
    
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:self.filePath];
    [fileHandle seekToEndOfFile];
    [fileHandle writeData:self.cache];
    [fileHandle closeFile];
}

@end

//
//        DataHandler *dataHandler = [[DataHandler alloc] initWithFilePath:@"/path/to/your/file.dat"];
//        
//        // Simulating receiving data
//        NSData *receivedData = [@"Some data" dataUsingEncoding:NSUTF8StringEncoding];
//        [dataHandler receiveData:receivedData];
//        
//        // Make sure to write remaining data if the cache is not full when the application ends
//if ([dataHandler.cache length] > 0) {
//  [dataHandler writeCacheToFile];
//
//}
