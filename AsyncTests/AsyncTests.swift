//
//  AsyncTests.swift
//  AsyncTests
//
//  Created by Alastair Houghton on 12/06/2014.
//  Copyright (c) 2014 Alastair Houghton. All rights reserved.
//

import XCTest
import Dispatch
import Async

class AsyncTests: XCTestCase {
    
  override func setUp() {
    super.setUp()
    
    Async.unschedule()
  }
  
  override func tearDown() {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    super.tearDown()
  }
  
  func testSimple() {
    let task = async { () -> Int in
      return 5
    }
    
    let result = await(task)

    XCTAssertEqual(result, 5, "Simple task returns 5")
    
    let task2 = async { () -> String in
      return "😈"
    }
    
    let result2 = await(task2)
    
    XCTAssertEqual(result2, "😈", "Simple task returns \"😈\"")
  }

  func testDeep() {
    let task = async { () -> Int in
      let task2 = async { () -> Int in
        return 6
      }
      
      return await(task2) + 2
    }
    
    let result = await(task)
    
    XCTAssertEqual(result, 8, "Deep task returns 8")
  }
  
  func testSuspend() {
    let task = async { (t : Async.Task<Int>) -> Int in
      /* Wake in 2s */
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2000000000),
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0)) {
        Async.wake(t)
      }
      println("Going to suspend")
      Async.suspend()
      println("Finished")
      return 7
    }
    
    let result = await(task)
    
    XCTAssertEqual(result, 7, "Suspended task returned 7")
  }
  
  func runAsync() -> Async.Task<Void> {
    let outer = async { () -> () in
      let task = async { () -> Int in
        let subtask = async { (t : Async.Task<()>) -> () in
          /* Wake in 2s */
          dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500000000),
            dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0)) {
              println("Waking")
              Async.wake(t)
          }
          println("Going to suspend")
          Async.suspend()
          println("Finished")
        }
        
        println("Waiting for subtask")
        await(subtask)
        println("Subtask complete")
        
        return 6
      }
      
      println("Should return straight away")
      
      let result = await(task)
      XCTAssertEqual(result, 6, "Should return 6")
      
      println("Finished now")
    }
    
    return outer
  }
  
  /* CFRunLoopGetCurrent() is not yet fixed in the iOS 8 headers */
  func fixupRunLoop(rl: CFRunLoop) -> CFRunLoop {
    return rl
  }
  
  func fixupRunLoop(rl: Unmanaged<CFRunLoop>) -> CFRunLoop {
    return rl.takeUnretainedValue()
  }
  
  func testWithRunLoop() {
    var runLoop: CFRunLoop = fixupRunLoop(CFRunLoopGetCurrent());
    
    Async.schedule(runLoop)
    
    let task = runAsync()
    
    println("Starting run loop")
    
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 4.0, 0)
    
    println("Finished run loop")
    
    XCTAssert(task.done, "Task should have finished")
    
    println("Test complete")
  }
  
  func testWithDispatchQueue() {
    var queue = dispatch_get_main_queue()
    var runLoop = CFRunLoopGetCurrent();
    var task : Async.Task<Void>!
    
    Async.schedule(queue)
    
    dispatch_async(queue) {
      println("Block started")
      task = self.runAsync()
      println("Block complete")
    }

    println("Starting run loop")
    
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 4.0, 0)
    
    println("Finished run loop")

    XCTAssert(task.done, "Task should have finished")
    
    println("Test complete")
  }

  func hiresTime() -> Double {
    var tv : timeval = timeval(tv_sec: 0, tv_usec: 0)
    gettimeofday(&tv, nil)
    return Double(tv.tv_sec) + 1.0e-6 * Double(tv.tv_usec);
  }
  
  func testPerformance() {
    println("Timing")
    
    let count = 1000000
    let start = hiresTime()
    for i in 1...count {
      let task = async {
      }
      
      await(task)
    }
    let elapsed = hiresTime() - start
    
    println("\(elapsed / Double(count))s per async/await")
  }
}
