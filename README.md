Async Swift
===========

This framework implements C#-like async/await primitives in Swift.  Owing to
some problems with the current operating system bindings, together with the
need for a tiny bit of assembly language to make this work, the guts of the
implementation are currently written in C.

The implementation could be adapted to work with Objective-C or C++ in a
relatively straightforward manner.

Usage
-----

Basic usage is as follows:

~~~~
let task = async { () -> Int in
  return 5
}

let result = await(task)
~~~~

Note that the type of the block is *not* optional.

You can return any Swift object you like, and the result is returned from
the `await` call.

Obviously, it's permissible to invoke asynchronous tasks within asynchronous
tasks, for instance

~~~~
let task = async { () -> Int in
  let subtask = async { () -> Int in
    return 15
  }

  return await(subtask) * 2
}

let result = await(task)
~~~~

Neither of these examples are particularly useful, so let’s give an example
that is:

~~~~
let task = async { () -> () in
  let fetch = async { (t: Task<NSData>) -> NSData in
    let req = NSURLRequest(URL: NSURL.URLWithString("http://www.google.com"))
    let queue = NSOperationQueue.mainQueue()
    var data = NSData!
    NSURLConnection.sendAsynchronousRequest(req,
                                            queue:queue,
      completionHandler:{ (r: NSURLResponse!, d: NSData!, error: NSError!) -> Void in
        data = d
        Async.wake(t)
      })
    Async.suspend()
    return data!
  }

  let data = await(fetch)
  let str = NSString(bytes: data.bytes, length: data.length,
                     encoding: NSUTF8StringEncoding)

  println(str)
}
~~~~

You need to do a little set-up to make this work in your Cocoa/Cocoa Touch
code, namely at some point you need to bind the Async module to the run loop
with

~~~~
Async.schedule(NSRunLoop.currentRunLoop())
~~~~

After doing that, if you invoke the code above, you’ll find that it fetches
the Google home page into a string, which is returned as the result of `task`.

**Note**: You *must not* call `await` directly from a non-async context in a
Cocoa program unless you are *certain* the task in question has completed.
Doing so will trigger an assertion failure.

`await` semantics
-----------------

`async` and `await` do not behave the way you might naïvely assume.  If you
call `await` (or `Async.suspend`) in an async context, *control will return to
the calling frame*.  It does *not* block.  All that is suspended is execution
within the async context.

The only time that `await` will block is if you are at the top level, outside
of any async context.  In that case, it will block the top level (but will
continue running any async code as it becomes ready) until the specified task
is complete.

If you're using this module in a Cocoa or Cocoa Touch program, and you want to
run asynchronous code on the main thread, you can tell the framework that you
want it to attach to the run loop, as shown before, with

~~~~
Async.schedule(NSRunLoop.currentRunLoop())
~~~~

This also works for `CFRunLoopRef`, and it will work with the main dispatch
queue as well if your programs use those instead.

Once you have done that, async tasks that you start from event handlers (or
from blocks dispatched by the main dispatch queue) will continue to run to
completion automatically.  The framework does this by scheduling callbacks
for itself in the run loop at appropriate times.

`Async.suspend()` and `Async.wake()`
------------------------------------

These two functions allow you to suspend the current async context, and to
wake a previously suspended context, respectively.  They are used to interface
async code with code that uses other methods of asynchronous behaviour (e.g.
threads, dispatch queues, callbacks, completion blocks and so on).

Waking is not instant; the context will resume from the point of the
`Async.suspend` call when either (a) `await` is called at top level *and has
to wait*, or (b) your program returns to the run loop or dispatch queue with
which the `Async` module is scheduled.

Note that the order that suspended async contexts resume is not guaranteed.

Threading support
-----------------

The `Async` module is designed to work with threads in the following manner;
each thread has its own entirely separate pool of async contexts, and its own
distinct set of async tasks.  You *must not* attempt to `await` on a task that
is owned by another thread.

**Important**: dispatch queues other than the main queue **do not guarantee
that tasks will be invoked on the same thread**.  This applies *even to serial
queues*, and is the reason that you must only ever pass the main dispatch
queue to the `Async.schedule` function.

It *is* safe to use async contexts within a block dispatched to a queue, but
bear in mind that you cannot `await` on a task from a different block, though
it is certainly permissible to call `Async.wake` on one.