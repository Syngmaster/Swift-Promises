# Swift-Promises
Promise concept in Swift
Handy solution for async tasks to avoid the "callback hell"


### How to use:
1. Setup your sequence.

```
func createSequence() -> SequenceASync<Error?> {
    return async {
        do {
            // 1.
            _ = try await(self.firstTask())
            // 2.
            _ = try await(self.secondTask())
            // 3.
            _ = try await(self.thirdTask())
            
            return nil
        } catch {
            return error
        }
    }
}

func firstTask() -> SequenceASync<Any> {
    return SequenceASync<Any>({ (resolve, reject) in
    
        YourClass.yourMethod(completion: { (success, error) in
            guard error == nil else {
                reject(error)
                return
            }
            resolve(true)
        })
    })
    
}

func secondTask() -> SequenceASync<Any> {
    return SequenceASync<Any>({ (resolve, reject) in
        YourClass.yourMethod(completion: { (success, error) in
            guard error == nil else {
                reject(error)
                return
            }
            resolve(true)
        })
    })
}

func thirdTask() -> SequenceASync<Any> {
    return SequenceASync<Any>({ (resolve, reject) in
        YourClass.yourMethod(completion: { (success, error) in
            guard error == nil else {
                reject(error)
                return
            }
            resolve(true)
        })
    })
}
```

2. Implement in your code

```
let queue = DispatchQueue.global(qos: .userInitiated)
queue.async {
    let sequence = self.createSequence()
    sequence.then(queue: .main, { (success, error) in
        
        
    })
}
```

