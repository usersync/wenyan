//
//  GitHubUploader.swift
//  WenYan
//
//  Created by Lei Cao on 2025/2/19.
//

import Foundation

struct GitHubImageHost: Codable {
    var type: String = Settings.ImageHosts.github.id
    var token: String = ""
    var repo: String = ""
    var branch: String = "main"
    var path: String = ""
}
class GitHubUploader: Uploader {
    private var config: GitHubImageHost
    
    init(config: GitHubImageHost) {  // 确保初始化器参数类型正确
        self.config = config
    }
    
    func upload(fileData: Data, fileName: String, mimeType: String) async throws -> String? {
        let baseUrl = "https://api.github.com/repos/" + config.repo + "/contents/" + (config.path.isEmpty ? "" : config.path + "/") + fileName
        
        let headers = [
            "Authorization": "token " + config.token,
            "Accept": "application/vnd.github.v3+json"
        ]
        
        let body: [String: Any] = [
            "message": "Upload image via WenYan",
            "branch": config.branch,
            "content": fileData.base64EncodedString()
        ]
        
        let request = try createRequest(url: baseUrl, method: "PUT", headers: headers, body: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // 检查HTTP响应状态码
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "GitHubUploader", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的HTTP响应"])
        }
        
        // 打印响应数据以便调试
        if let responseString = String(data: data, encoding: .utf8) {
            print("GitHub API响应: \(responseString)")
        }
        
        // 检查状态码是否表示成功
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            throw NSError(domain: "GitHubUploader", code: httpResponse.statusCode, 
                          userInfo: [NSLocalizedDescriptionKey: "GitHub API错误: \(errorMessage?["message"] as? String ?? "未知错误") (状态码: \(httpResponse.statusCode))"])
        }
        
        // 解析响应JSON
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [String: Any],
              let url = content["download_url"] as? String else {
            throw NSError(domain: "GitHubUploader", code: -2, 
                          userInfo: [NSLocalizedDescriptionKey: "无法从GitHub响应中获取下载URL"])
        }
        
        return url
    }
    
    private func createRequest(url: String, method: String, headers: [String: String], body: [String: Any]) throws -> URLRequest {
        guard let url = URL(string: url) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        headers.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        if !body.isEmpty {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        
        return request
    }
}
