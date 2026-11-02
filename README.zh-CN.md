# Palette Islands

JetBrains 风格的 Emacs minibuffer 浮动面板，基于
[Vertico](https://github.com/minad/vertico) 和
[posframe](https://github.com/tumashu/posframe)。附带一个按前缀切换类型的搜索窗口，
类似 Search Everywhere 和 VS Code 的 quick open。

[English](README.md)

- minibuffer 显示在带圆角、页眉、分隔线和页脚的子窗口里。焦点始终留在编辑器，
  所以键位、输入法和递归 minibuffer 都照常工作。
- 两种位置：`palette` 在窗口顶部，`point` 在光标处的符号或按钮下方。
- 输入前缀可在文件、命令、结构、行和文本之间切换；页眉的标签显示当前类型，也能点击切换。

## 依赖

Emacs 29.1 及以上（需要 SVG 支持）、Vertico（及其依赖 compat）、posframe、
[expui-icons](https://github.com/wwulfric/expui-icons)。Consult 可选。
在文本终端里 minibuffer 留在回显区。

面板 advice 了 Vertico 和 posframe 的内部函数，已在 Vertico 2.15 和 posframe 1.5.3
上测试，其他版本可能需要调整。

## 配置

```elisp
(require 'vertico)
(vertico-mode 1)
(require 'palette-islands-search)
(palette-islands-mode 1)
(keymap-global-set "s-p" #'palette-islands-search)
```

开启 `palette-islands-mode` 之前，它不绑定按键，也不改变任何行为。

可配置项见 `palette-islands-env.el`（背景色、图标、详情、标题、忽略命令、搜索类型），
颜色见 `palette-islands` 分组里的 face。详细说明见 [README.md](README.md)。

## 许可证

Apache-2.0。
