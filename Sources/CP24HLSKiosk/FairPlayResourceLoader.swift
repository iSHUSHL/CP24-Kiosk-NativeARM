import AVFoundation
import Foundation

/// Uses the broadcaster's normal FairPlay certificate/license exchange.
final class FairPlayResourceLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "com.local.cp24-hls.fairplay")
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest) -> Bool {
        guard let url = request.request.url, url.scheme == "skd", let id = url.host else { return false }
        let key = ObjectIdentifier(request)
        tasks[key] = Task {
            do {
                let certificate = try await fetch(URLRequest(url: URL(string: "https://license.9c9media.ca/fairplay/cert")!))
                let spc = try request.streamingContentKeyRequestData(forApp: certificate, contentIdentifier: Data(id.utf8), options: nil)
                var license = URLRequest(url: URL(string: "https://license.9c9media.ca/fairplay/ckc")!)
                license.httpMethod = "POST"
                license.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                license.httpBody = spc
                let ckc = try await fetch(license)
                try Task.checkCancellation()
                queue.async {
                    guard !request.isCancelled else { return }
                    request.contentInformationRequest?.contentType = AVStreamingKeyDeliveryContentKeyType
                    request.dataRequest?.respond(with: ckc)
                    request.finishLoading()
                    self.tasks.removeValue(forKey: key)
                }
            } catch {
                queue.async {
                    guard !request.isCancelled else { return }
                    request.finishLoading(with: error)
                    self.tasks.removeValue(forKey: key)
                }
            }
        }
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForRenewalOfRequestedResource request: AVAssetResourceRenewalRequest) -> Bool {
        self.resourceLoader(resourceLoader, shouldWaitForLoadingOfRequestedResource: request)
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel request: AVAssetResourceLoadingRequest) {
        tasks.removeValue(forKey: ObjectIdentifier(request))?.cancel()
    }

    private func fetch(_ request: URLRequest) async throws -> Data {
        var request = request
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), !data.isEmpty else {
            throw NSError(domain: "CP24FairPlay", code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                          userInfo: [NSLocalizedDescriptionKey: "CP24 playback authorization failed. HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)"])
        }
        return data
    }
}
