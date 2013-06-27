# Project find in Chocolat using [ag](https://github.com/ggreer/the_silver_searcher)

Here's my plan with this:

1. Create an XPC service
2. Turn ag into a library, and add hooks so we can get events when things change
3. Report progress back to Chocolat
4. On the Chocolat side, we need a window controller, with a text view
5. Get the XPC progress events and add new lines to the text view as matches come in
6. Handle cancelling by terminating the XPC service with extreme prejudice
