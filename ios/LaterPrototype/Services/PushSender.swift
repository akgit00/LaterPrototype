import Foundation

/// Fire-and-forget client for the `send-push` Supabase Edge Function.
///
/// Push delivery is always best-effort: failures are logged in debug builds
/// but never surfaced to the sender, because a missing notification should
/// never break messaging, sharing, or commenting.
nonisolated enum PushSender {
    private struct Payload: Encodable {
        let recipients: [String]
        let title: String
        let body: String
        let threadId: String?
    }

    /// Sends a push notification to each user in `recipients` (Supabase user
    /// ids). Requires a signed-in session; silently does nothing otherwise.
    /// `threadID` groups related notifications and lets the app suppress
    /// banners for the conversation currently on screen.
    static func send(to recipients: [String], title: String, body: String, threadID: String? = nil) {
        let targets = Array(Set(recipients.map { $0.lowercased() }.filter { !$0.isEmpty }))
        guard !targets.isEmpty,
              SupabaseConfig.isConfigured,
              let token = KeychainHelper.get(SupabaseREST.accessTokenKey),
              let url = URL(string: "\(SupabaseConfig.url)/functions/v1/send-push")
        else { return }

        let payload = Payload(
            recipients: targets,
            title: String(title.prefix(100)),
            body: String(body.prefix(180)),
            threadId: threadID?.lowercased()
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = data

        Task.detached(priority: .utility) {
            do {
                let (respData, response) = try await URLSession.shared.data(for: request)
                #if DEBUG
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    print("[PushSender] send failed (\(http.statusCode)): \(String(data: respData, encoding: .utf8) ?? "")")
                }
                #else
                _ = respData
                _ = response
                #endif
            } catch {
                #if DEBUG
                print("[PushSender] send error: \(error.localizedDescription)")
                #endif
            }
        }
    }
}
