# loader.js

同源加载独立 widget；VK1Dash.mount/unmount 可热挂载和清理。菜单调用 connectBalance 显示密码框，仅 POST /vk-1/api/session；不读取已有服务器凭据，不把 key 写 localStorage 或文件。disconnectBalance 删除会话。无需单独执行，构建器复制到 release，dash defer 引用。
