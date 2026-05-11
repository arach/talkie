//
//  WorkflowControlPlaneClient.swift
//  Talkie macOS
//
//  Thin HTTP client for Talkie's live workflow queue API.
//

import Foundation
import TalkieKit

private let clientLog = Log(.workflow)

struct WorkflowControlPlaneClient {
    struct ExecutorDescriptor: Sendable {
        let deviceId: String
        let name: String
        let platform: String
        let status: String
        let priority: Int
        let capabilities: [String]
        let installId: String?
        let appVersion: String?
        let tailscaleHostname: String?
        let metadata: [String: String]?
    }

    struct WorkflowRunEnvelope: Codable, Sendable {
        let id: String
        let workflowId: String
        let workflowName: String
        let workflowIcon: String?
        let memoId: String
        let status: String
        let executionClass: String
        let routingMode: String
        let createdAt: String
        let updatedAt: String
        let runDate: String
        let claimedByDeviceId: String?
        let leaseExpiresAt: String?
        let backendId: String?
        let output: String?
        let finalOutputs: [String: String]?
        let stepOutputsJSON: String?
        let errorMessage: String?

        var runId: String { id }
    }

    struct ClaimResponse: Codable, Sendable {
        let granted: Bool
        let reason: String?
        let leaseToken: String?
        let leaseExpiresAt: String?
    }

    struct ExecutorUpsertResponse: Codable, Sendable {
        let deviceId: String
        let heartbeatExpiresAt: String?
    }

    struct SimpleResponse: Codable, Sendable {
        let ok: Bool
        let reason: String?
        let run: WorkflowRunEnvelope?
    }

    struct HeartbeatResponse: Codable, Sendable {
        let ok: Bool
        let reason: String?
        let heartbeatExpiresAt: String?
    }

    struct LeaseRenewalResponse: Codable, Sendable {
        let ok: Bool
        let reason: String?
        let leaseExpiresAt: String?
    }

    private struct WorkflowRunListResponse: Codable {
        let runs: [WorkflowRunEnvelope]
    }

    private struct UpsertExecutorRequest: Encodable {
        let deviceId: String
        let name: String
        let platform: String
        let status: String
        let priority: Int
        let capabilities: [String]
        let installId: String?
        let appVersion: String?
        let tailscaleHostname: String?
        let metadata: [String: String]?
    }

    private struct HeartbeatExecutorRequest: Encodable {
        let deviceId: String
        let status: String
        let claimedRunId: String?
        let metadata: [String: String]?
    }

    private struct ClaimRunRequest: Encodable {
        let deviceId: String
        let backendId: String?
    }

    private struct LeaseRequest: Encodable {
        let deviceId: String
        let leaseToken: String
    }

    private struct StartRunRequest: Encodable {
        let deviceId: String
        let leaseToken: String
        let backendId: String?
    }

    private struct CompleteRunRequest: Encodable {
        let deviceId: String
        let leaseToken: String
        let finalOutputs: [String: String]
        let output: String?
        let stepOutputsJSON: String?
        let backendId: String?
    }

    private struct FailRunRequest: Encodable {
        let deviceId: String
        let leaseToken: String
        let error: ErrorPayload
        let backendId: String?
    }

    private struct ReleaseRunRequest: Encodable {
        let deviceId: String
        let leaseToken: String
        let reason: String?
    }

    private struct ErrorPayload: Encodable {
        let message: String
    }

    enum ClientError: LocalizedError {
        case invalidBaseURL
        case missingAuthToken
        case invalidResponse
        case server(status: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .invalidBaseURL:
                return "The Talkie API URL is invalid."
            case .missingAuthToken:
                return "You need to sign into Talkie before this Mac can claim live workflows."
            case .invalidResponse:
                return "The Talkie API returned an invalid response."
            case .server(_, let message):
                return message
            }
        }
    }

    private let baseURL: URL
    private let authToken: String
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(baseURLString: String, authToken: String, session: URLSession = .shared) throws {
        guard let baseURL = URL(string: baseURLString) else {
            throw ClientError.invalidBaseURL
        }

        let trimmedToken = authToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            throw ClientError.missingAuthToken
        }

        self.baseURL = baseURL
        self.authToken = trimmedToken
        self.session = session
    }

    func upsertExecutor(_ descriptor: ExecutorDescriptor) async throws {
        let request = UpsertExecutorRequest(
            deviceId: descriptor.deviceId,
            name: descriptor.name,
            platform: descriptor.platform,
            status: descriptor.status,
            priority: descriptor.priority,
            capabilities: descriptor.capabilities,
            installId: descriptor.installId,
            appVersion: descriptor.appVersion,
            tailscaleHostname: descriptor.tailscaleHostname,
            metadata: descriptor.metadata
        )

        _ = try await send(
            method: "POST",
            path: "api/executors/register",
            body: request,
            responseType: ExecutorUpsertResponse.self
        )
    }

    func heartbeatExecutor(
        deviceId: String,
        status: String,
        claimedRunId: String?,
        metadata: [String: String]?
    ) async throws -> HeartbeatResponse {
        try await send(
            method: "POST",
            path: "api/executors/heartbeat",
            body: HeartbeatExecutorRequest(
                deviceId: deviceId,
                status: status,
                claimedRunId: claimedRunId,
                metadata: metadata
            ),
            responseType: HeartbeatResponse.self
        )
    }

    func listClaimableRuns(limit: Int = 1) async throws -> [WorkflowRunEnvelope] {
        var components = URLComponents(url: endpointURL(path: "api/workflow-runs/claimable"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
        ]

        guard let url = components?.url else {
            throw ClientError.invalidBaseURL
        }

        var request = authorizedRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let response = try await send(request, responseType: WorkflowRunListResponse.self)
        return response.runs
    }

    func claimRun(runId: String, deviceId: String, backendId: String) async throws -> ClaimResponse {
        try await send(
            method: "POST",
            path: "api/workflow-runs/\(runId)/claim",
            body: ClaimRunRequest(deviceId: deviceId, backendId: backendId),
            responseType: ClaimResponse.self
        )
    }

    func markRunStarted(runId: String, deviceId: String, leaseToken: String, backendId: String) async throws {
        _ = try await send(
            method: "POST",
            path: "api/workflow-runs/\(runId)/start",
            body: StartRunRequest(deviceId: deviceId, leaseToken: leaseToken, backendId: backendId),
            responseType: SimpleResponse.self
        )
    }

    func renewLease(runId: String, deviceId: String, leaseToken: String) async throws -> LeaseRenewalResponse {
        try await send(
            method: "POST",
            path: "api/workflow-runs/\(runId)/renew",
            body: LeaseRequest(deviceId: deviceId, leaseToken: leaseToken),
            responseType: LeaseRenewalResponse.self
        )
    }

    func releaseRun(runId: String, deviceId: String, leaseToken: String, reason: String?) async throws {
        _ = try await send(
            method: "POST",
            path: "api/workflow-runs/\(runId)/release",
            body: ReleaseRunRequest(deviceId: deviceId, leaseToken: leaseToken, reason: reason),
            responseType: SimpleResponse.self
        )
    }

    func completeRun(
        runId: String,
        deviceId: String,
        leaseToken: String,
        backendId: String,
        finalOutputs: [String: String],
        output: String?,
        stepOutputsJSON: String?
    ) async throws {
        _ = try await send(
            method: "POST",
            path: "api/workflow-runs/\(runId)/complete",
            body: CompleteRunRequest(
                deviceId: deviceId,
                leaseToken: leaseToken,
                finalOutputs: finalOutputs,
                output: output,
                stepOutputsJSON: stepOutputsJSON,
                backendId: backendId
            ),
            responseType: SimpleResponse.self
        )
    }

    func failRun(
        runId: String,
        deviceId: String,
        leaseToken: String,
        backendId: String,
        message: String
    ) async throws {
        _ = try await send(
            method: "POST",
            path: "api/workflow-runs/\(runId)/fail",
            body: FailRunRequest(
                deviceId: deviceId,
                leaseToken: leaseToken,
                error: ErrorPayload(message: message),
                backendId: backendId
            ),
            responseType: SimpleResponse.self
        )
    }

    private func endpointURL(path: String) -> URL {
        baseURL.appending(path: path)
    }

    private func authorizedRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func send<RequestBody: Encodable, ResponseBody: Decodable>(
        method: String,
        path: String,
        body: RequestBody,
        responseType: ResponseBody.Type
    ) async throws -> ResponseBody {
        var request = authorizedRequest(url: endpointURL(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try encoder.encode(body)
        return try await send(request, responseType: responseType)
    }

    private func send<ResponseBody: Decodable>(
        _ request: URLRequest,
        responseType: ResponseBody.Type
    ) async throws -> ResponseBody {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = Self.decodeErrorMessage(from: data) ??
                "Live workflow request failed (\(httpResponse.statusCode))."
            clientLog.warning("Live workflow request failed: \(message)")
            throw ClientError.server(status: httpResponse.statusCode, message: message)
        }

        return try decoder.decode(ResponseBody.self, from: data)
    }

    private static func decodeErrorMessage(from data: Data) -> String? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = json["error"] as? String
        else {
            return nil
        }
        return error
    }
}
