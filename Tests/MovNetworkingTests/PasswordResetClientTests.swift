import Foundation
import XCTest
@testable import MovNetworking

private struct CapturedResetRequest: Sendable {
    let path: String
    let method: String
    let body: Data?
    let headers: [String: String]
}

/// In-memory transport: password reset tests never open a socket or contact email infrastructure.
private actor PasswordResetResponseMock: APIResponseSending {
    private let response: APIClientResponse
    private var captured: [CapturedResetRequest] = []

    init(statusCode: Int, body: String = "", requestID: String? = nil) {
        response = APIClientResponse(statusCode: statusCode, data: Data(body.utf8), requestID: requestID)
    }

    func sendResponse(path: String, method: String, body: Data?, headers: [String: String], queryItems: [URLQueryItem]) async throws -> APIClientResponse {
        captured.append(CapturedResetRequest(path: path, method: method, body: body, headers: headers))
        return response
    }

    func requests() -> [CapturedResetRequest] { captured }
}

private struct PasswordResetTransportFailure: APIResponseSending {
    func sendResponse(path: String, method: String, body: Data?, headers: [String: String], queryItems: [URLQueryItem]) async throws -> APIClientResponse {
        throw APIClientError.transport(.timedOut)
    }
}

final class PasswordResetClientTests: XCTestCase {
    private let validProof = String(repeating: "P", count: 43)

    func testRequestCodeUsesNeutralEndpointAndNoAccountSpecificBranch() async throws {
        for email in ["local@example.com", "unknown@example.com", "social@example.com"] {
            let mock = PasswordResetResponseMock(statusCode: 202)
            let client = PasswordResetClient(apiClient: mock)
            try await client.requestCode(email: "  \(email)  ")

            let requests = await mock.requests()
            let request = try XCTUnwrap(requests.first)
            XCTAssertEqual(request.path, "auth/password/reset/verifications")
            XCTAssertEqual(request.method, "POST")
            XCTAssertEqual(try JSONSerialization.jsonObject(with: XCTUnwrap(request.body)) as? [String: String], ["email": email])
            XCTAssertEqual(request.headers["Cache-Control"], "no-store")
            XCTAssertNil(request.headers["Authorization"])
        }
    }

    func testConfirmCodeUsesPasswordResetPurposeEndpointAndValidatesTenMinuteProof() async throws {
        let mock = PasswordResetResponseMock(statusCode: 200, body: "{\"resetProof\":\"\(validProof)\",\"expiresInSeconds\":600}")
        let proof = try await PasswordResetClient(apiClient: mock).confirmCode(email: "runner@example.com", code: "038261")
        XCTAssertEqual(proof, PasswordResetProof(value: validProof, expiresInSeconds: 600))

        let requests = await mock.requests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.path, "auth/password/reset/verifications/confirm")
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(try JSONSerialization.jsonObject(with: XCTUnwrap(request.body)) as? [String: String], ["email": "runner@example.com", "code": "038261"])

        let wrongLifetime = PasswordResetResponseMock(statusCode: 200, body: "{\"resetProof\":\"\(validProof)\",\"expiresInSeconds\":300}")
        do {
            _ = try await PasswordResetClient(apiClient: wrongLifetime).confirmCode(email: "runner@example.com", code: "038261")
            XCTFail("Only the backend's ten-minute reset proof is accepted")
        } catch let failure as PasswordResetFailure {
            XCTAssertEqual(failure, .invalidResponse)
        }
    }

    func testResetPasswordPostsProofRequestIDEmailAndExactPasswordAndRequires204() async throws {
        let mock = PasswordResetResponseMock(statusCode: 204)
        try await PasswordResetClient(apiClient: mock).resetPassword(
            resetProof: validProof,
            requestID: "5e10d6bf-53db-4ba0-9070-85af456a00d5",
            email: "runner@example.com",
            password: "NewRunner4826!"
        )
        let requests = await mock.requests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.path, "auth/password/reset")
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(try JSONSerialization.jsonObject(with: XCTUnwrap(request.body)) as? [String: String], [
            "resetProof": validProof,
            "requestId": "5e10d6bf-53db-4ba0-9070-85af456a00d5",
            "email": "runner@example.com",
            "password": "NewRunner4826!"
        ])
        XCTAssertNil(request.headers["Authorization"])

        let unexpectedBody = PasswordResetResponseMock(statusCode: 204, body: "ok")
        do {
            try await PasswordResetClient(apiClient: unexpectedBody).resetPassword(
                resetProof: validProof,
                requestID: "req-2",
                email: "runner@example.com",
                password: "NewRunner4826!"
            )
            XCTFail("A 204 with a response body is not the API contract")
        } catch let failure as PasswordResetFailure {
            XCTAssertEqual(failure, .invalidResponse)
        }
    }

    func testVerificationFailureCollapsesWrongExpiredConsumedAndWrongPurposeCodes() async throws {
        for requestID in ["wrong", "expired", "consumed", "signup-purpose"] {
            let mock = PasswordResetResponseMock(
                statusCode: 422,
                body: "{\"code\":\"VERIFICATION_FAILED\",\"requestId\":\"\(requestID)\",\"message\":\"private diagnostic\"}"
            )
            do {
                _ = try await PasswordResetClient(apiClient: mock).confirmCode(email: "runner@example.com", code: "038261")
                XCTFail("Expected a collapsed verification failure")
            } catch let failure as PasswordResetFailure {
                XCTAssertEqual(failure, .verificationFailed(requestID: requestID))
                XCTAssertFalse(failure.userMessage.contains(requestID))
                XCTAssertFalse(failure.userMessage.contains("private diagnostic"))
            }
        }
    }

    func testBackendRateAndAvailabilityCodesMapToRetryableFailures() async throws {
        let cases: [(Int, String, PasswordResetFailure)] = [
            (429, "TOO_MANY_REQUESTS", .tooManyRequests(requestID: "retry-429")),
            (503, "AUTH_UNAVAILABLE", .serviceUnavailable(requestID: "retry-auth")),
            (503, "VERIFICATION_EMAIL_UNAVAILABLE", .serviceUnavailable(requestID: "retry-mail"))
        ]
        for (status, code, expected) in cases {
            let mock = PasswordResetResponseMock(statusCode: status, body: "{\"code\":\"\(code)\",\"requestId\":\"\(expected.requestID!)\"}")
            do {
                try await PasswordResetClient(apiClient: mock).requestCode(email: "runner@example.com")
                XCTFail("Expected \(code)")
            } catch let failure as PasswordResetFailure {
                XCTAssertEqual(failure, expected)
            }
        }
    }

    func testValidationRejectsMalformedInputsBeforeTransportAndTransportFailureCanRetryExactly() async throws {
        let unused = PasswordResetResponseMock(statusCode: 202)
        let client = PasswordResetClient(apiClient: unused)
        do {
            _ = try await client.confirmCode(email: "runner@example.com", code: "１２３４５６")
            XCTFail("Only six ASCII digits match the backend contract")
        } catch let failure as PasswordResetFailure {
            XCTAssertEqual(failure, .invalidRequest)
        }
        do {
            try await client.resetPassword(resetProof: validProof, requestID: "req-1", email: "runner@example.com", password: "spaces are invalid1")
            XCTFail("Backend passwords are 8–20 printable ASCII characters without spaces")
        } catch let failure as PasswordResetFailure {
            XCTAssertEqual(failure, .invalidRequest)
        }
        let requests = await unused.requests()
        XCTAssertTrue(requests.isEmpty)

        do {
            try await PasswordResetClient(apiClient: PasswordResetTransportFailure()).requestCode(email: "runner@example.com")
            XCTFail("Expected a mocked timeout")
        } catch let failure as PasswordResetFailure {
            XCTAssertEqual(failure, .transport(.timedOut))
            XCTAssertTrue(failure.requiresExactRetry)
        }
    }
}
