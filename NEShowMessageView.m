//
//  NEShowMessageView.m
//  Elements
//
//  Created by yongjing.xiao on 2017/7/28.
//  Copyright © 2017年 fengzixiao. All rights reserved.
//

#import "NEShowMessageView.h"
#import <MMProgressHUD.h>

@implementation NEShowMessageView

+ (void)showErrorWithMessage:(NSString *)message
{
    [MMProgressHUD setPresentationStyle:MMProgressHUDPresentationStyleSwingRight];
    [MMProgressHUD setDisplayStyle:MMProgressHUDDisplayStyleBordered];
    [MMProgressHUD dismissWithError:nil title:message afterDelay:2.0];
    
}
+ (void)showSuccessWithMessage:(NSString *)message
{
    [MMProgressHUD setPresentationStyle:MMProgressHUDPresentationStyleSwingRight];
    [MMProgressHUD setDisplayStyle:MMProgressHUDDisplayStyleBordered];
    [MMProgressHUD dismissWithSuccess:nil title:message afterDelay:2.0];
}
+ (void)showStatusWithMessage:(NSString *)message
{
    [MMProgressHUD setPresentationStyle:MMProgressHUDPresentationStyleExpand];
    [MMProgressHUD showWithTitle:nil status:message];
}
+ (void)dismissSuccessView:(NSString *)message
{
    [MMProgressHUD dismissWithSuccess:message];
}
+ (void)dismissErrorView:(NSString *)message
{
    [MMProgressHUD dismissWithError:message];
}

@end
