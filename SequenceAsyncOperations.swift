//
//  SequenceAsyncOperations.swift
//  RowanProject
//


import Foundation

public func async<AsyncResult>(_ executor: @escaping () throws -> AsyncResult) -> SequenceASync<AsyncResult> {
	return SequenceASync<AsyncResult>({ (resolve, reject) in
		DispatchQueue.global().async {
			do {
				let result = try executor()
				resolve(result)
			} catch {
				reject(error)
			}
		}
	})
}

public func sync<AsyncResult>(_ executor: @escaping () throws -> AsyncResult) -> SequenceASync<AsyncResult> {
	return SequenceASync<AsyncResult>({ (resolve, reject) in
		DispatchQueue.main.async {
			do {
				let result = try executor()
				resolve(result)
			} catch {
				reject(error)
			}
		}
	})
}

public func await<AsyncResult>(_ promise: SequenceASync<AsyncResult>) throws -> AsyncResult {
	var returnVal: AsyncResult?
	var throwVal: Error?
	
	let group = DispatchGroup()
	group.enter()
	
	promise.then(
		onresolve: { (result) in
			returnVal = result
			group.leave()
	},
		onreject: { (error) in
			throwVal = error
			group.leave()
	})
	
	group.wait()
	if throwVal != nil {
		throw throwVal!
	}
	return returnVal!
}
