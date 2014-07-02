//
//  Async.swift
//  Async
//
//  Created by Alastair Houghton on 12/06/2014.
//  Copyright (c) 2014 Alastair Houghton. All rights reserved.
//

import Foundation
import Swift
import Darwin

/* This is just so we can use the nice async { } syntax. */
func async(block: (Async.Task<Void>) -> ()) -> Async.Task<Void> {
  return Async.VoidTask(block)
}

func async(block: () -> ()) -> Async.Task<Void> {
  return Async.VoidTask(block)
}

func async<T>(block: (Async.Task<T>) -> T) -> Async.Task<T> {
  return Async.Task<T>(block)
}

func async<T>(block: () -> T) -> Async.Task<T> {
  return Async.Task<T>(block)
}

func await(task: Async.Task<Void>) {
  async_await(task.task)
  task.task = nil
}

func await<T>(task: Async.Task<T>) -> T {
  async_await(task.task)
  task.task = nil
  return task.result[0]
}

struct Async {
  /* We should really use T?, but that causes a compiler error about non-fixed
     class layouts:

      LLVM ERROR: unimplemented IRGen feature! non-fixed class layout

     so instead we use an array. */

  class Task<T> {
    var task : async_task_t = nil
    var result : T[]!
    var done : Bool {
      get {
        return !task || async_done(task)
      }
    }
    
    init() {
    }
    
    init(block: (Task) -> T) {
      task = async_call {
        self.result = [block(self)]
        return 0
      }
    }
    
    init(block: () -> T) {
      task = async_call {
        self.result = [block()]
        return 0
      }
    }
    
    deinit {
      if task {
        async_await(task)
        task = nil
      }
    }
  }

  /* This is unfortunately necessary because of the array hack; an array of
     void[] type causes a crash when you assign to it. */
  class VoidTask<T> : Task<T> {
    init(block: (VoidTask) -> ()) {
      super.init()
      task = async_call {
        block(self)
        return 0
      }
    }
    
    init(block: () -> ()) {
      super.init()
      task = async_call {
        block()
        return 0
      }
    }
  }

  static func suspend() {
    async_suspend()
  }

  static func wake<T>(task: Task<T>) {
    async_wake(task.task)
  }

  /* This should only ever be called with dispatch_get_main_queue(); it absolutely
     requires that the queue uses only a single thread. */
  static func schedule(q: dispatch_queue_t) {
    async_schedule_in_queue(q)
  }

  static func schedule(runLoop: CFRunLoop) {
    async_schedule_in_runloop(runLoop)
  }

  static func schedule(runLoop: NSRunLoop) {
    async_schedule_in_runloop(runLoop.getCFRunLoop())
  }

  static func unschedule() {
    async_unschedule()
  }
}
