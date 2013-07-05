// Created by alexgordon on 05/04/2013.

#import <Foundation/Foundation.h>
#import "FSPCShared.h"

@class FXPCChannel;


typedef enum {
    FXPCErrorConnectionInterrupted = 1,
    FXPCErrorConnectionInvalid = 2,
    FXPCErrorTerminationImminent = 3,
} FXPCErrorCode;

typedef void (^FXPCEventHandler)(FXPCChannel* channel, NSDictionary* args);
typedef void (^FXPCConnectionHandler)(FXPCChannel* channel);

FXPC_EXTERN_C xpc_object_t ns_to_xpc(id obj);
FXPC_EXTERN_C id xpc_to_ns(xpc_object_t obj);

FXPC_EXTERN_C void fxpc_run_server(dispatch_queue_t queue, FXPCConnectionHandler callback);
FXPC_EXTERN_C void fxpc_connect_named(NSString* identifier, dispatch_queue_t queue, FXPCConnectionHandler callback);
FXPC_EXTERN_C xpc_handler_t fxpc_handler(void(^callback)(NSDictionary* args, NSError* err, xpc_object_t obj));

@interface FXPCChannel
@property xpc_connection_t connection;
@property (copy) FXPCEventHandler receiveMessage;

- (void)sendMessage:(NSDictionary*)msg;
- (void)_startUp; // for subclasses!
- (void)start;
- (void)pause;
- (void)invalidate;
@end

@interface FXPCClient : FXPCChannel
@end

@interface FXPCServer : FXPCChannel
@end

