import SwiftUI
import UIKit
import Photos
import UniformTypeIdentifiers

@main
struct ImportApp: App {
    var body: some Scene {
        WindowGroup { ImportView() }
    }
}

struct ImportView: View {
    @State private var picking = false
    @State private var running = false
    @State private var status = "请选择存放照片的文件夹。"
    @State private var progress = 0.0
    @State private var issues: [String] = []
    @State private var folderStatus = "正在创建导入目录…"

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("选择文件夹并导入") { picking = true }
                        .disabled(running)
                    Button("导入 App 文件夹中的照片") {
                        do {
                            let folder = try FileManager.default.url(for: .documentDirectory,
                                                                      in: .userDomainMask,
                                                                      appropriateFor: nil, create: true)
                            start(folder, needsScope: false)
                        } catch {
                            status = error.localizedDescription
                        }
                    }
                    .disabled(running)
                    Text(status)
                    Text(folderStatus).font(.footnote)
                    if running || progress > 0 {
                        ProgressView(value: progress)
                    }
                } footer: {
                    Text("会扫描子文件夹。导入时请保持 App 在前台。如果「打开」无响应，可在「文件」中把照片文件夹复制到「我的 iPhone → 照片批量导入」，然后使用第二个按钮。")
                }
                if !issues.isEmpty {
                    Section("未导入的项目") {
                        ForEach(issues.indices, id: \.self) { index in
                            Text(issues[index]).font(.footnote)
                        }
                    }
                }
            }
            .navigationTitle("照片批量导入")
        }
        .onAppear {
            do {
                let documents = try FileManager.default.url(for: .documentDirectory,
                                                             in: .userDomainMask,
                                                             appropriateFor: nil, create: true)
                let inbox = documents.appendingPathComponent("把照片复制到这里", isDirectory: true)
                try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
                let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
                let sharing = Bundle.main.object(forInfoDictionaryKey: "UIFileSharingEnabled") as? Bool == true
                let inPlace = Bundle.main.object(forInfoDictionaryKey: "LSSupportsOpeningDocumentsInPlace") as? Bool == true
                if sharing && inPlace {
                    folderStatus = "v\(version) · 已创建「把照片复制到这里」"
                } else {
                    folderStatus = "v\(version) · 当前安装包缺少「文件」共享设置"
                }
            } catch {
                folderStatus = "创建目录失败：\(error.localizedDescription)"
            }
        }
        .sheet(isPresented: $picking) {
            FolderPicker { folder in
                picking = false
                if let folder { start(folder, needsScope: true) }
            }
            .ignoresSafeArea()
        }
    }

    private func start(_ folder: URL, needsScope: Bool) {
        running = true
        issues = []
        progress = 0
        status = "正在准备导入…"
        Task { @MainActor in
            defer { running = false }
            let permission = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard permission == .authorized || permission == .limited else {
                status = "请在设置中允许此 App 添加照片，然后重新选择文件夹。"
                return
            }
            let report = await Task.detached(priority: .userInitiated) {
                await Importer.run(folder: folder, needsScope: needsScope) { done, total in
                    await MainActor.run {
                        progress = Double(done) / Double(max(total, 1))
                        status = "已处理 \(done) / \(total)"
                    }
                }
            }.value
            issues = report.issues
            status = "已导入 \(report.saved) 张，已跳过 \(report.skipped) 张。"
            if !issues.isEmpty { status += " 有 \(issues.count) 项需要检查。" }
            if report.saved + report.skipped == 0 && issues.isEmpty {
                status = "这个文件夹没有找到可导入的图片。"
            }
        }
    }
}

struct FolderPicker: UIViewControllerRepresentable {
    let finish: (URL?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(finish: finish)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let finish: (URL?) -> Void

        init(finish: @escaping (URL?) -> Void) {
            self.finish = finish
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            finish(urls.first)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            finish(nil)
        }
    }
}

enum Importer {
    struct Report: Sendable {
        var saved = 0
        var skipped = 0
        var issues: [String] = []
    }

    struct StagedPhoto {
        let source: URL
        let copy: URL
        let identifier: String
    }

    static func run(folder: URL, needsScope: Bool, update: @Sendable (Int, Int) async -> Void) async -> Report {
        var report = Report()
        let scoped = needsScope && folder.startAccessingSecurityScopedResource()
        guard !needsScope || scoped else {
            report.issues.append("无法访问所选文件夹。")
            return report
        }
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }

        let manager = FileManager.default
        let staging = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? manager.removeItem(at: staging) }
        do {
            try manager.createDirectory(at: staging, withIntermediateDirectories: true)
            let appData = try manager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                          appropriateFor: nil, create: true)
            let journal = appData.appendingPathComponent("Imported.json")
            var imported = Set<String>()
            if manager.fileExists(atPath: journal.path) {
                imported = try JSONDecoder().decode(Set<String>.self, from: Data(contentsOf: journal))
            }

            let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
            var files: [URL] = []
            try coordinate(folder) { directory in
                guard let children = manager.enumerator(at: directory, includingPropertiesForKeys: Array(keys),
                                                        options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                                        errorHandler: { url, error in
                    report.issues.append("\(url.lastPathComponent) · \(error.localizedDescription)")
                    return true
                }) else {
                    throw CocoaError(.fileReadUnknown)
                }
                files = children.compactMap { entry in
                    guard let url = entry as? URL,
                          let type = UTType(filenameExtension: url.pathExtension),
                          type.conforms(to: .image) else { return nil }
                    return url
                }.sorted { $0.path < $1.path }
            }

            for offset in stride(from: 0, to: files.count, by: 16) {
                let end = min(offset + 16, files.count)
                var batch: [StagedPhoto] = []
                for source in files[offset..<end] {
                    do {
                        try coordinate(source) { readable in
                            let values = try readable.resourceValues(forKeys: keys)
                            guard values.isRegularFile == true else { return }
                            let identifier = "\(source.path)\n\(values.fileSize ?? 0)\n\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
                            if imported.contains(identifier) {
                                report.skipped += 1
                                return
                            }
                            let copy = staging.appendingPathComponent(UUID().uuidString)
                                .appendingPathExtension(source.pathExtension)
                            try manager.copyItem(at: readable, to: copy)
                            batch.append(StagedPhoto(source: source, copy: copy, identifier: identifier))
                        }
                    } catch {
                        report.issues.append("\(source.lastPathComponent) · \(error.localizedDescription)")
                    }
                }

                if !batch.isEmpty {
                    var saved: [StagedPhoto] = []
                    do {
                        try save(batch)
                        saved = batch
                    } catch {
                        for photo in batch {
                            do {
                                try save([photo])
                                saved.append(photo)
                            } catch {
                                report.issues.append("\(photo.source.lastPathComponent) · \(error.localizedDescription)")
                            }
                        }
                    }
                    report.saved += saved.count
                    imported.formUnion(saved.map(\.identifier))
                    try JSONEncoder().encode(imported).write(to: journal, options: .atomic)
                    for photo in batch { try? manager.removeItem(at: photo.copy) }
                }
                await update(end, files.count)
            }
        } catch {
            report.issues.append("导入已停止 · \(error.localizedDescription)")
        }
        return report
    }

    private static func coordinate(_ url: URL, read: (URL) throws -> Void) throws {
        var coordinationError: NSError?
        var readError: Error?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readable in
            do { try read(readable) }
            catch { readError = error }
        }
        if let coordinationError { throw coordinationError }
        if let readError { throw readError }
    }

    private static func save(_ photos: [StagedPhoto]) throws {
        try PHPhotoLibrary.shared().performChangesAndWait {
            for photo in photos {
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = photo.source.lastPathComponent
                PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: photo.copy, options: options)
            }
        }
    }
}
