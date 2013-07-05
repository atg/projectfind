#import <Foundation/Foundation.h>

typedef void (^FPCCallback)(NSDictionary* args);

static NSString* FPCNewUUID() {
    return [NSString stringWithFormat:@"%X.%X.%X", arc4random(), arc4random(), arc4random()];
}

#if !OS_OBJECT_USE_OBJC // __has_feature(objc_arc)
 #define fpc_dispatch_release(...) ((void)0)
 #define fpc_xpc_release(...) ((void)0)
 #define fpc_xpc_retain(...) ((void)0)
 #define fpc_block_copy(...) (__VA_ARGS__)
#else
 #define fpc_dispatch_release dispatch_release
 #define fpc_xpc_release xpc_release
 #define fpc_xpc_retain xpc_retain
 #define fpc_block_copy Block_copy
#endif

#ifdef __cplusplus
#define FXPC_EXTERN_C extern "C"
#else
#define FXPC_EXTERN_C
#endif
