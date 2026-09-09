import SwiftUI
import AppKit
import LingCore

struct AssistantView: View {
    @ObservedObject var model: AssistantModel
    var capture: () -> Void
    var openSettings: () -> Void
    @FocusState private var questionFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "viewfinder").font(.title2).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("百灵视觉助手").font(.headline)
                    Text("框选屏幕，随手一问").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: capture) { Image(systemName: "camera.viewfinder") }
                    .help("重新框选 ⌘⇧A").accessibilityLabel("重新框选")
                Button(action: openSettings) { Image(systemName: "gearshape") }
                    .help("设置").accessibilityLabel("设置")
            }

            if let data = model.imageData, let image = NSImage(data: data) {
                ZStack(alignment: .topTrailing) {
                    Image(nsImage: image).resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 155)
                        .padding(8)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .accessibilityLabel("选中区域截图")
                    Button {
                        model.cancel()
                        model.imageData = nil
                        model.answer = ""
                        model.answerIsTruncated = false
                        model.error = nil
                    } label: { Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette)
                            .foregroundStyle(.secondary, Color(nsColor: .windowBackgroundColor)) }
                        .buttonStyle(.plain).padding(8).help("移除截图")
                        .accessibilityLabel("移除截图")
                }
            } else {
                Button(action: capture) {
                    HStack {
                        Image(systemName: "rectangle.dashed")
                        Text("框选屏幕区域")
                        Spacer()
                        Text("⌘⇧A").foregroundStyle(.secondary)
                    }.padding(14).frame(maxWidth: .infinity)
                }.buttonStyle(.bordered).accessibilityLabel("框选屏幕区域")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("想了解什么？").font(.subheadline.weight(.medium))
                ZStack(alignment: .topLeading) {
                    if model.question.isEmpty {
                        Text(model.imageData == nil ? "也可以直接输入文字问题。" : "例如：这个报错是什么意思？\n留空发送可直接解释截图。")
                            .foregroundStyle(.tertiary).padding(.top, 8).padding(.leading, 6)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $model.question)
                        .font(.body).scrollContentBackground(.hidden)
                        .padding(3).focused($questionFocused)
                        .accessibilityLabel("问题")
                }
                .frame(height: 76)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
            }

            HStack {
                Text("仅发送当前问题与所选截图").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if model.isLoading {
                    ProgressView().controlSize(.small)
                    Button("取消") { model.cancel() }
                } else {
                    Button("发送", action: model.submit)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(model.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && model.imageData == nil)
                }
            }

            Divider()

            HStack {
                Text(model.isLoading ? "百灵正在回答…" : "回答").font(.subheadline.weight(.medium))
                Spacer()
                if let elapsed = model.elapsed {
                    Text(String(format: "%.1f 秒", elapsed)).font(.caption).foregroundStyle(.secondary)
                }
                if !model.answer.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(model.answer, forType: .string)
                    } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.plain).help("复制回答").accessibilityLabel("复制回答")
                }
            }
            if model.answerIsTruncated {
                Label("回答达到长度上限，内容可能不完整。可以缩小问题范围后重新提问。",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ScrollView {
                Group {
                    if let error = model.error {
                        Text(error).foregroundStyle(.red).accessibilityLabel("请求错误：\(error)")
                    } else if !model.answer.isEmpty {
                        Text(model.answer).accessibilityLabel("百灵回答：\(model.answer)")
                    } else {
                        Text(model.isLoading ? "正在读取内容，请稍候。" : "解释界面、分析报错、翻译或提取文字。")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.body).lineSpacing(5).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(20)
        .frame(minWidth: 430, minHeight: 570)
        .onAppear { questionFocused = true }
        .onChange(of: model.imageData) { _, _ in questionFocused = true }
    }
}

struct SettingsView: View {
    @ObservedObject var editor: SettingsEditorModel
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("连接百灵").font(.title2.weight(.semibold))
            VStack(alignment: .leading, spacing: 6) {
                Text("API Base URL").font(.subheadline.weight(.medium))
                TextField(LingConfiguration().baseURL, text: $editor.configuration.baseURL)
                    .textFieldStyle(.roundedBorder).accessibilityLabel("API Base URL")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("API Key").font(.subheadline.weight(.medium))
                SecureField("填写百灵 API Key", text: $editor.apiKey)
                    .textFieldStyle(.roundedBorder).accessibilityLabel("API Key")
                Text("保存在本机 macOS 钥匙串中。").font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Model Name").font(.subheadline.weight(.medium))
                TextField("Ling-3.0-flash-VL", text: $editor.configuration.model)
                    .textFieldStyle(.roundedBorder).accessibilityLabel("Model Name")
            }
            Text("保存后才会用于提问；关闭或取消会放弃未保存的修改。")
                .font(.caption).foregroundStyle(.secondary)
            if let error = editor.settings.loadError {
                Text(error).foregroundStyle(.red).font(.caption).textSelection(.enabled)
            }
            if !editor.message.isEmpty {
                ScrollView {
                    Text(editor.message).font(.callout).foregroundStyle(editor.failed ? Color.red : Color.green)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 90).accessibilityLabel("连接状态：\(editor.message)")
            }
            HStack {
                Button("测试连接", action: editor.test)
                    .disabled(editor.testing || editor.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if editor.testing { ProgressView().controlSize(.small) }
                Spacer()
                Button("取消", action: close)
                Button("保存") {
                    if editor.save() { close() }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: .command)
            }
        }.padding(24).frame(width: 450)
    }
}
