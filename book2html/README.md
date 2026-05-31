# Book2HTML

本目录是 Chrome / Edge / Brave 收藏夹导出工具。

启动本地网页界面：

```powershell
powershell -ExecutionPolicy Bypass -File .\book2html-server.ps1
```

默认行为：

- 只监听 `127.0.0.1`，不会暴露到局域网。
- 自动打开 `http://127.0.0.1:8765/`。
- 自动扫描 Chromium 系浏览器的 `Bookmarks` 文件。
- 右侧收藏夹列表按层级浏览，默认打开书签栏；可通过面包屑返回根目录。
- 可以选择一个或多个收藏夹组合生成同一个页面。
- 左侧已选收藏夹列表可拖动调整上下顺序，生成页面会按这个顺序输出。
- 可自定义顶栏名；顶栏名会同步作为页面标题、导航标签和 `bookmarks_顶栏名.html` 的文件名基准。
- 默认优先使用父目录站点资源并输出到父目录；如果父目录没有资源，会依次查找脚本同级资源、`data` 极简资源。
- 使用 `data` 极简资源时，工具左上角 `Book2HTML` 会标红显示“极简模式”，生成结果写到本目录的 `bookmarks_顶栏名.html`。
- 如果目标文件已存在，页面会提示覆盖或自动加序号。
- 可选把生成页跳转加入其他页面。
- 可用单独按钮清理已删除生成页的跳转。

如果端口被占用，脚本会从 `8765` 开始向后尝试。也可以手动指定：

```powershell
powershell -ExecutionPolicy Bypass -File .\book2html-server.ps1 -Port 8899
```

不自动打开浏览器：

```powershell
powershell -ExecutionPolicy Bypass -File .\book2html-server.ps1 -NoBrowser
```
