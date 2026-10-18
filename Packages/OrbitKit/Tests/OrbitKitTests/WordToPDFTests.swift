import Testing

/// Groups the tests that lay out text. They run one at a time: CoreText blocks the threads it runs on,
/// and when every thread of the cooperative pool waits in it at once, they deadlock.
@Suite(.serialized) enum WordToPDFTests {}
