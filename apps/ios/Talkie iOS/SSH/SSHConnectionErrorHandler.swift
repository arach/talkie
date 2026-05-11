//
//  SSHConnectionErrorHandler.swift
//  Talkie iOS
//
//  Propagates SSH pipeline errors back to the session model.
//

import NIOCore

final class SSHConnectionErrorHandler: ChannelInboundHandler {
    typealias InboundIn = Any

    private let onError: @Sendable (Error) -> Void

    init(onError: @escaping @Sendable (Error) -> Void) {
        self.onError = onError
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        onError(error)
        context.close(promise: nil)
    }
}
