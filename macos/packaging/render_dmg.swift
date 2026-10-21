import AppKit

// Reproducible vector artwork; Finder supplies the actual draggable icons.
let size = NSSize(width:760,height:300)
func color(_ hex:Int) -> NSColor { NSColor(srgbRed:CGFloat((hex>>16)&255)/255,green:CGFloat((hex>>8)&255)/255,blue:CGFloat(hex&255)/255,alpha:1) }
func text(_ value:String,y:CGFloat,font:CGFloat,weight:NSFont.Weight = .regular,ink:Int = 0x697386) {
    let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
    (value as NSString).draw(in:NSRect(x:24,y:y,width:712,height:font*1.6),withAttributes:[.font:NSFont.systemFont(ofSize:font,weight:weight),.foregroundColor:color(ink),.paragraphStyle:paragraph])
}
func artwork() {
    color(0xf6f7fb).setFill(); NSBezierPath(rect:NSRect(origin:.zero,size:size)).fill()
    text("CapCut Launcher",y:26,font:27,weight:.semibold,ink:0x182237)
    text("Перетащите в «Программы»  /  Drag to Applications",y:68,font:13,ink:0x5f6b80)
    color(0xe8edff).setFill(); NSBezierPath(ovalIn:NSRect(x:254,y:150,width:42,height:42)).fill()
    let arrow=NSBezierPath();arrow.move(to:NSPoint(x:265,y:171));arrow.line(to:NSPoint(x:285,y:171));arrow.move(to:NSPoint(x:278,y:164));arrow.line(to:NSPoint(x:285,y:171));arrow.line(to:NSPoint(x:278,y:178));arrow.lineWidth=2.2;arrow.lineCapStyle = .round;arrow.lineJoinStyle = .round;color(0x5570d6).setStroke();arrow.stroke()
}
let image=NSImage(size:size,flipped:true) { _ in artwork(); return true }
let output=URL(fileURLWithPath:CommandLine.arguments[1]);try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
for scale in [1,2] {
    let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(size.width)*scale,pixelsHigh:Int(size.height)*scale,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState();let context=NSGraphicsContext(bitmapImageRep:rep)!;NSGraphicsContext.current=context
    context.cgContext.scaleBy(x:CGFloat(scale),y:CGFloat(scale));image.draw(in:NSRect(origin:.zero,size:size))
    NSGraphicsContext.restoreGraphicsState()
    let name=scale==1 ? "dmg-background.png" : "dmg-background@2x.png"
    try rep.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(name))
}
