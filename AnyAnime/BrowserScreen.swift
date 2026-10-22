import SwiftUI
import WebKit

struct AnimeWebView: UIViewRepresentable {
    @EnvironmentObject var browser: AnimeBrowserModel
    func makeUIView(context: Context) -> WKWebView { browser.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) { }
}

struct BrowserScreen: View {
    @EnvironmentObject private var browser: AnimeBrowserModel
    @State private var showSources = false
    @State private var showDiagnostics = false
    @State private var showRemoteSettings = false
    @State private var editingConfig = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "play.rectangle.fill").foregroundStyle(.red)
                Text("AnyAnime").font(.headline)
                Spacer()
                Button { showDiagnostics = true } label: {
                    Image(systemName: "ladybug")
                        .accessibilityLabel("Nhật ký kết nối")
                }
                Button { showSources = true } label: {
                    Image(systemName: "network")
                        .accessibilityLabel("Chọn nguồn phim")
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            HStack(spacing: 6) {
                Image(systemName: browser.siteVerified ? "checkmark.shield.fill" : "globe")
                    .foregroundStyle(browser.siteVerified ? .green : .secondary)
                Text(browser.status).lineLimit(1).font(.caption)
                Spacer(minLength: 2)
            }
            .padding(.horizontal, 14).padding(.vertical, 5)
            .background(Color(.secondarySystemBackground))
            if browser.isLoading { ProgressView().progressViewStyle(.linear) }
            AnimeWebView().ignoresSafeArea(edges: .bottom)
            HStack {
                toolbarButton("chevron.left", "Quay lại") { browser.goBack() }
                Spacer()
                toolbarButton("chevron.right", "Tiến tới") { browser.goForward() }
                Spacer()
                toolbarButton("house", "Trang chủ") { browser.goHome() }
                Spacer()
                toolbarButton("arrow.clockwise", "Tải lại") { browser.reload() }
                Spacer()
                toolbarButton("arrow.triangle.2.circlepath", "Thử nguồn kế") { browser.tryNextSource() }
                Spacer()
                toolbarButton("list.bullet", "Nguồn phim") { showSources = true }
            }
            .padding(.horizontal, 24).padding(.vertical, 10)
            .background(Color(.systemBackground))
        }
        .onAppear { browser.startOnce() }
        .sheet(isPresented: $showSources) {
            NavigationView {
                List {
                    Section("Nguồn website (tự động theo HTTP / JavaScript redirect)") {
                        ForEach(Array(browser.sourceURLs.enumerated()), id: \.offset) { index, link in
                            Button {
                                browser.loadSource(at: index)
                                showSources = false
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("Nguồn \(index + 1)").bold()
                                        Text(link).font(.caption).foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    if browser.selectedSource == index { Image(systemName: "checkmark") }
                                }
                            }
                        }
                    }
                    Section("Địa chỉ cuối cùng") {
                        Text(browser.displayedURL.isEmpty ? "Chưa xác định" : browser.displayedURL)
                            .font(.footnote).textSelection(.enabled)
                    }
                    Section {
                        Button("Cấu hình nguồn từ xa") {
                            showSources = false
                            editingConfig = browser.remoteConfigURL
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                                showRemoteSettings = true
                            }
                        }
                    }
                }
                .navigationTitle("Nguồn anime")
                .toolbar { ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Xong") { showSources = false }
                }}
            }
        }
        .sheet(isPresented: $showDiagnostics) {
            NavigationView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("URL hiện tại").font(.headline)
                        Text(browser.displayedURL).font(.caption).textSelection(.enabled)
                        Divider()
                        Text(browser.debugLines.joined(separator: "\n"))
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding()
                }
                .navigationTitle("Nhật ký")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Sao chép") { UIPasteboard.general.string = browser.copyDiagnostics() }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Xong") { showDiagnostics = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showRemoteSettings) {
            NavigationView {
                Form {
                    Section("URL config.json của bạn") {
                        TextField("https://.../config.json", text: $editingConfig)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    }
                    Section("Ví dụ nội dung JSON") {
                        Text("{\"sources\":[\"https://bit.ly/animevietsubtv\",\"https://www.animevietsub.sale/\"]}")
                            .font(.footnote.monospaced()).textSelection(.enabled)
                    }
                }
                .navigationTitle("Cập nhật tự động")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Hủy") { showRemoteSettings = false }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Lưu") {
                            browser.setRemoteConfig(editingConfig)
                            showRemoteSettings = false
                        }
                    }
                }
            }
        }
    }

    private func toolbarButton(_ image: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: image).font(.system(size: 19)) }
            .accessibilityLabel(label)
            .frame(minWidth: 32, minHeight: 28)
    }
}
