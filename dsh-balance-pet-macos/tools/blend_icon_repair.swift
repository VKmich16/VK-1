import AppKit
import CoreGraphics
// Restrict the image_gen repair to the soles and their immediate shadow.
let space=CGColorSpace(name:CGColorSpace.sRGB)!
func rgba(_ path:String)->[UInt8] {
 let image=NSBitmapImageRep(data:try! Data(contentsOf:URL(fileURLWithPath:path)))!.cgImage!
 precondition(image.width==1024 && image.height==1024)
 var data=[UInt8](repeating:0,count:1024*1024*4)
 data.withUnsafeMutableBytes { raw in
  let ctx=CGContext(data:raw.baseAddress,width:1024,height:1024,bitsPerComponent:8,bytesPerRow:4096,space:space,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
  ctx.draw(image,in:CGRect(x:0,y:0,width:1024,height:1024))
 }
 return data
}
var base=rgba(CommandLine.arguments[1]); let edit=rgba(CommandLine.arguments[2])
let before=base
for y in 825...895 { for x in 397...603 {
 let edge=min(Double(x-397)/15,Double(603-x)/15,Double(y-825)/9,Double(895-y)/15)
 let t=min(1,max(0,edge));let blend=t*t*(3-2*t)
 let i=(y*1024+x)*4
 for channel in 0..<3 {base[i+channel]=UInt8((Double(before[i+channel])*(1-blend)+Double(edit[i+channel])*blend).rounded())}
} }
var changed=0
for y in 0..<1024 {for x in 0..<1024 {
 let i=(y*1024+x)*4
 if base[i..<i+4] != before[i..<i+4] {precondition(x>397 && x<603 && y>825 && y<895);changed+=1}
} }
let provider=CGDataProvider(data:Data(base) as CFData)!
let image=CGImage(width:1024,height:1024,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:4096,space:space,bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),provider:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent)!
try NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[3]))
print("Repaired \(changed) pixels within the shoe area; all other rendered pixels identical")
