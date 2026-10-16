# YSwift Todo List example

The example uses SwiftUI and Apple's Observation framework, requiring iOS 17 or later.
Its model publishes a plain array snapshot through `@Observable`; it does not use
Combine or a custom observation framework.

The project manifest uses the Tuist 3 API. With Tuist 3.39.3 installed, build the local
YSwift XCFramework first, then run `tuist fetch` and `tuist generate` from this directory.
The dependency manifest references this checkout so the example uses the matching
Swift bindings and native framework.

The existing MultipeerConnectivity demonstration uses YSwift's synchronous protocol
APIs consistently. New clients should use async document transactions and
`await collection.observeAsync()` as shown in the repository README.
