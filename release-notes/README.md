# Release Notes Usage

This repository uses per-tag release notes files.

- Tag `v0.1` -> `release-notes/v0.1.md`
- Tag `v0.2` -> `release-notes/v0.2.md`

When GitHub Actions runs on a tag, it will fail if the matching file does not exist.

Suggested template:

```md
## 更新内容
- ...

## 说明
- 提供 v7a / v8a
- 提供带插件与不带插件版本
```
