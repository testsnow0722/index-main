# Book2HTML

本目录是 Chrome / Edge / Brave 收藏夹导出工具。

## 和主项目的关系

`Book2HTML` 最初是主项目 `index-main` 里的一个配套工具，用来把 Chromium 系浏览器收藏夹导出成和主站风格一致的静态导航页。

- 放在主项目 `book2html/` 目录下运行时，会优先复用父目录的 `css/`、`js/`、`images/` 资源。
- 这种模式下，生成的 `bookmarks_*.html` 默认输出到主项目根目录，并可把跳转入口写回现有页面导航。
- 如果父目录没有完整站点资源，程序会退回到当前目录或 `data/` 里的极简资源独立运行。

换句话说，`Book2HTML` 既可以作为主项目的内置导出器使用，也可以作为单独仓库独立运行。

## 依赖

- Windows PowerShell 5.1 或 PowerShell 7+
- 本机浏览器，用于打开 `http://127.0.0.1:8765/` 本地界面
- Chromium 系浏览器收藏夹文件 `Bookmarks`，当前自动扫描：
  - Chrome
  - Chrome Beta
  - Edge
  - Brave
  - Chromium

不依赖 Node.js、npm、Python 或数据库，也不需要联网。

独立运行时，至少需要以下文件存在：

- `book2html-server.ps1`
- `data/css/`
- `data/js/`
- `data/images/`

如果要和主项目联动，则父目录还需要有主站自己的 `css/`、`js/`、`images/`。

## 仓库链接

- 主项目 `index-main`：<https://github.com/testsnow0722/index-main>
- `Book2HTML` 独立仓库：<https://github.com/testsnow0722/Bookmarks-to-html>

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
