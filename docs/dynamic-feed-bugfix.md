# 动态页"暂无动态"高频出现 — 排查与修复记录

## 问题现象

2025-03-05 前后，动态页（`DynamicTab`）刷新时高频率显示"暂无动态"，约 2/3 的概率复现。

## 排查过程

### 1. 排除代码改动

- `dynamic_tab.dart` 和 `video_api.dart` 近期无代码变更
- 未提交的改动（哀悼模式、设置项）与动态加载无关

### 2. 排除 API 故障

用 curl 直接调用 B站 API（PC 端 SESSDATA + TV 端 SESSDATA），均返回正常：
- `code: 0`，`items count: 20`
- `visible=True (bool)`，字段类型和值无异常

### 3. 通过 adb logcat 定位

在 `video_api.dart` 的 `getDynamicFeed` 中添加临时日志，通过 `adb logcat | grep DynamicFeed` 观察：

```
# 刷新3次，同样的20条数据，结果不同：
[DynamicFeed] types: {DYNAMIC_TYPE_AV: 12, DYNAMIC_TYPE_DRAW: 6, DYNAMIC_TYPE_ARTICLE: 2}
[DynamicFeed] OK items=20 videos=12    ← 正常

[DynamicFeed] types: {DYNAMIC_TYPE_AV: 12, DYNAMIC_TYPE_DRAW: 6, DYNAMIC_TYPE_ARTICLE: 2}
[DynamicFeed] OK items=20 videos=0     ← 所有视频解析失败
```

进一步在 `catch` 块中打印异常：

```
[DynamicFeed] PARSE ERROR: type 'String' is not a subtype of type 'int'
```

## 根因

B站 API (`/x/polymer/web-dynamic/v1/feed/all`) **间歇性地**将 `author.mid` 和 `author.pub_ts` 字段从 `int` 返回为 `String`（如 `"12345"` 而非 `12345`）。

原代码直接赋值给 `int` 类型字段：

```dart
ownerMid: author['mid'] ?? 0,      // mid="12345" → 类型不匹配
pubdate: author['pub_ts'] ?? 0,    // pub_ts="1709600000" → 类型不匹配
```

赋值时抛出 `type 'String' is not a subtype of type 'int'`，被外层 `catch` 静默吞掉，导致该条视频解析失败。由于同一批 API 响应中所有 item 的字段类型一致，一旦发生则**全部 12 条视频项全部跳过** → `videos=0` → 界面显示"暂无动态"。

## 修复

**`lib/services/api/video_api.dart`** — `getDynamicFeed` 方法：

```dart
// 修复前
ownerMid: author['mid'] ?? 0,
pubdate: author['pub_ts'] ?? 0,

// 修复后 — 使用 BaseApi.toInt() 兼容 String/int/double
ownerMid: BaseApi.toInt(author['mid'] ?? 0),
pubdate: BaseApi.toInt(author['pub_ts'] ?? 0),
```

同时将 `visible` 字段校验从 `!= true`（白名单）改为 `== false`（黑名单），避免字段缺失或类型变化时误过滤：

```dart
// 修复前
if (item['visible'] != true) continue;

// 修复后
if (item['visible'] == false) continue;
```

## 教训

1. **B站 API 的字段类型不可靠** — 同一字段可能在不同请求中返回 `int` 或 `String`，所有数字类字段都应使用 `toInt()` / `toDouble()` 做防御性转换
2. **静默 catch 隐藏根因** — `catch (e) { continue; }` 让解析错误完全不可见，排查时极难发现；关键路径应至少保留 `debugPrint`
3. **排查手段** — TV 端无法直接看 debug console，但可通过 `adb logcat | grep xxx` 实时抓日志（即使是手动安装的 debug APK）
