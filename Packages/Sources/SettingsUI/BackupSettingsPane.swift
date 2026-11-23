import AppServices
import DesignSystem
import SwiftUI
import TallyCore
import UniformTypeIdentifiers

struct BackupSettingsPane: View {
    @Environment(AppSettings.self) private var settings
    @Environment(BudgetStore.self) private var store

    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var exportDocument: BackupJSONDocument?
    @State private var statusMessage: String?
    @State private var confirmingReset = false

    var body: some View {
        let lang = settings.language

        Form {
            Section {
                Button {
                    if let data = try? store.exportBackup(currency: settings.currency) {
                        exportDocument = BackupJSONDocument(data: data)
                        showingExporter = true
                    }
                } label: {
                    Label(L10n.text(lang, en: "Export Tally JSON backup", vi: "Xuất file sao lưu JSON"), systemImage: "square.and.arrow.up")
                }

                Button {
                    showingImporter = true
                } label: {
                    Label(L10n.text(lang, en: "Import JSON backup (iOS or Web)", vi: "Nhập file sao lưu JSON (iOS hoặc Web)"), systemImage: "square.and.arrow.down")
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.appCaption)
                        .foregroundStyle(Color.positive)
                }
            } header: {
                formSectionHeader(L10n.text(lang, en: "Backup & Portability", vi: "Sao lưu & Chuyển đổi"))
            } footer: {
                formSectionFooter(L10n.text(
                    lang,
                    en: "100% compatible with the Tally web app's JSON backup format.",
                    vi: "Tương thích hoàn toàn với file sao lưu JSON của bản Tally web."
                ))
            }

            Section {
                Button {
                    store.loadSampleData(settings: settings)
                    statusMessage = L10n.text(lang, en: "Sample data loaded.", vi: "Đã tải dữ liệu mẫu.")
                } label: {
                    Label(L10n.text(lang, en: "Load sample household data", vi: "Tải dữ liệu mẫu gia đình"), systemImage: "sparkles.rectangle.stack")
                }

                Button(role: .destructive) {
                    confirmingReset = true
                } label: {
                    Label(L10n.text(lang, en: "Clear all transactions & budgets", vi: "Xoá toàn bộ giao dịch & ngân sách"), systemImage: "trash")
                }
            } header: {
                formSectionHeader(L10n.text(lang, en: "Data management", vi: "Quản lý dữ liệu"))
            }
        }
        .scrollContentBackground(.hidden)
        .pageBackground()
        .navigationTitle(L10n.text(lang, en: "Backup & Data", vi: "Sao lưu & Dữ liệu"))
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "tally-backup-\(DateKey.dayKey(from: Date()))"
        ) { result in
            if case .success = result {
                statusMessage = L10n.text(lang, en: "Backup exported.", vi: "Đã xuất file sao lưu.")
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) {
                    do {
                        try store.importBackup(data, settings: settings)
                        statusMessage = L10n.text(lang, en: "Backup imported successfully.", vi: "Nhập dữ liệu thành công.")
                    } catch {
                        statusMessage = error.localizedDescription
                    }
                }
            case .failure(let error):
                statusMessage = error.localizedDescription
            }
        }
        .confirmationDialog(
            L10n.text(lang, en: "Clear all budget data?", vi: "Xoá toàn bộ dữ liệu ngân sách?"),
            isPresented: $confirmingReset,
            titleVisibility: .visible
        ) {
            Button(L10n.text(lang, en: "Delete all", vi: "Xoá tất cả"), role: .destructive) {
                store.resetAllLocalData()
            }
        }
    }
}

private struct BackupJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
