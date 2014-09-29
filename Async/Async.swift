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
public func async(block: (Task<Void>) -> Void) -> Task<Void> {
  return Task<Void>(block)
}

public func async(block: () -> Void) -> Task<Void> {
  return Task<Void>(block)
}

public func async<T>(block: (Task<T>) -> T) -> Task<T> {
  return Task<T>(block)
}

public func async<T>(block: () -> T) -> Task<T> {
  return Task<T>(block)
}

public func await(task: Task<Void>) {
  async_ll_await(task.task)
  task.task = nil
}

public func await<T>(task: Task<T>) -> T {
  async_ll_await(task.task)
  task.task = nil
  return task.result
}

public class Task<T> {
  internal var task : async_ll_task_t = nil
  internal var result : T!
  public var done : Bool {
    get {
      return task != nil || async_ll_done(task)
    }
  }
  
  public init() {
  }
  
  public init(block: (Task) -> T) {
    task = async_ll_call {
      self.result = block(self)
      return 0
    }
  }
  
  public init(block: () -> T) {
    task = async_ll_call {
      self.result = block()
      return 0
    }
  }
  
  deinit {
    if task != nil {
      async_ll_await(task)
      task = nil
    }
  }
}

public func suspend() {
  async_ll_suspend()
}

public func wake<T>(task: Task<T>) {
  async_ll_wake(task.task)
}

/* This should only ever be called with dispatch_get_main_queue(); it absolutely
   requires that the queue uses only a single thread. */
public func schedule(q: dispatch_queue_t) {
  async_ll_schedule_in_queue(q)
}

public func schedule(runLoop: CFRunLoop) {
  async_ll_schedule_in_runloop(runLoop)
}

public func schedule(runLoop: NSRunLoop) {
  async_ll_schedule_in_runloop(runLoop.getCFRunLoop())
}

public func unschedule() {
  async_ll_unschedule()
}
