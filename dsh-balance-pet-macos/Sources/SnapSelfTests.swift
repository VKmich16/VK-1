import AppKit

enum SnapSelfTests {
    static func run(_ expect: (Bool, String) -> Void) {
        for character in PetCharacter.allCases { for size in 0..<4 { autoreleasepool {
            var state = PetState(); state.character = character; state.sizeIndex = size
            state.snapOnRelease = false; state.mirrored = true; state.soundOn = false
            let side = PetController.sizePresets[size].side
            let v = PetView(model: PetModel(), character: character)
            v.frame.size = PetLayout.windowSize(side: side); v.mirrored = true
            let w = PetWindow(contentRect: v.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false; w.contentView = v
            let c = PetController(state: state, visible: false, window: w)
            c.view = v; v.controller = c; c.props.controller = c
            w.setFrameOrigin(CGPoint(x: 500, y: 500))
            var actions: [ActionBox] = []
            let menu = c.buildMenu(into: &actions)
            let item = menu.items.first { $0.title == "吸附回左下角" }
            let sent = item.map { NSApp.sendAction($0.action!, to: $0.target, from: $0) } ?? false
            for _ in 0..<6 { c.updateWindowMotion(1.0/30, buttonDown: false) }
            let home = c.homeOrigin()!
            expect(sent && !v.mirrored && hypot(w.frame.minX-home.x,w.frame.minY-home.y)<0.5,
                   "\(character.rawValue) size \(size): actual menu action returns native window to the left")
            let oldFoot = v.solidBounds
            for expression in PetExpression.allCases {
                v.setExpression(expression)
                expect(v.solidBounds == oldFoot, "\(character.rawValue) \(size) \(expression): expressions preserve snap alignment")
            }
            w.setFrameOrigin(CGPoint(x: 500,y: 500))
            for _ in 0..<30 { c.updateWindowMotion(1.0/30, buttonDown: false) }
            expect(w.frame.origin == CGPoint(x: 500,y: 500), "disabled automatic snap preserves manual position")
            let auto = menu.items.first { $0.title == "设置" }!.submenu!.items.first { $0.title.contains("自动回到所选底角") }!
            _ = NSApp.sendAction(auto.action!, to: auto.target, from: auto)
            for _ in 0..<30 { c.updateWindowMotion(1.0/30, buttonDown: true) }
            expect(w.frame.origin == CGPoint(x: 500,y: 500), "held buttons prevent idle snap")
            for _ in 0..<20 { c.updateWindowMotion(1.0/30, buttonDown: false) }
            expect(hypot(w.frame.minX-home.x,w.frame.minY-home.y)<0.5, "idle snap recovers without a character or size change")
            withExtendedLifetime(actions) {}
            c.props.removeAll(); w.contentView = nil; w.close()
        } } }
        for character in PetCharacter.allCases where character != .deepseek {
            var variants = Set<Data>()
            for expression in PetExpression.allCases where expression != .happy {
                if let image = PetAssets.facePatch(for: character, expression: expression), let provider = image.dataProvider?.data {
                    variants.insert(provider as Data)
                    expect(image.width == 330 && image.height == 300, "localized face patch has bounded size")
                } else { expect(false, "face patch loads") }
            }
            expect(variants.count == 3, "\(character.rawValue): three distinct face patches load")
        }
        for side in [CGFloat(110),150,210,280] {
            let system = PropSystem(visible: false)
            let z = PetPropRules.radarFraction * system.artSizes(side: side).rice.width
            for centre in [CGPoint(x: z*3,y:z*2.6), CGPoint(x:z*0.45,y:z*2.6), CGPoint(x:z*5.55,y:z*2.6)] {
                let radar = RadarOverlayView(frame: CGRect(x:0,y:0,width:z*6,height:z*3.0))
                var plate = RadarPlate(); plate.on = true; plate.locked = true; plate.s = z
                plate.distText = "12.3 kpt"; plate.closureText = "-4200 pt/s"; plate.altText = "-1999 pt"
                radar.plates = [(centre,plate)]
                if let bitmap = radar.bitmapImageRepForCachingDisplay(in: radar.bounds) {
                    radar.cacheDisplay(in:radar.bounds,to:bitmap)
                    expect(radar.drawnReadoutRects.count == 5 && radar.drawnReadoutRects.allSatisfy { radar.bounds.contains($0) },
                           "radar readouts remain visible at Dock floor and side edges, size \(side)")
                } else { expect(false,"radar renders") }
            }
        }
        var pat = PatGesture()
        pat.tick(1.0/30, point: .zero, onPet: true, button: true, movingPet: false, enabled: true, hasPot: false, knock: {})
        for i in 0..<29 { pat.tick(1.0/30, point: CGPoint(x: i%2*20,y:0), onPet: true, button: false, movingPet: false, enabled: true, hasPot: false, knock: {}) }
        expect(!pat.active, "button release enforces a one-second head-pat cooldown")
        for i in 0..<25 { pat.tick(1.0/30, point: CGPoint(x:i%2*20,y:0), onPet:true,button:false,movingPet:false,enabled:true,hasPot:false,knock:{}) }
        expect(pat.active, "a new sustained hover stroke works after cooldown")
        pat.tick(0.1,point:.zero,onPet:false,button:false,movingPet:false,enabled:true,hasPot:false,knock:{})
        pat.tick(0.06,point:.zero,onPet:false,button:false,movingPet:false,enabled:true,hasPot:false,knock:{})
        expect(!pat.active, "leaving the pet for 150ms ends the pat")
    }
}
