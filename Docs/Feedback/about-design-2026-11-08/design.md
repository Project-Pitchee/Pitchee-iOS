# Pitchee 关于页设计稿（2026-11-08）

> 状态：第二步已实现（2026-11-08）。按 Ryo 反馈「太 AI」收敛：保留 Hero、故事、功能三块的原有设计，去掉重复小标题、编号续行、技术参数卡与双行落款，改为更安静的编辑式排版。§2.4 技术参数块未进入实现，§2.5–§2.7 收敛为一段隐私说明、一组细线社区入口和单行页脚；实际结果与验证见 §7。已提交并合入 `main`，未 push。
>
> 分支：`about/community-links`（起点与 `main` 同一提交 `31e0d3f3`）
>
> 本文件路径：`Docs/Feedback/about-design-2026-11-08/design.md`

---

## 0. Skills 使用报告

### 0.1 五个技能逐项

| # | 技能 | 本机是否存在（实际路径） | 实际读了什么 | 用来做什么 |
|---|---|---|---|---|
| 1 | ponytail | 存在：`/Users/dannyfeng/.qoder/skills/ponytail/SKILL.md` | `SKILL.md` 全文（121 行） | 用阶梯约束范围：只解决关于页；不设计全 App 新设计系统；复用 `AppThemePalette`、`AboutStoryRow`、`communityLink` 的既有写法；不引入全局字体/间距 token；不新增不必要抽象 |
| 2 | native-ios-design | 存在：`/Users/dannyfeng/.cc-switch/skills/native-ios-design/` | `SKILL.md`（127 行）；`references/typography.md`（135 行，任务书写的 `typography-and-dynamic-type` 在本机实际文件名为 `typography.md`）；`references/liquid-glass.md`（107 行）；`references/layout-and-components.md`（106 行）；`references/review-checklist.md`（69 行） | 主设计依据：系统组件优先、Dynamic Type 语义字号、44×44 命中区、Liquid Glass 只用于导航层、逐区块引用 review-checklist 条目、第 5 节逐条自审 |
| 3 | swiftui-specialist | 存在：`/Users/dannyfeng/xcode-skills/swiftui-specialist/SKILL.md`（另有 `.qoder`、`.cc-switch` 副本） | `SKILL.md` 全文（20 行）及其 references 清单；本机未发现任务书提到的 `swiftui-expert-skill` 或 `swiftui-pro`，因此按任务书允许的替代口径使用 `swiftui-specialist` | 每块实现可行性：`ScrollView` + `VStack`、`AnyLayout` 大字号切换、`Link`、`@ScaledMetric`、`@Environment`、`String Catalog` 查表；不画现有 SwiftUI 落不了地的结构 |
| 4 | apple-design | **未接通**：本机未安装（已查 `~/.agents/skills`、`~/.claude/skills`、`~/.dsh/skills`、`~/.cc-switch/skills`、`~/.qoder/skills`，未见该技能；缺的是本机安装副本） | 按任务书路由从上游 `emilkowalski/skills`（MIT）读取 `skills/apple-design/SKILL.md` 原文（22,880 bytes，291 行），逐字副本在 `.research/skills/apple-design/SKILL.md`，来源审计在 `.research/skills/apple-design/00-EXCERPTS.md` | 只用于声波艺术组件与页面转场的动效口径；结论见 §1.3「动效维持现状」。它不是本机已安装技能，不冒充本机技能 |
| 5 | dsh-guizang-design | 存在：`/Users/dannyfeng/.dsh/profiles/desktop/node_modules/dsh-guizang-design/`（插件已安装） | `README.md` 相关章节；`skills/guizang-page-skill/references/design-rules.md` 全文；`skills/humanizer-zh/SKILL.md` 全文（409 行，31 条模式 + 交付前核对）；`own-skills/guizang-voice/SKILL.md` 全文（61 行）；`skills/manifest.json` | 用版式规则审版面节奏（单一强调色、留白分节、禁嵌套卡片/无意义装饰/emoji 当图标、中文排版）；用 humanizer-zh 的约束与 31 条模式审全部文案。**语气档案未接通**：本会话没有 `guizang_voice` 工具，`~/.dsh/guizang-design/voice.md` 也不存在，因此没有个人语气档案可套用；文案按 humanizer-zh 的编辑约束审，未按个人档案审 |

### 0.2 分支与 main 关系核查

- 当前分支：`about/community-links`
- `git rev-parse --short HEAD` → `31e0d3f3`
- `git rev-parse --short main` → `31e0d3f3`
- `git log --oneline -1` 两边同为 `31e0d3f3 Richer onboarding preview`
- 结论：设计分支与 `main` 同一提交，没有领先或落后提交；工作区未跟踪项只有前序调研的 `.research/` 与新增的 `Docs/Feedback/about-design-2026-11-08/design.md`，没有改动 Swift、资源或工程文件。

### 0.3 PitcheeCore 版本号当前显示位置核查

| 项 | 现状 | 出处 |
|---|---|---|
| App 版本 | `AppVersion.current` 从 `Bundle.main.infoDictionary` 读 `CFBundleShortVersionString` 与 `CFBundleVersion`，格式 `1.0 (1)` | `PitcheeApp/App/SettingsView.swift:11-25`，`SettingsView.swift:43-45` |
| App 版本显示位置 | 设置页「应用」分组的「版本」行 | `SettingsView.swift:107-111` |
| PitcheeCore 版本显示位置 | **关于页现在没有版本落款**；Core 版本只在设置页「分析引擎」行显示，且是硬编码字符串 `"PitcheeCore (5831e3c)"` | `SettingsView.swift:112` |
| 硬编码值与子模块是否对得上 | 子模块 `Dependencies/PitcheeCore` 固定提交 `5831e3cca1dde8416d0cf0c971c7ff0935fa2c1c`，前缀 `5831e3c` 一致 | `git submodule status` |
| Core 是否有版本 API | 有：`pitchee_version(void)` 声明在 `Dependencies/PitcheeCore/include/pitchee/pitchee.h:194`，实现返回 `"0.5.0"` | `Dependencies/PitcheeCore/src/analyzer.cpp:483` |
| Core 版本 API 是否被 Swift 使用 | 没有。App 侧没有任何 `pitchee_version` 调用；只有设置页的硬编码字符串 | 全仓 `grep -rn "pitchee_version" --include="*.swift"` 0 命中 |

设计结论：页脚落款显示 App 版本 + Core 版本；Core 版本建议统一成一个来源，避免设置页和关于页各写一份硬编码（见 §2.7 与 §6 问题 6）。

### 0.4 输入缺口与事实基线（必须先看）

任务书引用的主任务书 `about-page-redesign-task-2026-11-08.md` **在本机不存在**。已查 `~/Downloads`、`~/Documents`、用户主目录、废纸篓、iCloud、仓库 git 历史、DSH 会话记录，均无结果。前序设计主会话也已核实并给出结论：以仓库现状作为唯一事实基线，不编造主任务书内容。

因此本设计稿：

- 事实只来自仓库文件与可核实文件，逐条给出 `file:line`（见附录 A）；
- 主任务书 §1 事实清单、§2 逐键处置、§3.1–3.3 图标优先级无法对照，凡依赖它们的项都在 §6 列为待 Ryo 核对；
- 新增键名按任务书要求使用 `tech.*` / `community.*` 命名空间，但**不声称这是主任务书原文键名**；若主任务书另有命名，按 §3.5 的映射一对一替换；
- 不出现用户量、准确率、精度等数字；QQ 群号不写死（§2.6、§4.4）。

---

## 1. 整页结构总览

### 1.1 区块顺序与职责

| 顺序 | 区块 | 一句话职责 | 现状 |
|---|---|---|---|
| 1 | Hero | 用品牌标记、一句话主张和声波艺术建立「这是什么应用」的第一印象 | 已有 |
| 2 | 故事 | 说明 Pitchee 为什么存在、陪用户做什么 | 已有 |
| 3 | 功能 | 用三行说清「看见声音 / 找到节奏 / 留下变化」 | 已有 |
| 4 | 隐私 | 用一句话说明分析在本机完成、录音不上传 | **新增**（复用现有隐私文案） |
| 5 | 开源与社区 | 用三行细线入口给出 GitHub / Discord / QQ | **新增**（现有链接升级为三行入口） |
| 6 | 页脚 | 单行 App 版本，安静收束 | **新增** |

叙事逻辑：**先给感受（1–2）→ 再给能力（3）→ 一句隐私承诺（4）→ 给去处（5）→ 收束（6）**。隐私放在功能之后、社区之前，是因为它回答「录音去哪了」，而不是抢在功能前做技术宣讲。第一步稿中的独立「技术与工程」区（规格表、ONNX、模型数量）在第二步被去掉，理由见 §7。

### 1.2 版面节奏

- 全页容器沿用现状：`.frame(maxWidth: 620)`，水平内边距 28（常规）/ 24（无障碍大字号），底部 28（`AboutPitcheeView.swift:30-32`）。
- 区块间距沿用现状：Hero 底 44（`AboutPitcheeView.swift:93`）；故事底 42（`:116`）；功能底 42（`:130`）。新增区块一律用 42；页脚顶部用 30（Hero 顶部同值，`:65`），滚动容器底部 28 收尾。
- 全页只有一个强调色：`palette.accent`。新增区块不引入第二种强调色、不使用彩色底块、不使用嵌套卡片。
- 全页不使用悬浮 Liquid Glass。本页是设置型内容页，内容直接铺在 `AppThemeBackground` 上；卡片只是 `palette.surface` 的内容容器，不是玻璃材质（依据 `liquid-glass.md`「Principles 1: Content first, glass on top」与 review-checklist `LG1`）。
- 不新增全页入场动画、滚动视差、逐块 fade-up。新块静态出现，页面转场沿用系统导航 push。

### 1.3 动效口径（apple-design）

**结论：动效维持现状。**

| 对象 | 现状 | 本次设计 |
|---|---|---|
| 声波艺术组件 | `TimelineView(.animation(minimumInterval: 1/30, paused: reduceMotion || !isVisible || !isMounted || scenePhase != .active))`（`AboutPitcheeView.swift:230`）；点击后 `keyframeAnimator` 做 0.18s Cubic + 0.9s `.smooth` Spring 脉冲（`:235-243`）；`sensoryFeedback(.selection)`（`:246`） | 不改。它是低频装饰动效，不是手势驱动的连续交互；当前已处理 Reduce Motion、离屏、未挂载、非活跃四种暂停条件 |
| 页面转场 | 系统导航 push（设置页 → 关于页） | 不改。不自定义转场，不加 `.navigationTransition` |
| 新增区块 | 无 | 不加动效。Apple 的弹簧默认值（damping 1.0 / response 0.4）是给「可被触摸、可被中断的移动」用的；本页新增内容是静态阅读内容，加动效只会增加噪音，并与 Reduce Motion 的克制口径冲突 |

若 Ryo 后续要求新增动效，按 apple-design 的口径执行：容器变化用 damping 1.0、response 0.4；只有手势携带动量时才用 damping ~0.8；Reduce Motion 下改为短交叉淡化或静态变化。本稿不提出这类改动。

---

## 2. 逐区块设计

> 每个区块固定四项：**布局 / 规格 / 依据 / 实现注记**。
>
> 规格中的数值全部来自 `AboutPitcheeView.swift` 现有值或其组合；字号用 Dynamic Type 语义级别；颜色用 `AppThemePalette` 现有角色，不新增色值。

### 2.1 Hero

#### 布局

```
                 [28×28 app mark]  Pitchee
        ┌───────────────────────────────────┐
        │        声波艺术（max 430，1.45）     │
        └───────────────────────────────────┘
                   让声音，
                   更像你。            ← 居中
          认识自己的声音，也找到自己的节奏。  ← 居中
                       │
                      64
```

- 元素顺序：品牌标记行 → 声波艺术 → 主张（tagline）→ 说明（description）→ 渐变竖线。
- 全部居中；声波艺术是唯一的可点击元素，点击只触发视觉脉冲，不打开音频会话（文件头注释 `AboutPitcheeView.swift:3-4`）。

#### 规格

| 项 | 值 | 出处 |
|---|---|---|
| 标记行顶部间距 | 30 | `AboutPitcheeView.swift:65` |
| 标记尺寸 / 圆角 / 行内间距 | 28×28 / 7 continuous / 9 | `:58-59`、`:55` |
| 标记旁字 | `title3` semibold，tracking -0.6 | `:62-63` |
| 声波艺术 | 顶部 10，`maxWidth 430`，`aspectRatio 1.45` | `:68-69`、`:231` |
| tagline | `@ScaledMetric(relativeTo: .largeTitle)` 基准 42，bold，rounded，tracking -1.6，顶部 20 | `:9`、`:72-77` |
| description | `subheadline`，`secondaryText`，顶部 16 | `:80-84` |
| 渐变竖线 | 1×64，accent 0.5 → 0，顶部 34，装饰隐藏 | `:86-91` |
| 区块底部 | 44 | `:93` |

颜色：`primaryText`（tagline）、`secondaryText`（description）、`accent`（竖线渐变）；无新色值。字号：tagline 是页面唯一展示型字号，现状保留；description 为 `subheadline`。

#### 依据

- **Review checklist**
  - `Native structure 1`：使用系统 `ScrollView` 与系统导航栏，不自定义导航/返回（本页 `navigationTitle` + `.inline`，`AboutPitcheeView.swift:38-40`）。
  - `Typography 3`：AX5 下不裁切、不断词、不截断——tagline 与 description 都有 `fixedSize(horizontal: false, vertical: true)`（`:75`、`:82`）。
  - `Typography 2`：说明文字用 `subheadline`，高于 Caption 1；不使用 Ultralight/Thin/Light 文本字重（标记使用 semibold，tagline bold）。
  - `Color 1 / 4`：使用 `palette` 角色，浅色/深色都取自主题；强调色在两种外观下都由 `dashboardPalette` 提供。
  - `Accessibility 1`：声波艺术是纯图标按钮，已有本地化 label / hint（`:247-248`）。
  - `Accessibility 4`：Reduce Motion 下 `paused` 且时间固定为 0（`:230-231`）。
  - `Performance 2`：声波艺术的 30fps 重绘只在可见、挂载、活跃且非 Reduce Motion 时运行（`:230`、`:251-254`）。
  - `Liquid Glass 1 / 4`：Hero 不使用玻璃；导航栏保持系统默认，不加自定义 `toolbarBackground`。
- **Liquid Glass 参考**：`liquid-glass.md`「Principles 1: Content first, glass on top」——Hero 是内容，不是导航层，因此不用 glass；系统导航栏自带滚动边缘效果，符合 `LG4`。

#### 实现注记

- 现有结构原样保留：`hero(viewportHeight:)`（`AboutPitcheeView.swift:52-94`）。
- 大字号：tagline 由 `@ScaledMetric` 缩放；由于容器 `maxWidth: 620`、水平内边距在大字号降到 24（`:31`），AX5 下换行增加但不裁切。实现后需在 AX5 截图确认 tagline 不出现单字成行。
- 深色模式：`palette` 从 `dashboardPalette(for:contrast:)` 取，已有深色值；竖线用 accent 渐变，不写死 hex。
- **Typography 1 的遗留问题**：tagline 用 `.font(.system(size: headlineSize, ...))`（`:72`），严格按 review-checklist `Typography 1` 不算「语义字号角色」。这是现有设计语言的一部分，本次不改；是否改成 `.largeTitle`（会从 42pt 降到 34pt，削弱 Hero 的展示感）留给 Ryo 裁（§6 问题 5）。

### 2.2 故事

#### 布局

```
为每一种声音                        ← eyebrow，左对齐
你不必成为
另一个人。                          ← 标题，左对齐，两行
每一种声音都有自己的质感。Pitchee 陪你听见细节、
探索表达，让每一次练习都更接近自己的声音。   ← 正文，左对齐
```

- 单列、左对齐；元素顺序：eyebrow → 标题 → 正文。
- 标题允许自然换行（现有文案本身带换行），不做 `lineLimit`。

#### 规格

| 项 | 值 | 出处 |
|---|---|---|
| 区块内间距 | 18 | `AboutPitcheeView.swift:97` |
| eyebrow | `caption` semibold，tracking 2，`secondaryText` | `:99-101` |
| 标题 | `largeTitle` semibold，tracking -0.8，`primaryText`，`.isHeader` | `:104-107` |
| 正文 | `body`，`secondaryText`，行距 7（`lineSpacing`） | `:110-112` |
| 区块底部 | 42 | `:116` |

颜色：`secondaryText`（eyebrow、正文）、`primaryText`（标题）。字号：`caption` / `largeTitle` / `body`，全部为 Dynamic Type 语义级别。

#### 依据

- **Review checklist**
  - `Typography 2`：正文 `body` 高于 Caption 1；eyebrow 用 `caption` 仅作标签，不承载阅读正文。
  - `Typography 3`：标题与正文 `fixedSize(horizontal: false, vertical: true)`（`:106`、`:111`），AX5 下不裁切。
  - `Typography 5`：正文不限行，内容不被截断；只有 chrome（版本号）允许收紧。
  - `Writing 2`：正文是短句陈述，说清「是什么、怎么陪用户练」，不是宣传语。
  - `Color 1 / 2`：正文用 `secondaryText`，在两种外观下由主题提供对比度。
  - `Accessibility 2`：标题 `.isHeader`（`:107`）；正文独立阅读，不做无意义的合并。
  - `Native structure 1`：纯 `Text` 排版，不造自定义文本组件。
- **Liquid Glass 参考**：无玻璃；正文直接铺在主题背景上，符合 `LG1`。

#### 实现注记

- 现有结构原样保留：`story`（`:95-117`）。
- 大字号：`fixedSize` 已保证纵向扩展；`largeTitle` 在 AX5 会显著增大，标题可能从两行变三行，属于预期，不裁切。
- 深色模式：`primaryText` / `secondaryText` 自动适配；无自定义底色。
- 文案改动只有一处：中文正文最后一句「让每一次练习都更了解自己」主语错位，改为「让每一次练习都更接近自己的声音」（英文原句 `brings you closer to understanding your voice` 已是这个意思，不改）。完整键值见 §3.1。
- 标题「你不必成为／另一个人。」保留：它是面向用户的身份陈述，不是「不是 X，而是 Y」的抬价对比；若 Ryo 要求严格陈述句，备选见 §6 问题 8。

### 2.3 功能

#### 布局

```
01   [waveform]        看见声音
                       从音高到频谱，把听见的细节
                       变成看得见的反馈。
────────────────────────────────────────  ← accent 0.08
02   [circle.dotted]   找到节奏
                       用分析与练习资料，探索适合
                       自己的发声方式。
────────────────────────────────────────
03   [chart]           留下变化
                       将每次记录连成趋势，让细微
                       的变化也有迹可循。
```

- 单列三行，行内左侧是「图标 + 编号」竖排，右侧是「标题 + 说明」竖排；行间用细分割线。
- 功能块不另加 section 标题：它是故事承诺的具体展开，加了标题会多一层层级、也需要新键；保持现状（ponytail：不加不必要的结构）。

#### 规格

| 项 | 值 | 出处 |
|---|---|---|
| 行内边距 | 上下 26 | `AboutPitcheeView.swift:211` |
| 常规布局 | `HStack(alignment: .top, spacing: 22)` | `:186` |
| 无障碍布局 | `VStack(alignment: .leading, spacing: 18)` | `:185` |
| 图标 + 编号竖排 | 间距 12 | `:188` |
| 图标 | 现状固定 25pt light，frame 38×32；本稿改为 `title2` semantic light，`minWidth 38 / minHeight 32` 以随 Dynamic Type 缩放 | `:190-191` |
| 编号 | `caption2` monospaced，`accent` | `:192-193` |
| 文本竖排 | 间距 10 | `:198` |
| 行标题 | `title3` semibold，`primaryText`，`.isHeader` | `:200-202` |
| 行说明 | `subheadline`，`secondaryText`，行距 4 | `:204-206` |
| 分割线 | `Divider().overlay(palette.accent.opacity(0.08))` | `:122`、`:124` |
| 区块底部 | 42 | `:130` |

颜色：`accent`（图标、编号）、`primaryText`（标题）、`secondaryText`（说明）、`accent.opacity(0.08)`（分割线）。字号：`title2`（图标，语义）、`caption2`（编号）、`title3`（标题）、`subheadline`（说明）。

#### 依据

- **Review checklist**
  - `Typography 4`：常规 HStack / 无障碍 VStack 通过 `AnyLayout` 切换（`:185-186`），AX 下每行改为纵向，不会把标题挤成窄列。
  - `Typography 6`：图标从固定 25pt 改为 `title2` 语义字重，随 Dynamic Type 缩放；编号用 monospaced caption2，与图标同属装饰信息。
  - `Typography 3`：说明文字 `fixedSize`（`:208`），AX5 不裁切。
  - `Color 3`：编号与分割线颜色只是装饰，不单独承载含义；每行标题是主信息，颜色不是唯一区分手段。
  - `Interaction 1`：功能行本身不可点击，不涉及命中区；整页可点元素只有声波艺术和社区入口。
  - `Accessibility 2`：图标与编号已 `accessibilityHidden(true)`（`:196`）；标题 `.isHeader`，说明独立阅读。
  - `Liquid Glass 1`：功能行是内容，不是导航层，不用玻璃；分割线是内容内分隔，不是工具栏边缘效果。
- **Liquid Glass 参考**：`LG1`（content 保持不透明/平面），无例外。

#### 实现注记

- 复用 `AboutStoryRow`（`:176-213`），技术区也复用它；本次只加两个小改动：图标改语义字号 + frame 改 `minWidth/minHeight`，不新建全局组件。
- 大字号：现有 `AnyLayout` 已处理；改动图标字号后需在 AX5 确认图标不压到编号、编号不压到标题。
- 深色模式：分割线用 accent 0.08，在深色下仍可见但不抢眼；图标/编号用 accent，浅深两套由主题提供。
- 不新增行、不删除行；三行文案与键值保持（见 §3.1）。

### 2.4 技术与工程（第一步提案，未实现）

> 第二步实现说明：§2.4–§2.7 保留第一步原稿以记录取舍。Ryo 反馈「太 AI」后，实现没有采用技术参数清单、规格表、带图标的社区卡和双行版本落款；实际落地为 §7 所述的三块安静内容。

#### 布局

```
技术与工程                          ← eyebrow
声音如何被读懂                       ← 标题
────────────────────────────────────────
04   [cpu]              在本机完成
                        录音在本机进入分析流程，
                        音频不上传。
────────────────────────────────────────
05   [stack]            六个模型协同
                        语音活动检测、基频、音色与
                        自然度由六个 ONNX 模型分工
                        完成，经 ONNX Runtime 1.24.2
                        在本机运行。
────────────────────────────────────────
06   [gauge]            留下可回看的指标
                        基频 F0、音色 VFP、自然度、
                        HNR 与声音健康度来自同一次
                        分析，连同综合评分留在记录里。
```

- 结构：section header（eyebrow + 标题）+ 三条 `AboutStoryRow`。编号延续功能区的 01–03，技术区用 04–06，让整页读成一本连续的小册子，而不是两套并列清单。
- 行内结构与功能区完全一致：左「图标 + 编号」，右「标题 + 说明」，行间细分割线。
- 区块底部 42。

#### 规格

| 项 | 值 | 出处 |
|---|---|---|
| section header 竖排间距 | 18 | `AboutPitcheeView.swift:97` |
| eyebrow | `caption` semibold，tracking 2，`secondaryText` | `:99-101` |
| section 标题 | `title2` semibold，tracking -0.4，`primaryText`，`.isHeader` | 新用语义级别；tracking 按 largeTitle -0.8 的比例收敛 |
| header 与首行间距 | 8 | `:152`（现有小间距值） |
| 行规格 | 同 §2.3：上下 26、HStack spacing 22 / AX VStack spacing 18、文本间距 10、标题 `title3`、说明 `subheadline` 行距 4、分割线 accent 0.08 | `:185-211`、`:122`、`:124` |
| 图标 | `cpu` / `square.stack.3d.up` / `gauge.with.dots.needle.50percent`，`title2` light | 新用 SF Symbols；字号语义级别 |
| 行编号 | `04` / `05` / `06`，`caption2` monospaced | `:192-193` |
| 区块底部 | 42 | `:116`、`:130` |

颜色：全部沿用 `accent` / `primaryText` / `secondaryText` / `accent.opacity(0.08)`；没有新色值。字号：`caption`（eyebrow）、`title2`（section 标题）、`title2`（图标）、`caption2`（编号）、`title3`（行标题）、`subheadline`（行说明）。

#### 依据

- **Review checklist**
  - `Native structure 1`：section header 用 `Text`，行复用现有 `AboutStoryRow`，没有引入列表/表单之外的定制容器。
  - `Typography 4`：三条技术行沿用 `AnyLayout`，AX 下自动改为纵向。
  - `Typography 6`：图标用 `title2` 语义字号，与行标题同一 Dynamic Type 体系；不是固定 pt。
  - `Typography 3`：说明 `fixedSize`，AX5 不裁切；技术术语（ONNX Runtime、HNR、VFP）允许在词内换行吗？不允许——用 `fixedSize` 让整词保持，必要时整行下移。
  - `Color 1 / 2`：正文 `secondaryText`，标题 `primaryText`；两套外观由 `dashboardPalette` 提供。
  - `Accessibility 2`：每行图标/编号隐藏，标题 `.isHeader`，说明独立阅读；三条行都是「标题 + 说明」的复合信息，VoiceOver 顺序见 §4.3。
  - `Writing 2`：三条说明都是陈述句，说清「在哪里跑、跑什么、产出什么」，不写宣传语、不写精度数字。
  - `Liquid Glass 1`：技术行是内容，不是导航层；无玻璃、无悬浮卡片堆叠。
- **Liquid Glass 参考**：`LG1`；技术区没有需要浮在内容之上的控件，因此没有例外。

#### 实现注记

- 复用 `AboutStoryRow`（`:176-213`），只传新的 number / symbol / title / detail；不新建技术专用视图。
- 大字号：与功能区同一 `AnyLayout`；技术行文本更长，AX5 下可能一行变四到五行，行高随内容增长，不设 `lineLimit`。
- 深色模式：同功能区；分割线 accent 0.08 在深色背景仍可见。
- 文案必须只用已核实事实；每条事实的来源见附录 A。**「共振峰」已删除**：`Dependencies/PitcheeCore/include` 与 `src` 中 `formant|共振峰` 0 命中；只有 `Resources/VoiceTrainingLibrary/voice-training-library.json:124,127,246,249` 的英文参考文献标题出现 “formant”，那不是 Core 的输出字段，不能作为产品事实。
- 技术行不使用「女性化分数」「准确率」「精度」等未在本稿核实的表述；综合评分用「综合评分」，音色用「音色 VFP」。
- 若 Ryo 认为 ONNX Runtime 版本号对普通用户太深，可把 05 行说明缩为「六个 ONNX 模型分工完成语音活动检测、基频、音色与自然度，全部在本机运行」，版本号留在 GitHub README；本稿默认保留版本号，因为它可核实且能建立工程可信度。

### 2.5 隐私（新增）

#### 布局

```
┌──────────────────────────────────────────┐
│ [lock.shield]  隐私说明                   │
│                只在设备上分析              │
│                声音分析在本机完成，录音不会 │
│                上传到服务器，也不会共享给   │
│                第三方。                    │
└──────────────────────────────────────────┘
```

- 一块全宽卡片，内部左侧图标、右侧「标题 + 副标题 + 说明」纵排；不再加 section header，卡片本身就是这一块的标题。
- 卡片圆角 18，填充 `palette.surface`；`reduceTransparency` 时改用 `secondarySystemGroupedBackground`（沿用社区入口现有回退，`:164-166`）。

#### 规格

| 项 | 值 | 出处 |
|---|---|---|
| 卡片内边距 | 上下 26，左右 16 | 26 来自行节奏 `:211`；16 来自 Hero 说明间距 `:84` |
| 卡片圆角 | 18 continuous | `:165` |
| 卡片填充 | `palette.surface`；Reduce Transparency → `secondarySystemGroupedBackground` | `:164-166` |
| 内部横排 | `HStack(alignment: .top, spacing: 22)`；AX → `VStack(alignment: .leading, spacing: 18)` | `:185-186` |
| 图标 | `lock.shield`，`title2` light，`minWidth 38 / minHeight 32` | `:190-191`（语义化后） |
| 文本竖排 | 间距 10；标题与副标题之间 6 | `:198`、`:226` |
| 标题 | `title3` semibold，`primaryText`，`.isHeader` | `:200-202` |
| 副标题 | `body` semibold，`accent` | 现有 `body` 语义；强调色不新增 |
| 说明 | `subheadline`，`secondaryText`，行距 4 | `:204-206` |
| 区块底部 | 42 | `:116`、`:130` |

颜色：`surface`（卡片）、`accent`（图标、副标题）、`primaryText`（标题）、`secondaryText`（说明）。字号：`title3` / `body` / `subheadline`，全部语义级别。

#### 依据

- **Review checklist**
  - `Typography 3`：说明 `fixedSize`，AX5 不裁切；卡片高度随内容增长。
  - `Typography 4`：AX 下图标与文本从横排改纵排。
  - `Color 1 / 2`：卡片与文字全部用主题角色；`secondaryText` 在两种外观下都有对比度保障。
  - `Accessibility 2`：图标隐藏，标题 + 副标题 + 说明合并为一个可读块（详见 §4.3）。
  - `Accessibility 5`：`reduceTransparency` 回退到系统分组背景；Increase Contrast 由 `dashboardPalette(for:contrast:)` 处理。
  - `Writing 2`：说明是两短句，说清「在哪里分析、录音去哪里」，没有恐吓式措辞。
  - `Liquid Glass 1 / 2`：这是内容卡片，不是玻璃材质；不使用 `.ultraThinMaterial` / `.regularMaterial` 仿玻璃。
- **Liquid Glass 参考**：`LG1`（content 不透明）、`LG2`（不用材料仿玻璃）；无例外。

#### 实现注记

- 复用现有 `AboutStoryRow` 的排版常量最省事，但它现在固定 `number` 与 `tableName: "AboutPitchee"`。实现时可给 `AboutStoryRow` 加两个最小参数：`number: String?`（nil 时不显示编号）与 `tableName: String = "AboutPitchee"`；隐私卡片传 `number: nil`、`tableName: "Localizable"`。若不想改 `AboutStoryRow` 签名，就在同文件内写一个 20 行的 `AboutPrivacyCard`，但排版值必须照抄上表，不另造一套。
- 大字号：`AnyLayout` 切换后图标在上、文本在下；卡片左右 16 的内边距在 AX 下保持，避免文本贴边。
- 深色模式：`palette.surface` 深色值是半透明深色（`AppTheme.swift` 中的 0.38 透明度），卡片下是主题背景，层次仍在；Reduce Transparency 时换系统分组背景。
- 文案复用现有 `Localizable.xcstrings` 的三个键（29 个本地化全有值），不新增隐私键：
  - `voiceProfile.privacyPromise.title`（隐私说明 / Privacy information）
  - `voiceProfile.privacyPromise.onDevice.title`（只在设备上分析 / Analyzed Only on Your Device）
  - `voiceProfile.privacyPromise.onDevice.description`（声音分析在本机完成，录音不会上传到服务器，也不会共享给第三方。 / Voice analysis happens on this device. Recordings are never uploaded to a server or shared with third parties.）
- 这三条键当前在设置/引导里使用，语气与关于页一致；如果 Ryo 想强调「不追踪、不收集数据」的隐私清单事实，需要新增 `privacy.*` 键，本稿不擅自加（§6 问题 3）。

### 2.6 开源与社区（新增）

#### 布局

**非空状态（QQ 群号已配置）**

```
开源与社区                          ← eyebrow
一起练下去                          ← 标题
┌──────────────────────────────────────────┐
│ [code]   查看 GitHub 项目            [↗] │
│          源代码与版本记录，GPL-3.0 许可。  │
├──────────────────────────────────────────┤
│ [chat]   加入 Discord                [↗] │
│          在 Discord 里交流。              │
├──────────────────────────────────────────┤
│ [group]  加入 QQ 群                  [↗] │
│          群号 {QQ 群号}                   │
└──────────────────────────────────────────┘
```

**空状态（QQ 群号常量为空）**

```
开源与社区
一起练下去
┌──────────────────────────────────────────┐
│ [code]   查看 GitHub 项目            [↗] │
│          源代码与版本记录，GPL-3.0 许可。  │
├──────────────────────────────────────────┤
│ [chat]   加入 Discord                [↗] │
│          在 Discord 里交流。              │
└──────────────────────────────────────────┘
```

- 三行顺序固定为 GitHub → Discord → QQ；QQ 放最后，空状态时直接省略该行和它上方的分割线，不会留下尾部空线。
- 每一行都是整行可点击的 `Link`，左侧图标、中间两行文字、右侧外链箭头。
- 区块底部 42；页脚在其后。

#### 规格

| 项 | 值 | 出处 |
|---|---|---|
| section header | 同 §2.4：`caption` eyebrow + `title2` 标题，竖排 18，header 底部 8 | `:97-105`、`:152` |
| 行容器 | `RoundedRectangle(cornerRadius: 18, style: .continuous)`，填充 `palette.surface`；Reduce Transparency → `secondarySystemGroupedBackground` | `:164-166` |
| 行内边距 | 左右 14，上下 14 | `:161-162` |
| 行最小高度 | 48 | `:163` |
| 行内横排 | 图标 → 文本 → Spacer → 箭头，间距 12 | 12 来自 `:188`；现状行内是 8（`:152`），因新增左侧图标，取 12 更稳 |
| 文本竖排 | 标题 + 说明，间距 6 | `:226` |
| 行标题 | `body` semibold，`primaryText` | 现有 `body` 语义；行标题不再用 accent |
| 行说明 | `caption`，`secondaryText`，`fixedSize(vertical)` | 现有 `caption` 语义；行说明可换行 |
| 左侧图标 | GitHub `chevron.left.forwardslash.chevron.right`；Discord `bubble.left.and.bubble.right`；QQ `person.3`；`body` medium，`accent`，frame 24 | SF Symbols；装饰隐藏 |
| 右侧箭头 | `arrow.up.right`，`caption` medium，`tertiary` | `:155-157`（现状图标与字重） |
| 行间分割线 | `Divider().overlay(palette.accent.opacity(0.08))` | `:122`、`:124` |
| 区块底部 | 42 | `:116`、`:130` |

颜色：`accent`（左侧图标）、`primaryText`（标题）、`secondaryText`（说明）、`tertiary`（箭头）、`surface`（容器）、`accent.opacity(0.08)`（分割线）；没有新色值。字号：`caption`（eyebrow）、`title2`（section 标题）、`body`（行标题/图标）、`caption`（说明/箭头），全部语义级别。

#### 依据

- **Review checklist**
  - `Native structure 1`：整行用系统 `Link`，不自己造外链按钮；导航栏仍由系统提供。
  - `Typography 3`：标题与说明都允许纵向扩展；德语等长文本不截断（见 §4.5）。
  - `Typography 4`：行本身已是纵向两行文字，AX 下不需要再换布局；左右 14 内边距在 AX 下保持。
  - `Typography 6`：三个左侧图标都用 `body` 语义字号，随 Dynamic Type 缩放；箭头 `caption` 与说明同级。
  - `Color 3`：外链含义由 `Link` 语义 + 箭头共同表达，不靠颜色单独承载；标题用 `primaryText` 而非 accent，避免「整行都是链接色」的噪音。
  - `Interaction 1`：行最小高度 48，高于 44×44 要求；整行 `contentShape` 可点。
  - `Interaction 5`：GitHub / Discord / QQ 是社区入口，按系统行为离开 App（Safari / Discord / QQ），不使用 `SFSafariViewController` 强行留在应用内；本条判为不适用，理由见 §5 `I5`。
  - `Accessibility 1`：左侧图标与外链箭头都是装饰，`accessibilityHidden(true)`；整行有标题，不需要图标单独命名。
  - `Accessibility 2`：每行合并为一个元素，读出「标题 + 说明 + 链接」，详见 §4.3。
  - `Writing 1`：英文按钮文案用 title-case 动词（View on GitHub / Join Discord / Join the QQ Group）。
  - `Liquid Glass 1 / 2`：社区行是内容卡片，不是导航层，不用玻璃；不使用 `.regularMaterial` 仿玻璃。
- **Liquid Glass 参考**：`LG1`、`LG2`；无例外。本页不使用 `GlassEffectContainer`，因为没有任何悬浮控件。

#### 实现注记

- 现状 `communityLinks` 是「GitHub 整行 + QQ/Discord 两列」的 `Link` 芯片（`:133-147`、`:150-173`）。设计改为三行同构入口：
  - 复用现有 `Link(destination:)`、`buttonStyle(.plain)`、`accessibilityIdentifier`（`:171`）与 `contentShape`；
  - 新增一个同文件私有 `AboutCommunityRow`（或在 `communityLink` 上扩参数），只表达「图标 + 标题 + 说明 + 箭头」，不新建全局组件；
  - 保留三个 identifier：`about.pitchee.github`、`about.pitchee.discord`、`about.pitchee.qq`，现有 UI 测试不用改。
- QQ 两态：实现时用一个常量（例如 `qqGroupNumber`）控制；为空时 `if !qqGroupNumber.isEmpty` 不渲染 QQ 行及其上方分割线。**设计稿不写任何具体群号**；外部队列海报上的 957130533 未在仓库核实，不作为设计输入（§6 问题 2）。
- 大字号：行内两行文字自然增高，`minHeight 48` 只是下限；AX5 下标题可能换成两行，说明换成三行，容器随内容增长，不裁切。
- 深色模式：`palette.surface` 深色下半透明，卡片与背景仍有层次；分割线 accent 0.08 可见；箭头 `tertiary` 在深色下有独立值。
- 图标档位：任务书 3.3 的优先级无法读取，本稿采用并明确以下替代档位（按「可用性 / 授权 / 维护成本」排序）：
  1. **SF Symbols**（本稿选此档）：系统矢量、可着色、随 Dynamic Type 缩放、无外部授权与资产维护；
  2. **仓库内已有品牌资产**：`Resources/Assets.xcassets` 只有 App 图标 imageset（AquaEcho、AquaWave、CoralNote、CoralSong、Default、LaunchLogo、SageCub、SageHaven），没有 GitHub/Discord/QQ 品牌图；
  3. **纯文字行（无图标）**：会削弱三行入口的扫描性，不选。
  本稿不使用 GitHub/Discord/QQ 品牌 logo 的仿制图形，也不引入 Bezel 或任何外部素材（任务书 §3 硬边界）。

### 2.7 页脚版本落款（新增）

#### 布局

```
                 Pitchee 1.0 (1)
            PitcheeCore 0.5.0 (5831e3c)
```

- 页面最底部，居中两行；与社区卡片之间用 30 的顶部间距，滚动容器底部 28 收尾。
- 不加分割线、不加背景、不加按钮；它是落款，不是新section。

#### 规格

| 项 | 值 | 出处 |
|---|---|---|
| 顶部间距 | 30 | `AboutPitcheeView.swift:65`（同值） |
| 两行间距 | 6 | `:226` |
| 字体 | `caption`（两行同字号） | 语义级别；版本属于 chrome，不是阅读正文 |
| 颜色 | `secondaryText`（第一行）、`tertiary`（第二行） | `AppThemePalette` 现有角色；不新增色值 |
| 对齐 | 居中 | 与 Hero 的居中形成首尾对称；页面中段保持左对齐 |
| 底部 | 由容器 `.padding(.bottom, 28)` 收尾 | `:32` |

颜色：`secondaryText`（第一行）/ `tertiary`（第二行）；字号：`caption`。版本号本身是运行时值，不是本地化文案。

#### 依据

- **Review checklist**
  - `Typography 2`：版本是 chrome，用 `caption`，不低于 Caption 1；不使用 Light 字重。
  - `Typography 5`：只有 chrome 被限制为短文本；正文不设 `lineLimit`。
  - `Color 1 / 4`：`tertiary` / `secondaryText` 在浅深两套主题下都有值；版本号不承担导航含义。
  - `Accessibility 2`：两行合并成一个元素，避免 VoiceOver 把版本号拆成两次无意义停顿。
  - `Writing 2`：落款不写宣传句，只给版本指纹。
  - `Liquid Glass 1`：落款是内容，不用玻璃。
- **Liquid Glass 参考**：`LG1`；无例外。

#### 实现注记

- App 版本：复用 `AppVersion.current`（`SettingsView.swift:11-25`，`:43-45`），不复制格式化逻辑。
- Core 版本：
  - 现状只有 `SettingsView.swift:112` 的硬编码 `"PitcheeCore (5831e3c)"`；
  - Core C API 有 `pitchee_version()`，返回 `"0.5.0"`（`pitchee.h:194`、`analyzer.cpp:483`），但 Swift 侧没有调用，且需要确认模块/桥接暴露；
  - 本稿显示 `PitcheeCore 0.5.0 (5831e3c)`：`0.5.0` 来自 C API 的实际返回值，`5831e3c` 来自子模块提交。
  - 建议在 `AppVersion` 旁增加一个 `CoreVersion`（或复用同一个常量），让设置页和关于页读同一个来源；不要在关于页再写一份硬编码。是否改用 C API 还是保留常量，留给 Ryo 定（§6 问题 6）。
- 大字号：两行 `caption` 在 AX5 会变大，允许换行；不设 `lineLimit`，不做缩放。
- 深色模式：`tertiary` 在深色下有独立值（`AppTheme.swift` 的 deep palette），不需要额外处理。

---

## 3. 全量文案终稿

> 第二步实际落地：未迁移任何现有键名，`link.github.title` / `link.discord.title` / `link.qq.title` 保持原名原值（英文仍为 `Join the QQ group`）；`story.body` 只改 zh-Hans / zh-Hant。§3.2 的 `tech.*` / `community.*` 新增键未写入。以下保留第一步终稿，作为对照记录。

### 3.1 现有键处置总表（17 键）

> 现有 `Resources/AboutPitchee.xcstrings` 共 17 键、29 个本地化、源语言 `en`。下表逐键给出终稿；「保留」表示不改值，「迁移」表示键名改到 `community.*` 但值保留，「改值」只列实际改动。

| # | 现有键 | zh-Hans 现值 | en 现值 | 处置 | zh-Hans 终稿 | en 终稿 | 理由 |
|---|---|---|---|---|---|---|---|
| 1 | `screen.title` | 关于 Pitchee | About Pitchee | 保留 | 关于 Pitchee | About Pitchee | 导航标题，准确 |
| 2 | `hero.tagline` | 让声音，\n更像你。 | Your voice.\nMore like you. | 保留 | 让声音，\n更像你。 | Your voice.\nMore like you. | 品牌主张，短、具体，不空泛 |
| 3 | `hero.description` | 认识自己的声音，也找到自己的节奏。 | Get to know your voice. Find your own rhythm. | 保留 | 认识自己的声音，也找到自己的节奏。 | Get to know your voice. Find your own rhythm. | 陈述句，说清用途 |
| 4 | `hero.accessibility.label` | 声波互动 | Interactive sound waves | 保留 | 声波互动 | Interactive sound waves | 说明控件是什么 |
| 5 | `hero.accessibility.hint` | 播放一段视觉声波动效。 | Plays a visual sound wave animation. | 保留 | 播放一段视觉声波动效。 | Plays a visual sound wave animation. | 说明点击后发生什么 |
| 6 | `story.eyebrow` | 为每一种声音 | For every voice | 保留 | 为每一种声音 | For every voice | 标签，简短 |
| 7 | `story.title` | 你不必成为\n另一个人。 | You don’t have to become\nsomeone else. | 保留（见 §6 问题 8） | 你不必成为\n另一个人。 | You don’t have to become\nsomeone else. | 面向用户的身份陈述，是品牌语义；不是「不是 X，而是 Y」的抬价对比 |
| 8 | `story.body` | 每一种声音都有自己的质感。Pitchee 陪你听见细节、探索表达，让每一次练习都更了解自己。 | Every voice has its own character. Pitchee helps you notice the details and explore how you express yourself, so every practice brings you closer to understanding your voice. | **改值（仅 zh-Hans）** | 每一种声音都有自己的质感。Pitchee 陪你听见细节、探索表达，让每一次练习都更接近自己的声音。 | 不变 | 原中文「让每一次练习都更了解自己」主语错位；改为「更接近自己的声音」，与英文 closer to understanding your voice 对齐 |
| 9 | `feature.listen.title` | 看见声音 | See your voice | 保留 | 看见声音 | See your voice | 三字动作，具体 |
| 10 | `feature.listen.body` | 从音高到频谱，把听见的细节变成看得见的反馈。 | From pitch to spectrum, turn what you hear into feedback you can see. | 保留 | 从音高到频谱，把听见的细节变成看得见的反馈。 | From pitch to spectrum, turn what you hear into feedback you can see. | 说清「从什么到什么」，不空泛 |
| 11 | `feature.practice.title` | 找到节奏 | Find your rhythm | 保留 | 找到节奏 | Find your rhythm | 与「练习」主题一致 |
| 12 | `feature.practice.body` | 用分析与练习资料，探索适合自己的发声方式。 | Explore a way of using your voice that works for you, with analysis and practice resources. | 保留 | 用分析与练习资料，探索适合自己的发声方式。 | Explore a way of using your voice that works for you, with analysis and practice resources. | 陈述句，说明手段与目的 |
| 13 | `feature.progress.title` | 留下变化 | Trace the changes | 保留 | 留下变化 | Trace the changes | 与「趋势」呼应 |
| 14 | `feature.progress.body` | 将每次记录连成趋势，让细微的变化也有迹可循。 | Turn individual recordings into trends, so even subtle changes leave a trace. | 保留 | 将每次记录连成趋势，让细微的变化也有迹可循。 | Turn individual recordings into trends, so even subtle changes leave a trace. | 说清机制「记录 → 趋势」 |
| 15 | `link.github.title` | 查看 GitHub 项目 | View on GitHub | **迁移**到 `community.github.title` | 查看 GitHub 项目 | View on GitHub | 值保留；键名归入 `community.*` |
| 16 | `link.qq.title` | 加入 QQ 群 | Join the QQ group | **迁移**到 `community.qq.title`，并改大小写 | 加入 QQ 群 | Join the QQ Group | 值保留；英文按 title-case 动词改 `group` → `Group` |
| 17 | `link.discord.title` | 加入 Discord | Join Discord | **迁移**到 `community.discord.title` | 加入 Discord | Join Discord | 值保留；键名归入 `community.*` |

语气：本表逐条按 §3.4 审校；个人语气档案未接通（本会话无 `guizang_voice` 工具、本机无 `voice.md`），因此只按 humanizer-zh 的通用约束审，未按 Ryo 的个人档案审。

### 3.2 新增键（tech.* / community.*）

| 键 | zh-Hans | en | 用在哪 | 事实 / 语气说明 |
|---|---|---|---|---|
| `tech.eyebrow` | 技术与工程 | Under the hood | 技术区 eyebrow | 标签，不夸大 |
| `tech.title` | 声音如何被读懂 | How Pitchee reads a voice | 技术区标题 | 陈述句，说清这一块在讲「怎么读」 |
| `tech.onDevice.title` | 在本机完成 | Runs on this device | 技术 04 行标题 | 事实：分析在本机完成；不写「绝对安全」 |
| `tech.onDevice.body` | 录音在本机进入分析流程，音频不上传。 | Recordings are analyzed on this device. Audio is never uploaded. | 技术 04 行说明 | 事实：录音不上传；与现有隐私文案一致，不新增数字 |
| `tech.models.title` | 六个模型协同 | Six models working together | 技术 05 行标题 | 事实：Core `models/manifest.json` 列 6 个 ONNX 文件 |
| `tech.models.body` | 语音活动检测、基频、音色与自然度由六个 ONNX 模型分工完成，经 ONNX Runtime 1.24.2 在本机运行。 | Six ONNX models cover voice activity, pitch, timbre, and naturalness, running on this device with ONNX Runtime 1.24.2. | 技术 05 行说明 | 事实：6 个 ONNX 模型；ONNX Runtime 1.24.2；不写准确率/速度 |
| `tech.metrics.title` | 留下可回看的指标 | Indicators you can revisit | 技术 06 行标题 | 事实：历史保存分析指标；不写「全部指标」 |
| `tech.metrics.body` | 基频 F0、音色 VFP、自然度、HNR 与声音健康度来自同一次分析，连同综合评分留在记录里。 | F0 pitch, VFP timbre, naturalness, HNR, and voice health come from the same analysis, with a composite score kept in your history. | 技术 06 行说明 | 事实：Core 输出字段含 F0、VFP、naturalness、HNR、voice health、综合分；不写「共振峰」 |
| `community.eyebrow` | 开源与社区 | Open source and community | 社区区 eyebrow | 标签，准确 |
| `community.title` | 一起练下去 | Keep practicing together | 社区区标题 | 陈述式邀请，不喊口号 |
| `community.github.title` | 查看 GitHub 项目 | View on GitHub | GitHub 行标题 | 迁移自 `link.github.title`，值保留 |
| `community.github.detail` | 源代码与版本记录，GPL-3.0 许可。 | Source code and version history. GPL-3.0. | GitHub 行说明 | 事实：仓库 `LICENSE.txt` 为 GPL-3.0；不写 star 数/贡献者数 |
| `community.discord.title` | 加入 Discord | Join Discord | Discord 行标题 | 迁移自 `link.discord.title` |
| `community.discord.detail` | 在 Discord 里交流。 | Join the conversation on Discord. | Discord 行说明 | 不承诺人数、不写「官方」 |
| `community.qq.title` | 加入 QQ 群 | Join the QQ Group | QQ 行标题 | 迁移自 `link.qq.title`；英文 title case |
| `community.qq.detail` | 群号 %@。 | Group number %@. | QQ 行说明 | **%@ 是占位符，不是群号**；群号为空时整行隐藏，见 §4.4 |

语气：新增键全部按 §3.4 审校；技术说明只陈述已核实事实，社区说明不承诺人数/官方身份，QQ 说明不含具体群号。

### 3.3 复用的隐私键（不新增）

| 键 | zh-Hans | en | 用在哪 | 本地化覆盖 |
|---|---|---|---|---|
| `voiceProfile.privacyPromise.title` | 隐私说明 | Privacy information | 隐私卡片标题 | 29 个本地化全有值 |
| `voiceProfile.privacyPromise.onDevice.title` | 只在设备上分析 | Analyzed Only on Your Device | 隐私卡片副标题 | 29 个本地化全有值 |
| `voiceProfile.privacyPromise.onDevice.description` | 声音分析在本机完成，录音不会上传到服务器，也不会共享给第三方。 | Voice analysis happens on this device. Recordings are never uploaded to a server or shared with third parties. | 隐私卡片说明 | 29 个本地化全有值 |

### 3.4 语气审校记录（dsh-guizang-design）

- **版式审校**：采用单一强调色；区块之间用间距（42/44）分节，不叠加重线；不嵌套卡片；不使用 emoji 当图标；不使用 SaaS 式三列功能卡；标题层级由「字号 + 字重」共同定义（eyebrow caption / section title title2 / 行标题 title3 / 正文 subheadline / body）；中文正文左对齐、行距 7（故事）与 4（行说明），符合 `design-rules.md` 的中文排版原则（正文不首行缩进、段间留白、标题不用负字距到粘连）。
- **humanizer-zh 31 条模式**：逐条对照后，本稿文案没有「不是 X，而是 Y」的抬价对比、没有强凑三段式、没有「深入探索 / 赋能 / 无缝 / 闭环」等空泛词、没有戏剧性碎片、没有「总而言之 / 让我们一起期待」式套话、没有客服腔、没有知识边界免责、没有首句复读标题。技术区说明只写「是什么、怎么工作」，不写性能结论。
- **保留的现有文案**：`hero.tagline`、`story.title`、三条 feature 文案都已是具体、通顺、有品牌语气的句子；按 humanizer-zh「不要为了展示工作量强行修改已通顺的文字」，不改。唯一改值是 `story.body` 的中文语法问题（见 §3.1 第 8 行）。
- **语气档案**：未接通（本会话无 `guizang_voice` 工具，`~/.dsh/guizang-design/voice.md` 不存在），因此没有按 Ryo 的个人语气档案审；上述结论只基于 humanizer-zh 的通用编辑约束。若后续接通档案，需要再审一遍 `community.title` 与三条 detail 的措辞。

### 3.5 键迁移与本地化覆盖

- `link.github.title` → `community.github.title`；`link.qq.title` → `community.qq.title`；`link.discord.title` → `community.discord.title`。迁移时把 29 个本地化的现有值原样带到新键，避免丢失翻译；`community.qq.title` 的英文值按 title case 调整。
- 新增的 `tech.*`（8 键）与 `community.*`（8 键，含 3 个迁移键和 5 个新键）需要补齐 29 个本地化；本设计稿只给 zh-Hans / en 终稿，其余语言按现有术语表翻译。键名若与主任务书不一致，按「同义一对一」替换，不另起一套命名。
- `AboutPitchee.xcstrings` 的源语言是 `en`；新增键的 en 值即源文。`Localizable.xcstrings` 的隐私键保持原位，不迁移到 `AboutPitchee` 表，避免重复维护。

---

## 4. 两态与边界检查表

### 4.1 大字号无障碍档位（AX1–AX5）

| 区块 | 设计结论 |
|---|---|
| Hero | tagline 由 `@ScaledMetric` 缩放；description 换行；声波艺术宽度仍受 `maxWidth 430` 与容器约束；不裁切、不缩字。AX5 需真机截图确认 tagline 不出现单字成行。 |
| 故事 | 单列纵向，`fixedSize` 保证标题与正文向下扩展；eyebrow 仍是一行（短标签），不截断。 |
| 功能 | `AnyLayout` 从 HStack 切到 VStack；图标/编号在上，标题/说明在下；行高随内容增长；不设 `lineLimit`。 |
| 技术 | 同行式结构，同一 `AnyLayout`；三条说明更长，AX5 下可能占 4–6 行，允许；不裁切。 |
| 隐私 | `AnyLayout` 切 VStack；图标在上、文本在下；卡片左右 16 内边距保持；说明换行。 |
| 社区 | 行本身就是纵向两行文字，AX 下不需要换布局；标题/说明换行，行高增长；右侧箭头保持可见；三个入口仍可整行点击。 |
| 页脚 | 两行 `caption` 允许换行；不缩放、不截断；居中改为自然换行仍居中。 |

### 4.2 深色模式

| 元素 | 设计结论 |
|---|---|
| 页面背景 | 沿用 `AppThemeBackground` + 系统背景叠加（`AboutPitcheeView.swift:41-49`）；深色叠加 0.22，浅色 0.55，保持现状。 |
| 文字 | `primaryText` / `secondaryText` / `tertiary` 全部取 `dashboardPalette(for: .dark)` 的值；不写死 hex。 |
| 卡片 | `palette.surface` 深色为半透明深色；卡片下是主题背景，层次可见；Reduce Transparency 时换 `secondarySystemGroupedBackground`。 |
| 分割线 | `accent.opacity(0.08)` 在深色下仍可见但不刺眼；不额外加白色描边。 |
| 强调色 | `palette.accent` 深色值独立；链接箭头用 `tertiary`，不靠 accent 单独区分。 |

### 4.3 VoiceOver 阅读顺序与每行标签

| 顺序 | 元素 | 读法 / 处理 |
|---|---|---|
| 1 | 品牌标记 | 图片 `accessibilityHidden(true)`（`:60`）；只读 “Pitchee” |
| 2 | 声波艺术 | 按钮，label「声波互动」，hint「播放一段视觉声波动效。」；读作按钮 |
| 3 | tagline | 标题（`.isHeader`），读「让声音，更像你。」 |
| 4 | description | 普通文本，读「认识自己的声音，也找到自己的节奏。」 |
| 5 | 故事 eyebrow / 标题 / 正文 | 顺序阅读；标题带 header trait；正文独立 |
| 6 | 功能每行 | 图标与编号隐藏；标题（header）+ 说明；建议每行 `.accessibilityElement(children: .combine)`，读成「看见声音，从音高到频谱……」一次，减少 3×2 次滑动 |
| 7 | 技术 section | eyebrow 普通文本 → 标题（header）→ 三行同功能区合并 |
| 8 | 隐私卡片 | 图标隐藏；标题（header）+ 副标题 + 说明合并为一个元素，读「隐私说明，只在设备上分析，声音分析在本机完成……」。若合并后过长，可保留标题独立、正文合并 |
| 9 | 社区 section | eyebrow → 标题（header）→ 每行一个 `Link`，label 为「标题，说明」，系统追加「链接」；不读图标和箭头 |
| 10 | 页脚 | 两行合并为一个元素，读「Pitchee 1.0 (1)，PitcheeCore 0.5.0 (5831e3c)」 |

补充：

- 所有装饰图标（功能/技术/隐私左侧图标、社区左侧图标、外链箭头、Hero 竖线、分割线）加 `accessibilityHidden(true)`；现有代码已隐藏功能图标、编号和竖线（`:60`、`:196`、`:88`），新增元素照做。
- 社区每行的 label 用标题 + 说明，不用「点击这里」；`Link` 自带 link trait，不重复加 hint。
- 隐私与社区卡片合并元素时，保持标题的 header trait 优先；如果 SwiftUI 合并后丢失 header trait，可在外层加 `.accessibilityAddTraits(.isHeader)` 到标题所在的合并元素上。

### 4.4 QQ 行空 / 非空两态

| 状态 | 触发条件 | 布局 | 无障碍 / 测试 |
|---|---|---|---|
| 非空 | 群号常量非空 | 三行：GitHub → Discord → QQ；QQ 行显示「加入 QQ 群 / 群号 {群号}」；三条分割线（GitHub/Discord、Discord/QQ） | VoiceOver 读到三个链接；identifier `about.pitchee.qq` 存在 |
| 空 | 群号常量为空 | 两行：GitHub → Discord；QQ 行与其上方分割线都不渲染；容器高度自然缩短；区块底部 42 不变 | VoiceOver 只读两个链接；identifier `about.pitchee.qq` 不存在；不出现空行、禁用态或「敬请期待」占位 |

设计稿不写具体群号；`community.qq.detail` 的 `%@` 是占位符。若 Ryo 确认使用外部海报上的 957130533，再把它写入实现常量并补一条真实值截图；在此之前，设计以两态为准。

### 4.5 长文本语言（以德语为例）

| 位置 | 风险 | 策略 |
|---|---|---|
| Hero tagline | 德语 “Deine Stimme. Ganz du.” 比英文短，无风险；其他语言可能更长 | 允许换行，`fixedSize`，不缩字 |
| 故事标题 | 德语 “Du musst niemand anderes werden.” 可能三行 | 允许三行，不做 `lineLimit`；标题不截断 |
| 功能/技术行标题 | 德语 “Verfolge Veränderungen” 等较长 | 标题不设 `lineLimit`，可两行；说明可三行；行高增长 |
| Section 标题 | “Open source and community” / 德语 “Open Source und Community” 较长 | `title2` 允许两行；header 竖排间距 18 保持；不与下一行重叠 |
| 社区行标题 | “Der QQ-Gruppe beitreten” 较长；`Join the QQ Group` 中等 | 标题两行上限不设；说明 `caption` 可两行；右侧箭头固定，不挤压文本（文本列 `.frame(maxWidth: .infinity, alignment: .leading)`） |
| 页脚 | 版本号是 verbatim，不本地化；语言无关 | 不截断；两行可换行 |
| 中文 | 不使用斜体；正文左对齐；行距 7/4 保持 | 符合 guizang 中文排版规则 |

结论：全页不使用 `lineLimit(1)`；只有版本号是固定 chrome。德语、俄语等长文本通过「允许换行 + 行高增长 + 不缩字」处理，必要时在实现后用德语截图复核社区三行与 section 标题。

### 4.6 其他边界

| 项 | 设计结论 |
|---|---|
| Reduce Motion | 声波艺术暂停并固定时间 0（现状）；新增区块无动效；页面转场为系统 push。 |
| Reduce Transparency | 隐私卡片、社区容器改用 `secondarySystemGroupedBackground`；社区入口现有回退保留（`:164-166`）。 |
| Increase Contrast | `dashboardPalette(for:contrast:)` 提供高对比 palette；分割线仍用 accent 0.08，必要时在实现时提高到 0.12，但本稿不新增数值。 |
| Bold Text | 全部语义字号自动响应；不写死行高。 |
| 横屏 / iPad | 容器 `maxWidth 620` 保证行长；导航结构沿用设置页，不新增分栏。 |
| 空数据 | 本页无列表数据；QQ 空态见 §4.4；版本号缺失时 `AppVersion` 回退 “—”，页脚显示占位而非崩溃。 |
| 动态主题切换 | `@AppStorage` 主题变化时 `palette` 重新计算；卡片与图标没有缓存颜色。 |
| 录音/音频会话 | 本页不打开音频会话（文件头注释 `:3-4`）；声波艺术只是 Canvas 绘制。 |

---

## 5. 自审结论（native-ios-design review-checklist 逐条）

> 结果定义：**通过** = 设计已覆盖；**不适用** = 本页没有该类元素；**未通过** = 设计或现状不满足，写明改法或留给 Ryo 的问题。
>
> 条目编号对应 `references/review-checklist.md` 的章节与顺序。

### Native structure

| ID | 条目 | 结果 | 落到本页的说明 |
|---|---|---|---|
| N1 | 能用系统组件就用系统组件（navigation、lists、forms、menus、sheets、pickers、search） | 通过 | 页面用 `ScrollView` + `VStack` + 系统导航栏（`.navigationTitle` / `.inline`），社区入口用系统 `Link`；没有自造导航、列表或按钮组件 |
| N2 | 不自造 tab bar、导航栏或返回按钮 | 通过 | 本页没有 tab bar、没有自定义导航栏/返回按钮；返回由系统导航提供 |
| N3 | iPad 使用 sidebar / split view；内容有可读宽度 | 不适用（页面级） | 本页挂在设置页的 `NavigationStack` 内，不承担 App 级 iPad 导航结构；页面自身内容 `maxWidth 620` + 28/24 内边距，行长可读。App 是否改用 `NavigationSplitView` 是设置页/App 级决定，不在本页范围 |
| N4 | 深链、通知、widget 通过一个 router 打开正确页面 | 不适用 | 本页不是深链入口；没有新增路由 |

### Typography

| ID | 条目 | 结果 | 落到本页的说明 |
|---|---|---|---|
| T1 | 所有字体是 typography 文件里的角色；视图文本不用 `.font(.system(size:))` | **未通过（现状遗留）** | Hero tagline 用 `.font(.system(size: headlineSize, weight: .bold, design: .rounded))`（`AboutPitcheeView.swift:72`），`headlineSize` 是 `@ScaledMetric` 基准 42。它随 Dynamic Type 缩放，但不是语义角色。**改法 A（严格合规）**：改成 `.largeTitle.weight(.bold).design(.rounded)`，字号从 42 降到 34，Hero 展示感变弱；**改法 B（保 identity）**：保留现状，在 design system 里登记一个展示型字号 token。留给 Ryo 裁（§6 问题 5） |
| T2 | 阅读文本不低于 Caption 1；不用 Ultralight/Thin/Light | 通过 | 所有阅读文本最低 `caption`（eyebrow/说明/页脚）；没有 Light 文本。功能/技术/隐私图标用 light 字重，但它们是装饰图标且 `accessibilityHidden`，不是阅读文本 |
| T3 | AX5 下不裁切、不断词、不截断重要文本 | 通过（设计约束） | 全页无 `lineLimit(1)`；故事、功能、技术、隐私、社区说明都 `fixedSize(horizontal:false, vertical:true)`；社区行标题允许两行。实现后需 AX5 真机截图复核（特别是社区德语与 Hero tagline） |
| T4 | 行在无障碍字号下重排；`lineLimit` 在该档位解除 | 通过 | 功能/技术/隐私用 `AnyLayout` 从 HStack 切 VStack（`:185-186`）；社区行本身纵排；没有需要解除的 `lineLimit` |
| T5 | 只有 chrome 被限制；内容不被限制 | 通过 | 唯一短文本是页脚版本号（chrome）；正文、行标题、说明都不限行 |
| T6 | SF Symbols 用字号设定，与相邻文本匹配 | 通过（含现状修正） | 新增社区/隐私图标用 `title2`/`body` 语义字号；功能/技术行图标从固定 25pt 改为 `title2` light，frame 改 `minWidth 38 / minHeight 32` 以随字号增长；编号用 `caption2` monospaced，与图标同属装饰层 |
| T7 | UIKit 文本用 `preferredFont(forTextStyle:)` + `adjustsFontForContentSizeCategory` | 不适用 | 本页全部 SwiftUI，没有 UIKit 文本 |

### Liquid Glass

| ID | 条目 | 结果 | 落到本页的说明 |
|---|---|---|---|
| LG1 | Glass 只用于导航层（bars、floating controls、sheets）；内容不透明 | 通过 | 本页不使用 Liquid Glass；内容铺在主题背景上，隐私/社区卡片是 `palette.surface` 内容容器，不是玻璃 |
| LG2 | 不玻璃叠玻璃；不用材料仿玻璃 | 通过 | 没有 `.ultraThinMaterial` / `.regularMaterial` / `.glassEffect`；卡片是单一层 surface |
| LG3 | 相邻自定义 glass 共享 `GlassEffectContainer`；可点击的加 `.interactive()` | 不适用 | 本页没有自定义 glass 形状 |
| LG4 | 不残留自定义 bar 背景、sheet 背景或按钮 chrome 遮住系统玻璃 | 通过 | 没有 `toolbarBackground`、没有自定义导航栏背景；社区行是内容按钮，不是工具栏按钮 |
| LG5 | 滚动内容上的 bar 用 `safeAreaBar` 或系统 toolbar | 通过 | 本页用系统导航栏（inline），滚动内容在导航栏下由系统处理边缘效果；没有自造 bar |
| LG6 | Sheet 用 `Button(role: .close)` 关闭 | 不适用 | 本页没有 sheet |

### Color

| ID | 条目 | 结果 | 落到本页的说明 |
|---|---|---|---|
| C1 | 颜色是系统色或能适配深色模式的有名角色 | 通过 | 全部用 `AppThemePalette` 的 `primaryText/secondaryText/accent/tertiary/surface`；分割线用 `accent.opacity(0.08)`；无新 hex |
| C2 | 文本对比度 ≥ 4.5:1（大字/粗体 ≥ 3:1），两种外观都检查 | 通过（待实测） | 正文用 `secondaryText`，与现有页面同角色；实现后需用 Accessibility Inspector 在浅/深、标准/高对比下抽查故事正文、技术说明、社区说明、页脚 |
| C3 | 含义不只靠颜色；链接有下划线或非颜色提示 | 通过 | 社区行有外链箭头 + `Link` 语义 + 标题；分割线只是装饰；功能编号不承载唯一含义 |
| C4 | identity 色在深色模式仍可见 | 通过 | `accent` 在深色 palette 中有独立值；图标/编号/分割线都用同一角色，不写死浅色值 |

### Interaction

| ID | 条目 | 结果 | 落到本页的说明 |
|---|---|---|---|
| I1 | 命中区 ≥ 44×44 | 通过 | 社区行 `minHeight 48` + 整行 `contentShape`；声波艺术是大尺寸按钮；页脚不可点击 |
| I2 | 破坏性操作要确认并说明丢失什么 | 不适用 | 本页没有破坏性操作 |
| I3 | 手势有可见/菜单替代，并有 accessibility action | 通过 | 本页唯一手势是点击声波艺术（有按钮语义）；没有滑动/拖拽/长按手势 |
| I4 | 键盘：点内容收起、滚动不收起、聚焦不跳滚动 | 不适用 | 本页没有文本输入/键盘 |
| I5 | Web 链接在应用内打开 | 不适用（有理由） | GitHub/Discord/QQ 是社区入口，按系统行为交给 Safari / Discord / QQ 打开；强行用 `SFSafariViewController` 会破坏跨 App 跳转，也不是「站内阅读链接」场景 |

### Accessibility

| ID | 条目 | 结果 | 落到本页的说明 |
|---|---|---|---|
| A1 | 纯图标控件有命名其动作的 label | 通过 | 声波艺术有 label/hint；其他图标都是装饰并隐藏；社区行标题即动作名 |
| A2 | 复合行读成一个元素，有有用的 label 和 value | 通过 | 功能/技术/隐私/社区/页脚都设计为合并朗读；标题/说明顺序见 §4.3；没有 value 型复合行（版本号不是控件） |
| A3 | 自定义 picker 是可调节元素 | 不适用 | 本页没有 picker |
| A4 | Reduce Motion 去掉装饰动效 | 通过 | 声波艺术在 Reduce Motion 下暂停且时间固定 0（`:230-231`）；新增区块无动效 |
| A5 | Bold Text、Increase Contrast、Reduce Transparency 下可用 | 通过（待实测） | 语义字号响应 Bold Text；`dashboardPalette(for:contrast:)` 响应 Increase Contrast；卡片与社区容器在 Reduce Transparency 下回退系统背景；实现后需三项各截图一次 |

### Performance

| ID | 条目 | 结果 | 落到本页的说明 |
|---|---|---|---|
| P1 | 长列表 lazy、稳定 ID、行内不用 AnyView | 不适用 | 本页是短静态页，没有长列表；没有 `AnyView` 行 |
| P2 | 不因滚动/几何每帧更新状态 | 通过 | 声波艺术只在可见时 30fps 重绘（`:230`、`:251-254`）；滚动本身不驱动状态；没有 `GeometryReader` 驱动的逐帧写入 |
| P3 | 图片降采样；附件存文件 | 通过 | 只用一个 28×28 的 App 标记（`Image("Default")`），没有大图/附件；声波艺术是 Canvas 绘制 |
| P4 | 异步工作放 `.task(id:)` | 不适用 | 本页没有异步加载/网络请求 |
| P5 | 真机滚动流畅 | 通过（设计约束，待真机） | 新增区块是静态 `Text`/`Link`，不引入滚动期重绘；实现后需在真机滚动一遍确认 |

### Writing

| ID | 条目 | 结果 | 落到本页的说明 |
|---|---|---|---|
| W1 | 按钮和菜单项用 title-case 动词 | 通过 | 英文按钮：View on GitHub / Join Discord / Join the QQ Group；中文「查看 GitHub 项目 / 加入 Discord / 加入 QQ 群」是动词开头 |
| W2 | 页脚和 alert 是短句，说清发生什么 | 通过 | 隐私说明是两短句；社区说明是短句；页脚是版本文本，不写宣传句 |
| W3 | 空状态说明下一步做什么 | 不适用 | 本页没有列表空状态；QQ 空态是整行隐藏，不展示空状态文案 |

### 自审汇总

| 结果 | 数量 | 条目 |
|---|---|---|
| 通过 | 26 | N1–N2、T2–T6、LG1–LG2、LG4–LG5、C1–C4、I1、I3、A1–A2、A4–A5、P2–P3、P5、W1–W2 |
| 不适用 | 12 | N3（页面级）、N4、T7、LG3、LG6、I2、I4、I5、A3、P1、P4、W3（其中 I5 为「有理由不适用」，P1/P4 为无该类工作） |
| 未通过 | 1 | T1（Hero tagline 非语义字号；现状遗留，改法见上，待 Ryo 裁） |

> 计数说明：上表「通过 26 / 不适用 12 / 未通过 1」合计 39 条；T1 是唯一未通过项，且不是本次新增设计造成的，是现有 Hero 的遗留。

---

## 6. 留给 Ryo 裁的问题

第二步按「更安静、去 AI 味」的最小改动口径处理如下，后续仍可推翻：

1. 键名不追主任务书；实际只新增 `link.github.title` / `link.discord.title` / `link.qq.title` 三个键，隐私文案复用 `Localizable.xcstrings` 现有键。
2. QQ 不写群号，沿用仓库现有的邀请链接 `https://qm.qq.com/q/w0pvVpKEyy`。
3. 隐私只复用 `voiceProfile.privacyPromise.onDevice.*` 两键，不新增「不追踪 / 不收集数据」。
4. 功能块不加 section 标题，保持承接故事。
5. Hero tagline 保留 `@ScaledMetric 42`；T1 仍未通过，作为品牌字号接受。
6. 页脚只显示 App 版本（`Pitchee 1.0 (1)`）；Core 版本不进入关于页，设置页硬编码未动。
7. 社区入口不用品牌图标，也不用 SF Symbol 图标块，只保留文字与 `arrow.up.right`。
8. 故事标题保留「你不必成为／另一个人。」，`story.body` 的中文已改为「更接近自己的声音」。

### 6.1 原始问题记录（第一步）

1. **主任务书缺失**：`about-page-redesign-task-2026-11-08.md` 本机不存在，本稿的 `tech.*` / `community.*` 键名与逐键处置是按任务书命名空间和仓库现状推的，不是主任务书原文。请确认键名映射，或把主任务书补到仓库/Downloads 后再对一遍。
2. **QQ 群号**：仓库内没有群号；外部队列海报上有 `957130533`，未在仓库核实。本稿按「空 → 整行隐藏」设计，不写死数字。请确认是否使用该群号、以及是否允许在关于页展示。
3. **隐私块文案来源**：本稿复用 `Localizable.xcstrings` 的 `voiceProfile.privacyPromise.*` 三键（29 个本地化已有值），没有新增 `privacy.*`。若希望在关于页单独强调「不追踪、不收集数据」，需要新增键；请确认是复用还是新增。
4. **功能块是否加 section 标题**：现设计保持功能块无标题（承接故事），技术/社区有标题。若希望三块都有标题，需要新增 `feature.eyebrow` / `feature.title` 两个键，并调整版面节奏。
5. **Hero tagline 字号**：保留 `@ScaledMetric 42` 的展示型字号（T1 未通过，但 identity 更强），还是改成 `.largeTitle`（T1 通过，但视觉变小）？这是唯一一条自审未通过项。
6. **页脚 Core 版本**：显示 `PitcheeCore 0.5.0 (5831e3c)`、只显示 commit、还是只显示 App 版本？以及是否把设置页的硬编码 `"PitcheeCore (5831e3c)"` 与关于页统一到一个 `CoreVersion` 来源（或改用 `pitchee_version()`）。
7. **社区图标档位**：本稿选 SF Symbols（`chevron.left.forwardslash.chevron.right` / `bubble.left.and.bubble.right` / `person.3`），因为仓库没有品牌资产、任务书禁止外部素材。若 Ryo 有授权的 GitHub/Discord/QQ 品牌图标并愿意入库，可换第二档，但需要新增 assets 与授权说明。
8. **故事标题**：保留「你不必成为／另一个人。」（品牌身份句），还是改成更陈述式的备选「每一种声音，都有自己的样子。」？若改，`story.body` 首句需要同步调整避免重复。

---

## 7. 实现与截图对照

> 实现已完成。截图在本地 `.build/about-dark6-attachments/`（深色）、`.build/about-ax2-attachments/`（无障碍大字号）；截图测试脚手架与强制深色开关在验收后已还原，不进入提交。

| 区块 | 设计稿（本文件对应节） | 实现 | 差异 / 处理 |
|---|---|---|---|
| Hero | §2.1 | 原样保留：品牌标记、声波雕塑、`@ScaledMetric 42` tagline、渐变竖线 | 无改动 |
| 故事 | §2.2 | 原样保留 eyebrow、标题与正文 | `story.body` 中文改为「让每一次练习都更接近自己的声音。」，与英文语义对齐；29 个语言仍完整 |
| 功能 | §2.3 | 原样保留 `AboutStoryRow` 01–03 与细线分隔 | 无改动 |
| 技术与工程 | §2.4 | **未实现** | 去掉规格表、ONNX / 模型数量等参数化文案；这些内容读起来像产品规格页，也是「AI 味」最重的一块 |
| 隐私 | §2.5 | 「只在设备上分析」+ 一段正文，无卡片、无图标 | 复用 `Localizable.xcstrings` 的 `voiceProfile.privacyPromise.onDevice.*`，不新增键 |
| 开源与社区 | §2.6 | 三行细线入口：GitHub / Discord / QQ，右侧 `arrow.up.right` | 不用图标块或品牌图标；QQ 沿用现有邀请链接，不写群号 |
| 页脚 | §2.7 | 单行 `Pitchee 1.0 (1)` | 不显示 Core 版本，不做双行落款 |
| 全页 | §1.2 | 仍为 620 宽、28/24 边距、42 区块间距、单一 accent、无卡片堆叠 | 新增块与原有节奏一致 |

验证记录：

- 常规字号、简体中文：`about-light` / 最终 `about-verify`，排版、换行、底部触底正常。
- 无障碍大字号（Accessibility L）：`about-ax2`，功能行切换为纵向布局，隐私、社区、页脚均可达，链接行高与命中区正常。
- 深色：本机 iOS 27.2 模拟器的 `simctl ui appearance` 与 `XCUIDevice.appearance` 都未能让系统 App 变色（连系统设置都保持浅色），因此截图时用 DEBUG 启动参数强制 `.preferredColorScheme(.dark)`，确认深色调色板、分隔线和页脚对比正常；该开关已还原。
- 本地化：`Scripts/validate-localizations.py` 通过，714 个键、20,783 个字符串单元、947 个格式化单元，29 个语言完整。
- UI 测试：关于页截图测试通过；未改产品逻辑。

---

## 附录 A：事实清单与出处

| 事实 | 出处 |
|---|---|
| 关于页现有顺序：hero → story → features → communityLinks | `PitcheeApp/App/AboutPitcheeView.swift:24-29` |
| 页面容器 maxWidth 620、水平 28/24、底部 28 | `AboutPitcheeView.swift:30-32` |
| Hero 各间距（30/10/20/16/34/44） | `AboutPitcheeView.swift:65,68-69,77,84,90,93` |
| 故事 VStack spacing 18、标题 largeTitle、正文 body lineSpacing 7、底部 42 | `AboutPitcheeView.swift:97,104-112,116` |
| 功能行上下 26、HStack 22、AX VStack 18、文本间距 10、图标 25/38×32、编号 caption2 | `AboutPitcheeView.swift:186,185,198,190-193,211` |
| 分割线 accent 0.08 | `AboutPitcheeView.swift:122,124` |
| 社区入口现有布局与 Link 实现 | `AboutPitcheeView.swift:133-173` |
| 社区链接 URL：GitHub / QQ / Discord | `AboutPitcheeView.swift:139-145` |
| 声波动效暂停条件、30fps、脉冲、sensoryFeedback | `AboutPitcheeView.swift:230,235-243,246,251-254` |
| 主题角色 `AppThemePalette`（primaryText/secondaryText/accent/secondary/tertiary/surface/glass） | `PitcheeApp/App/AppTheme.swift:157`；palette 取值 `:47-155` |
| `AppVersion` 从 Bundle 读版本，格式 `1.0 (1)` | `PitcheeApp/App/SettingsView.swift:11-25,43-45` |
| App 版本在设置页显示 | `SettingsView.swift:107-111` |
| Core 版本在设置页硬编码 `"PitcheeCore (5831e3c)"` | `SettingsView.swift:112` |
| Core 子模块提交 `5831e3cca1dde8416d0cf0c971c7ff0935fa2c1c` | `git submodule status` |
| `pitchee_version()` 声明 / 返回 `"0.5.0"` | `Dependencies/PitcheeCore/include/pitchee/pitchee.h:194`、`Dependencies/PitcheeCore/src/analyzer.cpp:483` |
| Core 是 C++17 跨平台库，输出 F0、自然度、音色、HNR、声音健康度等 | `Dependencies/PitcheeCore/README.md:3-20` |
| 6 个 ONNX 模型（ECAPA、ECAPAFrontend、SileroVAD、SwiftF0、VFPHead、Naturalness） | `Dependencies/PitcheeCore/models/manifest.json` |
| ONNX Runtime 1.24.2 | `Dependencies/PitcheeCore/README.md:20-27`；`Scripts/bootstrap-native-dependencies.sh:7` |
| Core 输出结构含 `hnr_db`、`f0_median`、`cpps_db` 等 | `Dependencies/PitcheeCore/include/pitchee/pitchee.h:114-137` |
| `formant` / `共振峰` 不在 Core include/src；仅在 VoiceTrainingLibrary 参考文献标题 | 全仓搜索：`PitcheeCore/include`、`src` 0 命中；`Resources/VoiceTrainingLibrary/voice-training-library.json:124,127,246,249` |
| 隐私清单：不追踪、不收集数据、仅 UserDefaults 与 SystemBootTime API | `Resources/PrivacyInfo.xcprivacy` |
| 根许可证 GPL-3.0 | `LICENSE.txt:1-3` |
| 29 个本地化；源语言 en；17 个 About 键 | `Resources/AboutPitchee.xcstrings`（JSON 清点） |
| 隐私三键 29 个本地化全有值 | `Resources/Localizable.xcstrings`（JSON 清点） |
| 仓库没有 GitHub/Discord/QQ 品牌 imageset | `Resources/Assets.xcassets` 仅有 8 个 App 图标 imageset |
| 关于页不打开音频会话 | `AboutPitcheeView.swift:3-4`（文件头注释） |

## 附录 B：本稿未做 / 未核实

- 未写/改任何 Swift 代码，未改 `AboutPitchee.xcstrings` 或 `Localizable.xcstrings`。
- 未构建、未运行模拟器、未截图；所有大字号/深色结论是设计约束，需第二步实现后实测。
- 未读取主任务书（不存在），未核对其 §1 事实清单、§2 逐键处置、§3.3 图标优先级。
- 未核实外部 QQ 海报的群号；未使用任何用户量、准确率、精度数字。
- 未使用 Bezel 或外部素材；未引入品牌图标资产。
- `apple-design` 是本机未安装、从上游读取的原文，不是本机已装技能；`dsh-guizang-design` 的 `guizang_voice` 语气档案未接通。
