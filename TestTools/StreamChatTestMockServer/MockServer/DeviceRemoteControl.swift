//
// Copyright © 2022 Stream.io Inc. All rights reserved.
//

public extension StreamMockServer {
    
    func pushNotification(
        senderName: String,
        text: String,
        messageId: String,
        cid: String,
        targetBundleId: String
    ) {
        var json: [String: Any]
        if pushNotificationPayload.isEmpty {
            json = TestData.toJson(.pushNotification)
            var aps = json[APNSKey.aps] as? [String: Any]
            var alert = aps?[APNSKey.alert] as? [String: Any]
            alert?[APNSKey.title] = "New message from \(senderName)"
            alert?[APNSKey.body] = text
            aps?[APNSKey.alert] = alert
            json[APNSKey.aps] = aps
            
            var stream = json[APNSKey.stream] as? [String: Any]
            stream?[APNSKey.messageId] = messageId
            stream?[APNSKey.cid] = cid
            json[APNSKey.stream] = stream
        } else {
            json = pushNotificationPayload
        }
        
        let udid = ProcessInfo.processInfo.environment["SIMULATOR_UDID"] ?? ""
        let urlString = "\(MockServerConfiguration.httpHost):4567/push/\(udid)/\(targetBundleId)"
        guard let url = URL(string: urlString) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = json.jsonToString().data(using: .utf8)
        URLSession.shared.dataTask(with: request).resume()
    }
    
    func recordVideo(name: String, delete: Bool = false, stop: Bool = false) {
        let json: [String: Any] = ["delete": delete, "stop": stop]
        let udid = ProcessInfo.processInfo.environment["SIMULATOR_UDID"] ?? ""
        let urlString = "\(MockServerConfiguration.httpHost):4567/record_video/\(udid)/\(name)"
        guard let url = URL(string: urlString) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = json.jsonToString().data(using: .utf8)
        URLSession.shared.dataTask(with: request).resume()
    }
}
