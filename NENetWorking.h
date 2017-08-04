//
//  NENetWorking.h
//  Elements
//
//  Created by yongjing.xiao on 2017/7/28.
//  Copyright © 2017年 fengzixiao. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

/*
 *
 *  下载进度
 *
 *  @param bytesRead                 已下载的大小
 *  @param totalBytesRead            文件总大小
 *  @param totalBytesExpectedToRead  还有多少需要下载
 */
typedef void (^NEDownloadProgress)(int64_t bytesRead,
                                  int64_t totalBytesRead);
typedef NEDownloadProgress NEGetProgress;
typedef NEDownloadProgress NEPostProgress;

/*
 *
 *  上传进度
 *
 *  @param bytesWritten              已上传的大小
 *  @param totalBytesWritten         总上传大小
 */
typedef void (^NEUploadProgress)(int64_t bytesWritten,
int64_t totalBytesWritten);

typedef NS_ENUM(NSUInteger, NEResponseType) {
    kNEResponseTypeJSON = 1, // 默认
    kNEResponseTypeXML  = 2, // XML
    kNEResponseTypeData = 3  //
};

typedef NS_ENUM(NSUInteger, NERequestType) {
    kNERequestTypeJSON = 1,       // 默认
    kNERequestTypePlainText  = 2  // 普通text/html
};

typedef NS_ENUM(NSInteger, NENetworkStatus) {
    kNENetworkStatusUnknown          = -1,  //未知网络
    kNENetworkStatusNotReachable     = 0,   //网络无连接
    kNENetworkStatusReachableViaWWAN = 1,   //2，3，4G网络
    kNENetworkStatusReachableViaWiFi = 2,   //WIFI网络
};

/**
 *  所有的接口返回值均为NSURLSessionTask
 */
typedef NSURLSessionTask NEURLSessionTask;

/*
 *
 *  请求成功的回调
 *
 *  @param response 服务端返回的数据类型
 */
typedef void(^NEResponseSuccess)(id response);

/*
 *
 *  网络响应失败时的回调
 *
 *  @param error 错误信息
 */
typedef void(^NEResponseFail)(NSError *error);


@interface NENetWorking : NSObject


/*!
 *
 *  用于指定网络请求接口的基础url
 *  @param baseUrl 网络接口的基础url
 */
+ (void)updateBaseUrl:(NSString *)baseUrl;
+ (NSString *)baseUrl;

/**
 *	设置请求超时时间，默认为30秒
 *
 *	@param timeout 超时时间
 */
+ (void)setTimeout:(NSTimeInterval)timeout;

/**
 *	当检查到网络异常时，是否从从本地提取数据。默认为NO。一旦设置为YES,当设置刷新缓存时，
 *  若网络异常也会从缓存中读取数据。同样，如果设置超时不回调，同样也会在网络异常时回调，除非
 *  本地没有数据！
 *
 *	@param shouldObtain	YES/NO
 */
+ (void)obtainDataFromLocalWhenNetworkUnconnected:(BOOL)shouldObtain;

/**
 *
 *	默认请求是不缓存的。如果要缓存获取的数据，需要手动调用设置
 *
 *
 *	@param isCacheGet			默认为NO
 *	@param shouldCachePost      默认为NO
 */
+ (void)cacheGetRequest:(BOOL)isCacheGet shoulCachePost:(BOOL)shouldCachePost;

/**
 *
 *	获取缓存总大小/bytes
 *
 *	@return 缓存大小
 */
+ (unsigned long long)totalCacheSize;

/**
 *
 *	清除缓存
 */
+ (void)clearCaches;

/*!
 *
 *
 *  开启或关闭接口打印信息
 *
 *  @param isDebug 开发期，最好打开，默认是NO
 */
+ (void)enableInterfaceDebug:(BOOL)isDebug;

/*!
 *
 *  配置请求格式，默认为JSON。
 *
 *  @param requestType                      请求格式，默认为JSON
 *  @param responseType                     响应格式，默认为JSO，
 *  @param shouldAutoEncode                 YES or NO,默认为NO，是否自动encode url
 *  @param shouldCallbackOnCancelRequest    当取消请求时，是否要回调，默认为YES
 */
+ (void)configRequestType:(NERequestType)requestType
             responseType:(NEResponseType)responseType
      shouldAutoEncodeUrl:(BOOL)shouldAutoEncode
  callbackOnCancelRequest:(BOOL)shouldCallbackOnCancelRequest;

/*!
 *
 *  配置公共的请求头，只调用一次即可
 *
 *  @param httpHeaders 只需要将与服务器商定的固定参数设置即可
 */
+ (void)configCommonHttpHeaders:(NSDictionary *)httpHeaders;

/**
 *
 *	取消所有请求
 */
+ (void)cancelAllRequest;
/**
 *
 *	取消某个请求
 *
 *	@param url				URL，可以是绝对URL，也可以是path（也就是不包括baseurl）
 */
+ (void)cancelRequestWithURL:(NSString *)url;

/*
 *
 *  GET请求接口，若不指定baseurl，可传完整的url
 *
 *  @param url          接口路径
 *  @param refreshCache 是否刷新缓存
 *  @param statusText   提示框文字
 *  @param params       接口中所需要的拼接参数
 *  @param success      接口成功请求到数据的回调
 *  @param fail         接口请求数据失败的回调
 *
 *  @return             返回的对象中有可取消请求的API
 */
+ (NEURLSessionTask *)getWithUrl:(NSString *)url
                    refreshCache:(BOOL)refreshCache
                         success:(NEResponseSuccess)success
                            fail:(NEResponseFail)fail;
// （有提示框）
+ (NEURLSessionTask *)getWithUrl:(NSString *)url
                    refreshCache:(BOOL)refreshCache
                         showHUD:(NSString *)statusText
                         success:(NEResponseSuccess)success
                            fail:(NEResponseFail)fail;
// 多一个params参数（无提示框）
+ (NEURLSessionTask *)getWithUrl:(NSString *)url
                    refreshCache:(BOOL)refreshCache
                          params:(NSDictionary *)params
                         success:(NEResponseSuccess)success
                            fail:(NEResponseFail)fail;
// 多一个params参数（有提示框）
+ (NEURLSessionTask *)getWithUrl:(NSString *)url
                    refreshCache:(BOOL)refreshCache
                         showHUD:(NSString *)statusText
                          params:(NSDictionary *)params
                         success:(NEResponseSuccess)success
                            fail:(NEResponseFail)fail;
// 多一个带进度回调（无提示框）
+ (NEURLSessionTask *)getWithUrl:(NSString *)url
                    refreshCache:(BOOL)refreshCache
                          params:(NSDictionary *)params
                        progress:(NEGetProgress)progress
                         success:(NEResponseSuccess)success
                            fail:(NEResponseFail)fail;
// 多一个带进度回调（有提示框）
+ (NEURLSessionTask *)getWithUrl:(NSString *)url
                    refreshCache:(BOOL)refreshCache
                         showHUD:(NSString *)statusText
                          params:(NSDictionary *)params
                        progress:(NEGetProgress)progress
                         success:(NEResponseSuccess)success
                            fail:(NEResponseFail)fail;

/*!
 *
 *  POST请求接口，若不指定baseurl，可传完整的url
 *
 *  @param url     接口路径
 *  @param params  接口中所需的参数
 *  @param success 接口成功请求到数据的回调
 *  @param fail    接口请求数据失败的回调
 *
 *  @return        返回的对象中有可取消请求的API
 */
+ (NEURLSessionTask *)postWithUrl:(NSString *)url
                     refreshCache:(BOOL)refreshCache
                           params:(NSDictionary *)params
                          success:(NEResponseSuccess)success
                             fail:(NEResponseFail)fail;

// (有提示框)
+ (NEURLSessionTask *)postWithUrl:(NSString *)url
                     refreshCache:(BOOL)refreshCache
                          showHUD:(NSString *)statusText
                           params:(NSDictionary *)params
                          success:(NEResponseSuccess)success
                             fail:(NEResponseFail)fail;
// 多一个带进度回调（无提示框）
+ (NEURLSessionTask *)postWithUrl:(NSString *)url
                     refreshCache:(BOOL)refreshCache
                           params:(NSDictionary *)params
                         progress:(NEPostProgress)progress
                          success:(NEResponseSuccess)success
                             fail:(NEResponseFail)fail;
// 多一个带进度回调（有提示框）
+ (NEURLSessionTask *)postWithUrl:(NSString *)url
                     refreshCache:(BOOL)refreshCache
                          showHUD:(NSString *)statusText
                           params:(NSDictionary *)params
                         progress:(NEPostProgress)progress
                          success:(NEResponseSuccess)success
                             fail:(NEResponseFail)fail;
/*
 *
 *	图片上传接口，若不指定baseurl，可传完整的url
 *
 *	@param image		图片对象
 *	@param url			上传图片的接口路径，如/path/images/
 *	@param filename		给图片起一个名字，默认为当前日期时间,格式为"yyyyMMddHHmmss"，后缀为`jpg`
 *	@param name			与指定的图片相关联的名称，这是由后端写接口的人指定的，如imagefiles
 *	@param mimeType		默认为image/jpeg
 *	@param parameters	参数
 *	@param progress		上传进度
 *	@param success		上传成功回调
 *	@param fail			上传失败回调
 *
 *	@return
 */
+ (NEURLSessionTask *)uploadWithImage:(UIImage *)image
                                  url:(NSString *)url
                             filename:(NSString *)filename
                                 name:(NSString *)name
                             mimeType:(NSString *)mimeType
                           parameters:(NSDictionary *)parameters
                             progress:(NEUploadProgress)progress
                              success:(NEResponseSuccess)success
                                 fail:(NEResponseFail)fail;

/*
 *
 *	上传文件操作
 *
 *	@param url				上传路径
 *	@param uploadingFile	待上传文件的路径
 *	@param progress			上传进度
 *	@param success			上传成功回调
 *	@param fail				上传失败回调
 *
 *	@return
 */
+ (NEURLSessionTask *)uploadFileWithUrl:(NSString *)url
                          uploadingFile:(NSString *)uploadingFile
                               progress:(NEUploadProgress)progress
                                success:(NEResponseSuccess)success
                                   fail:(NEResponseFail)fail;


/*!
 *
 *  下载文件
 *
 *  @param url           下载URL
 *  @param saveToPath    下载到哪个路径下
 *  @param progressBlock 下载进度
 *  @param success       下载成功后的回调
 *  @param failure       下载失败后的回调
 */
+ (NEURLSessionTask *)downloadWithUrl:(NSString *)url
                           saveToPath:(NSString *)saveToPath
                             progress:(NEDownloadProgress)progressBlock
                              success:(NEResponseSuccess)success
                              failure:(NEResponseFail)failure;




@end
