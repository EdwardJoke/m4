# m4

<p align="center">
  <a href="README.md">English</a> | <a href="README_ZH.md">中文</a>
</p>

> 一门静态类型、缩进敏感、AI 原生的脚本语言，专注于确定性语法、低内存占用、快速执行和可靠的 LLM 代码生成。

m4 是一门用 Zig 实现的极简脚本语言，包含手写词法分析器、递归下降 Pratt 解析器、单通道字节码编译器、类型检查器和基于寄存器的虚拟机。它从头设计就是为了低 token 用量、规范格式化和高 LLM 生成可靠性。

## 特性

- **静态类型** — 编译时类型检查，具有丰富的类型系统（基本类型、泛型、Option/Result 类型）
- **缩进敏感** — 无花括号、无分号；通过缩进定义代码块（类似 Python）
- **基于寄存器的虚拟机** — 启动快、内存开销低、可移植执行
- **单通道字节码编译器** — 从 AST 直接编译为字节码，仅需一次遍历
- **Pratt 解析器** — 清晰、可扩展的表达式解析，支持运算符优先级
- **REPL** — 交互式模式，便于快速实验
- **规范格式化** — 每个结构只有一种确定的输出风格
- **仅 15 个关键字** — 最小语法，最小语法熵
- **基于 Result 的错误处理** — `res[T E]` 类型配合 `?` 传播运算符
- **结构化错误输出** — 支持 ZON、JSON 或 YAML 格式的诊断信息
- **32 个错误码** — 通过 `m4 explain <code>` 提供可读的诊断说明
- **彩色错误输出** — `--pretty` 标志提供终端友好的彩色诊断

## 快速开始

### 前置条件

- [Zig](https://ziglang.org/download/) 0.16.0 或更高版本

### 构建

```sh
zig build
```

二进制文件位于 `zig-out/bin/m4`。

### 运行

```sh
# 启动 REPL
zig build run

# 运行文件
zig build run -- hello.m4

# 从标准输入运行
echo 'std.println(42)' | zig build run -- -

# 或者构建后直接使用二进制文件
zig build
./zig-out/bin/m4 hello.m4
```

## CLI

```
m4 v0.3.2 — 静态类型、AI 原生脚本语言

用法：
  m4 [flags] <file.m4>          运行文件
  m4 [flags] -                  从标准输入运行
  m4                            启动 REPL

命令：
  m4 help [--zon|--json|--yaml]    显示帮助信息
  m4 version [--zon|--json|--yaml] 显示版本
  m4 lint <file.m4>                仅进行解析和类型检查
  m4 build <file.m4> [opts]        编译为本地二进制文件
  m4 explain <code>                解释错误码的含义

使用 'm4 <command> help' 查看命令特定帮助（例如 'm4 lint help --zon'）。

标志：
  -d, --debug                    执行前显示字节码
  -f, --format                   格式化源代码并打印
  -p, --pretty                   彩色错误输出，便于终端阅读
  --native                       发射 QBE IR 而非通过字节码 VM 运行
  --zon, --json, --yaml           结构化错误输出格式

  -o, --output <path>            输出二进制路径（仅用于 build，默认为 <file>.out）
  --target <arch>                构建的目标架构（amd64_apple, arm64_apple, arm64, amd64_sysv, rv64）
```

## 语言概述

### 关键字（共 15 个）

| 关键字      | 用途             |
| ----------- | ---------------- |
| `let`       | 不可变变量       |
| `mut`       | 可变变量         |
| `fun`       | 函数声明         |
| `pub`       | 公开声明         |
| `if`        | 条件语句         |
| `elif`      | 替代条件         |
| `else`      | 回退条件         |
| `loop`      | 无限循环         |
| `for`       | 迭代             |
| `continue`  | 继续循环         |
| `esc`       | 退出循环         |
| `ret`       | 返回值           |
| `nil`       | 空值             |
| `use`       | 模块导入         |
| `type`      | 类型声明         |

### 示例程序

```m4
use std

type User
    name str
    age  i32

fun greet(u User)
    std.println("hello " + u.name)

pub fun main()
    let user User = User(
        name: "edward"
        age: 20
    )

    greet(user)

    for n in [1, 2, 3]
        std.println(n)
```

### 变量

```m4
let x i32 = 10          # 不可变，带类型注解
mut counter i32 = 0     # 可变
let pi = 3.14           # 类型推断
```

### 函数

```m4
fun add(a i32, b i32) i32
    ret a + b
```

### 控制流

```m4
if score > 90
    grade = "A"
elif score > 80
    grade = "B"
else
    grade = "C"

loop
    tick()

for item in items
    print(item)
```

### 类型

**基本类型：** `i8 i16 i32 i64 u8 u16 u32 u64 f32 f64 bool char str bytes`

**容器类型：** `vec[T] map[K V] opt[T] res[T E]`

## 项目结构

```
src/
├── main.zig          — 入口点
├── cli.zig           — CLI 标志解析、REPL、文件执行
├── cli_info.zig      — CLI 帮助/版本元数据类型
├── scanner.zig       — 手写词法分析器，支持缩进跟踪
├── token.zig         — Token 类型和关键字定义
├── ast.zig           — AST 节点定义和 arena 分配器
├── parser.zig        — 递归下降 Pratt 解析器
├── compiler.zig      — 单通道字节码编译器
├── vm.zig            — 基于寄存器的虚拟机
├── opcode.zig        — 字节码指令编码/解码
├── chunk.zig         — 字节码块（代码 + 常量 + 行信息）
├── value.zig         — 运行时值表示
├── object.zig        — 堆分配对象（函数、结构体、向量）
├── type.zig          — 类型系统定义
├── type_check.zig    — 类型检查器，基于作用域链环境
├── fmt.zig           — 规范化 AST 美化打印
├── debug.zig         — 字节码反汇编器
├── error.zig         — 结构化诊断系统（ZON/JSON/YAML）
├── root.zig          — 模块根，重新导出公开声明
├── qbe.zig           — QBE IR 发射器，用于本地编译
├── qbe_build.zig     — QBE 本地二进制构建流水线
├── runtime/
│   ├── m4rt.c       — 本地编译程序的最小 C 运行时
│   ├── m4rt.h       — 运行时头文件，包含类型定义
│   ├── qbe_wrap.c   — QBE C API 包装器
│   └── qbe_wrap.h   — QBE 包装器头文件
└── stdlib/
    ├── std.zig      — 核心标准库（println, print, readln, read, readChar, range）
    ├── thread.zig   — 线程原语（spawn, join, channel, send, recv）
    ├── range.zig    — 数值范围生成器
    ├── fs.zig       — 文件系统（read, write, exists, delete）
    └── str.zig      — 字符串工具（len, slice）
```

## 状态

m4 处于**早期开发阶段**（v0.3.2）。核心流水线（扫描 → 解析 → 类型检查 → 编译 → 执行）功能完整，并具备 QBE 本地编译后端。预计会有重大变化和新增功能。

### 已实现
- 扫描器、解析器、AST、编译器、虚拟机、类型检查器
- REPL 和文件执行
- 整数、浮点数、布尔值、字符串、nil、字符
- 变量（`let`, `mut`）、函数（`fun`）、条件语句（`if`/`elif`/`else`）
- 循环（`loop`, `for`）、循环控制（`continue`, `esc`）
- 字符串拼接、比较、索引、长度
- 算术、比较、逻辑运算符
- `std.println` / `std.print` / `std.readln` / `std.read` / `std.readChar` / `std.range`
- `thread.spawn` / `thread.join` / 通道
- `range.range` — 数值范围生成器
- `fs.read` / `fs.write` / `fs.exists` / `fs.delete` — 文件系统
- `str.len` / `str.slice` — 字符串工具
- 带命名字段的结构体字面量
- 向量（列表字面量、索引、迭代）
- 使用 `?` 进行错误传播
- 规范格式化器
- 字节码反汇编器
- 结构化诊断（ZON, JSON, YAML）
- 32 个错误码，支持 `m4 explain <code>`
- 彩色错误输出（`--pretty` / `-p`）
- 所有公开 Zig API 函数的文档字符串
- QBE 后端：IR 发射器和本地二进制流水线（开发中）
- 与 Python/TypeScript 的基准测试对比

### 尚未实现
- 完整标准库（`net`, `json`, `time` 等）
- Result 类型运行时支持
- 除 `std` / `thread` / `range` / `fs` / `str` 以外的模块
- 类型错误的源代码位置
- 标准输入/文件模式下的自动注册 `std` 模块
- Cranelift JIT 后端
- 轻量级所有权内存模型
- 包管理器

## 许可证

MIT

## 致谢

本项目建设于开源项目之上：

感谢 [QBE](https://c9x.me/compile/) 编译器后端。

感谢 [Zig](https://ziglang.org/)。

感谢 [serde.zig](https://github.com/OrlovEvgeny/serde.zig)。
