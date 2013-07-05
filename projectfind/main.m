//  Created by Alex Gordon on 27/06/2013.

#include <xpc/xpc.h>
#include <Foundation/Foundation.h>
#import <syslog.h>
#import "XPCBridge.h"

// main.c
int projectfind(int argc, const char **argv);

static xpc_connection_t global_peer = NULL;

void send_dict(NSDictionary* dict) {
    xpc_object_t obj = ns_to_xpc(dict);
    xpc_connection_send_message(global_peer, obj);
}

static void projectfind_peer_event_handler(xpc_connection_t peer, xpc_object_t event) {
    global_peer = peer;
	xpc_type_t type = xpc_get_type(event);
	if (type == XPC_TYPE_ERROR) {
		if (event == XPC_ERROR_CONNECTION_INVALID) {
			// The client process on the other end of the connection has either
			// crashed or cancelled the connection. After receiving this error,
			// the connection is in an invalid state, and you do not need to
			// call xpc_connection_cancel(). Just tear down any associated state
			// here.
		} else if (event == XPC_ERROR_TERMINATION_IMMINENT) {
			// Handle per-connection termination cleanup.
		}
	} else {
		assert(type == XPC_TYPE_DICTIONARY);
        
        if (xpc_dictionary_get_bool(event, "kill")) {
            syslog(LOG_ERR, "[project find] KILLING");
            exit(0);
            return;
        }
        
		// Handle the message.
        syslog(LOG_ERR, "[project find] start");
        chdir(xpc_string_get_string_ptr(xpc_dictionary_get_value(event, "directory")));
        xpc_object_t xpcargs = xpc_dictionary_get_value(event, "args");
        syslog(LOG_ERR, "[project find] %s", xpc_copy_description(xpcargs));
        
        int nargs = (int)xpc_array_get_count(xpcargs);
        char** args = calloc(sizeof(const char*), nargs);
        
        xpc_array_apply(xpcargs, ^bool(size_t index, xpc_object_t value) {
            assert(xpc_get_type(value) == XPC_TYPE_STRING);
            const char* str = xpc_string_get_string_ptr(value);
            size_t nbytes = strlen(str ?: "") + 1;
            args[index] = calloc(nbytes, 1);
            memcpy(args[index], str ?: "", nbytes);
            return true;
        });
        syslog(LOG_ERR, "[project find] args %d", nargs);

        
        xpc_transaction_begin();
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            syslog(LOG_ERR, "[project find] start project find");
            projectfind(nargs, args);
            xpc_transaction_end();
            send_dict(@{ @"done": @YES });
        });
        
	    syslog(LOG_ERR, "[project find] end");
    }
}

static void projectfind_event_handler(xpc_connection_t peer) {
	// By defaults, new connections will target the default dispatch
	// concurrent queue.
	xpc_connection_set_event_handler(peer, ^(xpc_object_t event) {
		projectfind_peer_event_handler(peer, event);
	});
    
	// This will tell the connection to begin listening for events. If you
	// have some other initialization that must be done asynchronously, then
	// you can defer this call until after that initialization is done.
	xpc_connection_resume(peer);
}

int main(int argc, const char *argv[])
{
    syslog(LOG_ERR, "[project find] xpc");
	xpc_main(projectfind_event_handler);
	return 0;
}
