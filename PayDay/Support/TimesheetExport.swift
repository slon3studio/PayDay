import SwiftUI
import UIKit

/// Turns a month's shifts into a file you can send someone — a spreadsheet,
/// or a page to print and sign.
enum TimesheetExport {

    enum Format: String, Identifiable {
        case csv, pdf
        var id: String { rawValue }
    }

    /// A file ready to share. Wrapped so `.sheet(item:)` has something
    /// `Identifiable` to hang off.
    struct File: Identifiable {
        let id = UUID()
        let url: URL
    }

    /// Main actor because rendering the PDF goes through `ImageRenderer`,
    /// which lays out real SwiftUI views.
    @MainActor
    static func make(_ format: Format, job: Job, month: Date, shifts: [Shift]) -> File? {
        let url: URL?
        switch format {
        case .csv: url = csv(job: job, month: month, shifts: shifts)
        case .pdf: url = pdf(job: job, month: month, shifts: shifts)
        }
        return url.map(File.init)
    }

    // MARK: - Naming

    /// "PayDay-Macek-2026-10". Anything a file system might object to is
    /// replaced, since job names are free text and often carry emoji.
    private static func baseName(job: Job, month: Date) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let name = job.displayName.unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
            .reduce(into: "") { $0.append($1) }
            .split(separator: "-").joined(separator: "-")
        return "PayDay-\(name.isEmpty ? "Job" : name)-\(isoMonth.string(from: month))"
    }

    private static let isoMonth: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM"
        return f
    }()

    private static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    // MARK: - CSV

    /// Plain RFC-4180 CSV: comma separated, full stop for decimals, ISO dates.
    /// Deliberately not localised — this file's job is to open anywhere.
    private static func csv(job: Job, month: Date, shifts: [Shift]) -> URL? {
        let currency = AppSettings.currencyCode
        var lines: [String] = []

        lines.append(field("Job") + "," + field("Month") + "," + field("Currency"))
        lines.append(field(job.displayName) + "," + field(isoMonth.string(from: month)) + "," + field(currency))
        lines.append("")
        lines.append(["Date", "From", "To", "Overnight", "Hours", "Rate", "Base pay", "Tips", "Total", "Note"]
            .map(field).joined(separator: ","))

        for shift in shifts {
            lines.append([
                isoDay.string(from: shift.checkIn),
                clock.string(from: shift.checkIn),
                clock.string(from: shift.checkOut),
                shift.isOvernight ? "yes" : "no",
                amount(shift.hours),
                amount(shift.hourlyRate),
                amount(shift.basePay),
                amount(shift.tipsAmount),
                amount(shift.totalPay),
                shift.note,
            ].map(field).joined(separator: ","))
        }

        let hours = shifts.reduce(0) { $0 + $1.hours }
        let base = shifts.reduce(0) { $0 + $1.basePay }
        let tips = shifts.reduce(0) { $0 + $1.tipsAmount }
        lines.append("")
        lines.append(["Total", "", "", "", amount(hours), "", amount(base), amount(tips), amount(base + tips), ""]
            .map(field).joined(separator: ","))

        return write(lines.joined(separator: "\r\n"), to: baseName(job: job, month: month) + ".csv")
    }

    private static func amount(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    /// Quotes a field, and doubles any quote inside it, so a note containing a
    /// comma doesn't shift every column after it.
    private static func field(_ raw: String) -> String {
        "\"" + raw.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func write(_ text: String, to name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        // A leading BOM is what makes Excel open a UTF-8 CSV without mangling
        // accented job names.
        guard var data = "\u{FEFF}".data(using: .utf8),
              let body = text.data(using: .utf8) else { return nil }
        data.append(body)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - PDF

    /// One A4 page, rendered from the same numbers the screen shows. A long
    /// month is scaled down to fit rather than clipped.
    @MainActor
    private static func pdf(job: Job, month: Date, shifts: [Shift]) -> URL? {
        let page = CGSize(width: 595, height: 842)   // A4 at 72 dpi
        let margin: CGFloat = 36
        let contentWidth = page.width - margin * 2

        let renderer = ImageRenderer(
            content: TimesheetPage(job: job, month: month, shifts: shifts)
                .frame(width: contentWidth))
        renderer.proposedSize = ProposedViewSize(width: contentWidth, height: nil)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(baseName(job: job, month: month) + ".pdf")
        var box = CGRect(origin: .zero, size: page)

        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil)
        else { return nil }

        var ok = false
        renderer.render { size, draw in
            context.beginPDFPage(nil)
            let scale = min(1, (page.height - margin * 2) / max(size.height, 1))
            context.translateBy(x: margin, y: page.height - margin - size.height * scale)
            context.scaleBy(x: scale, y: scale)
            draw(context)
            context.endPDFPage()
            ok = true
        }
        context.closePDF()
        return ok ? url : nil
    }
}

// MARK: - The printed page

/// The timesheet laid out for paper: always light, with its own colours rather
/// than the app's, so it doesn't come out white-on-white from a dark phone.
private struct TimesheetPage: View {
    let job: Job
    let month: Date
    let shifts: [Shift]

    private var hours: Double { shifts.reduce(0) { $0 + $1.hours } }
    private var base: Double { shifts.reduce(0) { $0 + $1.basePay } }
    private var tips: Double { shifts.reduce(0) { $0 + $1.tipsAmount } }
    private var days: Int { Set(shifts.map(\.day)).count }

    private let ink = Color(white: 0.08)
    private let faint = Color(white: 0.45)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(job.displayName)
                    .font(.system(size: 22, weight: .bold))
                Text(Fmt.monthTitle(month))
                    .font(.system(size: 14))
                    .foregroundStyle(faint)
            }

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 7) {
                GridRow {
                    Text("Date")
                    Text("From")
                    Text("To")
                    Text("Hours").gridColumnAlignment(.trailing)
                    Text("Pay").gridColumnAlignment(.trailing)
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(faint)

                Divider().gridCellColumns(5)

                ForEach(shifts) { shift in
                    GridRow {
                        Text(Fmt.dayInMonth(shift.checkIn))
                        Text(shift.checkIn.formatted(date: .omitted, time: .shortened))
                        Text(shift.checkOut.formatted(date: .omitted, time: .shortened)
                             + (shift.isOvernight ? " +1" : ""))
                        Text(Fmt.hours(shift.hours))
                        Text(Fmt.money(shift.totalPay))
                    }
                    .font(.system(size: 11))
                }

                Divider().gridCellColumns(5)

                GridRow {
                    Text("Total").gridCellColumns(3)
                    Text(Fmt.hours(hours))
                    Text(Fmt.money(base + tips))
                }
                .font(.system(size: 12, weight: .bold))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("\(Fmt.count(days, "day")) · \(Fmt.count(shifts.count, "shift")) · base \(Fmt.money(base))"
                     + (tips > 0 ? " · tips \(Fmt.money(tips))" : ""))
                Text("Exported from PayDay on \(Date().formatted(date: .long, time: .shortened))")
            }
            .font(.system(size: 9))
            .foregroundStyle(faint)
        }
        .foregroundStyle(ink)
        .monospacedDigit()
        .padding(24)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}

// MARK: - Sharing

/// The system share sheet. `ShareLink` would want the file built before the
/// button is even drawn; this way it's built when you pick a format.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
