# 动态栏三 Tab 功能

动态页（`DynamicTab`）从单一视频列表扩展为三个子 Tab：**视频**、**图文**、**专栏**，各 Tab 独立数据源、独立缓存、独立滚动位置。

## 1. 架构

### 1.1 Tab 切换模式

采用与 `HomeTab` 相同的「单内容重建 + 缓存」策略，不使用 `IndexedStack`：

- 同一时刻只渲染当前 Tab 的 Widget 树
- 切换 Tab 时销毁旧 Widget、创建新 Widget
- 已加载数据保存在 `_videos` / `_draws` / `_articles` 列表中，切换回时直接使用

原因：TV 设备内存有限，`IndexedStack` 同时保留三份 Widget 树 + 图片缓存开销过大。

### 1.2 数据缓存

每个 Tab 各自维护缓存，通过 `SettingsService` 持久化到 `SharedPreferences`：

| Tab | 列表变量 | 缓存 key |
|---|---|---|
| 视频 | `_videos` | `cached_dynamic_json` |
| 图文 | `_draws` | `cached_dynamic_draw_json` |
| 专栏 | `_articles` | `cached_dynamic_article_json` |

冷启动时从缓存恢复上次数据，避免白屏。

## 2. API

### 2.1 动态列表

三个 Tab 共用同一 API，通过 `type` 参数区分：

```
GET /x/polymer/web-dynamic/v1/feed/all
  ?type=video   (视频)
  ?type=draw    (图文)
  ?type=article (专栏)
  &offset=...   (翻页游标)
```

- 文件：`lib/services/api/video_api.dart`
- 方法：`getDynamicFeed`（视频）、`getDynamicDrawFeed`（图文）、`getDynamicArticleFeed`（专栏）
- 认证：需要 `SESSDATA` cookie

### 2.2 专栏文章全文

```
GET /x/article/view?id={cvid}
```

- 文件：`lib/services/api/article_api.dart`
- 返回格式有两种：
  - **旧版**：`data.content` 为 HTML 字符串（含 `<p>`、`<figure>`、`<img>`）
  - **新版（opus）**：`data.content` 为纯文本，富文本数据在 `data.opus.content.paragraphs`
- `ArticleApi.getArticleContent()` 统一返回 HTML：优先将 opus 转换为 HTML，回退到旧版 content

### 2.3 Opus 格式

B站新版文章使用结构化 paragraphs 替代 HTML：

```json
{
  "opus": {
    "content": {
      "paragraphs": [
        { "para_type": 1, "text": { "nodes": [{ "word": { "words": "正文" } }] } },
        { "para_type": 2, "pic": { "pics": [{ "url": "http://...", "width": 800, "height": 600 }] } }
      ]
    }
  }
}
```

- `para_type=1`：文本段落，文字在 `text.nodes[].word.words`
- `para_type=2`：图片段落，URL 在 `pic.pics[].url`

`ArticleApi._opusToHtml()` 将其转为 `<p>` + `<figure><img>` 标准 HTML。

### 2.4 评论

图文和专栏的评论类型不同：

| 类型 | `commentType` | `commentOid` |
|---|---|---|
| 图文 | `11` | 动态 ID |
| 专栏 | `12` | 文章 cv号 |

复用 `CommentListView` 组件，通过 `commentType` 参数区分。

## 3. 数据模型

文件：`lib/models/dynamic_item.dart`

| 模型 | 用途 |
|---|---|
| `DynamicDraw` | 图文：id、text、images、author、stats |
| `DynamicArticle` | 专栏：id、title、desc、coverUrl、jumpUrl、author、stats |
| `DynamicDrawFeed` | 图文分页：items + offset + hasMore |
| `DynamicArticleFeed` | 专栏分页：items + offset + hasMore |

视频 Tab 复用已有 `Video` 模型和 `DynamicFeed`。

## 4. 卡片组件

文件：`lib/widgets/tv_dynamic_card.dart`

### 4.1 图文卡片 `TvDynamicDrawCard`

- 继承 `BaseTvCard`，复用通用焦点和滚动对齐逻辑
- 默认 3 列网格（可在界面设置中通过"图文卡片列数"调整）
- 列数设置 key：`draw_grid_columns`
- 布局：封面图（`AspectRatio(4/3)`） + 底部信息（文本摘要、作者、图片数量、点赞/评论）
- 图片：`CachedNetworkImage` + `ImageUrlUtils.getResizedUrl()` + `memCacheWidth/Height`

### 4.2 专栏卡片 `TvDynamicArticleCard`

- 不继承 `BaseTvCard`，自行实现焦点和滚动对齐（`Row` 横向布局）
- 单列列表（`ListView.separated`，固定行高 134px）
- 布局：左侧封面（`AspectRatio(16/9)`） + 右侧标题/描述/元数据
- 底部元数据 Row 结构：
  - 左侧 `Expanded`：up主名、点赞、评论（up 名过长自动省略）
  - 右侧固定：发布时间（始终紧贴右边缘）

## 5. 详情页

文件：`lib/screens/dynamic_detail_screen.dart`

图文和专栏共用一个详情页，通过 `commentType` 区分模式：

### 5.1 图文模式（`commentType=11`）

- 顶部 header（标题、作者、统计）
- 图片网格（上下键切换焦点，图片带 CDN 缩放）
- 底部操作栏（评论按钮）
- 评论：弹窗 popup

### 5.2 专栏模式（`commentType=12`）

- 顶部 header
- 全文渲染（从 API 获取 HTML，手动解析为 Flutter Widget）
- 上下键滚动浏览（步长 = 视口高度 × 0.65）
- 按确认键打开评论弹窗
- 评论：弹窗 popup

### 5.3 返回键处理

使用 `PopScope(canPop: false)` 拦截系统级返回（Android TV 返回键走 navigation channel，不经过 Focus 事件）：

```dart
PopScope(
  canPop: false,
  onPopInvokedWithResult: (didPop, _) {
    if (didPop) return;
    if (_showComments) {
      // 评论打开 → 关闭评论，回到正文
      setState(() => _showComments = false);
    } else {
      // 正文 → 退出详情页
      Navigator.of(context).pop();
    }
  },
)
```

## 6. 文章渲染

采用手动 HTML 解析 + 原生 Flutter Widget 渲染，不使用 `flutter_widget_from_html_core`。

### 6.1 渲染流程

```
API → ArticleApi.getArticleContent()
    → opus 格式? → _opusToHtml() → HTML 字符串
    → 旧版 HTML? → 直接使用
→ _preprocessHtml() (协议修复: // → https://, http → https)
→ html_parser.parse() (package:html)
→ _walkBlockNodes() 递归遍历 DOM
→ 分派到各渲染方法 → Flutter Widget 列表
```

### 6.2 支持的 HTML 标签

| 标签 | 渲染 |
|---|---|
| `<p>` | `Text.rich`（支持嵌套 `<b>`/`<strong>`/`<a>`） |
| `<figure>` | 提取内部 `<img>` + `<figcaption>` |
| `<img>` | `CachedNetworkImage`（CDN 缩放 + memCacheWidth） |
| `<h1>`/`<h2>`/`<h3>` | `Text`（加大加粗） |
| `<blockquote>` | 带左边线的引用块 |
| `<br>` | `SizedBox(height: 8)` |

### 6.3 图片优化

- CDN 缩放：B站 hdslb.com 图片自动添加 `@800w.webp` 后缀
- 内存限制：`memCacheWidth` 横图 800 / 竖图 300
- 显示约束：横图最大高度 420px 撑满宽度；竖图最大高度 360px、宽度 300px 居中
- 缓存：`BiliCacheManager.instance`（带 `Referer: https://www.bilibili.com` 请求头）

### 6.4 为什么不用 HtmlWidget

- opus 生成的 HTML 结构简单固定（只有 `<p>`/`<figure>`/`<img>`/`<b>`/`<strong>`），手动解析完全覆盖
- 少一个依赖，APK 更小
- 图片 Referer、暗色/浅色主题等 TV 需求直接处理
- 如未来需要支持复杂富文本（表格、有序列表），数据层不需改动，只需替换渲染层

## 7. 浅色模式适配

遵循 `player-playback.md` 11.3 的颜色策略，所有文字和背景使用语义色 token：

| 元素 | 颜色 |
|---|---|
| 页面背景 | `AppColors.headerBackground`（浅色 `#F5F5F5` / 深色 `#121212`） |
| 正文 | `AppColors.secondaryText` |
| 标题 / 加粗 | `AppColors.primaryText` |
| 引用块 / 图注 | `AppColors.inactiveText` |
| 引用块边线 | 浅色 `#cccccc` / 深色 `#444444` |
| 链接 | 固定 `#00aeec`（B站蓝，双主题均可读） |

## 8. 焦点导航

遵循 `card-focus-alignment.md` 的对齐逻辑。

### 8.1 Tab 切换

- 顶部三个 Tab（视频/图文/专栏）使用 `TvKeyHandler.handleSinglePress`
- 左右切换 Tab，下键进入内容区，左键回侧边栏

### 8.2 图文网格

- 列数可配置（`SettingsService.drawGridColumns`，默认 3）
- 方向键规则同首页视频网格
- 聚焦时自动滚动对齐（`BaseTvCard._scrollToRevealPreviousRow`）

### 8.3 专栏列表

- 单列 `ListView`，上下移动焦点
- `TvDynamicArticleCard` 自实现滚动对齐（与 `BaseTvCard` 算法一致）

### 8.4 详情页

- 专栏正文：上下键滚动页面，确认键打开评论
- 图文详情：上下键切换图片焦点
- 评论弹窗：左键或返回键关闭

## 9. 涉及文件清单

| 文件 | 变更 |
|---|---|
| `lib/screens/home/dynamic_tab.dart` | 三 Tab 架构、数据加载、缓存 |
| `lib/screens/dynamic_detail_screen.dart` | 图文/专栏详情页 |
| `lib/widgets/tv_dynamic_card.dart` | 图文卡片、专栏卡片 |
| `lib/models/dynamic_item.dart` | DynamicDraw、DynamicArticle 模型 |
| `lib/services/api/video_api.dart` | getDynamicDrawFeed、getDynamicArticleFeed |
| `lib/services/api/article_api.dart` | 专栏全文 API（opus + legacy HTML） |
| `lib/services/api/comment_api.dart` | 评论 API 增加 type 参数 |
| `lib/services/bilibili_api.dart` | 转发新 API 方法 |
| `lib/services/settings_service.dart` | 图文/专栏缓存 key、图文列数设置 |
| `lib/screens/home/settings/tabs/interface_settings.dart` | 图文卡片列数设置 UI |
