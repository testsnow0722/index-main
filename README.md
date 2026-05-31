# 个人导航

一个纯静态的个人导航页，可以直接打开 `index.html` 使用，也可以放到任意静态托管服务上。

## 结构

- `index.html`、`common.html`、`develop.html`、`tools.html`：页面壳，负责页面元信息和挂载点。
- `js/site-data.js`：所有导航分类、站点、链接和图标数据。
- `js/site-shell.js`：渲染顶部导航。
- `js/site-preferences.js`：渲染主题、质感、文字和密度偏好面板，并保存本地偏好。
- `js/site-renderer.js`：根据 `js/site-data.js` 渲染站点卡片。
- `js/nav.ops-coffee.min.js`：首页搜索框和搜索引擎切换逻辑。
- `js/liquid-glass.js`：液态玻璃的真折射实现（仅 Chromium 系生效，其他浏览器自动回退）。
- `js/background-loader.js`：异步加载背景图。
- `css/ops-coffee.css`：基础样式、主题与质感定义。
- `images/paper-texture.png`：磨砂纸质感的纸纹叠加层。
- `book2html/`：本地网页界面的收藏夹导出工具，可复用本站资源生成同风格导航页，也可用 `data/` 资源独立运行。
- `scripts/check-project.ps1`：项目自检脚本。
- `scripts/export-chrome-bookmarks.ps1`：命令行版收藏夹导出工具。
- `scripts/format-site-data.js`：一次性把 `site-data.js` 重排为标准 2 空格缩进的工具。

## 修改导航

新增或调整站点时，优先编辑 `js/site-data.js`。每个站点对象包含：

```js
{
  "name": "站点名",
  "url": "https://example.com/",
  "icon": "images/example.png",
  "description": "可选简介"
}
```

`description` 为空时会渲染为更紧凑的卡片；有描述时会保留两行简介区域。

## 导出 Chrome 收藏夹

推荐使用 `book2html` 的本地网页界面：

```powershell
cd book2html
powershell -ExecutionPolicy Bypass -File .\book2html-server.ps1
```

页面会自动扫描 Chromium 系浏览器的 `Bookmarks` 文件，右侧按层级浏览收藏夹，勾选一个收藏夹后生成根目录下的 `bookmarks_收藏夹名称.html`。

补充说明：

- 主项目仓库：<https://github.com/testsnow0722/index-main>
- `Book2HTML` 独立仓库：<https://github.com/testsnow0722/Bookmarks-to-html>
- 更完整的关系、依赖和运行说明见 [book2html/README.md](book2html/README.md)。

也可以继续使用命令行版：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/export-chrome-bookmarks.ps1 -BookmarksPath "C:\Users\你的用户名\AppData\Local\Google\Chrome\User Data\Default\Bookmarks" -Folder "chrome://bookmarks/?id=123" -Open
```

## 外观偏好

顶部导航右侧的“偏好”面板支持本地设置：

- 主题：浅色 / 深色
- 质感（10 种）：
  - **毛玻璃**：标准 backdrop-filter blur + 高饱和。
  - **液态玻璃**：用 SVG `feDisplacementMap` 做物理折射；hover 时被悬停的卡片折射变厚。仅 Chromium 系生效。
  - **液态·兼容**：纯 CSS 实现的伪液态玻璃，全浏览器可用，作为液态玻璃的回退。
  - **亚克力**：更厚的磨砂 + 内描边。
  - **云母**：参考 Win11 Mica，高 blur + 厚底色，让壁纸色温微微透出。
  - **磨砂纸**：全屏覆盖一层真实纸纹（PNG）。
  - **黑曜石**：火山玻璃质感，深黑底 + 冷调亮边。
  - **赛博霓虹**：黑底 + 粉色边框 + 多层 box-shadow 内外发光，hover 切换到青色。
  - **8-bit 像素**：阶梯式 box-shadow 模拟像素方块边框 + monospace 字体；hover 时框变粗、文字加粗变黄。
  - **简洁**：实心卡片，无任何模糊。
- 密度：宽松 / 紧凑
- 卡片明暗度：在 -100% 到 +100% 之间调整卡片底色明暗。
- 文字主题色：色板或十六进制色值，可还原为每个配色自带文字色，并可在 -100% 到 +100% 之间调整文字明暗度。
- 文字反色：关闭 / 标题 / 全部，可选择 CSS 差值混合或采样切换黑白。

偏好会保存到浏览器的 `localStorage`，不会影响 `js/site-data.js` 里的导航数据。默认值是浅色毛玻璃。

## 本地检查

运行基础检查：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/check-project.ps1
```

这个检查会验证：

- `js/site-data.js` 能被解析。
- 每个页面都有数据。
- 每个站点 URL 是合法的绝对 URL。
- 每个图标文件都存在。
- 是否还有 `http://` 链接。

需要联网检查远程链接状态时运行：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/check-project.ps1 -CheckRemote
```

远程检查可能受网络、站点反爬、地区访问限制影响，所以远程失败会作为警告输出。

## 第三方资源 / 许可

- `images/paper-texture.png`：来自 [transparenttextures.com](https://www.transparenttextures.com/)，作者 Atle Mo，CC BY-SA 3.0。
