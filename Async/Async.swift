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

let asyncNull = unsafeBitCast(0, to: async_ll_task_t.self)

/* This is just so we can use the nice async { } syntax. */
public func async(block: @escaping (Task<Void>) -> Void) -> Task<Void> {
  return Task<Void>(block: block)
}

public func async(block: @escaping () -> Void) -> Task<Void> {
  return Task<Void>(block: block)
}

public func async<T>(block: @escaping (Task<T>) -> T) -> Task<T> {
  return Task<T>(block: block)
}

public func async<T>(block: @escaping () -> T) -> Task<T> {
  return Task<T>(block: block)
}

public func await(_ task: Task<Void>) {
  async_ll_await(task.task)
  task.task = asyncNull
}

public func await<T>(_ task: Task<T>) -> T {
  async_ll_await(task.task)
  task.task = asyncNull
  return task.result
}

public class Task<T> {
  internal var task = asyncNull
  internal var result : T!
  public var done : Bool {
    get {
      return task != asyncNull || async_ll_done(task)
    }
  }
  
  public init() {
  }
  
  public init(block: @escaping (Task) -> T) {
    task = async_ll_call {
      self.result = block(self)
      return 0
    }
  }
  
  public init(block: @escaping () -> T) {
    task = async_ll_call {
      self.result = block()
      return 0
    }
  }
  
  deinit {
    if task != asyncNull {
      async_ll_await(task)
      task = asyncNull
    }
  }
}

public func suspend() {
  async_ll_suspend()
}

public func wake<T>(_ task: Task<T>) {
  async_ll_wake(task.task)
}

/* This should only ever be called with dispatch_get_main_queue(); it absolutely
   requires that the queue uses only a single thread. */
public func schedule(queue: DispatchQueue) {
  async_ll_schedule_in_queue(queue)
}

public func schedule(runLoop: CFRunLoop) {
  async_ll_schedule_in_runloop(runLoop)
}

public func schedule(runLoop: RunLoop) {
  async_ll_schedule_in_runloop(runLoop.getCFRunLoop())
}

public func unschedule() {
  async_ll_unschedule()
}
