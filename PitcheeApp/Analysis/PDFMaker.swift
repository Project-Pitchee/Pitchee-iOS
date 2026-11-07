import SwiftUI
import UIKit

// Adapted from Kavsoft's PDFHelper.zip:
// PDFHelper/PDFHelper/Helpers/PDFMaker.swift (Balaji Venkatesh).
// Return data for FileDocument so exporting needs no temporary file.
@MainActor
enum PDFMaker {
    static func makeData<PageContent: View>(
        _ pageSize: PageSize = .a4(),
        pageCount: Int,
        format: UIGraphicsPDFRendererFormat = UIGraphicsPDFRendererFormat(),
        @ViewBuilder pageContent: (_ pageIndex: Int) -> PageContent
    ) throws -> Data {
        guard pageCount > 0 else { throw RenderingError.noPages }
        let size = pageSize.size
        guard size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else {
            throw RenderingError.invalidPageSize
        }

        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(origin: .zero, size: size),
            format: format
        )
        var failedPage: Int?
        let data = renderer.pdfData { context in
            for index in 0..<pageCount {
                let didRender = autoreleasepool {
                    context.beginPage()
                    let swiftUIRenderer = ImageRenderer(
                        content: pageContent(index)
                            .frame(width: size.width, height: size.height)
                    )
                    swiftUIRenderer.proposedSize = ProposedViewSize(size)

                    // ImageRenderer draws in Quartz coordinates. UIKit's PDF
                    // context needs its vertical axis flipped for each page.
                    let cgContext = context.cgContext
                    cgContext.saveGState()
                    defer { cgContext.restoreGState() }
                    cgContext.translateBy(x: 0, y: size.height)
                    cgContext.scaleBy(x: 1, y: -1)

                    var didRender = false
                    swiftUIRenderer.render { _, render in
                        render(cgContext)
                        didRender = true
                    }
                    return didRender
                }
                guard didRender else {
                    failedPage = index
                    return
                }
            }
        }
        if let failedPage { throw RenderingError.pageRenderingFailed(failedPage) }
        return data
    }

    nonisolated struct PageSize: Sendable {
        let size: CGSize

        init(width: CGFloat, height: CGFloat) {
            size = CGSize(width: width, height: height)
        }

        static func a4() -> Self { .init(width: 595.28, height: 841.89) }
        static func usLetter() -> Self { .init(width: 612, height: 792) }
    }

    enum RenderingError: Error {
        case noPages
        case invalidPageSize
        case pageRenderingFailed(Int)
    }
}
