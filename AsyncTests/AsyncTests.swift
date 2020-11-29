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
import Darwin

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
      let globalQueue = DispatchQueue.global(qos: .background)
      globalQueue.asyncAfter(deadline: .now() + 2.0) {
        Async.wake(t)
      }
      print("Going to suspend")
      Async.suspend()
      print("Finished")
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
          let globalQueue = DispatchQueue.global(qos: .background)
          globalQueue.asyncAfter(deadline: .now() + 2.0) {
            Async.wake(t)
          }
          print("Going to suspend")
          Async.suspend()
          print("Finished")
        }
        
        print("Waiting for subtask")
        await(subtask)
        print("Subtask complete")
        
        return 6
      }
      
      print("Should return straight away")
      
      let result = await(task)
      XCTAssertEqual(result, 6, "Should return 6")
      
      print("Finished now")
    }
    
    return outer
  }
  
  func testWithRunLoop() {
    let runLoop: CFRunLoop = CFRunLoopGetCurrent();
    
    Async.schedule(runLoop: runLoop)
    
    let task = runAsync()
    
    print("Starting run loop")
    
    CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 4.0, false)
    
    print("Finished run loop")
    
    XCTAssert(task.done, "Task should have finished")
    
    print("Test complete")
  }
  
  func testWithDispatchQueue() {
    let queue = DispatchQueue.main
    var task : Async.Task<Void>!
    
    Async.schedule(queue: queue)
    
    queue.async {
      print("Block started")
      task = self.runAsync()
      print("Block complete")
    }

    print("Starting run loop")
    
    CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 4.0, false)
    
    print("Finished run loop")

    XCTAssert(task.done, "Task should have finished")
    
    print("Test complete")
  }

  func hiresTime() -> Double {
    var tv : timeval = timeval(tv_sec: 0, tv_usec: 0)
    gettimeofday(&tv, nil)
    return Double(tv.tv_sec) + 1.0e-6 * Double(tv.tv_usec);
  }
  
  func testPerformance() {
    print("Timing")
    
    let count = 1000000
    let start = hiresTime()
    for _ in 1...count {
      let task = async {
      }
      
      await(task)
    }
    let elapsed = hiresTime() - start
    
    print("\(elapsed / Double(count))s per async/await")
  }
  
}
