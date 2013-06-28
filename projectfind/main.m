//  Created by Alex Gordon on 27/06/2013.

#include <xpc/xpc.h>
#include <Foundation/Foundation.h>

// main.c
int projectfind(int argc, const char **argv);

static void projectfind_peer_event_handler(xpc_connection_t peer, xpc_object_t event) {
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
        
		// Handle the message.
        xpc_object_t xpcargs = xpc_dictionary_get_value(event, "args");

        int nargs = (int)xpc_array_get_count(xpcargs);
        const char** args = calloc(sizeof(const char*), nargs);
        
        xpc_array_apply(xpcargs, ^bool(size_t index, xpc_object_t value) {
            assert(xpc_get_type(value) == XPC_TYPE_STRING);
            args[index] = xpc_string_get_string_ptr(value);
            return true;
        });
        
        projectfind(nargs, args);
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
	xpc_main(projectfind_event_handler);
	return 0;
}
