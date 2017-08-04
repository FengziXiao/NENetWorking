//
//  NENetWorking.m
//  Elements
//
//  Created by yongjing.xiao on 2017/7/28.
//  Copyright © 2017年 fengzixiao. All rights reserved.
//

#import "NENetWorking.h"
#import <AFNetworking.h>
#import <AFNetworkActivityIndicatorManager.h>
#import <AFHTTPSessionManager.h>
#import "NEAppDotNetAPIClient.h"

#import "NEShowMessageView.h"
#include <CommonCrypto/CommonCrypto.h>

#ifndef dispatch_main_async_safe
#define dispatch_main_async_safe(block)\
if (strcmp(dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL), dispatch_queue_get_label(dispatch_get_main_queue())) == 0) {\
block();\
} else {\
dispatch_async(dispatch_get_main_queue(), block);\
}
#endif

/**
 *  基础URL
 */
static NSString *NE_privateNetworkBaseUrl = nil;
/**
 *  是否开启接口打印信息
 */
static BOOL NE_isEnableInterfaceDebug = NO;
/**
 *  是否开启自动转换URL里的中文
 */
static BOOL NE_shouldAutoEncode = NO;
/**
 *  设置请求头，默认为空
 */
static NSDictionary *NE_httpHeaders = nil;
/**
 *  设置的返回数据类型
 */
static NEResponseType NE_responseType = kNEResponseTypeData;
/**
 *  设置的请求数据类型
 */
static NERequestType  NE_requestType  = kNERequestTypePlainText;
/**
 *  监测网络状态
 */
static NENetworkStatus NE_networkStatus = kNENetworkStatusUnknown;
/**
 *  保存所有网络请求的task
 */
static NSMutableArray *NE_requestTasks;
/**
 *  GET请求设置不缓存，Post请求不缓存
 */
static BOOL NE_cacheGet  = NO;
static BOOL NE_cachePost = NO;
/**
 *  是否开启取消请求
 */
static BOOL NE_shouldCallbackOnCancelRequest = YES;
/**
 *  请求的超时时间
 */
static NSTimeInterval NE_timeout = 25.0f;
/**
 *  是否从从本地提取数据
 */
static BOOL NE_shoulObtainLocalWhenUnconnected = NO;
/**
 *  基础url是否更改，默认为yes
 */
static BOOL NE_isBaseURLChanged = YES;
/**
 *  请求管理者
 */
static NEAppDotNetAPIClient *NE_sharedManager = nil;


@implementation NENetWorking

+(void)cacheGetRequest:(BOOL)isCacheGet shoulCachePost:(BOOL)shouldCachePost{
    NE_cacheGet = isCacheGet;
    NE_cachePost = shouldCachePost;
}

+(void)updateBaseUrl:(NSString *)baseUrl{
    if ([baseUrl isEqualToString:NE_privateNetworkBaseUrl] && baseUrl && baseUrl.length) {
        NE_isBaseURLChanged = YES;
    }else{
        NE_isBaseURLChanged = NO;
    }
    NE_privateNetworkBaseUrl = baseUrl;
}

+(NSString *)baseUrl{
    return NE_privateNetworkBaseUrl;
}

+(void)setTimeout:(NSTimeInterval)timeout{
    NE_timeout = timeout;
}

+(void)obtainDataFromLocalWhenNetworkUnconnected:(BOOL)shouldObtain{
    NE_shoulObtainLocalWhenUnconnected = shouldObtain;
}


/**
 开关打印信息

 @param isDebug 是否是debug模式
 */
+(void)enableInterfaceDebug:(BOOL)isDebug{
    NE_isEnableInterfaceDebug = isDebug;
}

/**
 是否是debug模式
 */
+ (BOOL)isDebug {
    return NE_isEnableInterfaceDebug;
}

/**
 沙盒路径

 @return 沙盒路径
 */
static inline NSString *cachePath() {
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/NENetworkingCaches"];
}

/**
 清除缓存
 */
+(void)clearCaches{
    NSString *directoryPath = cachePath();
    if ([[NSFileManager defaultManager] fileExistsAtPath:directoryPath isDirectory:nil]) {
        NSError *error = nil;
        [[NSFileManager defaultManager] removeItemAtPath:directoryPath error:&error];
        if (error) {
            NSLog(@"NENetworking clear caches error: %@", error);
        }else{
            NSLog(@"NENetworking clear caches ok");
        }
    }
}

/**
 获取缓存大小

 @return 缓存大小  M
 */
+(unsigned long long)totalCacheSize{
    NSString *directoryPath = cachePath();
    BOOL isDir = NO;
    unsigned long long total = 0;
    if ([[NSFileManager defaultManager] fileExistsAtPath:directoryPath isDirectory:&isDir]) {
        if (isDir) {
            NSError *error = nil;
            NSArray *array = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directoryPath error:&error];
            
            if (error == nil) {
                for (NSString *subpath in array) {
                    NSString *path = [directoryPath stringByAppendingPathComponent:subpath];
                    NSDictionary *dict = [[NSFileManager defaultManager] attributesOfItemAtPath:path
                                                                                          error:&error];
                    if (!error) {
                        total += [dict[NSFileSize] unsignedIntegerValue];
                    }
                }
            }
        }
    }
    return total;
}

+ (NSMutableArray *)allTasks {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (NE_requestTasks == nil) {
            NE_requestTasks = @[].mutableCopy;
        }
    });
    
    return NE_requestTasks;
}

+(void)cancelAllRequest{
    @synchronized (self) {
        [[self allTasks] enumerateObjectsUsingBlock:^(NEURLSessionTask * _Nonnull task, NSUInteger idx, BOOL * _Nonnull stop) {
            if ([task isKindOfClass:[NEURLSessionTask class]]) {
                [task cancel];
            }
        }];
        
        [[self allTasks] removeAllObjects];
    }
}

+(void)cancelRequestWithURL:(NSString *)url{
    if (url == nil) {
        return;
    }
    @synchronized(self) {
        [[self allTasks] enumerateObjectsUsingBlock:^(NEURLSessionTask * _Nonnull task, NSUInteger idx, BOOL * _Nonnull stop) {
            if ([task isKindOfClass:[NEURLSessionTask class]]
                && [task.currentRequest.URL.absoluteString hasSuffix:url]) {
                [task cancel];
                [[self allTasks] removeObject:task];
                return;
            }
        }];
    };
}

+(void)configRequestType:(NERequestType)requestType responseType:(NEResponseType)responseType shouldAutoEncodeUrl:(BOOL)shouldAutoEncode callbackOnCancelRequest:(BOOL)shouldCallbackOnCancelRequest{
    NE_requestType = requestType;
    NE_responseType = responseType;
    NE_shouldAutoEncode = shouldAutoEncode;
    NE_shouldCallbackOnCancelRequest = shouldCallbackOnCancelRequest;
}

+ (BOOL)shouldEncode {
    return NE_shouldAutoEncode;
}

+(void)configCommonHttpHeaders:(NSDictionary *)httpHeaders{
    NE_httpHeaders = httpHeaders;
}

// 无进度回调 无提示框
+ (NEURLSessionTask *)getWithUrl:(NSString *)url
                    refreshCache:(BOOL)refreshCache
                         success:(NEResponseSuccess)success
                            fail:(NEResponseFail)fail{
    return [self NE_requestWithUrl:url
                      refreshCache:refreshCache
                         isShowHUD:NO
                           showHUD:nil
                         httpMedth:1
                            params:nil
                          progress:nil
                           success:success
                              fail:fail];
}

// 无进度回调 有提示框
+ (NEURLSessionTask *)getWithUrl:(NSString *)url
                    refreshCache:(BOOL)refreshCache
                         showHUD:(NSString *)statusText
                         success:(NEResponseSuccess)success
                            fail:(NEResponseFail)fail{
    return [self NE_requestWithUrl:url
                      refreshCache:refreshCache
                         isShowHUD:YES
                           showHUD:statusText
                         httpMedth:1
                            params:nil
                          progress:nil
                           success:success
                              fail:fail];
}

// 无进度回调 无提示框
+ (NEURLSessionTask *)getWithUrl:(NSString *)url
                    refreshCache:(BOOL)refreshCache
                          params:(NSDictionary *)params
                         success:(NEResponseSuccess)success
                            fail:(NEResponseFail)fail{
    return [self NE_requestWithUrl:url
                      refreshCache:refreshCache
                         isShowHUD:NO
                           showHUD:nil
                         httpMedth:1
                            params:params
                          progress:nil
                           success:success
                              fail:fail];
}

// 无进度回调 有提示框
+ (NEURLSessionTask *)getWithUrl:(NSString *)url
                    refreshCache:(BOOL)refreshCache
                         showHUD:(NSString *)statusText
                          params:(NSDictionary *)params
                         success:(NEResponseSuccess)success
                            fail:(NEResponseFail)fail{
    return [self NE_requestWithUrl:url
                      refreshCache:refreshCache
                         isShowHUD:YES
                           showHUD:statusText
                         httpMedth:1
                            params:params
                          progress:nil
                           success:success
                              fail:fail];
}

// 有进度回调 无提示框
+ (NEURLSessionTask *)getWithUrl:(NSString *)url
                    refreshCache:(BOOL)refreshCache
                          params:(NSDictionary *)params
                        progress:(NEGetProgress)progress
                         success:(NEResponseSuccess)success
                            fail:(NEResponseFail)fail {
    return [self NE_requestWithUrl:url
                      refreshCache:refreshCache
                         isShowHUD:NO
                           showHUD:nil
                         httpMedth:1
                            params:params
                          progress:progress
                           success:success
                              fail:fail];
}

// 有进度回调 有提示框
+ (NEURLSessionTask *)getWithUrl:(NSString *)url
                    refreshCache:(BOOL)refreshCache
                         showHUD:(NSString *)statusText
                          params:(NSDictionary *)params
                        progress:(NEGetProgress)progress
                         success:(NEResponseSuccess)success
                            fail:(NEResponseFail)fail{
    return [self NE_requestWithUrl:url
                      refreshCache:refreshCache
                         isShowHUD:YES
                           showHUD:statusText
                         httpMedth:1
                            params:params
                          progress:progress
                           success:success
                              fail:fail];
}

/**
 *  无进度回调 无提示框
 */

+ (NEURLSessionTask *)postWithUrl:(NSString *)url
                     refreshCache:(BOOL)refreshCache
                           params:(NSDictionary *)params
                          success:(NEResponseSuccess)success
                             fail:(NEResponseFail)fail{
    return [self NE_requestWithUrl:url
                      refreshCache:refreshCache
                         isShowHUD:NO
                           showHUD:nil
                         httpMedth:2
                            params:params
                          progress:nil
                           success:success
                              fail:fail];
}

/**
 *  无进度回调 有提示框
 *
 */
+ (NEURLSessionTask *)postWithUrl:(NSString *)url
                     refreshCache:(BOOL)refreshCache
                          showHUD:(NSString *)statusText
                           params:(NSDictionary *)params
                          success:(NEResponseSuccess)success
                             fail:(NEResponseFail)fail{
    return [self NE_requestWithUrl:url
                      refreshCache:refreshCache
                         isShowHUD:YES
                           showHUD:statusText
                         httpMedth:2
                            params:params
                          progress:nil
                           success:success
                              fail:fail];
}
// 有进度回调 无提示框
+ (NEURLSessionTask *)postWithUrl:(NSString *)url
                     refreshCache:(BOOL)refreshCache
                           params:(NSDictionary *)params
                         progress:(NEPostProgress)progress
                          success:(NEResponseSuccess)success
                             fail:(NEResponseFail)fail {
    
    return [self NE_requestWithUrl:url
                      refreshCache:refreshCache
                         isShowHUD:NO
                           showHUD:nil
                         httpMedth:2
                            params:params
                          progress:progress
                           success:success
                              fail:fail];
}
// 有进度回调 有提示框
+ (NEURLSessionTask *)postWithUrl:(NSString *)url
                     refreshCache:(BOOL)refreshCache
                          showHUD:(NSString *)statusText
                           params:(NSDictionary *)params
                         progress:(NEPostProgress)progress
                          success:(NEResponseSuccess)success
                             fail:(NEResponseFail)fail{
    
    return [self NE_requestWithUrl:url
                      refreshCache:refreshCache
                         isShowHUD:YES
                           showHUD:statusText
                         httpMedth:2
                            params:params
                          progress:progress
                           success:success
                              fail:fail];
}


+ (NEURLSessionTask *)NE_requestWithUrl:(NSString *)url
                           refreshCache:(BOOL)refreshCache
                              isShowHUD:(BOOL)isShowHUD
                                showHUD:(NSString *)statusText
                              httpMedth:(NSUInteger)httpMethod
                                 params:(NSDictionary *)params
                               progress:(NEDownloadProgress)progress
                                success:(NEResponseSuccess)success
                                   fail:(NEResponseFail)fail {
    
    if (url) {
        if ([url hasPrefix:@"http://"] || [url hasPrefix:@"https://"]) {
            
        }else{
            return nil;
        }
    }else{
        return nil;
    }
    
    if ([self shouldEncode]) {
        url = [self encodeUrl:url];
    }
    
    NEAppDotNetAPIClient *manager = [self manager];
    NSString *absolute = [self absoluteUrlWithPath:url];
    
    NEURLSessionTask *session = nil;
    //显示提示框
    if (isShowHUD) {
        [NENetWorking showHUD:statusText];
    }
    
    if (httpMethod == 1) {
        if (NE_cacheGet) {
            if (NE_shoulObtainLocalWhenUnconnected) {
                if (NE_networkStatus == kNENetworkStatusNotReachable || NE_networkStatus == kNENetworkStatusUnknown) {
                    id response = [NENetWorking cahceResponseWithURL:absolute
                                                          parameters:params];
                    if (response) {
                        if (success) {
                            [self successResponse:response callback:success];
                            if ([self isDebug]) {
                                [self logWithSuccessResponse:response
                                                         url:absolute
                                                      params:params];
                            }
                        }
                        return nil;
                    }
                }
            }
            if (!refreshCache) {
                id response = [NENetWorking cahceResponseWithURL:absolute
                                                      parameters:params];
                if (response) {
                    if (success) {
                        [self successResponse:response callback:success];
                        
                        if ([self isDebug]) {
                            [self logWithSuccessResponse:response
                                                     url:absolute
                                                  params:params];
                        }
                    }
                    return nil;
                }
            }
        }
        session = [manager GET:url parameters:params progress:^(NSProgress * _Nonnull downloadProgress) {
            if (progress) {
                progress(downloadProgress.completedUnitCount, downloadProgress.totalUnitCount);
            }
        } success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
            
            // 移除提示框
            if (isShowHUD) {
                [NENetWorking dismissSuccessHUD];
            }
            
            [[self allTasks] removeObject:task];
            
            [self successResponse:responseObject callback:success];
            
            if (NE_cacheGet) {
                [self cacheResponseObject:responseObject request:task.currentRequest parameters:params];
            }
            
            if ([self isDebug]) {
                [self logWithSuccessResponse:responseObject
                                         url:absolute
                                      params:params];
            }
            
            
        } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
            // 移除提示框
            if (isShowHUD) {
                [NENetWorking dismissErrorHUD];
            }
            [[self allTasks] removeObject:task];
            
            if ([error code] < 0 && NE_cacheGet) {// 获取缓存
                id response = [NENetWorking cahceResponseWithURL:absolute
                                                      parameters:params];
                if (response) {
                    if (success) {
                        [self successResponse:response callback:success];
                        
                        if ([self isDebug]) {
                            [self logWithSuccessResponse:response
                                                     url:absolute
                                                  params:params];
                        }
                    }
                } else {
                    [self handleCallbackWithError:error fail:fail];
                    
                    if ([self isDebug]) {
                        [self logWithFailError:error url:absolute params:params];
                    }
                }
            } else {
                [self handleCallbackWithError:error fail:fail];
                
                if ([self isDebug]) {
                    [self logWithFailError:error url:absolute params:params];
                }
            }
        }];
    }
    else if (httpMethod == 2) {
        if (NE_cachePost ) {// 获取缓存
            if (NE_shoulObtainLocalWhenUnconnected) {
                if (NE_networkStatus == kNENetworkStatusNotReachable ||  NE_networkStatus == kNENetworkStatusUnknown ) {
                    id response = [NENetWorking cahceResponseWithURL:absolute
                                                          parameters:params];
                    if (response) {
                        if (success) {
                            [self successResponse:response callback:success];
                            
                            if ([self isDebug]) {
                                [self logWithSuccessResponse:response
                                                         url:absolute
                                                      params:params];
                            }
                        }
                        return nil;
                    }
                }
            }
            if (!refreshCache) {
                id response = [NENetWorking cahceResponseWithURL:absolute
                                                      parameters:params];
                if (response) {
                    if (success) {
                        [self successResponse:response callback:success];
                        
                        if ([self isDebug]) {
                            [self logWithSuccessResponse:response
                                                     url:absolute
                                                  params:params];
                        }
                    }
                    return nil;
                }
            }
        }
        
        
        session = [manager POST:url parameters:params progress:^(NSProgress * _Nonnull downloadProgress) {
            if (progress) {
                progress(downloadProgress.completedUnitCount, downloadProgress.totalUnitCount);
            }
        } success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
            
            // 移除提示框
            if (isShowHUD) {
                [NENetWorking dismissSuccessHUD];
            }
            
            [[self allTasks] removeObject:task];
            
            [self successResponse:responseObject callback:success];
            
            if (NE_cachePost) {
                [self cacheResponseObject:responseObject request:task.currentRequest  parameters:params];
            }
            
            if ([self isDebug]) {
                [self logWithSuccessResponse:responseObject
                                         url:absolute
                                      params:params];
            }
            
            
        } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
            // 移除提示框
            if (isShowHUD) {
                [NENetWorking dismissErrorHUD];
            }
            [[self allTasks] removeObject:task];
            if ([error code] < 0 && NE_cachePost) {// 获取缓存
                id response = [NENetWorking cahceResponseWithURL:absolute
                                                      parameters:params];
                
                if (response) {
                    if (success) {
                        [self successResponse:response callback:success];
                        
                        if ([self isDebug]) {
                            [self logWithSuccessResponse:response
                                                     url:absolute
                                                  params:params];
                        }
                    }
                } else {
                    [self handleCallbackWithError:error fail:fail];
                    
                    if ([self isDebug]) {
                        [self logWithFailError:error url:absolute params:params];
                    }
                }
            } else {
                [self handleCallbackWithError:error fail:fail];
                
                if ([self isDebug]) {
                    [self logWithFailError:error url:absolute params:params];
                }
            }
        }];
    }
    if (session) {
        [[self allTasks] addObject:session];
    }
    return session;
}

+(NEURLSessionTask *)uploadFileWithUrl:(NSString *)url uploadingFile:(NSString *)uploadingFile progress:(NEUploadProgress)progress success:(NEResponseSuccess)success fail:(NEResponseFail)fail{
    if ([NSURL URLWithString:uploadingFile] == nil) {
        
        return nil;
    }
    
    NSURL *uploadURL = nil;
    if ([self baseUrl] == nil) {
        uploadURL = [NSURL URLWithString:url];
    } else {
        uploadURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", [self baseUrl], url]];
    }
    
    if (uploadURL == nil) {
        
        return nil;
    }
    
    NEAppDotNetAPIClient *manager = [self manager];
    NSURLRequest *request = [NSURLRequest requestWithURL:uploadURL];
    NEURLSessionTask *session = nil;
    
    [manager uploadTaskWithRequest:request fromFile:[NSURL URLWithString:uploadingFile] progress:^(NSProgress * _Nonnull uploadProgress) {
        if (progress) {
            progress(uploadProgress.completedUnitCount, uploadProgress.totalUnitCount);
        }
    } completionHandler:^(NSURLResponse * _Nonnull response, id  _Nullable responseObject, NSError * _Nullable error) {
        [[self allTasks] removeObject:session];
        
        [self successResponse:responseObject callback:success];
        
        if (error) {
            [self handleCallbackWithError:error fail:fail];
            
            if ([self isDebug]) {
                [self logWithFailError:error url:response.URL.absoluteString params:nil];
            }
        } else {
            if ([self isDebug]) {
                [self logWithSuccessResponse:responseObject
                                         url:response.URL.absoluteString
                                      params:nil];
            }
        }
    }];
    
    if (session) {
        [[self allTasks] addObject:session];
    }
    
    return session;
}

+ (NEURLSessionTask *)uploadWithImage:(UIImage *)image
                                  url:(NSString *)url
                             filename:(NSString *)filename
                                 name:(NSString *)name
                             mimeType:(NSString *)mimeType
                           parameters:(NSDictionary *)parameters
                             progress:(NEUploadProgress)progress
                              success:(NEResponseSuccess)success
                                 fail:(NEResponseFail)fail {
    if ([self baseUrl] == nil) {
        if ([NSURL URLWithString:url] == nil) {
            
            return nil;
        }
    } else {
        if ([NSURL URLWithString:[NSString stringWithFormat:@"%@%@", [self baseUrl], url]] == nil) {
            
            return nil;
        }
    }
    
    if ([self shouldEncode]) {
        url = [self encodeUrl:url];
    }
    
    NSString *absolute = [self absoluteUrlWithPath:url];
    
    NEAppDotNetAPIClient *manager = [self manager];
    NEURLSessionTask *session = [manager POST:url parameters:parameters constructingBodyWithBlock:^(id<AFMultipartFormData>  _Nonnull formData) {
        NSData *imageData = UIImageJPEGRepresentation(image, 1);
        
        NSString *imageFileName = filename;
        if (filename == nil || ![filename isKindOfClass:[NSString class]] || filename.length == 0) {
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            formatter.dateFormat = @"yyyyMMddHHmmss";
            NSString *str = [formatter stringFromDate:[NSDate date]];
            imageFileName = [NSString stringWithFormat:@"%@.jpg", str];
        }
        
        // 上传图片，以文件流的格式
        [formData appendPartWithFileData:imageData name:name fileName:imageFileName mimeType:mimeType];
    } progress:^(NSProgress * _Nonnull uploadProgress) {
        if (progress) {
            progress(uploadProgress.completedUnitCount, uploadProgress.totalUnitCount);
        }
    } success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        [[self allTasks] removeObject:task];
        [self successResponse:responseObject callback:success];
        
        if ([self isDebug]) {
            [self logWithSuccessResponse:responseObject
                                     url:absolute
                                  params:parameters];
        }
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        [[self allTasks] removeObject:task];
        
        [self handleCallbackWithError:error fail:fail];
        
        if ([self isDebug]) {
            [self logWithFailError:error url:absolute params:nil];
        }
    }];
    
    
    if (session) {
        [[self allTasks] addObject:session];
    }
    
    return session;
}

+ (NEURLSessionTask *)downloadWithUrl:(NSString *)url
                           saveToPath:(NSString *)saveToPath
                             progress:(NEDownloadProgress)progressBlock
                              success:(NEResponseSuccess)success
                              failure:(NEResponseFail)failure {
    if ([self baseUrl] == nil) {
        if ([NSURL URLWithString:url] == nil) {
            
            return nil;
        }
    } else {
        if ([NSURL URLWithString:[NSString stringWithFormat:@"%@%@", [self baseUrl], url]] == nil) {
            
            return nil;
        }
    }
    
    NSURLRequest *downloadRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:url]];
    NEAppDotNetAPIClient *manager = [self manager];
    
    NEURLSessionTask *session = nil;
    
    session = [manager downloadTaskWithRequest:downloadRequest progress:^(NSProgress * _Nonnull downloadProgress) {
        if (progressBlock) {
            progressBlock(downloadProgress.completedUnitCount, downloadProgress.totalUnitCount);
        }
    } destination:^NSURL * _Nonnull(NSURL * _Nonnull targetPath, NSURLResponse * _Nonnull response) {
        return [NSURL fileURLWithPath:saveToPath];
    } completionHandler:^(NSURLResponse * _Nonnull response, NSURL * _Nullable filePath, NSError * _Nullable error) {
        [[self allTasks] removeObject:session];
        
        if (error == nil) {
            if (success) {
                success(filePath.absoluteString);
            }
            
            if ([self isDebug]) {
                NSLog(@"Download success for url %@",
                      [self absoluteUrlWithPath:url]);
            }
        } else {
            [self handleCallbackWithError:error fail:failure];
            
            if ([self isDebug]) {
                NSLog(@"Download fail for url %@, reason : %@",
                      [self absoluteUrlWithPath:url],
                      [error description]);
            }
        }
    }];
    
    if (session) {
        [[self allTasks] addObject:session];
    }
    
    return session;
}


+ (NSString *)encodeUrl:(NSString *)url {
    return [self NE_URLEncode:url];
}

+ (NSString *)NE_URLEncode:(NSString *)url {
    if ([url respondsToSelector:@selector(stringByAddingPercentEncodingWithAllowedCharacters:)]) {
        
        static NSString * const kAFCharacterHTeneralDelimitersToEncode = @":#[]@";
        static NSString * const kAFCharactersSubDelimitersToEncode = @"!$&'()*+,;=";
        
        NSMutableCharacterSet * allowedCharacterSet = [[NSCharacterSet URLQueryAllowedCharacterSet] mutableCopy];
        [allowedCharacterSet removeCharactersInString:[kAFCharacterHTeneralDelimitersToEncode stringByAppendingString:kAFCharactersSubDelimitersToEncode]];
        static NSUInteger const batchSize = 50;
        
        NSUInteger index = 0;
        NSMutableString *escaped = @"".mutableCopy;
        
        while (index < url.length) {
            NSUInteger length = MIN(url.length - index, batchSize);
            NSRange range = NSMakeRange(index, length);
            range = [url rangeOfComposedCharacterSequencesForRange:range];
            NSString *substring = [url substringWithRange:range];
            NSString *encoded = [substring stringByAddingPercentEncodingWithAllowedCharacters:allowedCharacterSet];
            [escaped appendString:encoded];
            
            index += range.length;
        }
        return escaped;
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        CFStringEncoding cfEncoding = CFStringConvertNSStringEncodingToEncoding(NSUTF8StringEncoding);
        NSString *encoded = (__bridge_transfer NSString *)
        CFURLCreateStringByAddingPercentEscapes(
                                                kCFAllocatorDefault,
                                                (__bridge CFStringRef)url,
                                                NULL,
                                                CFSTR("!#$&'()*+,/:;=?@[]"),
                                                cfEncoding);
        return encoded;
#pragma clang diagnostic pop
    }
}

#pragma mark - Private
+ (NEAppDotNetAPIClient *)manager {
    
    @synchronized (self) {
        
        if (NE_sharedManager == nil || NE_isBaseURLChanged) {
            // 开启转圈圈
            [AFNetworkActivityIndicatorManager sharedManager].enabled = YES;
            
            NEAppDotNetAPIClient *manager = nil;;
            if ([self baseUrl] != nil) {
                manager = [[NEAppDotNetAPIClient sharedClient] initWithBaseURL:[NSURL URLWithString:[self baseUrl]]];
            } else {
                manager = [NEAppDotNetAPIClient sharedClient];
            }
            
            switch (NE_requestType) {
                case kNERequestTypeJSON: {
                    manager.requestSerializer = [AFJSONRequestSerializer serializer];
                    break;
                }
                case kNERequestTypePlainText: {
                    manager.requestSerializer = [AFHTTPRequestSerializer serializer];
                    break;
                }
                default: {
                    break;
                }
            }
            
            switch (NE_responseType) {
                case kNEResponseTypeJSON: {
                    manager.responseSerializer = [AFJSONResponseSerializer serializer];
                    break;
                }
                case kNEResponseTypeXML: {
                    manager.responseSerializer = [AFXMLParserResponseSerializer serializer];
                    break;
                }
                case kNEResponseTypeData: {
                    manager.responseSerializer = [AFHTTPResponseSerializer serializer];
                    break;
                }
                default: {
                    break;
                }
            }
            
            manager.requestSerializer.stringEncoding = NSUTF8StringEncoding;
            
            
            for (NSString *key in NE_httpHeaders.allKeys) {
                if (NE_httpHeaders[key] != nil) {
                    [manager.requestSerializer setValue:NE_httpHeaders[key] forHTTPHeaderField:key];
                }
            }
            
            // 设置cookie
            //            [self setUpCoookie];
            
            manager.responseSerializer.acceptableContentTypes = [NSSet setWithArray:@[@"application/json",
                                                                                      @"text/html",
                                                                                      @"text/json",
                                                                                      @"text/plain",
                                                                                      @"text/javascript",
                                                                                      @"text/xml",
                                                                                      @"image/*"]];
            
            manager.requestSerializer.timeoutInterval = NE_timeout;
            
            manager.operationQueue.maxConcurrentOperationCount = 3;
            NE_sharedManager = manager;
        }
    }
    
    return NE_sharedManager;
}

+ (NSString *)absoluteUrlWithPath:(NSString *)path {
    if (path == nil || path.length == 0) {
        return @"";
    }
    
    if ([self baseUrl] == nil || [[self baseUrl] length] == 0) {
        return path;
    }
    
    NSString *absoluteUrl = path;
    
    if (![path hasPrefix:@"http://"] && ![path hasPrefix:@"https://"]) {
        if ([[self baseUrl] hasSuffix:@"/"]) {
            if ([path hasPrefix:@"/"]) {
                NSMutableString * mutablePath = [NSMutableString stringWithString:path];
                [mutablePath deleteCharactersInRange:NSMakeRange(0, 1)];
                absoluteUrl = [NSString stringWithFormat:@"%@%@",
                               [self baseUrl], mutablePath];
            }else {
                absoluteUrl = [NSString stringWithFormat:@"%@%@",[self baseUrl], path];
            }
        }else {
            if ([path hasPrefix:@"/"]) {
                absoluteUrl = [NSString stringWithFormat:@"%@%@",[self baseUrl], path];
            }else {
                absoluteUrl = [NSString stringWithFormat:@"%@/%@",
                               [self baseUrl], path];
            }
        }
    }
    
    
    return absoluteUrl;
}



+ (id)cahceResponseWithURL:(NSString *)url parameters:params {
    id cacheData = nil;
    
    if (url) {
        
        NSString *directoryPath = cachePath();
        NSString *absoluteURL = [self generateGETAbsoluteURL:url params:params];
        NSString *key = [self md5String:absoluteURL];
        NSString *path = [directoryPath stringByAppendingPathComponent:key];
        
        NSData *data = [[NSFileManager defaultManager] contentsAtPath:path];
        if (data) {
            cacheData = data;
            NSLog(@"Read data from cache for url: %@\n", url);
        }
    }
    
    return cacheData;
}

+ (NSString *)generateGETAbsoluteURL:(NSString *)url params:(NSDictionary *)params {
    if (params == nil || ![params isKindOfClass:[NSDictionary class]] || [params count] == 0) {
        return url;
    }
    
    NSString *queries = @"";
    for (NSString *key in params) {
        id value = [params objectForKey:key];
        
        if ([value isKindOfClass:[NSDictionary class]]) {
            continue;
        } else if ([value isKindOfClass:[NSArray class]]) {
            continue;
        } else if ([value isKindOfClass:[NSSet class]]) {
            continue;
        } else {
            queries = [NSString stringWithFormat:@"%@%@=%@&",
                       (queries.length == 0 ? @"&" : queries),
                       key,
                       value];
        }
    }
    
    if (queries.length > 1) {
        queries = [queries substringToIndex:queries.length - 1];
    }
    
    if (([url hasPrefix:@"http://"] || [url hasPrefix:@"https://"]) && queries.length > 1) {
        if ([url rangeOfString:@"?"].location != NSNotFound
            || [url rangeOfString:@"#"].location != NSNotFound) {
            url = [NSString stringWithFormat:@"%@%@", url, queries];
        } else {
            queries = [queries substringFromIndex:1];
            url = [NSString stringWithFormat:@"%@?%@", url, queries];
        }
    }
    
    return url.length == 0 ? queries : url;
}

+(NSString *)md5String:(NSString *)absoluteURL{
    NSData *data = [absoluteURL dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char result[CC_MD5_DIGEST_LENGTH];
    CC_MD5(data.bytes, (CC_LONG)data.length, result);
    return [NSString stringWithFormat:
            @"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
            result[0], result[1], result[2], result[3],
            result[4], result[5], result[6], result[7],
            result[8], result[9], result[10], result[11],
            result[12], result[13], result[14], result[15]
            ];
}

+ (void)successResponse:(id)responseData callback:(NEResponseSuccess)success {
    if (success) {
        success([self tryToParseData:responseData]);
    }
}

// 解析json数据
+ (id)tryToParseData:(id)json {
    if (!json || json == (id)kCFNull) return nil;
    NSDictionary *dic = nil;
    NSData *jsonData = nil;
    if ([json isKindOfClass:[NSDictionary class]]) {
        dic = json;
    } else if ([json isKindOfClass:[NSString class]]) {
        jsonData = [(NSString *)json dataUsingEncoding : NSUTF8StringEncoding];
    } else if ([json isKindOfClass:[NSData class]]) {
        jsonData = json;
    }
    if (jsonData) {
        dic = [NSJSONSerialization JSONObjectWithData:jsonData options:kNilOptions error:NULL];
        if (![dic isKindOfClass:[NSDictionary class]]) dic = nil;
    }
    return dic;
}

+ (void)cacheResponseObject:(id)responseObject request:(NSURLRequest *)request parameters:params {
    if (request && responseObject && ![responseObject isKindOfClass:[NSNull class]]) {
        NSString *directoryPath = cachePath();
        
        NSError *error = nil;
        
        if (![[NSFileManager defaultManager] fileExistsAtPath:directoryPath isDirectory:nil]) {
            [[NSFileManager defaultManager] createDirectoryAtPath:directoryPath
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:&error];
            if (error) {
                NSLog(@"create cache dir error: %@\n", error);
                return;
            }
        }
        
        NSString *absoluteURL = [self generateGETAbsoluteURL:request.URL.absoluteString params:params];
        NSString *key = [self md5String:absoluteURL];
        NSString *path = [directoryPath stringByAppendingPathComponent:key];
        NSDictionary *dict = (NSDictionary *)responseObject;
        
        NSData *data = nil;
        if ([dict isKindOfClass:[NSData class]]) {
            data = responseObject;
        } else {
            data = [NSJSONSerialization dataWithJSONObject:dict
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:&error];
        }
        
        if (data && error == nil) {
            BOOL isOk = [[NSFileManager defaultManager] createFileAtPath:path contents:data attributes:nil];
            if (isOk) {
                NSLog(@"cache file ok for request: %@\n", absoluteURL);
            } else {
                NSLog(@"cache file error for request: %@\n", absoluteURL);
            }
        }
    }
}

+ (void)handleCallbackWithError:(NSError *)error fail:(NEResponseFail)fail {
    if ([error code] == NSURLErrorCancelled) {
        if (NE_shouldCallbackOnCancelRequest) {
            if (fail) {
                fail(error);
            }
        }
    } else {
        if (fail) {
            fail(error);
        }
    }
}

+ (void)logWithSuccessResponse:(id)response url:(NSString *)url params:(NSDictionary *)params {
    NSLog(@"\n");
    NSLog(@"\nRequest success, URL: %@\n params:%@\n response:%@\n\n",
          [self generateGETAbsoluteURL:url params:params],
          params,
          [self tryToParseData:response]);
}

+ (void)logWithFailError:(NSError *)error url:(NSString *)url params:(id)params {
    NSString *format = @" params: ";
    if (params == nil || ![params isKindOfClass:[NSDictionary class]]) {
        format = @"";
        params = @"";
    }
    
    NSLog(@"\n");
    if ([error code] == NSURLErrorCancelled) {
        NSLog(@"\nRequest was canceled mannully, URL: %@ %@%@\n\n",
              [self generateGETAbsoluteURL:url params:params],
              format,
              params);
    } else {
        NSLog(@"\nRequest error, URL: %@ %@%@\n errorInfos:%@\n\n",
              [self generateGETAbsoluteURL:url params:params],
              format,
              params,
              [error localizedDescription]);
    }
}

#pragma mark - HUD

+ (void)showHUD:(NSString *)showMessge
{
    
    
    dispatch_main_async_safe(^{
        [NEShowMessageView showStatusWithMessage:showMessge];
        
        //        [[HTAlertShowView sharedAlertManager] showHTAlertView];
    });
}

+ (void)dismissSuccessHUD
{
    dispatch_main_async_safe(^{
        [NEShowMessageView dismissSuccessView:@"success"];
        //        [[HTAlertShowView sharedAlertManager] dismissAlertView];
    });
    
}
+ (void)dismissErrorHUD
{
    dispatch_main_async_safe(^{
        [NEShowMessageView dismissErrorView:@"Error"];
        //        [[HTAlertShowView sharedAlertManager] dismissAlertView];
    });
    
}


@end
