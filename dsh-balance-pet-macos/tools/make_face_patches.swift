import AppKit
guard CommandLine.arguments.count == 3 else { fatalError("Usage: swift make_face_patches.swift <generation-directory> <Resources-directory>") }
let input = CommandLine.arguments[1]+"/"
let dest = CommandLine.arguments[2]+"/"
let sources = ["gpt-nervous":"e6e1072b-60f0-4897-979c-35224897b758", "gpt-aloof":"0c307eee-cbb3-4c03-ba1d-9b151f352155", "gpt-calm":"03831c6c-59e8-4933-8cce-5a9b6ef80d70", "claude-nervous":"34c37a40-efa3-4ace-bb10-fe5b60cc03b3", "claude-aloof":"8c98481b-ae86-4f08-b851-9a4838e5327b", "claude-calm":"055c75e5-3e1a-42fe-9b4d-457af6fff707", "gemini-nervous":"7a2bec43-3c11-481a-bc51-a1b1bb7ea1e5", "gemini-aloof":"b7ceb349-8da1-46f8-8036-aa265c88e29f", "gemini-calm":"6a9da92c-a798-4d47-af60-40357acd4cf7"]
let ellipses:[(Double,Double,Double,Double)] = [(1105,438,89,64),(1243,489,65,62),(1158,554,88,65)]
for (name,id) in sources {
 let image = NSBitmapImageRep(data:try Data(contentsOf: URL(fileURLWithPath:input+"exec-"+id+".png")))!
 let out = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:330,pixelsHigh:300,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
 for y in 0..<300 { for x in 0..<330 {
  let px=Double(x+1010), py=Double(y+330)
  var alpha = 0.0
  for (cx,cy,rx,ry) in ellipses {
   let d = hypot((px-cx)/rx,(py-cy)/ry)
   let t = min(1,max(0,(1-d)/0.16)); alpha=max(alpha,t*t*(3-2*t))
  }
  let c=image.colorAt(x:x+1010,y:y+330)!.usingColorSpace(.deviceRGB)!
  out.setColor(NSColor(deviceRed:c.redComponent,green:c.greenComponent,blue:c.blueComponent,alpha:c.alphaComponent*alpha),atX:x,y:y)
 } }
 try out.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:dest+"face-"+name+".png"))
 print(name)
}
