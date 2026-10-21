# Mouse Scroll Flip

Menu-bar app for macOS. With **Natural scrolling left on**, the trackpad and Magic Mouse keep natural scrolling. A normal mouse wheel is reversed so it scrolls like Windows.

[Download the latest release](https://github.com/yerled/mouse-scroll-flip/releases/latest) (universal binary, Apple Silicon and Intel, macOS 13 or later).

The download is **ad-hoc signed**. No paid Apple Developer account is used. macOS quarantines that file. The install steps below are the way to open it.

## Install

1. Download `MouseScrollFlip-*-macOS.dmg` (or the `.zip`) from [Releases](https://github.com/yerled/mouse-scroll-flip/releases).
2. Open the disk image and drag **Mouse Scroll Flip** to **Applications**.
3. macOS will refuse a normal double-click. Do one of these:
   - In Finder, **right-click** (or Control-click) the app, choose **Open**, then choose **Open** again.
   - Or clear the quarantine flag in Terminal:

     ```sh
     xattr -dr com.apple.quarantine "/Applications/Mouse Scroll Flip.app"
     ```

     Use this if macOS says the app is damaged or from an unidentified developer. That message is Gatekeeper reacting to the download, not a broken file.
4. A mouse icon appears in the menu bar. There is no Dock icon.
5. Allow **Accessibility** when macOS asks. You can also use the menu item **Open Accessibility Settings…** (System Settings → Privacy & Security → Accessibility) and turn on **Mouse Scroll Flip**.
6. Leave **Natural scrolling** on: System Settings → Mouse, and System Settings → Trackpad.

Granting Accessibility is picked up while the app is running. You do not need to log out. Quit and reopen only if the menu still says the permission is missing after you turned it on.

Launch at login uses `SMAppService`. macOS may ask you to approve the app under **System Settings → General → Login Items & Extensions**. Keep the app in Applications. Moving it later breaks the login item.

## Menu

| Item | What it does |
| --- | --- |
| Reverse mouse wheel | Turns the fix on or off. On by default. The choice is remembered. |
| Also reverse horizontal | Also flips a sideways tilt-wheel. Off by default. |
| Launch at Login | Opens the app when you log in. |
| Open Accessibility Settings… | Shown when the event tap is not allowed yet. |
| Quit | Stops flipping. The wheel goes back to plain macOS behavior. |

Run one copy. A second copy would flip the wheel twice and put it back where it started.

## How it works

The app installs a `CGEvent` tap on scroll-wheel events (`CGEvent.tapCreate`, session tap, head insert). The callback looks at three fields and changes nothing else:

| Field | Discrete mouse wheel | Trackpad or Magic Mouse |
| --- | --- | --- |
| `scrollWheelEventIsContinuous` (field 88) | `0` | `1` |
| `scrollWheelEventScrollPhase` (field 99) | `0` | began / changed / ended / mayBegin |
| `scrollWheelEventMomentumPhase` (field 123) | `0` | non-zero while the gesture is coasting |

An event is treated as a **mouse wheel only when all three say so**: not continuous, no gesture phase, no momentum phase. Anything else, including a Magic Mouse and a trackpad, is passed through untouched, so natural scrolling on those devices stays exactly as macOS set it.

For a wheel notch the app negates vertical axis 1. If **Also reverse horizontal** is on, it also negates axis 2. Each axis is written in this order, because setting the line delta makes the window server rewrite the other two:

1. Line delta (`scrollWheelEventDeltaAxis*`)
2. Fixed-point delta (`scrollWheelEventFixedPtDeltaAxis*`, what AppKit exposes as `scrollingDelta*`)
3. Point delta (`scrollWheelEventPointDeltaAxis*`)
4. The embedded IOHID scroll value (`kIOHIDEventFieldScrollY` / `ScrollX`)

Safari and other WebKit apps read that IOHID value, not only the Quartz deltas. The IOHID symbols are private SPI, loaded with `dlsym`. If they are missing, the public deltas are still flipped.

The tap runs on its own thread. If macOS disables it (`tapDisabledByTimeout` or `tapDisabledByUserInput`, including after sleep), the callback re-enables the port. If the port will not come back, it is thrown away and created again. A one-second timer does the same check, which is also how the app notices that Accessibility was just granted.

### Mice that still scroll the macOS way

Some mice never send a discrete notch. Logitech Options / Logi Options+ “smooth scrolling”, and similar high-resolution modes, mark the wheel as continuous. Those events look like a trackpad, so they are **not** flipped. Turning smooth scrolling off in the vendor app makes the wheel discrete, and this app will reverse it. Flipping every continuous event would also flip the Magic Mouse and the trackpad.

Holding Shift turns a vertical wheel into a horizontal one before the session tap sees it. That sideways event follows the horizontal setting.

## Build

The release workflow runs on a macOS runner: tests, a universal ad-hoc signed `.app`, a `.zip`, and a `.dmg`. Pushes to `main` upload those archives as a workflow artifact. A tag named `v*` (for example `v0.1.0`) also publishes a GitHub Release with the same files.

Local build, on a Mac with Xcode:

```sh
swift test
./scripts/build-app.sh
```

The script writes `dist/Mouse Scroll Flip.app`, `dist/MouseScrollFlip-<version>-macOS.zip`, and a `.dmg`. The deployment target is macOS 13.0. The binary contains `arm64` and `x86_64`.

---

# 鼠标滚轮翻转

macOS 菜单栏应用。**「自然滚动」保持打开**时，触控板和妙控鼠标仍然是自然滚动；普通鼠标的滚轮会被反过来，手感和 Windows 一样。

[下载最新版本](https://github.com/yerled/mouse-scroll-flip/releases/latest)（通用二进制，支持 Apple 芯片和 Intel，macOS 13 及以上）。

安装包是**临时签名（ad-hoc）**，没有使用付费的 Apple 开发者账号。macOS 会给下载的文件加上隔离标记。按下面的步骤才能打开。

## 安装

1. 从 [Releases](https://github.com/yerled/mouse-scroll-flip/releases) 下载 `MouseScrollFlip-*-macOS.dmg`（或 `.zip`）。
2. 打开磁盘映像，把 **Mouse Scroll Flip** 拖到**应用程序**文件夹。
3. 直接双击会被系统拒绝。任选一种方式打开：
   - 在访达里**按住 Control 点按**（或右键）应用，选择**打开**，再点一次**打开**。
   - 或者在终端去掉隔离标记：

     ```sh
     xattr -dr com.apple.quarantine "/Applications/Mouse Scroll Flip.app"
     ```

     如果系统提示应用已损坏，或来自身份不明的开发者，用这条命令。那是 Gatekeeper 在拦截下载，不是文件坏了。
4. 菜单栏会出现一个鼠标图标，程序坞里没有图标。
5. 按提示允许**辅助功能**。也可以用菜单里的**打开辅助功能设置…**（系统设置 → 隐私与安全性 → 辅助功能），打开 **Mouse Scroll Flip**。
6. 让**自然滚动**保持打开：系统设置 → 鼠标，以及系统设置 → 触控板。

在系统设置里打开辅助功能之后，正在运行的应用会自己开始工作，不用注销。只有菜单仍然提示缺少权限时，才需要退出后重新打开。

登录时启动用的是 `SMAppService`。macOS 可能会要求你在**系统设置 → 通用 → 登录项与扩展**里允许它。请把应用留在「应用程序」文件夹里，之后再挪位置，登录项会失效。

## 菜单

| 项目 | 作用 |
| --- | --- |
| 反转鼠标滚轮 | 开关整个功能。默认打开，选择会被记住。 |
| 同时反转水平滚动 | 连滚轮左右倾斜也反过来。默认关闭。 |
| 登录时启动 | 登录后自动打开。 |
| 打开辅助功能设置… | 事件监听还没被允许时显示。 |
| 退出 | 停止反转，滚轮恢复成 macOS 原来的方向。 |

只运行一份。开两份会把滚轮翻转两次，等于没翻。

## 工作原理

应用通过 `CGEvent.tapCreate` 在滚动事件上安装一个事件监听（session tap，插在队列最前面）。回调只看三个字段，其他事件原样放过：

| 字段 | 普通鼠标滚轮 | 触控板或妙控鼠标 |
| --- | --- | --- |
| `scrollWheelEventIsContinuous`（字段 88） | `0` | `1` |
| `scrollWheelEventScrollPhase`（字段 99） | `0` | 开始 / 变化 / 结束 / mayBegin |
| `scrollWheelEventMomentumPhase`（字段 123） | `0` | 惯性滑动时非 0 |

**三个条件同时成立**才当成鼠标滚轮：不是连续滚动、没有手势相位、没有惯性相位。其余事件（包括妙控鼠标和触控板）完全不改，所以这些设备上的自然滚动保持系统原来的样子。

对滚轮齿格，应用把垂直方向（轴 1）取反。如果打开了**同时反转水平滚动**，轴 2 也取反。每个轴按下面的顺序写回。先写行增量会让窗口服务器改掉后面两个值，所以必须再写一遍：

1. 行增量（`scrollWheelEventDeltaAxis*`）
2. 定点数增量（`scrollWheelEventFixedPtDeltaAxis*`，AppKit 的 `scrollingDelta*` 用的就是它）
3. 点增量（`scrollWheelEventPointDeltaAxis*`）
4. 嵌在事件里的 IOHID 滚动量（`kIOHIDEventFieldScrollY` / `ScrollX`）

Safari 和其他 WebKit 应用读的是这个 IOHID 值，而不只是 Quartz 的增量。IOHID 符号是私有 SPI，用 `dlsym` 加载。找不到这些符号时，公开的增量仍然会被反转。

监听跑在单独的线程上。如果 macOS 关掉了它（`tapDisabledByTimeout` 或 `tapDisabledByUserInput`，睡眠唤醒后也会发生），回调会重新启用这个端口。端口起不来就丢掉重建。另外每秒检查一次，辅助功能刚刚被打开时也是靠这次检查接上的。

### 有些鼠标还是 macOS 的方向

有些鼠标根本不发送一格一格的滚轮事件。罗技 Options / Logi Options+ 的「平滑滚动」，以及其他高分辨率模式，会把滚轮标成连续滚动。这种事件和触控板一样，**不会**被反转。在厂商软件里关掉平滑滚动，滚轮变成离散齿格后，这个应用才会反转它。如果把所有连续事件都反转，妙控鼠标和触控板也会被一起改掉。

按住 Shift 时，系统会先把垂直滚轮转成水平滚动，然后才送到 session tap。这种横向事件跟着「水平滚动」那个开关走。

## 构建

发布流程在 macOS runner 上运行：测试、通用二进制、临时签名的 `.app`、`.zip` 和 `.dmg`。推送到 `main` 时，这些压缩包会作为 workflow artifact 上传。名为 `v*` 的标签（例如 `v0.1.0`）还会附带这些文件发布 GitHub Release。

在装有 Xcode 的 Mac 上本地构建：

```sh
swift test
./scripts/build-app.sh
```

脚本会生成 `dist/Mouse Scroll Flip.app`、`dist/MouseScrollFlip-<版本>-macOS.zip` 和 `.dmg`。部署目标是 macOS 13.0，二进制同时包含 `arm64` 和 `x86_64`。
