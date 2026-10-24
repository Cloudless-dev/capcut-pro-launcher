import AppKit
import SwiftUI

/// One document and one viewport. AppKit scrolls the layer-backed clip view;
/// the SwiftUI document is measured only for its content and viewport width.
struct PageScrollView<Content:View>: NSViewRepresentable {
    let page: String
    let content: Content
    init(page:String,@ViewBuilder content:()->Content) { self.page = page; self.content = content() }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context:Context) -> NSScrollView {
        let scroll = ViewportScrollView(frame:NSRect(x:0,y:0,width:790,height:550))
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true; scroll.scrollerStyle = .overlay
        scroll.automaticallyAdjustsContentInsets = false
        scroll.verticalScrollElasticity = .none; scroll.horizontalScrollElasticity = .none
        scroll.contentView.wantsLayer = true
        let host = NSHostingView(rootView:Document(content:content,width:790))
        host.isFlipped = true; host.sizingOptions = [.intrinsicContentSize]
        host.translatesAutoresizingMaskIntoConstraints = false
        host.frame = NSRect(x:0,y:0,width:790,height:1)
        scroll.documentView = host
        host.widthAnchor.constraint(equalTo:scroll.contentView.widthAnchor).isActive = true
        scroll.viewportChanged = { [weak host] width in
            guard let host else { return }
            host.rootView = Document(content:host.rootView.content,width:width)
        }
        context.coordinator.page = page
        return scroll
    }
    func updateNSView(_ scroll:NSScrollView,context:Context) {
        guard let host = scroll.documentView as? NSHostingView<Document> else { return }
        host.rootView = Document(content:content,width:max(1,scroll.contentView.bounds.width))
        if context.coordinator.page != page {
            context.coordinator.page = page
            DispatchQueue.main.async { [weak scroll] in
                guard let scroll else { return }
                scroll.layoutSubtreeIfNeeded()
                scroll.contentView.scroll(to:.zero)
                scroll.reflectScrolledClipView(scroll.contentView)
            }
        }
    }
    func sizeThatFits(_ proposal:ProposedViewSize,nsView:NSScrollView,context:Context) -> CGSize? {
        let width = proposal.width.flatMap { $0.isFinite ? max(1,$0) : nil } ?? 790
        let height = proposal.height.flatMap { $0.isFinite ? max(1,$0) : nil } ?? 550
        return CGSize(width:width,height:height)
    }
    final class Coordinator { var page = "" }
    struct Document:View {
        @ObservedObject private var interface = InterfacePreferences.shared
        let content:Content
        let width:CGFloat
        var body:some View { content.veilContext().frame(width:width).fixedSize(horizontal:false,vertical:true) }
    }
}

private final class ViewportScrollView:NSScrollView {
    var viewportChanged:((CGFloat)->Void)?
    private var measuredWidth:CGFloat = 0
    override func layout() {
        super.layout()
        let width = contentView.bounds.width
        if width > 1, abs(width-measuredWidth) > 0.5 {
            measuredWidth = width
            viewportChanged?(width)
        }
    }
}
