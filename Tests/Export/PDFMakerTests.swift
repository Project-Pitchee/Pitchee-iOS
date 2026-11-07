import PDFKit
import SwiftUI
import UIKit

// A small simulator app exercises the production renderer in an active UIKit
// application. Run it with Scripts/test-pdf-export.sh.
@main
enum PDFMakerTestApplication {
    @MainActor
    static func main() {
        UIApplicationMain(
            CommandLine.argc,
            CommandLine.unsafeArgv,
            nil,
            NSStringFromClass(PDFMakerTestDelegate.self)
        )
    }
}

@MainActor
final class PDFMakerTestDelegate: UIResponder, UIApplicationDelegate { }

@MainActor
@objc(PDFMakerTestSceneDelegate)
final class PDFMakerTestSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var didRun = false

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let controller = UIViewController()
        controller.view.backgroundColor = .white
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        guard !didRun else { return }
        didRun = true
        DispatchQueue.main.async {
            let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            var tests = PDFMakerChecks()
            do {
                try tests.run(in: directory)
            } catch {
                tests.failures.append("Unexpected error: \(error)")
            }
            let report: [String: Any] = [
                "passed": tests.failures.isEmpty,
                "checks": tests.count,
                "failures": tests.failures
            ]
            do {
                let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: directory.appendingPathComponent("results.json"), options: .atomic)
            } catch {
                print("Unable to write PDF test results: \(error)")
            }
        }
    }
}

@MainActor
private struct PDFMakerChecks {
    var count = 0
    var failures: [String] = []

    mutating func check(_ condition: Bool, _ message: String) {
        count += 1
        if !condition { failures.append(message) }
    }

    mutating func run(in directory: URL) throws {
        let a4 = CGSize(width: 595.28, height: 841.89)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: "Pitchee PDF renderer checks"]
        let data = try PDFMaker.makeData(pageCount: 3, format: format) { index in
            PDFTestPage(number: index + 1, size: a4)
        }
        try data.write(to: directory.appendingPathComponent("multipage-a4.pdf"))
        guard let document = PDFDocument(data: data) else {
            check(false, "The generated data must decode as a PDF")
            return
        }
        check(document.pageCount == 3, "The PDF must contain all three pages")
        check(
            document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String == "Pitchee PDF renderer checks",
            "The PDF must retain the supplied document metadata"
        )

        var firstHeaderBounds: CGRect?
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else {
                check(false, "Page \(index + 1) must be readable")
                continue
            }
            checkSize(page, expected: a4, label: "A4 page \(index + 1)")
            let contents = page.string ?? ""
            let header = "Header page \(index + 1)"
            let footer = "Footer page \(index + 1)"
            check(contents.contains(header), "Page \(index + 1) must retain selectable header text")
            check(contents.contains(footer), "Page \(index + 1) must retain selectable footer text")
            for other in 1...3 where other != index + 1 {
                check(!contents.contains("Header page \(other)"), "Page contents must not leak between pages")
            }

            if let headerBounds = bounds(of: header, in: page),
               let footerBounds = bounds(of: footer, in: page) {
                // PDFKit reports text bounds in PDF coordinates, whose origin
                // is at the bottom left. These assertions catch upside-down
                // rendering without duplicating the renderer's transforms.
                check(headerBounds.minY > a4.height * 0.85, "Headers must appear at the top of each PDF page")
                check(footerBounds.maxY < a4.height * 0.15, "Footers must appear at the bottom of each PDF page")
                check(headerBounds.minX > 15 && headerBounds.minX < 40, "Headers must keep their left margin")
                if let firstHeaderBounds {
                    check(
                        abs(headerBounds.minY - firstHeaderBounds.minY) < 0.5
                            && abs(headerBounds.minX - firstHeaderBounds.minX) < 0.5,
                        "Page \(index + 1) must not accumulate coordinate transforms"
                    )
                } else {
                    firstHeaderBounds = headerBounds
                }
            } else {
                check(false, "Page \(index + 1) must expose text selection bounds")
            }

            let thumbnail = page.thumbnail(of: a4, for: .mediaBox)
            if index == 0, let png = thumbnail.pngData() {
                try png.write(to: directory.appendingPathComponent("first-page.png"))
            }
            let red = sample(thumbnail, x: 40 / a4.width, y: 80 / a4.height)
            let blue = sample(thumbnail, x: (a4.width - 40) / a4.width, y: (a4.height - 72) / a4.height)
            check(red.map { $0.0 > 220 && $0.1 < 35 && $0.2 < 35 } ?? false,
                  "Page \(index + 1) must place its red graphic at the upper left")
            check(blue.map { $0.0 < 35 && $0.1 < 35 && $0.2 > 220 } ?? false,
                  "Page \(index + 1) must place its blue graphic at the lower right")
        }

        for (label, pageSize, expected) in [
            ("US Letter", PDFMaker.PageSize.usLetter(), CGSize(width: 612, height: 792)),
            ("Custom", PDFMaker.PageSize(width: 320, height: 480), CGSize(width: 320, height: 480))
        ] {
            let output = try PDFMaker.makeData(pageSize, pageCount: 1) { _ in
                PDFTestPage(number: 1, size: expected)
            }
            let pdf = PDFDocument(data: output)
            check(pdf?.pageCount == 1, "\(label) must export exactly one page")
            if let page = pdf?.page(at: 0) {
                checkSize(page, expected: expected, label: label)
                check(page.string?.contains("Header page 1") == true, "\(label) must retain its contents")
            }
        }

        var contentRequests = 0
        for pageCount in [0, -1] {
            do {
                _ = try PDFMaker.makeData(pageCount: pageCount) { _ in
                    contentRequests += 1
                    return Text("Must not render")
                }
                check(false, "Page count \(pageCount) must fail")
            } catch PDFMaker.RenderingError.noPages {
                check(true, "An empty page range is rejected")
            } catch {
                check(false, "Page count \(pageCount) returned the wrong error: \(error)")
            }
        }
        for size in [
            CGSize(width: 0, height: 100), CGSize(width: -1, height: 100),
            CGSize(width: CGFloat.nan, height: 100), CGSize(width: CGFloat.infinity, height: 100),
            CGSize(width: 100, height: 0), CGSize(width: 100, height: -1),
            CGSize(width: 100, height: CGFloat.nan), CGSize(width: 100, height: CGFloat.infinity)
        ] {
            do {
                _ = try PDFMaker.makeData(.init(width: size.width, height: size.height), pageCount: 1) { _ in
                    contentRequests += 1
                    return Text("Must not render")
                }
                check(false, "Invalid page size \(size) must fail")
            } catch PDFMaker.RenderingError.invalidPageSize {
                check(true, "An invalid page size is rejected")
            } catch {
                check(false, "Invalid page size \(size) returned the wrong error: \(error)")
            }
        }
        check(contentRequests == 0, "Invalid input must fail before requesting any page content")
    }

    private mutating func checkSize(_ page: PDFPage, expected: CGSize, label: String) {
        let bounds = page.bounds(for: .mediaBox)
        check(abs(bounds.width - expected.width) < 0.02 && abs(bounds.height - expected.height) < 0.02,
              "\(label) must preserve its requested physical paper size")
    }

    private func bounds(of text: String, in page: PDFPage) -> CGRect? {
        let range = ((page.string ?? "") as NSString).range(of: text)
        guard range.location != NSNotFound else { return nil }
        return page.selection(for: range)?.bounds(for: page)
    }

    // PDFKit creates the correctly oriented thumbnail. Cropping a single
    // source pixel avoids imposing our own PDF coordinate transform.
    private func sample(_ image: UIImage, x: CGFloat, y: CGFloat) -> (UInt8, UInt8, UInt8)? {
        guard let source = image.cgImage,
              let pixel = source.cropping(to: CGRect(
                x: floor(x * CGFloat(source.width)), y: floor(y * CGFloat(source.height)), width: 1, height: 1
              )) else { return nil }
        var rgba = [UInt8](repeating: 0, count: 4)
        let drawn = rgba.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return false }
            context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        return drawn ? (rgba[0], rgba[1], rgba[2]) : nil
    }
}

private struct PDFTestPage: View {
    let number: Int
    let size: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.white
            Text("Header page \(number)")
                .offset(x: 24, y: 24)
            Rectangle().fill(Color(red: 1, green: 0, blue: 0))
                .frame(width: 32, height: 32)
                .offset(x: 24, y: 64)
            Rectangle().fill(Color(red: 0, green: 0, blue: 1))
                .frame(width: 32, height: 32)
                .offset(x: size.width - 56, y: size.height - 88)
            Text("Footer page \(number)")
                .offset(x: 24, y: size.height - 48)
        }
        .font(.system(size: 18))
        .foregroundStyle(.black)
        .environment(\.colorScheme, .light)
        .environment(\.dynamicTypeSize, .medium)
    }
}
