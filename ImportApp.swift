import SwiftUI
import UIKit
import AVFoundation
import ImageIO
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
    @State private var status = "从「文件」把原始图片批量保存到系统照片。"
    @State private var progress = 0.0
    @State private var issues: [String] = []
    @State private var folderStatus = ""

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var measured = false
    @State private var completed = false

    private let mint = Color(red: 0.65, green: 0.96, blue: 0.77)
    private let ink = Color(red: 0.05, green: 0.11, blue: 0.10)

    var body: some View {
        ZStack {
            ink.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Text("照片批量导入")
                            .font(.headline)
                        Spacer()
                        Text("v" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    hero
                    VStack(alignment: .leading, spacing: 12) {
                        Button {
                            importLocalFolder()
                        } label: {
                            Label("导入 App 文件夹中的照片", systemImage: "square.and.arrow.down")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(16)
                                .foregroundStyle(ink)
                                .background(mint, in: RoundedRectangle(cornerRadius: 17))
                        }
                        Button {
                            picking = true
                        } label: {
                            Label("从「文件」选择其他文件夹", systemImage: "folder")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(15)
                                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 17))
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(running)
                    .opacity(running ? 0.5 : 1)
                    VStack(alignment: .leading, spacing: 8) {
                        Label("照片存放位置", systemImage: "folder.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(mint)
                        Text("文件 → 我的 iPhone → 照片批量导入 → 把照片复制到这里")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if !folderStatus.isEmpty {
                            Text(folderStatus).font(.footnote).foregroundStyle(.orange)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if !issues.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("未导入的项目").font(.headline)
                            ForEach(issues.indices, id: \.self) { index in
                                Text(issues[index]).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(maxWidth: 560)
                .padding(22)
                .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
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
                    folderStatus = ""
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

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(mint.opacity(0.10))
                    .frame(width: 66, height: 66)
                if running && !reduceMotion {
                    TimelineView(.animation) { context in
                        let turn = context.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: 1.4) / 1.4
                        Circle().trim(from: 0, to: 0.24)
                            .stroke(mint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .frame(width: 53, height: 53)
                            .rotationEffect(.degrees(turn * 360))
                    }
                    .accessibilityHidden(true)
                }
                Image(systemName: completed ? "checkmark" : running ? "arrow.down" : "photo.on.rectangle.angled")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(mint)
                    .accessibilityHidden(true)
            }
            .frame(width: 66, height: 66)

            Text(running ? "正在导入" : completed ? "导入完成" : "把照片放回相册")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .accessibilityAddTraits(.isHeader)

            Text(status)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if running || measured {
                if measured {
                    ProgressView(value: progress)
                        .tint(mint)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.28), value: progress)
                        .accessibilityLabel("导入进度")
                } else {
                    ProgressView().tint(mint)
                        .accessibilityLabel("正在扫描照片")
                }
            }
            if running {
                Text("导入期间请保持 App 在前台。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(red: 0.13, green: 0.28, blue: 0.23), Color(red: 0.08, green: 0.18, blue: 0.16)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 29)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 29).strokeBorder(mint.opacity(0.14))
        }
    }

    private func importLocalFolder() {
        do {
            let folder = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: true)
            start(folder, needsScope: false)
        } catch {
            status = error.localizedDescription
        }
    }

    private func start(_ folder: URL, needsScope: Bool) {
        running = true
        issues = []
        progress = 0
        measured = false
        completed = false
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
                        measured = true
                        progress = Double(done) / Double(max(total, 1))
                        status = "已处理 \(done) / \(total)"
                    }
                }
            }.value
            issues = report.issues
            completed = report.saved + report.skipped > 0
            if completed && !reduceMotion {
                UINotificationFeedbackGenerator().notificationOccurred(issues.isEmpty ? .success : .warning)
            }
            status = "已导入 \(report.saved) 张，已跳过 \(report.skipped) 张。"
            if report.live > 0 { status += " 含 \(report.live) 张实况照片。" }
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
        var live = 0
        var skipped = 0
        var issues: [String] = []
    }

    struct StagedResource {
        let source: URL
        let copy: URL
        let identifier: String
    }

    struct StagedPhoto {
        let still: StagedResource
        let video: StagedResource?
        let liveIdentifier: String?
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
            var movies: [URL] = []
            try coordinate(folder) { directory in
                guard let children = manager.enumerator(at: directory, includingPropertiesForKeys: Array(keys),
                                                        options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                                        errorHandler: { url, error in
                    report.issues.append("\(url.lastPathComponent) · \(error.localizedDescription)")
                    return true
                }) else {
                    throw CocoaError(.fileReadUnknown)
                }
                for entry in children {
                    guard let url = entry as? URL else { continue }
                    if url.pathExtension.lowercased() == "mov" {
                        movies.append(url)
                    } else if let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image) {
                        files.append(url)
                    }
                }
            }
            files.sort { $0.path < $1.path }

            // Match original assets by their embedded ID, even when export renamed the files.
            var pairedMovies: [String: URL] = [:]
            if !files.isEmpty {
                for movie in movies.sorted(by: { $0.path < $1.path }) {
                    do {
                        try coordinate(movie) { readable in
                            let metadata = AVURLAsset(url: readable).metadata(forFormat: .quickTimeMetadata)
                            if let id = metadata.first(where: { $0.identifier == .quickTimeMetadataContentIdentifier })?.stringValue,
                               !id.isEmpty, pairedMovies[id.lowercased()] == nil {
                                pairedMovies[id.lowercased()] = movie
                            }
                        }
                    } catch {
                        report.issues.append("\(movie.lastPathComponent) · \(error.localizedDescription)")
                    }
                }
            }

            for offset in stride(from: 0, to: files.count, by: 16) {
                let end = min(offset + 16, files.count)
                var batch: [StagedPhoto] = []
                for source in files[offset..<end] {
                    do {
                        var still: StagedResource?
                        var movie: URL?
                        try coordinate(source) { readable in
                            let values = try readable.resourceValues(forKeys: keys)
                            guard values.isRegularFile == true else { return }
                            let stillID = fingerprint(source, values)
                            if !pairedMovies.isEmpty,
                               let image = CGImageSourceCreateWithURL(readable as CFURL, nil),
                               let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as NSDictionary?,
                               let maker = properties[kCGImagePropertyMakerAppleDictionary] as? NSDictionary,
                               let id = maker["17"] as? String {
                                movie = pairedMovies[id.lowercased()]
                            }
                            if movie == nil && imported.contains(stillID) {
                                report.skipped += 1
                                return
                            }
                            still = try stage(source: source, readable: readable, identifier: stillID, in: staging)
                        }
                        guard let still else { continue }
                        var retained = false
                        defer { if !retained { try? manager.removeItem(at: still.copy) } }
                        var video: StagedResource?
                        if let movie {
                            try coordinate(movie) { readable in
                                let values = try readable.resourceValues(forKeys: keys)
                                video = try stage(source: movie, readable: readable,
                                                  identifier: fingerprint(movie, values), in: staging)
                            }
                        }
                        let liveIdentifier = video.map { "live\n\(still.identifier)\n\($0.identifier)" }
                        if let liveIdentifier, imported.contains(liveIdentifier) {
                            report.skipped += 1
                            if let video { try? manager.removeItem(at: video.copy) }
                            continue
                        }
                        batch.append(StagedPhoto(still: still, video: video, liveIdentifier: liveIdentifier))
                        retained = true
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
                                report.issues.append("\(photo.still.source.lastPathComponent) · \(error.localizedDescription)")
                            }
                        }
                    }
                    report.saved += saved.count
                    for photo in saved {
                        imported.insert(photo.still.identifier)
                        if let liveIdentifier = photo.liveIdentifier {
                            report.live += 1
                            imported.insert(liveIdentifier)
                        }
                    }
                    try JSONEncoder().encode(imported).write(to: journal, options: .atomic)
                    for photo in batch {
                        try? manager.removeItem(at: photo.still.copy)
                        if let video = photo.video { try? manager.removeItem(at: video.copy) }
                    }
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

    private static func fingerprint(_ source: URL, _ values: URLResourceValues) -> String {
        "\(source.path)\n\(values.fileSize ?? 0)\n\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
    }

    private static func stage(source: URL, readable: URL, identifier: String, in directory: URL) throws -> StagedResource {
        let copy = directory.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(source.pathExtension)
        try FileManager.default.copyItem(at: readable, to: copy)
        return StagedResource(source: source, copy: copy, identifier: identifier)
    }

    private static func add(_ resource: StagedResource, as type: PHAssetResourceType, to asset: PHAssetCreationRequest) {
        let options = PHAssetResourceCreationOptions()
        options.originalFilename = resource.source.lastPathComponent
        asset.addResource(with: type, fileURL: resource.copy, options: options)
    }

    private static func save(_ photos: [StagedPhoto]) throws {
        try PHPhotoLibrary.shared().performChangesAndWait {
            for photo in photos {
                let asset = PHAssetCreationRequest.forAsset()
                add(photo.still, as: .photo, to: asset)
                if let video = photo.video {
                    add(video, as: .pairedVideo, to: asset)
                }
            }
        }
    }
}
