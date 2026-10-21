import AppKit

/// Sample the actual compositing result against independently decoded PNG edges.
enum CrownSelfTests {
    static func run(_ expect: (Bool, String) -> Void) {
        guard let url = PetAssets.resourceURL(named: "iron-bowl.png"),
              let image = NSBitmapImageRep(data: try! Data(contentsOf: url)) else {
            expect(false, "pot source loads for rim regression"); return
        }
        let sourceW = image.pixelsWide, sourceH = image.pixelsHigh
        var lower: [(CGFloat, CGFloat)] = []
        for fraction in [0.2, 0.5, 0.8] {
            let x = Int(Double(sourceW)*fraction)
            if let y = stride(from: sourceH-1, through: 0, by: -1).first(where: {
                (image.colorAt(x:x,y:$0)?.alphaComponent ?? 0) >= 224.0/255
            }) {
                lower.append(((CGFloat(x)+0.5)/CGFloat(sourceW)-0.5,
                              (CGFloat(sourceH-y)-0.5)/CGFloat(sourceH)-0.5))
            }
        }
        expect(lower.count == 3 && Set(lower.map { Int($0.1*1000) }).count > 1,
               "real rim has a curved lower boundary, not a rectangular crop")
        for index in 0..<4 { for mirror in [false,true] { autoreleasepool {
            var state = PetState(); state.sizeIndex = index; state.mirrored = mirror; state.soundOn = false
            let c = PetController(state:state,visible:false)
            let v = PetView(model:c.model); c.view=v; v.controller=c; c.props.controller=c
            v.frame.size = PetLayout.windowSize(side:c.side); v.mirrored=mirror
            c.props.headRim = {CGPoint(x:500,y:500)}
            c.props.spawnIronAboveHead()
            let pot=c.props.props[0]; c.props.attachPot(pot,slot:0)
            let rect=PetLayout.spriteRect(in:v.bounds)
            let centre=CGPoint(x:rect.minX+rect.width*(mirror ? 1-PetPropRules.headXFraction : PetPropRules.headXFraction),
                               y:rect.maxY-rect.height*PetPropRules.headRimFraction+pot.artSize.height/2)
            let theta=(mirror ? 1.0 : -1.0)*PetPropRules.ironTiltDeg * .pi/180
            func transformed(_ x:CGFloat,_ y:CGFloat)->CGPoint {
                CGPoint(x:centre.x+x*cos(theta)-y*sin(theta),y:centre.y+x*sin(theta)+y*cos(theta))
            }
            let scale:CGFloat=4, w=Int(ceil(v.bounds.width*scale)), h=Int(ceil(v.bounds.height*scale))
            func render()->[UInt8] {
                var bytes=[UInt8](repeating:0,count:w*h*4)
                bytes.withUnsafeMutableBytes { data in
                    let ctx=CGContext(data:data.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,
                                      space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
                    ctx.scaleBy(x:scale,y:scale)
                    ctx.setFillColor(NSColor.white.cgColor); ctx.fill(v.bounds)
                    c.props.maskCrown(ctx,in:v)
                }
                return bytes
            }
            func alpha(_ bytes:[UInt8],_ p:CGPoint)->UInt8 {
                let x=Int(p.x*scale), y=h-1-Int(p.y*scale)
                guard x>=0,x<w,y>=0,y<h else {return 0}
                return bytes[(y*w+x)*4+3]
            }
            let full=render()
            let underneath=lower.allSatisfy { x,y in
                alpha(full,transformed(x*pot.artSize.width,y*pot.artSize.height-1.5)) == 255
            }
            expect(underneath,"size \(index) mirror \(mirror): hair below curved lip stays opaque without a gap")
            expect([-1.0,1.0].allSatisfy { direction in
                alpha(full,transformed(direction*(pot.artSize.width/2+2),pot.artSize.height)) == 255
            },"side hair outside the pot survives crown masking")
            let crown=transformed(0,pot.artSize.height)
            expect(alpha(full,crown)==0,"crown hidden above solid pot rim")
            pot.headFadeT=PetPropRules.potFade/2
            let half=alpha(render(),crown)
            expect(half>=126 && half<=129,"half-faded pot restores half of crown alpha")
            pot.headFadeT=PetPropRules.potFade
            expect(alpha(render(),crown)==255,"fully removed pot restores crown without a sudden pop")
            c.props.removeAll()
        } } }
    }
}
