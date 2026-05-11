//
//  SSHTerminalChannelHandler.swift
//  Talkie iOS
//
//  Bridges an SSH session child channel to the embedded terminal surface.
//

import Foundation
import NIOCore
@preconcurrency import NIOSSH

final class SSHTerminalChannelHandler: ChannelDuplexHandler {
    typealias InboundIn = SSHChannelData
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = SSHChannelData

    private let term: String
    private let startupCommand: String?
    private let initialColumns: Int
    private let initialRows: Int
    private let initialPixelWidth: Int
    private let initialPixelHeight: Int
    private let onReady: @Sendable () -> Void
    private let onOutput: @Sendable (Data) -> Void
    private let onExit: @Sendable (Int?) -> Void
    private let onError: @Sendable (Error) -> Void

    init(
        term: String,
        startupCommand: String?,
        initialColumns: Int,
        initialRows: Int,
        initialPixelWidth: Int,
        initialPixelHeight: Int,
        onReady: @escaping @Sendable () -> Void,
        onOutput: @escaping @Sendable (Data) -> Void,
        onExit: @escaping @Sendable (Int?) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) {
        self.term = term
        self.startupCommand = startupCommand?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.initialColumns = initialColumns
        self.initialRows = initialRows
        self.initialPixelWidth = initialPixelWidth
        self.initialPixelHeight = initialPixelHeight
        self.onReady = onReady
        self.onOutput = onOutput
        self.onExit = onExit
        self.onError = onError
    }

    func handlerAdded(context: ChannelHandlerContext) {
        context.channel.setOption(ChannelOptions.allowRemoteHalfClosure, value: true).whenFailure { [onError] error in
            onError(error)
        }
    }

    func channelActive(context: ChannelHandlerContext) {
        let ptyRequest = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: true,
            term: term,
            terminalCharacterWidth: initialColumns,
            terminalRowHeight: initialRows,
            terminalPixelWidth: initialPixelWidth,
            terminalPixelHeight: initialPixelHeight,
            terminalModes: SSHTerminalModes([:])
        )

        let ptyPromise = context.eventLoop.makePromise(of: Void.self)
        let commandPromise = context.eventLoop.makePromise(of: Void.self)

        ptyPromise.futureResult.whenSuccess {
            if let startupCommand = self.startupCommand, !startupCommand.isEmpty {
                context.triggerUserOutboundEvent(
                    SSHChannelRequestEvent.ExecRequest(command: startupCommand, wantReply: true),
                    promise: commandPromise
                )
            } else {
                context.triggerUserOutboundEvent(
                    SSHChannelRequestEvent.ShellRequest(wantReply: true),
                    promise: commandPromise
                )
            }
        }

        ptyPromise.futureResult.whenFailure { [onError] error in
            onError(error)
        }

        commandPromise.futureResult.whenSuccess { [onReady] in
            onReady()
        }

        commandPromise.futureResult.whenFailure { [onError] error in
            onError(error)
        }

        context.triggerUserOutboundEvent(ptyRequest, promise: ptyPromise)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let message = unwrapInboundIn(data)

        guard case .byteBuffer(let bytes) = message.data else {
            return
        }

        let output = Data(bytes.readableBytesView)
        guard !output.isEmpty else { return }
        onOutput(output)
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let buffer = unwrapOutboundIn(data)
        let message = SSHChannelData(type: .channel, data: .byteBuffer(buffer))
        context.write(wrapOutboundOut(message), promise: promise)
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case let exit as SSHChannelRequestEvent.ExitStatus:
            onExit(exit.exitStatus)
        case is SSHChannelRequestEvent.ExitSignal:
            onExit(nil)
        case let channelEvent as ChannelEvent where channelEvent == .inputClosed:
            onExit(nil)
        default:
            context.fireUserInboundEventTriggered(event)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        onError(error)
        context.close(promise: nil)
    }
}
