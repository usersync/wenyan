//
//  SettingsView.swift
//  WenYan
//
//  Created by Lei Cao on 2025/2/18.
//

import SwiftUI
import AppKit // 用于NSImage图片处理

struct SettingsView: View {
    @State private var selectedTab: Settings? = .imageHosts(.gzh)

    var body: some View {
        Group {
            NavigationView {
                // 侧边栏
                Sidebar(selectedTab: $selectedTab)
                // 右侧详情视图
                SettingsContent(selectedTab: $selectedTab)
            }
            .frame(width: 650, height: 550)
        }
    }
}

// 侧边栏
struct Sidebar: View {
    @Binding var selectedTab: Settings?
    
    var body: some View {
        List(selection: $selectedTab) {
            Section {
                ForEach(Settings.ImageHosts.allCases) { imageHost in
                    SidebarItem(title: imageHost.rawValue, id: Settings.imageHosts(imageHost), padding: 16)
                }
            } header: {
                HStack {
                    Image(systemName: "square.grid.2x2")
                    Text("图床设置").font(.headline)
                }
                .padding(.leading, 8)
            }
            SidebarItem(title: "段落设置", id: Settings.paragraph, padding: 8)
            SidebarItem(title: "代码块设置", id: Settings.codeblock, padding: 8)
        }
        .padding(.leading, 8)
        .listStyle(.sidebar)
        .frame(minWidth: 200, maxWidth: 200, minHeight: 550, maxHeight: 550)
    }
}

// 侧边栏 item
struct SidebarItem: View {
    let title: String
    let id: Settings
    let padding: CGFloat
    
    var body: some View {
        Text(title)
            .tag(id)
            .padding(.leading, padding)
    }
}

struct SettingsContent: View {
    @Binding var selectedTab: Settings?
    
    var body: some View {
        VStack(alignment: .leading) {
            switch selectedTab {
            case .imageHosts(let imageHost):
                if imageHost == .gzh {
                    GzhImageHostSettingsView()
                } else if imageHost == .github {
                    GitHubImageHostSettingsView()
                }
            case .codeblock:
                CodeblockSettingsView()
            case .paragraph:
                ParagraphSettingsView()
            default:
                CardView {
                    HStack {
                        Image(systemName: "person.fill")
                        Text("文颜设置")
                    }
                }
            }
        }
        .frame(minWidth: 450, maxWidth: 450, minHeight: 550, maxHeight: 550, alignment: .topLeading)
        .padding()
    }
}

struct CardView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
            .cornerRadius(10)
            .shadow(radius: 3)
    }
}

// GitHub图床设置视图
struct GitHubImageHostSettingsView: View {
    @StateObject private var viewModel = GitHubImageHostSettingsViewModel()
    @State private var testResult: String? = nil
    @State private var isTesting = false
    @State private var selectedTestImage: NSImage? = nil
    @State private var showLogWindow = false
    @State private var logMessages: [String] = []

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(Settings.ImageHosts.github.rawValue)
                    .font(.title2)
                    .bold()
                Spacer()
                Toggle("", isOn: $viewModel.isEnabled)
                    .toggleStyle(.switch)
            }
            
            CardView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("GitHub Token")
                        .bold()
                    TextField("请输入GitHub Token", text: $viewModel.githubImageHost.token)
                        .textFieldStyle(.roundedBorder)
                        .padding(.bottom, 8)
                    
                    Text("仓库名称")
                        .bold()
                    TextField("如：username/repo", text: $viewModel.githubImageHost.repo)
                        .textFieldStyle(.roundedBorder)
                        .padding(.bottom, 8)
                    
                    Text("分支名称")
                        .bold()
                    TextField("默认为main", text: $viewModel.githubImageHost.branch)
                        .textFieldStyle(.roundedBorder)
                        .padding(.bottom, 8)
                    
                    Text("存储路径")
                        .bold()
                    TextField("可选，如：images", text: $viewModel.githubImageHost.path)
                        .textFieldStyle(.roundedBorder)
                        .padding(.bottom, 8)
                    
                    HStack {
                        Button("选择测试图片") {
                            let openPanel = NSOpenPanel()
                            openPanel.allowedContentTypes = [.png, .jpeg]
                            if openPanel.runModal() == .OK {
                                if let nsImage = NSImage(contentsOf: openPanel.url!) {
                                    selectedTestImage = nsImage
                                }
                            }
                        }
                        
                        if let image = selectedTestImage {
                            Text("已选择: \(image)")
                                .font(.caption)
                        }
                    }
                    
                    Button(action: testConnection) {
                        HStack {
                            if isTesting {
                                ProgressView()
                            }
                            Text("测试连接")
                        }
                    }
                    .disabled(isTesting || selectedTestImage == nil)
                    
                    Button("查看日志") {
                        showLogWindow = true
                    }
                    .disabled(logMessages.isEmpty)
                    
                    Button("保存配置") {
                        viewModel.saveSettings()
                    }
                    
                    if let result = testResult {
                        Text(result)
                            .foregroundColor(result.contains("成功") ? .green : .red)
                    }
                    
                    if showLogWindow {
                        VStack {
                            Text("测试日志")
                                .font(.headline)
                            ScrollView {
                                VStack(alignment: .leading) {
                                    ForEach(logMessages, id: \.self) { message in
                                        Text(message)
                                    }
                                }
                            }
                            .frame(height: 200)
                            Button("关闭") {
                                showLogWindow = false
                            }
                        }
                        .padding()
                        .background(Color(nsColor: .windowBackgroundColor))
                        .cornerRadius(10)
                    }
                }
            }
        }
        .padding()
    }
    
    private func testConnection() {
        isTesting = true
        testResult = nil
        logMessages.removeAll()
        
        Task {
            do {
                logMessages.append("开始测试连接...")
                let uploader = GitHubUploader(config: viewModel.githubImageHost) 
                // 参数类型已匹配 GitHubImageHost 结构体
                guard let selectedImage = selectedTestImage,
                      let cgImage = selectedImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
                      let bitmapRep = NSBitmapImageRep(cgImage: cgImage) as NSBitmapImageRep?,
                      let imageData = bitmapRep.representation(using: .png, properties: [:]) else {
                    testResult = "测试失败: 无法获取图片数据"
                    isTesting = false
                    return
                }
                
                logMessages.append("正在上传图片...")
                let fileName = "wenyan_test_\(UUID().uuidString).png"
                if let imageUrl = try await uploader.upload(fileData: imageData, fileName: fileName, mimeType: "image/png") {
                    logMessages.append("图片上传成功: \(fileName)")
                    logMessages.append("图片URL: \(imageUrl)")
                    testResult = "测试成功: 文件已上传到GitHub仓库"
                } else {
                    throw NSError(domain: "GitHubUploader", code: -3, userInfo: [NSLocalizedDescriptionKey: "上传成功但未返回有效URL"])
                }
            } catch {
                logMessages.append("上传失败: \(error.localizedDescription)")
                testResult = "测试失败: \(error.localizedDescription)"
            }
            isTesting = false
            showLogWindow = true
        }
    }
}

class GitHubImageHostSettingsViewModel: ObservableObject {
    @Published var githubImageHost: GitHubImageHost {
        didSet {
            saveSettings()
        }
    }
    @Published var isEnabled: Bool = false {
        didSet {
            if isEnabled {
                UserDefaults.standard.set(Settings.ImageHosts.github.id, forKey: "ebabledImageHost")
            } else {
                // Only clear if this was the active host
                if UserDefaults.standard.string(forKey: "ebabledImageHost") == Settings.ImageHosts.github.id {
                    UserDefaults.standard.set("", forKey: "ebabledImageHost")
                }
            }
        }
    }
    private static let key = "githubImageHost"
    
    init() {
        self.githubImageHost = Self.loadSettings() ?? GitHubImageHost()
        let ebabledImageHost = UserDefaults.standard.string(forKey: "ebabledImageHost")
        if let enabled = ebabledImageHost {
            isEnabled = enabled == Settings.ImageHosts.github.id
        }
    }
    
    func saveSettings() {
        if let encoded = try? JSONEncoder().encode(githubImageHost) {
            UserDefaults.standard.set(encoded, forKey: Self.key)
        }
    }
    

    private static func loadSettings() -> GitHubImageHost? {
        if let savedData = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(GitHubImageHost.self, from: savedData) {
            return decoded
        }
        return nil
    }
}

// 公众号图床设置视图
struct GzhImageHostSettingsView: View {
    @StateObject private var viewModel = GzhImageHostSettingsViewModel()

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(Settings.ImageHosts.gzh.rawValue)
                    .font(.title2)
                    .bold()
                Spacer()
                Toggle("", isOn: $viewModel.isEnabled)
                    .toggleStyle(.switch)
            }
            
            CardView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("开发者ID(AppID)")
                        .bold()
                    TextField("如：wx6e1234567890efa3", text: $viewModel.gzhImageHost.appId)
                        .textFieldStyle(.roundedBorder)
                        .padding(.bottom, 8)
                    
                    Text("开发者密码(AppSecret)")
                        .bold()
                    TextField("如：d9f1abcdef01234567890abcdef82397", text: $viewModel.gzhImageHost.appSecret)
                        .textFieldStyle(.roundedBorder)
                    
                    HStack {
                        Spacer()
                        Text("请务必开启“IP白名单”")
                    }
                    .padding(.top, 16)
                    HStack {
                        Spacer()
                        Link("使用帮助", destination: URL(string: "https://yuzhi.tech/docs/wenyan/upload")!)
                            .pointingHandCursor()
                    }
                }
            }

        }
        .padding()
    }
}

class GzhImageHostSettingsViewModel: ObservableObject {
    @Published var gzhImageHost: GzhImageHost {
        didSet {
            saveSettings()
        }
    }
    @Published var isEnabled: Bool = false {
        didSet {
            if isEnabled {
                UserDefaults.standard.set(Settings.ImageHosts.gzh.id, forKey: "ebabledImageHost")
            } else {
                // Only clear if this was the active host
                if UserDefaults.standard.string(forKey: "ebabledImageHost") == Settings.ImageHosts.gzh.id {
                    UserDefaults.standard.set("", forKey: "ebabledImageHost")
                }
            }
        }
    }
    private static let key = "gzhImageHost"
    
    init() {
        self.gzhImageHost = Self.loadSettings() ?? GzhImageHost()
        let ebabledImageHost = UserDefaults.standard.string(forKey: "ebabledImageHost")
        if let enabled = ebabledImageHost {
            isEnabled = enabled == Settings.ImageHosts.gzh.id
        }
    }
    
    private func saveSettings() {
        var clone = gzhImageHost
        clone.accessToken = ""
        clone.expireTime = nil
        if let encoded = try? JSONEncoder().encode(clone) {
            UserDefaults.standard.set(encoded, forKey: Self.key)
        }
    }
    

    private static func loadSettings() -> GzhImageHost? {
        if let savedData = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(GzhImageHost.self, from: savedData) {
            return decoded
        }
        return nil
    }
}

// 代码块设置视图
struct CodeblockSettingsView: View {
    @StateObject private var viewModel = CodeblockSettingsViewModel()
    @EnvironmentObject private var htmlViewModel: HtmlViewModel
    @State private var showBubble = false

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("代码块设置")
                    .font(.title2)
                    .bold()
            }
            
            CardView {
                ZStack {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Mac 风格")
                                .bold()
                            Spacer()
                            Toggle("", isOn: $viewModel.codeblockSettings.isMacStyle)
                                .toggleStyle(.switch)
                        }
                        .padding(.bottom, 8)
                        
                        Text("高亮主题")
                            .bold()
                        Picker("", selection: $viewModel.codeblockSettings.theme) {
                            ForEach(HighlightStyle.allCases, id: \.self.rawValue) { style in
                                Text(style.rawValue).tag(style.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .padding(.bottom, 8)
                        
                        Text("字体大小")
                            .bold()
                        Picker("", selection: $viewModel.codeblockSettings.fontSize) {
                            ForEach(FontSize.allCases, id: \.self.rawValue) { fontSize in
                                Text(fontSize.rawValue).tag(fontSize.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.bottom, 8)
                        
                        HStack {
                            Text("字体")
                                .bold()
                                Button("", systemImage: "questionmark.circle") {
                                    showBubble = true
                                }
                                .buttonStyle(.borderless)
                                .font(.system(size: 13))
                                .onHover { hovering in
                                    if hovering {
                                        showBubble = true
                                    } else {
                                        showBubble = false
                                    }
                                }
                        }
                        TextField("如：JetBrains Mono", text: $viewModel.codeblockSettings.fontFamily)
                            .textFieldStyle(.roundedBorder)
                        
                        HStack {
                            Spacer()
                            Link("使用帮助", destination: URL(string: "https://yuzhi.tech/docs/wenyan/codeblock")!)
                                .pointingHandCursor()
                        }
                        .padding(.top, 16)
                    }
                    if showBubble {
                        Text("你可以在这里设置你本机上已经安装的字体，但请注意：这里设置的字体只会影响你本地预览、导出图片时的显示，并不会影响公众号发布后用户看到的字体。具体说明请参阅“使用帮助”。")
                            .padding()
                            .offset(x: 20, y: 40)
                            .foregroundColor(.gray)
                            .font(.system(size: 12))
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Color.white)
                                    .shadow(radius: 5)
                                    .offset(x: 20, y: 40)
                            )
                            .frame(width: 300, height: 120)
                    }
                }
                .onReceive(viewModel.$codeblockSettings) { newContent in
                    if let highlightStyle = HighlightStyle(rawValue: newContent.theme) {
                        htmlViewModel.highlightStyle = highlightStyle
                    }
                    htmlViewModel.codeblockSettings.fontSize = newContent.fontSize
                    htmlViewModel.codeblockSettings.fontFamily = newContent.fontFamily
                    htmlViewModel.setCodeblock()
                    htmlViewModel.setTheme()
                    newContent.isMacStyle ? htmlViewModel.setMacStyle() : htmlViewModel.removeMacStyle()
                }
            }

        }
        .padding()
    }
}

class CodeblockSettingsViewModel: ObservableObject {
    @Published var codeblockSettings: CodeblockSettings {
        didSet {
            saveSettings()
        }
    }
    private static let key = "codeblockSettings"
    
    init() {
        self.codeblockSettings = Self.loadSettings() ?? CodeblockSettings()
    }
    
    private func saveSettings() {
        if let encoded = try? JSONEncoder().encode(codeblockSettings) {
            UserDefaults.standard.set(encoded, forKey: Self.key)
        }
    }

    static func loadSettings() -> CodeblockSettings? {
        if let savedData = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(CodeblockSettings.self, from: savedData) {
            return decoded
        }
        return nil
    }
}

struct CodeblockSettings: Codable {
    var isMacStyle: Bool = false
    var theme: String = HighlightStyle.github.rawValue
    var fontSize: String = FontSize.px12.rawValue
    var fontFamily: String = ""
}


// 段落设置视图
struct ParagraphSettingsView: View {
    @StateObject private var viewModel = ParagraphSettingsViewModel()
    @EnvironmentObject private var htmlViewModel: HtmlViewModel

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("段落设置")
                    .font(.title2)
                    .bold()
            }
            
            CardView {
                ZStack {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("跟随主题")
                                .bold()
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { !viewModel.paragraphSettings.isEnabled },
                                set: { viewModel.paragraphSettings.isEnabled = !$0 }
                            ))
                            .toggleStyle(.switch)
                        }
                        .padding(.bottom, 8)
                        
                        Text("字体大小")
                            .bold()
                        Picker("", selection: $viewModel.paragraphSettings.fontSize) {
                            ForEach(FontSize.allCases, id: \.self.rawValue) { fontSize in
                                Text(fontSize.rawValue).tag(fontSize.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.bottom, 8)
                        
                        Text("字体")
                            .bold()
                        Picker("", selection: $viewModel.paragraphSettings.fontType) {
                            ForEach(FontType.allCases, id: \.self.rawValue) { style in
                                Text(style.label).tag(style.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.bottom, 8)
                        
                        Text("文字粗细")
                            .bold()
                        Picker("", selection: $viewModel.paragraphSettings.fontWeight) {
                            ForEach(FontWeight.allCases, id: \.self.rawValue) { style in
                                Text(style.label).tag(style.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.bottom, 8)
                        
                        Text("字间距")
                            .bold()
                        Picker("", selection: $viewModel.paragraphSettings.wordSpacing) {
                            ForEach(WordSpacing.allCases, id: \.self.rawValue) { style in
                                Text(style.label).tag(style.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.bottom, 8)
                        
                        Text("行间距")
                            .bold()
                        Picker("", selection: $viewModel.paragraphSettings.lineSpacing) {
                            ForEach(LineSpacing.allCases, id: \.self.rawValue) { style in
                                Text(style.label).tag(style.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.bottom, 8)
                        
                        Text("段落间距")
                            .bold()
                        Picker("", selection: $viewModel.paragraphSettings.paragraphSpacing) {
                            ForEach(ParagraphSpacing.allCases, id: \.self.rawValue) { style in
                                Text(style.label).tag(style.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.bottom, 8)
                    }
                }
                .onReceive(viewModel.$paragraphSettings) { newContent in
                    htmlViewModel.setParagraphSettings(paragraphSettings: newContent)
                    htmlViewModel.setTheme()
                }
            }

        }
        .padding()
    }
}

class ParagraphSettingsViewModel: ObservableObject {
    @Published var paragraphSettings: ParagraphSettings {
        didSet {
            saveSettings()
        }
    }
    private static let key = "paragraphSettings"
    
    init() {
        self.paragraphSettings = Self.loadSettings() ?? ParagraphSettings()
    }
    
    private func saveSettings() {
        if let encoded = try? JSONEncoder().encode(paragraphSettings) {
            UserDefaults.standard.set(encoded, forKey: Self.key)
        }
    }

    static func loadSettings() -> ParagraphSettings? {
        if let savedData = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(ParagraphSettings.self, from: savedData) {
            return decoded
        }
        return nil
    }
}

struct ParagraphSettings: Codable {
    var isEnabled: Bool = false
    var fontSize: String = FontSize.px16.rawValue
    var fontType: String = FontType.sans.rawValue
    var fontWeight: String = FontWeight._400.rawValue
    var wordSpacing: String = WordSpacing.medium.rawValue
    var lineSpacing: String = LineSpacing.medium.rawValue
    var paragraphSpacing: String = ParagraphSpacing.medium.rawValue
}
