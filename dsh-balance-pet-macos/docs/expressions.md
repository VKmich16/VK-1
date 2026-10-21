# 表情素材来源与复现

模式：内置 `image_gen`，每个角色每个表情独立编辑，共九次，透明背景。参考图为本包三张 sprite 原图，分辨率 1536 × 1024。运行时使用下述局部脸部贴图，原始角色立绘沿用上游素材。

每次提示词骨架：Use case: precise-object-edit. Edit target to create ONE expression variant [state]. Change ONLY eyes eyebrows mouth. Preserve identity/style/eye colors, face geometry/angle, nose and chin. Preserve hair, horns, ears, clothing, hands, tail, tablet, pose, colors, lighting and alpha. Same 1536x1024 wide canvas and exact placement: character RIGHT, tail LEFT, tablet black and empty. Transparent background, no labels.

状态描述：nervous：tightly > < squeezed eyes, tiny wavy mouth and sweat；aloof：narrowed annoyed eyes, pout and wavy closed mouth；calm：half-lidded eyes and straight closed mouth。

集成：只取 x1010,y330,w330,h300 的脸部区域；以双眼、嘴部椭圆遮罩柔化边缘，运行时叠加到原图。原图轮廓用于点击与吸附，避免整张替换改变角色身体或位置。具体处理脚本随源码保存于 tools/make_face_patches.swift。
