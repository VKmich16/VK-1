# 图标局部修补

模式：内置 image_gen，参考原有 AppIcon 导出的 1024×1024 PNG。提示词：precise-object-edit / minimal icon repair. Repair ONLY the lowest shoe soles/toe outline and tiny contact shadow beneath both dark-blue shoes; complete gently rounded natural silhouettes, matching anime outlines. Preserve exact character identity, expression, pose, proportions, location, scale, colors, background gradient and composition; no text or new elements, no redesign or scaling. Artwork above y=810 unchanged.

生成图按原尺寸归一化后，使用 tools/blend_icon_repair.swift 的局部柔化遮罩合成，仅处理鞋底及近处阴影，保留原图 alpha 和圆角。改变像素限制在 x398–602、y826–894；其余渲染像素保持一致。最终预览为 previews/app-icon.png。
