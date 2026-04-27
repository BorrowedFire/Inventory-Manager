import Foundation
import PDFKit

final class PDFImportService: @unchecked Sendable {
    func parse(urls: [URL]) -> [ParsedImportItem] {
        urls.flatMap { parse(url: $0) }
    }

    private func parse(url: URL) -> [ParsedImportItem] {
        guard let document = PDFDocument(url: url) else { return [fallbackItem(for: url)] }

        let text = (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")
        let normalizedText = normalize(text)
        let poNumber = detectPONumber(from: normalizedText)
        let purchaseDate = detectPurchaseDate(from: normalizedText)
        let vendor = detectVendor(from: normalizedText, fallback: url.deletingPathExtension().lastPathComponent)
        let budgetType = detectBudgetType(from: url)

        let parsedLines = parseVendorSpecificLayouts(
            text: normalizedText,
            sourceFile: url.lastPathComponent,
            poNumber: poNumber,
            purchaseDate: purchaseDate,
            vendor: vendor,
            budgetType: budgetType
        )

        if !parsedLines.isEmpty {
            return parsedLines
        }

        let genericLines = normalizedText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .compactMap { parseGenericLine($0, sourceFile: url.lastPathComponent, poNumber: poNumber, purchaseDate: purchaseDate, vendor: vendor, budgetType: budgetType) }

        return genericLines.isEmpty ? [fallbackItem(for: url, poNumber: poNumber, purchaseDate: purchaseDate, vendor: vendor, budgetType: budgetType)] : genericLines
    }

    private func parseVendorSpecificLayouts(text: String, sourceFile: String, poNumber: String, purchaseDate: String, vendor: String, budgetType: String) -> [ParsedImportItem] {
        if isGenericPurchaseOrder(text) {
            return parseGenericPurchaseOrder(text: text, sourceFile: sourceFile, poNumber: poNumber, purchaseDate: purchaseDate, vendor: vendor, budgetType: budgetType)
        }

        return []
    }

    private func parseGenericPurchaseOrder(text: String, sourceFile: String, poNumber: String, purchaseDate: String, vendor: String, budgetType: String) -> [ParsedImportItem] {
        let pattern = #"(?ms)^\s*\d+\s*-\s*\d+\s+([A-Z0-9][A-Z0-9/\-\.]+)\s+(.+?)\s+[A-Z][A-Z ]+\s+(\d+(?:\.\d+)?)\s+EA\s+([\d,]+\.\d{2})\s+([\d,]+\.\d{2})\s+Requisition:"#
        return matches(in: text, pattern: pattern).compactMap { match in
            let description = cleanDescription(
                match[2].replacingOccurrences(of: #"Item Total\s+[\d,]+\.\d{2}"#, with: "", options: .regularExpression)
            )
            let quantity = Int(Double(match[3]) ?? 1)
            let partNumber = match[1]
            let unitCost = parseCurrency(match[4])
            return makeItem(
                sourceFile: sourceFile,
                itemType: guessItemType(from: description),
                description: description,
                manufacturer: detectManufacturer(from: description, vendor: vendor),
                partNumber: partNumber,
                purchaseDate: purchaseDate,
                vendor: vendor,
                unitCost: unitCost,
                quantity: quantity,
                poNumber: poNumber,
                budgetType: budgetType
            )
        }
    }

    private func parseGenericLine(_ line: String, sourceFile: String, poNumber: String, purchaseDate: String, vendor: String, budgetType: String) -> ParsedImportItem? {
        let pattern = #"([A-Z0-9][A-Z0-9\-\/\.#]{2,})\s+(.+?)\s+(\d{1,4})\s+\$?([\d,]+\.\d{2})"#
        guard let match = firstMatchGroups(in: line, pattern: pattern), match.count == 5 else { return nil }

        let partNumber = match[1]
        let description = cleanDescription(match[2])
        let quantity = Int(match[3]) ?? 1
        let unitCost = parseCurrency(match[4])
        let manufacturer = detectManufacturer(from: description, vendor: vendor)

        return makeItem(
            sourceFile: sourceFile,
            itemType: guessItemType(from: description),
            description: description,
            manufacturer: manufacturer,
            partNumber: partNumber,
            purchaseDate: purchaseDate,
            vendor: vendor,
            unitCost: unitCost,
            quantity: quantity,
            poNumber: poNumber,
            budgetType: budgetType
        )
    }

    private func makeItem(sourceFile: String, itemType: String, description: String, manufacturer: String, partNumber: String, purchaseDate: String, vendor: String, unitCost: Double, quantity: Int, poNumber: String, budgetType: String) -> ParsedImportItem {
        ParsedImportItem(
            sourceFile: sourceFile,
            itemType: itemType,
            description: description,
            manufacturer: manufacturer,
            partNumber: partNumber,
            purchaseDate: purchaseDate,
            vendor: vendor,
            unitCost: unitCost,
            quantity: quantity,
            qtyReceived: poNumber.isEmpty ? 0 : quantity,
            poNumber: poNumber,
            notes: "Imported from \(sourceFile)",
            budgetType: budgetType
        )
    }

    private func fallbackItem(for url: URL, poNumber: String = "", purchaseDate: String = "", vendor: String = "", budgetType: String = "Capital") -> ParsedImportItem {
        let baseName = url.deletingPathExtension().lastPathComponent
        return ParsedImportItem(
            sourceFile: url.lastPathComponent,
            itemType: "Peripheral",
            description: baseName.replacingOccurrences(of: "_", with: " "),
            manufacturer: vendor,
            partNumber: "",
            purchaseDate: purchaseDate,
            vendor: vendor,
            unitCost: 0,
            quantity: 1,
            qtyReceived: poNumber.isEmpty ? 0 : 1,
            poNumber: poNumber,
            notes: "Review imported PDF content manually.",
            budgetType: budgetType
        )
    }

    private func detectVendor(from text: String, fallback: String) -> String {
        let known: [String] = []
        let lowered = text.lowercased()
        if let vendor = known.first(where: { lowered.contains($0.lowercased()) }) {
            return vendor
        }
        return fallback
    }

    private func detectManufacturer(from description: String, vendor: String) -> String {
        let known: [String] = []
        if let manufacturer = known.first(where: { description.localizedCaseInsensitiveContains($0) }) {
            return manufacturer
        }
        return vendor
    }

    private func guessItemType(from description: String) -> String {
        let lowered = description.lowercased()
        if lowered.contains("ipad") || lowered.contains("tablet") { return "Tablet" }
        if lowered.contains("iphone") || lowered.contains("phone") { return "Phone" }
        if lowered.contains("monitor") || lowered.contains("display") { return "Monitor" }
        if lowered.contains("laptop") || lowered.contains("macbook") || lowered.contains("thinkpad") || lowered.contains("galaxy book") { return "Laptop" }
        if lowered.contains("keyboard") || lowered.contains("mouse") || lowered.contains("headset") || lowered.contains("airpods") { return "Peripheral" }
        if lowered.contains("mac mini") || lowered.contains("imac") || lowered.contains("desktop") { return "Desktop" }
        if lowered.contains("warranty") || lowered.contains("care plan") { return "Warranty" }
        if lowered.contains("dock") || lowered.contains("adapter") || lowered.contains("cable") || lowered.contains("charger") { return "Peripheral" }
        return "Accessory"
    }

    private func detectPONumber(from text: String) -> String {
        let patterns = [
            #"PO\s*#\s*(\d{6,12})"#,
            #"Purchase Order PO\s*#\s*(\d{6,12})"#,
            #"PO_(\d{6,12})"#,
            #"Customer PO:\s*(\d{6,12})"#
        ]
        return patterns.compactMap { firstMatch(in: text, pattern: $0) }.first(where: { !$0.isEmpty }) ?? ""
    }

    private func detectPurchaseDate(from text: String) -> String {
        let patterns = [
            #"Date\s+(\d{1,2}/\d{1,2}/\d{2,4})"#,
            #"Quote Date\s+(\d{1,2}/\d{1,2}/\d{2,4})"#,
            #"Purchase Order Date[^\n]*?(\d{2}/\d{2}/\d{4})"#,
            #"(\d{1,2}/\d{1,2}/\d{2,4})"#
        ]
        return patterns.compactMap { firstMatch(in: text, pattern: $0) }.first(where: { !$0.isEmpty }) ?? ""
    }

    private func detectBudgetType(from url: URL) -> String {
        let path = url.path.lowercased()
        return path.contains("/opex/") ? "OpEx" : "Capital"
    }

    private func isGenericPurchaseOrder(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return lowered.contains("purchase order") && (lowered.contains("po #") || lowered.contains("requisition") || lowered.contains("item total"))
    }

    private func between(_ text: String, start: String, end: String) -> String? {
        guard let startRange = text.range(of: start) else { return nil }
        let substring = String(text[startRange.upperBound...])
        guard let endRange = substring.range(of: end) else { return substring }
        return String(substring[..<endRange.lowerBound])
    }

    private func matches(in text: String, pattern: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).map { match in
            (0..<match.numberOfRanges).map { index in
                substring(text, match.range(at: index))
            }
        }
    }

    private func firstMatch(in text: String, pattern: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return "" }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1 else { return "" }
        return substring(text, match.range(at: 1))
    }

    private func firstMatchGroups(in text: String, pattern: String) -> [String]? {
        matches(in: text, pattern: pattern).first
    }

    private func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private func cleanDescription(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseCurrency(_ value: String) -> Double {
        Double(value.replacingOccurrences(of: ",", with: "")) ?? 0
    }

    private func parseCurrencyOptional(_ value: String) -> Double? {
        Double(value.replacingOccurrences(of: ",", with: ""))
    }

    private func substring(_ text: String, _ range: NSRange) -> String {
        guard let swiftRange = Range(range, in: text) else { return "" }
        return String(text[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
