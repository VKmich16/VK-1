# browser-test.cjs

真实 headless Chrome + 现有 Puppeteer 浏览器验证，独立本机HTTP测试站和模拟余额，不用真实Key，不改dash。覆盖右下角/镜像文字/透明穿透、右键菜单、扣费、鼠标跨内嵌iframe拖动/保存/resize、掉米饭/雷达/自动喂食/铁盆、热卸载、手机真实Touch协议长按/拖动/取消/刷新保存和连接弹窗。

用法：`node integration/browser-test.cjs RELEASE`。产物 integration/browser-test-report.json、desktop-test.png、mobile-test.png。需要现有工作区node_modules/puppeteer和/usr/bin/google-chrome，运行失败退出非零，不代表真实手机或真实余额已测。
