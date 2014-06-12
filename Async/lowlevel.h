//
//  lowlevel.h
//  Async
//
//  Created by Alastair Houghton on 10/06/2014.
//  Copyright (c) 2014 Coriolis Systems. All rights reserved.
//

#ifndef LOWLEVEL_H_
#define LOWLEVEL_H_

#include <CoreFoundation/CoreFoundation.h>
#include <inttypes.h>
#include <stdbool.h>
#include <setjmp.h>

/* These functions work on a per-thread basis.  That is, each thread has
   its own async. context.
 
   If you call async_await() at top-level, i.e. outside of an async_call()
   invocation, IT WILL BLOCK THE CURRENT THREAD UNTIL THE TASK YOU ARE
   AWAITING HAS COMPLETED.  Tasks that you started on the current thread may
   wake and execute in the meantime, but the top-level async_await() will
   remain blocked.
 
   If you are using a run loop or a dispatch queue to drive a given thread,
   you can register with those mechanisms.  In that case, YOU MUST NOT CALL
   async_await() OUTSIDE OF AN async_call() INVOCATION as it will block the
   thread and NO PROGRESS WILL BE MADE.  If you are registered with a queue
   or with a run loop, the queue/run loop will process events while your
   top-level task awaits the completion of a subtask. */

typedef struct async_task *async_task_t;

/* Call this if you are using dispatch_main(). */
void async_schedule_in_queue(dispatch_queue_t queue);

/* Call this if you are using a CF/NSRunLoop. */
void async_schedule_in_runloop(CFRunLoopRef runLoop);

/* Call this to undo the above */
void async_unschedule(void);

/* Call a block; this also works for Swift functions. */
async_task_t async_call(size_t stack_size,
                        int64_t (^blk)(void));

/* Call a function, passing in the specified argument */
async_task_t async_call_fn(void *arg,
                           size_t stack_size,
                           int64_t (*blk)(void *arg));

/* Wait for a given async task to complete */
int64_t async_await(async_task_t task);

/* Suspend the current async task */
void async_suspend(void);

/* Wake the specified async task, which should be suspended */
void async_wake(async_task_t task);

/* Get the current async task */
async_task_t async_current_task(void);

/* Check if the specified async task is done yet */
bool async_done(async_task_t task);

#endif /* ASYNC_H_ */
