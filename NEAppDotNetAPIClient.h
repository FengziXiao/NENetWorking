//
//  NEAppDotNetAPIClient.h
//  Elements
//
//  Created by yongjing.xiao on 2017/7/28.
//  Copyright © 2017年 fengzixiao. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AFNetworking/AFNetworking.h>


@interface NEAppDotNetAPIClient : AFHTTPSessionManager

+ (instancetype)sharedClient;

@end
