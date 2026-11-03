# drawio v32.6.9（静态副本）

静态版 drawio，用于第 31 课"企业网络架构图"任务，让学生无需安装任何软件即可在浏览器里画图。

- 原始来源：https://github.com/jgraph/drawio/releases/tag/v32.6.9（`draw.war`）
- 已剔除 Java 后端部分（`WEB-INF/`、`META-INF/`），只保留纯前端资源
- 许可：Apache 2.0（见 drawio 原仓库 LICENSE）

## 使用方式

- 直接访问：https://0xleir.github.io/win-server-course-slides/drawio/?offline=1&lang=zh
- 本地运行：`cd drawio && python3 -m http.server 8080`

## 关键参数

- `offline=1`：禁用所有外部存储（Google Drive 等），完全离线
- `lang=zh`：中文界面
- `nav=1`：显示左侧导航栏（画完的图可以保存成多页）

## 学生工作流

1. 浏览器打开上面的 URL（无需登录任何账号）
2. 新建空白图 → 画架构图（主机、网段、箭头）
3. `文件 → 另存为`：保存为 `.drawio` 文件下载到本地
4. `文件 → 导出为 → PDF` 导出 PDF（走浏览器打印，无需服务端）
5. PDF 和 .drawio 文件一并提交作业

## 更新方式

```bash
# 新版下载并替换（从 jgraph/drawio GitHub Release）
cd ~/win-course-tools/drawio
rm -rf *
curl -L -o draw.war https://github.com/jgraph/drawio/releases/latest/download/draw.war
unzip -q draw.war && rm draw.war

# 同步到仓库
rsync -av --delete --exclude='WEB-INF' --exclude='META-INF' \
  ~/win-course-tools/drawio/ \
  ~/codes/win-server-course-slides/drawio/
```
