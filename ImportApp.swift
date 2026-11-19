import SwiftUI
import UIKit
import AVFoundation
import ImageIO
import CryptoKit
import Photos
import UniformTypeIdentifiers

@main
struct ImportApp: App {
    var body: some Scene {
        WindowGroup { ImportView() }
    }
}


enum AppPalette {
    static let background = adaptive(light: 0xF4F7F4, dark: 0x0D1C19)
    static let card = adaptive(light: 0xFFFFFF, dark: 0x172D26)
    static let hero = adaptive(light: 0xE1F2E8, dark: 0x213F33)
    static let accent = adaptive(light: 0x6ADCA0, dark: 0xA6F5C5)
    static let border = adaptive(light: 0xDCE7E0, dark: 0x345346)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
}

struct ImportView: View {
    @State private var reviewingLibrary = false
    @State private var running = false
    @State private var status = "从「文件」批量保存照片和视频到系统相册。"
    @State private var progress = 0.0
    @State private var issues: [String] = []
    @State private var folderStatus = ""

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var measured = false
    @State private var completed = false

    private var mint: Color { AppPalette.accent }
    private let ink = Color(red: 0.05, green: 0.11, blue: 0.10)

    var body: some View {
        ZStack {
            AppPalette.background.ignoresSafeArea()
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
                            Label("导入 App 文件夹中的照片和视频", systemImage: "square.and.arrow.down")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(16)
                                .foregroundStyle(ink)
                                .background(mint, in: RoundedRectangle(cornerRadius: 17))
                        }

                    }
                    .buttonStyle(.plain)
                    .disabled(running)
                    .opacity(running ? 0.5 : 1)
                    Button {
                        reviewingLibrary = true
                    } label: {
                        Label("相册去重", systemImage: "square.on.square")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(15)
                            .background(AppPalette.card, in: RoundedRectangle(cornerRadius: 17))
                    }
                    .buttonStyle(.plain)
                    .disabled(running)
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
        .foregroundStyle(.primary)
        .tint(AppPalette.accent)
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
        .sheet(isPresented: $reviewingLibrary) { LibraryDuplicatesView() }

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
            LinearGradient(colors: [AppPalette.hero, AppPalette.card],
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
            status = "已导入 \(report.saved - report.videos) 张照片、\(report.videos) 个视频，跳过 \(report.skipped) 个重复文件。"
            if report.live > 0 { status += " 含 \(report.live) 张实况照片。" }
            if !issues.isEmpty { status += " 有 \(issues.count) 项需要检查。" }
            if report.saved + report.skipped == 0 && issues.isEmpty {
                status = "这个文件夹没有找到可导入的照片或视频。"
            }
        }
    }
}

enum Importer {
    struct Report: Sendable {
        var saved = 0
        var live = 0
        var videos = 0
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
        let contentIdentifier: String
        let standaloneVideo: Bool
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
                    if let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .movie) {
                        movies.append(url)
                    } else if let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image) {
                        files.append(url)
                    }
                }
            }
            files.sort { $0.path < $1.path }

            // Match original assets by their embedded ID, even when export renamed the files.
            var pairedMovies: [String: URL] = [:]
            var movieIDs: [URL: String] = [:]
            var pairedIDs = Set<String>()
            if !files.isEmpty {
                for movie in movies where movie.pathExtension.lowercased() == "mov" {
                    do {
                        try coordinate(movie) { readable in
                            let metadata = AVURLAsset(url: readable).metadata(forFormat: .quickTimeMetadata)
                            if let id = metadata.first(where: { $0.identifier == .quickTimeMetadataContentIdentifier })?.stringValue,
                               !id.isEmpty {
                                let key = id.lowercased()
                                movieIDs[movie] = key
                                if pairedMovies[key] == nil { pairedMovies[key] = movie }
                            }
                        }
                    } catch {
                        report.issues.append("\(movie.lastPathComponent) · \(error.localizedDescription)")
                    }
                }
            }

            let imageCount = files.count
            let videoFiles = Set(movies)
            files.append(contentsOf: movies.sorted { $0.path < $1.path })

            let imageBatches = stride(from: 0, to: imageCount, by: 16).map { $0..<min($0 + 16, imageCount) }
            let videoBatches = (imageCount..<files.count).map { $0..<($0 + 1) }
            for range in imageBatches + videoBatches {
                var batch: [StagedPhoto] = []
                var pending = Set<String>()
                var duplicates: [(source: URL, identifier: String)] = []
                let previousRecordCount = imported.count
                for source in files[range] {
                    let standaloneVideo = videoFiles.contains(source)
                    if let id = movieIDs[source], pairedIDs.contains(id) { continue }
                    do {
                        var still: StagedResource?
                        var movie: URL?
                        try coordinate(source) { readable in
                            let values = try readable.resourceValues(forKeys: keys)
                            guard values.isRegularFile == true else { return }
                            let stillID = fingerprint(source, values)
                            if !standaloneVideo, !pairedMovies.isEmpty,
                               let image = CGImageSourceCreateWithURL(readable as CFURL, nil),
                               let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as NSDictionary?,
                               let maker = properties[kCGImagePropertyMakerAppleDictionary] as? NSDictionary,
                               let id = maker["17"] as? String {
                                let key = id.lowercased()
                                movie = pairedMovies[key]
                                if movie != nil { pairedIDs.insert(key) }
                            }
                            still = try stage(source: source, readable: readable, identifier: stillID, in: staging)
                        }
                        guard let still else { continue }
                        var retained = false
                        var video: StagedResource?
                        defer {
                            if !retained {
                                try? manager.removeItem(at: still.copy)
                                if let video { try? manager.removeItem(at: video.copy) }
                            }
                        }
                        if let movie {
                            try coordinate(movie) { readable in
                                let values = try readable.resourceValues(forKeys: keys)
                                video = try stage(source: movie, readable: readable,
                                                  identifier: fingerprint(movie, values), in: staging)
                            }
                        }
                        let liveIdentifier = video.map { "live\n\(still.identifier)\n\($0.identifier)" }
                        let stillHash = try contentHash(still.copy)
                        let contentIdentifier: String
                        if let video {
                            contentIdentifier = "live-sha256:\(stillHash):\(try contentHash(video.copy))"
                        } else {
                            let prefix = standaloneVideo ? "video-sha256" : "photo-sha256"
                            contentIdentifier = "\(prefix):\(stillHash)"
                        }
                        // Older imports only recorded the file path, size and modification date.
                        if imported.contains(liveIdentifier ?? still.identifier) {
                            imported.insert(contentIdentifier)
                        }
                        if imported.contains(contentIdentifier) {
                            report.skipped += 1
                            continue
                        }
                        guard pending.insert(contentIdentifier).inserted else {
                            duplicates.append((source, contentIdentifier))
                            continue
                        }
                        batch.append(StagedPhoto(still: still, video: video, liveIdentifier: liveIdentifier,
                                                 contentIdentifier: contentIdentifier,
                                                 standaloneVideo: standaloneVideo))
                        retained = true
                    } catch {
                        report.issues.append("\(source.lastPathComponent) · \(error.localizedDescription)")
                    }
                }

                if !batch.isEmpty {
                    let candidates = batch.filter { !imported.contains($0.contentIdentifier) }
                    report.skipped += batch.count - candidates.count
                    var saved: [StagedPhoto] = []
                    do {
                        if !candidates.isEmpty { try save(candidates) }
                        saved = candidates
                    } catch {
                        for photo in candidates {
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
                        imported.insert(photo.contentIdentifier)
                        if photo.standaloneVideo { report.videos += 1 }
                        if photo.liveIdentifier != nil {
                            report.live += 1
                        }
                    }
                    for photo in batch {
                        try? manager.removeItem(at: photo.still.copy)
                        if let video = photo.video { try? manager.removeItem(at: video.copy) }
                    }
                }
                for duplicate in duplicates {
                    if imported.contains(duplicate.identifier) {
                        report.skipped += 1
                    } else {
                        report.issues.append("\(duplicate.source.lastPathComponent) · 相同内容的文件导入失败")
                    }
                }
                if imported.count != previousRecordCount {
                    try JSONEncoder().encode(imported).write(to: journal, options: .atomic)
                }
                await update(range.upperBound, files.count)
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

    private static func contentHash(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let chunk = try file.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            hash.update(data: chunk)
        }
        return Data(hash.finalize()).base64EncodedString()
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
                add(photo.still, as: photo.standaloneVideo ? .video : .photo, to: asset)
                if let video = photo.video {
                    add(video, as: .pairedVideo, to: asset)
                }
            }
        }
    }
}

struct LibraryDuplicatesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var groups: [DuplicateGroup] = []
    @State private var selected = Set<String>()
    @State private var scanID: UUID?
    @State private var status = "在本机查找文件内容完全相同的照片和视频。"
    @State private var thumbnailIDs: [String] = []
    @State private var scanned = 0
    @State private var total = 0
    @State private var scanning = false
    @State private var deleting = false
    @State private var confirming = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 16) {
                        Image(systemName: scanning ? "viewfinder" : "square.on.square")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(AppPalette.accent)
                            .padding(14)
                            .background(AppPalette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
                        Text(scanning ? "正在寻找重复内容" : "让相册轻一点")
                            .font(.system(.title, design: .rounded, weight: .bold))
                        Text(status).font(.subheadline).foregroundStyle(.secondary)
                        if scanning {
                            ScanningThumbnails(identifiers: thumbnailIDs)
                            if total > 0 {
                                ProgressView(value: Double(scanned), total: Double(total))
                                Text("已检查 \(scanned) / \(total)")
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            } else { ProgressView() }
                        }
                        Button {
                            groups = []
                            selected = []
                            thumbnailIDs = []
                            scanned = 0
                            total = 0
                            scanning = true
                            status = "正在准备扫描…"
                            scanID = UUID()
                        } label: {
                            Label(scanning ? "扫描中…" : "扫描相册", systemImage: "viewfinder")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(15)
                                .background(AppPalette.accent, in: RoundedRectangle(cornerRadius: 16))
                                .foregroundStyle(Color(red: 0.04, green: 0.15, blue: 0.11))
                        }
                        .buttonStyle(.plain)
                        .disabled(scanning || deleting)
                    }
                    .padding(22)
                    .background(AppPalette.hero, in: RoundedRectangle(cornerRadius: 26))

                    if !groups.isEmpty {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("\(groups.count) 组重复项目").font(.headline)
                                Text("已选 \(selected.count) 个")
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(selected == suggestedSelection ? "清空勾选" : "一键勾选") {
                                selected = selected == suggestedSelection ? [] : suggestedSelection
                            }
                            .buttonStyle(.bordered)
                            .disabled(scanning || deleting)
                        }
                        Text("每组优先保留收藏的项目，其次保留拍摄最早的一项。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }

                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("重复组 \(index + 1)").font(.headline)
                                Spacer()
                                Text("\(group.photos.count) 个项目")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach(group.photos) { photo in
                                let checked = selected.contains(photo.id)
                                let groupSelection = group.photos.filter { selected.contains($0.id) }.count
                                Button {
                                    if checked { selected.remove(photo.id) }
                                    else { selected.insert(photo.id) }
                                } label: {
                                    PhotoReviewRow(photo: photo, checked: checked)
                                        .padding(12)
                                        .background(checked ? AppPalette.accent.opacity(0.10) : Color.clear,
                                                    in: RoundedRectangle(cornerRadius: 16))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 16)
                                                .strokeBorder(checked ? AppPalette.accent.opacity(0.65) : AppPalette.border)
                                        }
                                }
                                .buttonStyle(.plain)
                                .disabled(deleting || (!checked && groupSelection >= group.photos.count - 1))
                            }
                        }
                        .padding(18)
                        .background(AppPalette.card, in: RoundedRectangle(cornerRadius: 24))
                    }
                    Label("仅扫描本机原件 · 每组至少保留一项", systemImage: "iphone")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: 600)
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .background(AppPalette.background.ignoresSafeArea())
            .tint(AppPalette.accent)
            .navigationTitle("相册去重")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }.disabled(deleting)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !groups.isEmpty {
                    Button(role: .destructive) { confirming = true } label: {
                        Text("删除选中的 \(selected.count) 个").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(selected.isEmpty || deleting)
                    .padding()
                    .background(.regularMaterial)
                }
            }
            .alert("删除选中的 \(selected.count) 个项目？", isPresented: $confirming) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) { Task { await deleteSelected() } }
            } message: {
                Text("系统会再次确认。所选照片和视频会进入「最近删除」。")
            }
        }
        .interactiveDismissDisabled(deleting)
        .task(id: scanID) {
            if scanID != nil { await scan() }
        }
    }

    private var suggestedSelection: Set<String> {
        Set(groups.flatMap { group in
            let keeper = group.photos.first(where: { $0.favorite }) ?? group.photos.first
            return group.photos.filter { $0.id != keeper?.id }.map(\.id)
        })
    }

    @MainActor
    private func scan() async {
        defer { scanning = false }
        let access = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard access == .authorized || access == .limited else {
            status = "请在系统设置里允许访问照片，再重新扫描。"
            return
        }
        let limited = access == .limited
        status = limited ? "正在扫描允许访问的照片…" : "正在检查本机照片…"
        let worker = Task.detached(priority: .userInitiated) {
            await LibraryDuplicateScanner.scan { done, count, identifiers in
                await MainActor.run {
                    thumbnailIDs = identifiers
                    scanned = done
                    total = count
                }
            }
        }
        let result = await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
        guard !Task.isCancelled else { return }
        groups = result.groups
        status = groups.isEmpty ? "未发现完全相同的照片或视频。" : "找到 \(groups.count) 组重复项目。"
        if result.skipped > 0 { status += " 有 \(result.skipped) 个项目无法在本机读取原件，已跳过。" }
        if limited { status += " 当前只扫描了你授权的照片。" }
    }

    @MainActor
    private func deleteSelected() async {
        guard !selected.isEmpty, !deleting else { return }
        deleting = true
        defer { deleting = false }
        let requested = selected
        let affected = groups.filter { group in group.photos.contains { requested.contains($0.id) } }
        let expected = affected.flatMap { $0.photos }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: expected.map(\.id), options: nil)
        var current: [String: PHAsset] = [:]
        assets.enumerateObjects { asset, _, _ in current[asset.localIdentifier] = asset }
        guard expected.allSatisfy({ photo in
            guard let asset = current[photo.id] else { return false }
            return asset.modificationDate == photo.modified
        }) else {
            status = "相册有变化，请重新扫描后再选择。"
            return
        }
        let targets = requested.compactMap { current[$0] }
        guard targets.count == requested.count else { return }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(targets as NSArray)
            }
            groups = groups.compactMap { group in
                let remaining = group.photos.filter { !requested.contains($0.id) }
                return remaining.count > 1 ? DuplicateGroup(id: group.id, photos: remaining) : nil
            }
            selected = []
            status = "已删除 \(targets.count) 个项目。"
        } catch {
            let failure = error as NSError
            if failure.domain == PHPhotosErrorDomain && failure.code == PHPhotosError.Code.userCancelled.rawValue {
                status = "已取消删除。"
            } else {
                status = "未删除所选项目。\(error.localizedDescription)"
            }
        }
    }
}

struct PhotoReviewRow: View {
    let photo: DuplicatePhoto
    let checked: Bool
    @State private var thumbnail: UIImage?
    @State private var request: PHImageRequestID?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(.quaternary)
                if let thumbnail {
                    Image(uiImage: thumbnail).resizable().scaledToFill()
                } else {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                }
            }
            .frame(width: 76, height: 76)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(photo.filename).lineLimit(2)
                if let date = photo.created {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if photo.favorite || photo.live || photo.video {
                    HStack {
                        if photo.favorite { Label("收藏", systemImage: "heart.fill") }
                        if photo.live { Label("实况", systemImage: "livephoto") }
                        if photo.video { Label("视频", systemImage: "video") }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(checked ? Color.accentColor : Color.secondary)
        }
        .contentShape(Rectangle())
        .accessibilityAddTraits(checked ? .isSelected : [])
        .onAppear {
            guard thumbnail == nil, request == nil,
                  let asset = PHAsset.fetchAssets(withLocalIdentifiers: [photo.id], options: nil).firstObject else { return }
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = false
            options.deliveryMode = .opportunistic
            request = PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 180, height: 180),
                                                            contentMode: .aspectFill, options: options) { image, _ in
                guard let image else { return }
                DispatchQueue.main.async { thumbnail = image }
            }
        }
        .onDisappear {
            if let request { PHImageManager.default().cancelImageRequest(request) }
            request = nil
        }
    }
}

struct DuplicatePhoto: Identifiable, Sendable {
    let id: String
    let filename: String
    let created: Date?
    let modified: Date?
    let favorite: Bool
    let live: Bool
    let video: Bool
}

struct DuplicateGroup: Identifiable, Sendable {
    let id: String
    let photos: [DuplicatePhoto]
}

enum LibraryDuplicateScanner {
    struct Result: Sendable {
        let groups: [DuplicateGroup]
        let skipped: Int
    }

    static func scan(update: @Sendable (Int, Int, [String]) async -> Void) async -> Result {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d",
                                        PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
        let assets = PHAsset.fetchAssets(with: options)
        var matches: [String: [DuplicatePhoto]] = [:]
        var skipped = 0
        await update(0, assets.count, [])
        var recent: [String] = []
        for index in 0..<assets.count {
            if Task.isCancelled { break }
            let asset = assets.object(at: index)
            recent.append(asset.localIdentifier)
            if recent.count > 4 { recent.removeFirst() }
            if index < 4 { await update(index, assets.count, recent) }
            let resources = PHAssetResource.assetResources(for: asset)
            let video = asset.mediaType == .video
            let primaryType: PHAssetResourceType = video ? .video : .photo
            if let original = resources.first(where: { $0.type == primaryType }) {
                do {
                    var keys: [String] = []
                    for resource in resources {
                        try Task.checkCancellation()
                        keys.append("\(resource.type.rawValue):\(try await hash(resource))")
                    }
                    let live = asset.mediaSubtypes.contains(.photoLive)
                    let key = "\(asset.mediaType.rawValue):\(live):" + keys.sorted().joined(separator: "|")
                    matches[key, default: []].append(DuplicatePhoto(id: asset.localIdentifier,
                        filename: original.originalFilename, created: asset.creationDate,
                        modified: asset.modificationDate, favorite: asset.isFavorite, live: live, video: video))
                } catch {
                    skipped += 1
                }
            } else {
                skipped += 1
            }
            if (index + 1).isMultiple(of: 16) || index + 1 == assets.count {
                await update(index + 1, assets.count, recent)
            }
        }
        let groups = matches.compactMap { key, photos in
            photos.count > 1 ? DuplicateGroup(id: key, photos: photos) : nil
        }.sorted { ($0.photos.first?.created ?? .distantPast, $0.id) < ($1.photos.first?.created ?? .distantPast, $1.id) }
        return Result(groups: groups, skipped: skipped)
    }

    private final class ResourceDigest: @unchecked Sendable {
        private let lock = NSLock()
        private var state = SHA256()

        func append(_ data: Data) {
            lock.lock()
            defer { lock.unlock() }
            state.update(data: data)
        }

        func finish() -> String {
            lock.lock()
            defer { lock.unlock() }
            return Data(state.finalize()).base64EncodedString()
        }
    }

    private static func hash(_ resource: PHAssetResource) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = false
            let digest = ResourceDigest()
            PHAssetResourceManager.default().requestData(for: resource, options: options,
                                                        dataReceivedHandler: { digest.append($0) }) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: digest.finish()) }
            }
        }
    }
}


@MainActor
final class ThumbnailFlow: ObservableObject {
    struct Flight: Identifiable {
        let id = UUID()
        let image: UIImage
        let started: TimeInterval
    }

    @Published private(set) var flights: [Flight] = []
    @Published private(set) var ready: [UIImage] = []
    private var requested: [String: PHImageRequestID] = [:]
    private var images: [String: UIImage] = [:]
    private var desired: [String] = []
    private var cursor = 0

    func update(_ identifiers: [String]) {
        desired = Array(identifiers.suffix(4))
        let keep = Set(desired)
        for key in Array(requested.keys) where !keep.contains(key) {
            if let request = requested.removeValue(forKey: key) {
                PHImageManager.default().cancelImageRequest(request)
            }
        }
        images = images.filter { keep.contains($0.key) }
        refreshReady()
        for identifier in desired where images[identifier] == nil && requested[identifier] == nil {
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject else { continue }
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = false
            options.deliveryMode = .fastFormat
            let request = PHImageManager.default().requestImage(
                for: asset, targetSize: CGSize(width: 136, height: 136),
                contentMode: .aspectFill, options: options
            ) { [weak self] image, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.desired.contains(identifier), let image else { return }
                    self.images[identifier] = image
                    self.refreshReady()
                }
            }
            requested[identifier] = request
        }
    }

    private func refreshReady() {
        let next = desired.compactMap { images[$0] }
        // Keep the last loaded set until replacements are ready.
        if !next.isEmpty { ready = next }
    }

    func advance() {
        let now = ProcessInfo.processInfo.systemUptime
        flights.removeAll { now - $0.started >= 3.8 }
        guard !ready.isEmpty else { return }
        let image = ready[cursor % ready.count]
        cursor = (cursor + 1) % ready.count
        flights.append(Flight(image: image, started: now))
    }

    func stop() {
        for request in requested.values { PHImageManager.default().cancelImageRequest(request) }
        requested = [:]
        images = [:]
        desired = []
        ready = []
        flights = []
    }
}

struct ScanningThumbnails: View {
    let identifiers: [String]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var flow = ThumbnailFlow()

    var body: some View {
        GeometryReader { geometry in
            if reduceMotion {
                HStack(spacing: 10) {
                    ForEach(Array(flow.ready.enumerated()), id: \.offset) { _, image in
                        thumbnail(image)
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { _ in
                    let now = ProcessInfo.processInfo.systemUptime
                    ZStack(alignment: .leading) {
                        ForEach(flow.flights) { flight in
                            let phase = min(1, max(0, (now - flight.started) / 3.8))
                            thumbnail(flight.image)
                                .opacity(min(1, min(phase / 0.14, (1 - phase) / 0.18)))
                                .offset(x: CGFloat(phase) * (geometry.size.width + 84) - 76)
                        }
                    }
                    .frame(width: geometry.size.width, height: 76, alignment: .leading)
                }
            }
        }
        .frame(height: 76)
        .clipped()
        .accessibilityHidden(true)
        .onAppear { flow.update(identifiers) }
        .onChange(of: identifiers) { flow.update($0) }
        .task(id: reduceMotion) {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                flow.advance()
                do { try await Task.sleep(nanoseconds: 850_000_000) }
                catch { return }
            }
        }
        .onDisappear { flow.stop() }
    }

    private func thumbnail(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: 68, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(AppPalette.border) }
    }
}
