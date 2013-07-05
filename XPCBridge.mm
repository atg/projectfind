// Created by alexgordon on 05/04/2013.

#import <vector>
#import <queue>
#import <string>
#import "XPCBridge.h"
#define iskind(a, t) [(a) isKindOfClass:[t class]]
#define isnumberkind(a, t) (strcmp([(NSNumber*)(a) objCType], @encode(t)) == 0)

xpc_handler_t fxpc_handler(void(^callback)(NSDictionary* args, NSError* err, xpc_object_t original)) {
    callback = [callback copy];
    
    return [^(xpc_object_t event) {
        xpc_type_t type = xpc_get_type(event);
        assert(type == XPC_TYPE_DICTIONARY || type == XPC_TYPE_ERROR);
        
        id args = xpc_to_ns(event);
        callback(type == XPC_TYPE_DICTIONARY ? args : nil,
                 type == XPC_TYPE_ERROR ? args : nil,
                 event);
    } copy];
}

xpc_object_t ns_to_xpc(id obj) {
    if ([obj respondsToSelector:@selector(mutableCopyWithZone:)]) {
        obj = [obj mutableCopy];
    }
    else {
        obj = [obj copy];
    }

    if (iskind(obj, NSNull)) {
        return xpc_null_create();
    }
    else if (obj == [NSNumber numberWithBool:YES]) {
        return xpc_bool_create(true);
    }
    else if (obj == [NSNumber numberWithBool:NO]) {
        return xpc_bool_create(false);
    }
    else if (iskind(obj, NSArray)) {
        if (![(NSArray*)obj count])
            return xpc_array_create(NULL, 0);
        
        // Call ns_to_xpc() on each child
        std::vector<xpc_object_t> xpcs;
        for (id child : (NSArray*)obj) {
            xpcs.push_back(ns_to_xpc(child));
        }

        xpc_object_t arrobj = xpc_array_create(&xpcs[0], xpcs.size());
#if !OS_OBJECT_USE_OBJC
        for (int i = 0, n = (int)xpcs.size(); i < n; i++) {
            xpc_release(xpcs[i]);
        }
#endif

        return arrobj;
    }
    else if (iskind(obj, NSDictionary)) {        
        std::vector<const char*> keyxpcs;
        std::vector<xpc_object_t> valuexpcs;
        NSDictionary* dobj = obj;
        if (![dobj count])
            return xpc_dictionary_create(NULL, NULL, 0);
        
        for (NSString* child in dobj) {
            const char* k = [child UTF8String];
            
            size_t n = strlen(k);//[child length];
            char* kbuffer = new char[ n + 1 ]();
            std::copy(k, k + n, kbuffer);
            
            keyxpcs.push_back(kbuffer);
            
            xpc_object_t v = ns_to_xpc([dobj objectForKey:child]);
            valuexpcs.push_back(v);
        }

        xpc_object_t dictobj = xpc_dictionary_create(&keyxpcs[0], &valuexpcs[0], keyxpcs.size());
        for (int i = 0, n = (int)valuexpcs.size(); i < n; i++) {
            delete[] (keyxpcs[i]);
#if !OS_OBJECT_USE_OBJC
xpc_release(valuexpcs[i]);
#endif
        }

        return dictobj;
    }
    else if (iskind(obj, NSString)) {
        
        
        NSString* sobj =
//#ifndef CHDebug
//           @"muttons"
//#else
           obj
//#endif
        ;
        
        
        NSData* kdata = [sobj dataUsingEncoding:NSUTF8StringEncoding];
        NSMutableData* kmutabledata = [kdata mutableCopy];
        size_t n = [kmutabledata length];
        [kmutabledata increaseLengthBy:1];
        
        const char* k = (const char*)[kmutabledata bytes];
        /*
#ifndef CHDebug
            "toast"
#else
            [sobj UTF8String]
#endif
;*/
//        size_t n = strlen(k);//[sobj length];
        if (!n)
            return xpc_string_create("");
        
        char* kbuffer = new char[ n + 1 ]();
        std::copy(k, k + n, kbuffer);
        
        xpc_object_t stringobj = xpc_string_create(kbuffer);
        delete[] kbuffer;
        return stringobj;
    }
    else if (iskind(obj, NSDate)) {
        NSTimeInterval t = [(NSDate*)obj timeIntervalSince1970];
        return xpc_date_create((int64_t)round(t * NSEC_PER_SEC));
    }
    else if (iskind(obj, NSData)) {
        if (![(NSData*)obj length])
            return xpc_data_create(NULL, 0);
        return xpc_data_create([(NSData*)obj bytes], [(NSData*)obj length]);
    }
    else if (iskind(obj, NSNumber)) {
        if (isnumberkind(obj, BOOL)
          || isnumberkind(obj, char)
          || isnumberkind(obj, short)
          || isnumberkind(obj, int)
          || isnumberkind(obj, long)
          || isnumberkind(obj, long long)) {
            return xpc_int64_create([(NSNumber*)obj longLongValue]);
        }
        else if (isnumberkind(obj, unsigned char)
               || isnumberkind(obj, unsigned short)
               || isnumberkind(obj, unsigned int)
               || isnumberkind(obj, unsigned long)
               || isnumberkind(obj, unsigned long long)) {
            return xpc_uint64_create([(NSNumber*)obj unsignedLongLongValue]);
        }
        else if (isnumberkind(obj, float)
               || isnumberkind(obj, double)
               || isnumberkind(obj, long double)) {
            return xpc_double_create([(NSNumber*)obj doubleValue]);
        }
    }

    return xpc_null_create();
}

id xpc_to_ns(xpc_object_t obj) {
    xpc_type_t ty = xpc_get_type(obj);
    if (ty == XPC_TYPE_ARRAY) {
        NSMutableArray* arr = [[NSMutableArray alloc] init];
        xpc_array_apply(obj, ^ bool (size_t index, xpc_object_t value) {
            id val = xpc_to_ns(value) ?: [NSNull null];
            [arr insertObject:val atIndex:index];
            return true;
        });
        return arr;
    }
    else if (ty == XPC_TYPE_BOOL) {
        return [NSNumber numberWithBool:xpc_bool_get_value(obj)];
    }
    else if (ty == XPC_TYPE_CONNECTION) {
        return nil; // irrelevant
    }
    else if (ty == XPC_TYPE_DATA) {
        return [NSData dataWithBytes:xpc_data_get_bytes_ptr(obj) length:xpc_data_get_length(obj)];
    }
    else if (ty == XPC_TYPE_DATE) {
        long double a = xpc_date_get_value(obj);
        long double b = NSEC_PER_SEC;
        return [NSDate dateWithTimeIntervalSince1970:double(a / b)];
    }
    else if (ty == XPC_TYPE_DICTIONARY) {
        NSMutableDictionary* dict = [[NSMutableDictionary alloc] init];
        xpc_dictionary_apply(obj, ^ bool (char const *key, xpc_object_t value) {
            NSString* k = [NSString stringWithUTF8String:key];
            id v = xpc_to_ns(value) ?: [NSNull null];
            [dict setObject:v forKey:k];
            return true;
        });
        return dict;
    }
    else if (ty == XPC_TYPE_DOUBLE) {
        return [NSNumber numberWithDouble:xpc_double_get_value(obj)];
    }
    else if (ty == XPC_TYPE_ENDPOINT) {
        return nil; // irrelevant
    }
    else if (ty == XPC_TYPE_ERROR) {
        int code = 0;
        if (obj == XPC_ERROR_CONNECTION_INTERRUPTED)
            code = FXPCErrorConnectionInterrupted;
        if (obj == XPC_ERROR_CONNECTION_INVALID)
            code = FXPCErrorConnectionInvalid;
        if (obj == XPC_ERROR_TERMINATION_IMMINENT)
            code = FXPCErrorTerminationImminent;
        
        return [NSError errorWithDomain:@"com.chocolatapp.fpc.xpc-error" code:code userInfo:nil];
    }
    else if (ty == XPC_TYPE_FD) {
        return [[NSFileHandle alloc] initWithFileDescriptor:xpc_fd_dup(obj) closeOnDealloc:YES];
    }
    else if (ty == XPC_TYPE_INT64) {
        return [NSNumber numberWithLongLong:xpc_int64_get_value(obj)];
    }
    else if (ty == XPC_TYPE_NULL) {
        return [NSNull null];
    }
    else if (ty == XPC_TYPE_SHMEM) {
        return nil; // no native type
    }
    else if (ty == XPC_TYPE_STRING) {
        return [NSString stringWithUTF8String:xpc_string_get_string_ptr(obj)];
    }
    else if (ty == XPC_TYPE_UINT64) {
        return [NSNumber numberWithUnsignedLongLong:xpc_uint64_get_value(obj)];
    }
    else if (ty == XPC_TYPE_UUID) {
        return nil; // need NSUUID but it doesn't exist on 10.7
    }
    return nil;
}
