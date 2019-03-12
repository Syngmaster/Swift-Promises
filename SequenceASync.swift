//
//  SequenceASync.swift
//  Promise
//


import Foundation
/**
Swiftlint recommendation is that 'Type body Length' should span 200 lines or less exclduing comments and whitespace.
Swiflint.yml already modifies this to 240 lines.
Ignoring this rule for the file until it can be refactored to less than 240
*/
//swiftlint:disable type_body_length
public class SequenceASync<AsyncResult> {
    public typealias Resolver = (AsyncResult) -> Void
    public typealias Rejecter = (Error) -> Void
    public typealias Then<Return> = (AsyncResult) -> Return
    public typealias Catch<ErrorType, Return> = (ErrorType) -> Return
    
    private enum State {
        case executing
        case resolved(result: AsyncResult)
        case rejected(error: Error)
        
        var finished: Bool {
                switch self {
                case .executing:
                    return false
                case .resolved:
                    return true
                case .rejected:
                    return true
                }
        }
        var result: AsyncResult? {
                switch self {
                case .executing:
                    return nil
                case .resolved(let result):
                    return result
                case .rejected:
                    return nil
                }
        }
        var error: Error? {
                switch self {
                case .executing:
                    return nil
                case .resolved:
                    return nil
                case .rejected(let error):
                    return error
                }
        }
    }
    private var state: State = .executing
    private var resolvers: [Resolver] = []
    private var rejecters: [Rejecter] = []
    private var sync: NSLock = NSLock()
    public init(_ executor: (@escaping Resolver, @escaping Rejecter) -> Void) {
        executor({ (result: AsyncResult) in
            self.handleResolve(result)
        }, { (error: Error) in
            self.handleReject(error)
        })
    }
	
	private func handleResolve(_ result: AsyncResult) {
        sync.lock()
        // ensure correct state
        var callbacks: [Resolver] = []
        switch state {
        case .executing:
            state = State.resolved(result: result)
            callbacks = resolvers
            resolvers.removeAll()
            rejecters.removeAll()
            sync.unlock()
            break
        //case .resolved: fallthrough
        case .resolved, .rejected:
            sync.unlock()
            assert(false, "Cannot resolve a promise multiple times")
            break
        }
        // call callbacks
        for callback in callbacks {
            callback(result)
        }
    }
    
    // send promise error
    private func handleReject(_ error: Error) {
        sync.lock()
        // ensure correct state
        var callbacks: [Rejecter] = []
        switch state {
        case .executing:
            state = State.rejected(error: error)
            callbacks = rejecters
            resolvers.removeAll()
            rejecters.removeAll()
            sync.unlock()
            break
        //case .resolved: fallthrough
        case .resolved, .rejected:
            sync.unlock()
            assert(false, "Cannot resolve a promise multiple times")
            break
        }
        // call callbacks
        for callback in callbacks {
            callback(error)
        }
    }
    
    @discardableResult
    public func then(queue: DispatchQueue = DispatchQueue.main, onresolve resolveHandler: @escaping Then<Void>, onreject rejectHandler: @escaping Catch<Error, Void>) -> SequenceASync<Void> {
        return SequenceASync<Void>({ (resolve, _) in
            sync.lock()
            switch state {
            case .executing:
                resolvers.append({ (result: AsyncResult) in
                    queue.async {
                        resolveHandler(result)
                        resolve(Void())
                    }
                })
                rejecters.append({ (error: Error) in
                    queue.async {
                        rejectHandler(error)
                    }
                })
                sync.unlock()
                break
            case .resolved(let result):
                sync.unlock()
                queue.async {
                    resolveHandler(result)
                    resolve(Void())
                }
                break
            case .rejected(let error):
                sync.unlock()
                queue.async {
                    rejectHandler(error)
                }
                break
            }
        })
    }
    @discardableResult
    public func then(queue: DispatchQueue = DispatchQueue.main, _ resolveHandler: @escaping Then<Void>) -> SequenceASync<Void> {
        return SequenceASync<Void>({ (resolve, reject) in
            sync.lock()
            switch state {
            case .executing:
                resolvers.append({ (result: AsyncResult) in
                    queue.async {
                        resolveHandler(result)
                        resolve(Void())
                    }
                })
                rejecters.append({ (error: Error) in
                    reject(error)
                })
                sync.unlock()
                break
            case .resolved(let result):
                sync.unlock()
                queue.async {
                    resolveHandler(result)
                    resolve(Void())
                }
                break
            case .rejected(let error):
                sync.unlock()
                reject(error)
                break
            }
        })
    }
    public func then<NextResult>(queue: DispatchQueue = DispatchQueue.main, _ resolveHandler: @escaping Then<SequenceASync<NextResult>>) -> SequenceASync<NextResult> {
        return SequenceASync<NextResult>({ (resolve, reject) in
            sync.lock()
            switch state {
            case .executing:
                resolvers.append({ (result: AsyncResult) in
                    queue.async {
                        resolveHandler(result).then(
                            onresolve: { (nextResult: NextResult) -> Void in
                                resolve(nextResult)
                        },
                            onreject: { (nextError: Error) -> Void in
                                reject(nextError)
                        }
                        )
                    }
                })
                rejecters.append({ (error: Error) in
                    reject(error)
                })
                sync.unlock()
                break
            case .resolved(let result):
                sync.unlock()
                queue.async {
                    resolveHandler(result).then(
                        onresolve: { (nextResult: NextResult) -> Void in
                            resolve(nextResult)
                    },
                        onreject: { (nextError: Error) -> Void in
                            reject(nextError)
                    }
                    )
                }
                break
            case .rejected(let error):
                sync.unlock()
                reject(error)
                break
            }
        })
    }
    
    @discardableResult
    public func `catch`<ErrorType>(queue: DispatchQueue = DispatchQueue.main, _ rejectHandler: @escaping Catch<ErrorType, Void>) -> SequenceASync<AsyncResult> {
        return SequenceASync<AsyncResult>({ (resolve, reject) in
            sync.lock()
            switch state {
            case .executing:
                resolvers.append({ (result: AsyncResult) in
                    resolve(result)
                })
                rejecters.append({ (error: Error) in	
					if let error = error as? ErrorType {
						queue.async {
							rejectHandler(error)
						}
					} else {
						reject(error)
					}
                })
                sync.unlock()
                break
            case .resolved(let result):
                sync.unlock()
                resolve(result)
                break
            case .rejected(let error):
                sync.unlock()
				if let error = error as? ErrorType {
					queue.async {
						rejectHandler(error)
					}
				} else {
					reject(error)
				}
                break
            }
        })
    }
    
    // handle promise rejection + continue
    public func `catch`<ErrorType>(queue: DispatchQueue = DispatchQueue.main, _ rejectHandler: @escaping Catch<ErrorType, SequenceASync<AsyncResult>>) -> SequenceASync<AsyncResult> {
        return SequenceASync<AsyncResult>({ (resolve, reject) in
            sync.lock()
            switch state {
            case .executing:
                resolvers.append({ (result: AsyncResult) in
                    resolve(result)
                })
                rejecters.append({ (error: Error) in
					if let error = error as? ErrorType {
						queue.async {
							rejectHandler(error).then(
								onresolve: { (result: AsyncResult) in
									resolve(result)
							},
								onreject: { (error: Error) in
									reject(error)
							})
						}
                    } else {
                        reject(error)
                    }
                })
                sync.unlock()
                break
            case .resolved(let result):
                sync.unlock()
                resolve(result)
                break
            case .rejected(let error):
                sync.unlock()
				if let error = error as? ErrorType {
					queue.async {
						rejectHandler(error).then(
							onresolve: { (result: AsyncResult) in
								resolve(result)
						},
							onreject: { (error: Error) in
								reject(error)
						})
					}
				} else {
					reject(error)
				}
                break
            }
        })
    }
    
    // handle promise resolution / rejection
    @discardableResult
    public func finally(queue: DispatchQueue = DispatchQueue.main, _ finallyHandler: @escaping () -> Void) -> SequenceASync<Void> {
        return SequenceASync<Void>({ (resolve, _) in
            self.then(queue: queue,
                      onresolve: { (_: AsyncResult) in
                        finallyHandler()
                        resolve(Void())
            },
                      onreject: { (_: Error) in
                        finallyHandler()
                        resolve(Void())
            })
        })
    }
    
    // handle promise resolution / rejection
    public func finally<NextResult>(queue: DispatchQueue = DispatchQueue.main, _ finallyHandler: @escaping () -> SequenceASync<NextResult>) -> SequenceASync<NextResult> {
        return SequenceASync<NextResult>({ (resolve, reject) in
            self.then(queue: queue,
                      onresolve: { (result: AsyncResult) in
                        finallyHandler().then(
                            onresolve: { (result: NextResult) in
                                resolve(result)
                        },
                            onreject: { (error: Error) in
                                reject(error)
                        })
            },
                      onreject: { (error: Error) in
                        finallyHandler().then(
                            onresolve: { (result: NextResult) in
                                resolve(result)
                        },
                            onreject: { (error: Error) in
                                reject(error)
                        })
            })
        })
    }
    
    // map to another result type
    public func map<T>(_ transform: @escaping (AsyncResult) throws -> T) -> SequenceASync<T> {
        return SequenceASync<T>({ (resolve, reject) in
            self.then(onresolve: { (result) in
                do {
                    let mappedResult = try transform(result)
                    resolve(mappedResult)
                } catch {
                    reject(error)
                }
            }, onreject: { (error: Error) -> Void in
                reject(error)
            })
        })
    }
    
    // create a resolved promise
    public static func resolve(_ result: AsyncResult) -> SequenceASync<AsyncResult> {
        return SequenceASync<AsyncResult>({ (resolve, _) in
            resolve(result)
        })
    }
    
    // create a rejected promise
    public static func reject(_ error: Error) -> SequenceASync<AsyncResult> {
        return SequenceASync<AsyncResult>({ (_, reject) in
            reject(error)
        })
    }
    
    private class AllData {
        var sync: NSLock = NSLock()
        var results: [AsyncResult?] = []
        var rejected: Bool = false
        var counter: Int = 0
        
        init(size: Int) {
            while results.count < size {
                results.append(nil)
            }
        }
    }
    
    // wait until all the promises are resolved and return the results
    public static func all(_ promises: [SequenceASync<AsyncResult>]) -> SequenceASync<[AsyncResult]> {
        return SequenceASync<[AsyncResult]>({ (resolve, reject) in
            let promiseCount = promises.count
            if promiseCount == 0 {
                resolve([])
                return
            }
            
            let sharedData = AllData(size: promiseCount)
            
            let resolveIndex = { (index: Int, result: AsyncResult) -> Void in
                sharedData.sync.lock()
                if sharedData.rejected {
                    sharedData.sync.unlock()
                    return
                }
                sharedData.results[index] = result
                sharedData.counter += 1
                let finished = (promiseCount == sharedData.counter)
                sharedData.sync.unlock()
                if finished {
                    let results = sharedData.results.map({ (result) -> AsyncResult in
                        return result!
                    })
                    resolve(results)
                }
            }
            
            let rejectAll = { (error: Error) -> Void in
                sharedData.sync.lock()
                if sharedData.rejected {
                    sharedData.sync.unlock()
                    return
                }
                sharedData.rejected = true
                sharedData.sync.unlock()
                reject(error)
            }
            
            for (i, promise) in promises.enumerated() {
                promise.then(
                    onresolve: { (result: AsyncResult) -> Void in
                        resolveIndex(i, result)
                },
                    onreject: { (error: Error) -> Void in
                        rejectAll(error)
                }
                )
            }
        })
    }
    
    // helper class for Promise.race
    private class RaceData {
        var sync: NSLock = NSLock()
        var finished: Bool = false
    }
    
    // return the result of the first promise to finish
    public static func race(_ promises: [SequenceASync<AsyncResult>]) -> SequenceASync<AsyncResult> {
        return SequenceASync<AsyncResult>({ (resolve, reject) in
            let sharedData = RaceData()
            
            let resolveIndex = { (result: AsyncResult) -> Void in
                sharedData.sync.lock()
                if sharedData.finished {
                    sharedData.sync.unlock()
                    return
                }
                sharedData.finished = true
                sharedData.sync.unlock()
                resolve(result)
            }
            
            let rejectAll = { (error: Error) -> Void in
                sharedData.sync.lock()
                if sharedData.finished {
                    sharedData.sync.unlock()
                    return
                }
                sharedData.finished = true
                sharedData.sync.unlock()
                reject(error)
            }
            
            for promise in promises {
                promise.then(
                    onresolve: { (result: AsyncResult) -> Void in
                        resolveIndex(result)
                },
                    onreject: { (error: Error) -> Void in
                        rejectAll(error)
                }
                )
            }
        })
    }
}
