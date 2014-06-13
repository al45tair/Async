//
//  lowlevel.c
//  await-test
//
//  Created by Alastair Houghton on 10/06/2014.
//  Copyright (c) 2014 Coriolis Systems. All rights reserved.
//

#include <CoreFoundation/CoreFoundation.h>
#include <sys/mman.h>
#include <stdlib.h>
#include <pthread.h>
#include <assert.h>

#include "lowlevel.h"

struct async_thread {
  pthread_mutex_t    q_mutex;
  pthread_cond_t     q_cond;
  struct async_task *ready_q;
  struct async_task *current_task;
  dispatch_queue_t   dispatch_q;
  CFRunLoopSourceRef source;
  CFRunLoopRef       runloop;
};

struct async_task {
  bool                 done;
  struct async_thread *owner;
  struct async_task   *next_ready;
  int64_t              result;
  jmp_buf              buf;
  void                *stack_base;
  size_t               stack_size;
  void                *arg;
  int64_t             (*entry_point)(void *arg);
  CFTypeRef           retained;
  struct async_task   *caller;
  struct async_task   *awaiting;
};

static int64_t call_block(void *arg) {
  int64_t (^blk)() = (int64_t (^)())arg;
  return blk();
}

static bool async_run_next(void);
static bool async_run_all_blocking(void);
static void async_perform(void *info);
static struct async_thread *async_current_thread(void);
static void async_switch_to(async_task_t task);

void enter_task(async_task_t task) {
  task->result = task->entry_point (task->arg);
  task->done = true;
  if (task->awaiting)
    async_switch_to (task->awaiting);
  async_switch_to (task->caller);
}

int64_t call_with_stack(async_task_t task,
                        void *stack_top) __attribute__((noreturn));

#if defined(__x86_64__)
__asm__ ("\
         .text\n\
         .align 4\n\
_call_with_stack:\n\
         movq  %rsi,%rsp\n\
         pushq %rbp\n\
         subq  $8,%rsp\n\
         callq _enter_task\n\
         int   $3\n\
         ");
#elif defined(__i386__)
__asm__ ("\
         .text\n\
         .align 4\n\
_call_with_stack:\n\
         movl  4(%esp),%eax\n\
         movl  8(%esp),%esp\n\
         pushl %eax\n\
         subl  $12,%esp\n\
         calll _enter_task\n\
         int   $3\n\
         ");
#elif defined(__arm__)
__asm__ ("\
         .text\n\
         .align 4\n\
_call_with_stack:\n\
         mov   sp,r1\n\
         b     _enter_task;\n\
         ");
#elif defined(__arm64__)
__asm__ ("\
         .text\n\
         .align 4\n\
_call_with_stack:\n\
         mov   sp,x1\n\
         b     _enter_task\n\
         ");
#else
#error You need to write code for your CPU
#endif

static pthread_key_t async_key;
static void async_teardown(void *arg);

static void
async_init(void)
{
  pthread_key_create (&async_key, async_teardown);
}

static void
async_teardown(void *arg)
{
  struct async_thread *thread = (struct async_thread *)arg;
  
  pthread_mutex_destroy (&thread->q_mutex);
  pthread_cond_destroy (&thread->q_cond);
  free (thread);
}

static struct async_thread *
async_current_thread(void)
{
  static pthread_once_t once = PTHREAD_ONCE_INIT;
  struct async_thread *thread;
  
  pthread_once(&once, async_init);
  
  thread = pthread_getspecific (async_key);
  
  if (!thread) {
    size_t size = sizeof(struct async_thread) + sizeof(struct async_task);
    thread = (struct async_thread *)malloc (size);
    
    memset (thread, 0, size);
    pthread_mutex_init (&thread->q_mutex, NULL);
    pthread_cond_init (&thread->q_cond, NULL);
    thread->current_task = (struct async_task *)(thread + 1);
    thread->current_task->owner = thread;
    
    pthread_setspecific (async_key, thread);
  }
  
  return thread;
}

void
async_schedule_in_runloop(CFRunLoopRef runLoop)
{
  struct async_thread *thread = async_current_thread();
  CFRunLoopSourceContext ctx;
  
  memset (&ctx, 0, sizeof(ctx));
  
  ctx.perform = async_perform;
  
  thread->runloop = runLoop;
  thread->source = CFRunLoopSourceCreate (kCFAllocatorDefault, 0, &ctx);
  
  CFRunLoopAddSource (thread->runloop, thread->source, kCFRunLoopCommonModes);
}

void
async_schedule_in_queue(dispatch_queue_t queue)
{
  struct async_thread *thread = async_current_thread();

  thread->dispatch_q = queue;
}

void
async_unschedule()
{
  struct async_thread *thread = async_current_thread();

  thread->dispatch_q = NULL;
  
  if (thread->source) {
    CFRunLoopSourceInvalidate (thread->source);
    CFRelease (thread->source);
    thread->source = NULL;
    thread->runloop = NULL;
  }
}

static void
async_switch_to(async_task_t task)
{
  struct async_thread *thread = async_current_thread();
  thread->current_task = task;
  _longjmp (thread->current_task->buf, 1);
}

static async_task_t
async_call_fn_impl(void *arg,
                   size_t stack_size,
                   int64_t (*pfn)(void *arg),
                   CFTypeRef retained)
{
  struct async_thread *thread = async_current_thread();
  volatile struct async_task *task
  = (struct async_task *)malloc (sizeof (struct async_task));
  
  memset ((void *)task, 0, sizeof(struct async_task));
  task->owner = (struct async_thread *)thread;
  
  if (_setjmp(thread->current_task->buf))
    return (async_task_t)task;
  
  task->caller = thread->current_task;
  thread->current_task = (async_task_t)task;
  
  // Call with a new stack
  volatile size_t size = stack_size;
  volatile void *base = mmap (NULL, size, PROT_READ|PROT_WRITE,
                              MAP_ANON|MAP_PRIVATE, -1, 0);
  void *top = (char *)base + size;
  
  task->stack_base = (void *)base;
  task->stack_size = size;
  task->entry_point = pfn;
  task->arg = arg;
  task->retained = retained ? CFRetain(retained) : NULL;
  
  call_with_stack ((async_task_t)task, top);
}


async_task_t
async_call_fn(void *arg,
              size_t stack_size,
              int64_t (*pfn)(void *arg))
{
  return async_call_fn_impl (arg, stack_size, pfn, NULL);
}

async_task_t
async_call(size_t stack_size,
           int64_t (^blk)(void))
{
  return async_call_fn_impl (blk, stack_size, call_block, blk);
}

int64_t async_await(async_task_t t)
{
  volatile async_task_t task = t;
  volatile struct async_thread *thread = async_current_thread();
  int64_t result;
  
  /* Must have the same owning thread */
  assert(t->owner == thread);
  
  while (!task->done) {
    if (_setjmp (thread->current_task->buf) == 0) {
      task->awaiting = thread->current_task;
      if (!thread->current_task->caller) {
        /* Don't allow await()ing from the run loop or from a dispatch
           queue without being in asynchronous context */
        assert(!thread->runloop && !thread->dispatch_q);
        
        async_run_all_blocking();
      } else {
        async_switch_to (thread->current_task->caller);
      }
    } else {
      task->awaiting = NULL;
    }
  }
  
  munmap (task->stack_base, task->stack_size);
  if (task->retained)
    CFRelease (task->retained);
  result = task->result;
  free (task);
  return result;
}

void
async_suspend()
{
  volatile struct async_thread *thread = async_current_thread();
  if (_setjmp (thread->current_task->buf) == 0)
    async_switch_to (thread->current_task->caller);
}

void
async_wake(async_task_t task)
{
  struct async_thread *owner = task->owner;
  pthread_mutex_lock (&owner->q_mutex);
  if (!task->next_ready) {
    if (owner->ready_q) {
      task->next_ready = owner->ready_q->next_ready;
      owner->ready_q->next_ready = task;
    } else {
      task->next_ready = task;
      owner->ready_q = task;
    }
  }

  if (owner->dispatch_q) {
    dispatch_async (owner->dispatch_q, ^{
      while (async_run_next());
    });
  } else if (owner->source) {
    CFRunLoopSourceSignal (owner->source);
    CFRunLoopWakeUp (owner->runloop);
  } else
    pthread_cond_signal (&owner->q_cond);
  
  pthread_mutex_unlock (&owner->q_mutex);
}

static bool
async_run_next(void)
{
  volatile struct async_thread *thread = async_current_thread();
  volatile async_task_t task = NULL;
  
  pthread_mutex_lock ((pthread_mutex_t *)&thread->q_mutex);
  if (thread->ready_q) {
    task = thread->ready_q->next_ready;
    thread->ready_q = task->next_ready;
    if (thread->ready_q == task)
      thread->ready_q = NULL;
  }
  pthread_mutex_unlock ((pthread_mutex_t *)&thread->q_mutex);
  
  if (task && _setjmp (thread->current_task->buf) == 0) {
    task->caller = thread->current_task;
    async_switch_to (task);
  }
  
  return task;
}

static bool
async_run_all_blocking(void)
{
  volatile struct async_thread *thread = async_current_thread();
  volatile async_task_t task = NULL;
  volatile bool ran_one = false;
  
  pthread_mutex_lock ((pthread_mutex_t *)&thread->q_mutex);
  if (!thread->ready_q) {
    pthread_cond_wait ((pthread_cond_t *)&thread->q_cond,
                       (pthread_mutex_t *)&thread->q_mutex);
  }
  if (thread->ready_q) {
    task = thread->ready_q->next_ready;
    thread->ready_q = task->next_ready;
    if (thread->ready_q == task)
      thread->ready_q = NULL;
  }
  pthread_mutex_unlock ((pthread_mutex_t *)&thread->q_mutex);
  
  if (task && _setjmp (thread->current_task->buf) == 0) {
    ran_one = true;
    task->caller = thread->current_task;
    async_switch_to (task);
  }
  
  return ran_one;
}

static void
async_perform(__unused void *info)
{
  while (async_run_next());
}

async_task_t
async_current_task(void)
{
  return async_current_thread()->current_task;
}

bool
async_done(async_task_t task)
{
  return task->done;
}
