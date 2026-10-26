#!/usr/bin/env python3
"""make_index.py — 从 lessonNN.html 自动生成课件目录页 index.html（仅已上完的课次）。
    python3 make_index.py
"""
import re, html, os

HERE = os.path.dirname(os.path.abspath(__file__))
DOWNLOADS = os.path.join(HERE, "downloads")

GROUPS = [
    ("基础模块", "项目 1 · 走进 Windows 服务器", [1, 2]),
    ("基础模块", "项目 2 · Windows 服务器用户管理", [3, 4, 5]),
    ("基础模块", "项目 3 · Windows 服务器共享管理", [6, 7]),
    ("阶段考核", "阶段考核 1 · 基础模块", [8]),
    ("进阶模块", "项目 4 · Windows 服务器网站管理", [9, 10, 11, 12]),
    ("阶段考核", "阶段考核 2 · 进阶模块 A", [13]),
    ("进阶模块", "项目 5 · Windows 服务器远程管理", [14, 15, 16]),
    ("进阶模块", "项目 6 · Windows 服务器域管理", [17, 18, 19]),
    ("阶段考核", "阶段考核 3 · 进阶模块 B", [20]),
    ("安全模块", "项目 7 · Windows 服务器安全管理", [21, 22]),
]
MOD_COLOR = {"基础模块": "var(--accent)", "进阶模块": "var(--green)", "阶段考核": "var(--red)", "安全模块": "#e88a3a"}

# 考核课次不发课件(内容=现场挑战赛), 只在目录里占位展示, 不链接到任何 lessonNN.html
EXAM_META = {
    8:  ("阶段考核 1 · 基础模块挑战赛", "现场限时挑战赛，配合 arena 线上比赛系统进行，不提供可下载课件"),
    13: ("阶段考核 2 · 网站管理挑战赛", "现场限时挑战赛，配合 arena 线上比赛系统进行，不提供可下载课件"),
    20: ("阶段考核 3 · 进阶模块B挑战赛", "现场限时挑战赛（覆盖远程管理·域用户与OU·组策略），配合 arena 线上比赛系统进行，不提供可下载课件"),
}


def text(s):
    return html.unescape(re.sub(r"<[^>]+>", "", s)).strip()


def lesson_info(n):
    f = f"lesson{n:02d}.html"
    s = open(os.path.join(HERE, f), encoding="utf-8").read()
    title = text(re.search(r"<title>(.*?)</title>", s).group(1))
    title = re.sub(r"^第\s*\d+\s*课\s*·\s*", "", title)
    cover = re.search(r'<section class="cover">(.*?)</section>', s, re.S)
    sub = ""
    if cover:
        ps = [text(p) for p in re.findall(r'<p class="muted">(.*?)</p>', cover.group(1), re.S)]
        if len(ps) >= 2:
            sub = ps[1]
    hours = re.search(r"学时\s*(\d+)\s*[–-]\s*(\d+)", s)
    return dict(
        n=n, file=f, title=title, sub=sub,
        hours=f"{hours.group(1)}–{hours.group(2)}" if hours else f"{2*n-1}–{2*n}",
        pages=len(re.findall(r"<section", s)),
        pops=len(set(re.findall(r'data-pop="([^"]+)"', s))),
        check=os.path.exists(os.path.join(DOWNLOADS, f"check{n:02d}.ps1")),
    )


def main():
    rows, total_pages, n_pop, n_chk = [], 0, 0, 0
    last_mod = None
    for mod, proj, lessons in GROUPS:
        is_exam = mod == "阶段考核"
        color = MOD_COLOR[mod]
        if not is_exam and mod != last_mod:
            rows.append(f'<div class="mod" style="--c:{color}">{mod}</div>')
            last_mod = mod
        items = []
        for n in lessons:
            if n in EXAM_META:
                title, sub = EXAM_META[n]
                hours = f"{2*n-1}–{2*n}"
                items.append(f'''
      <div class="lesson exam locked">
        <span class="no">{n:02d}</span>
        <span class="main"><span class="t">{html.escape(title)}</span><span class="s">{html.escape(sub)}</span></span>
        <span class="side"><span class="h">学时 {hours}</span><span class="bs"><span class="ix-b ix-lock" title="现场考核，不发课件">🔒 现场考核</span></span></span>
      </div>''')
                continue
            i = lesson_info(n)
            total_pages += i["pages"]
            badges = []
            if i["pops"]:
                n_pop += 1
                badges.append(f'<span class="ix-b ix-pop" title="任务页有详细步骤弹窗">📋 弹窗 {i["pops"]}</span>')
            if i["check"]:
                n_chk += 1
                badges.append(f'<span class="ix-b ix-chk" title="downloads/check{n:02d}.ps1">🧪 check{n:02d}</span>')
            items.append(f'''
      <a class="lesson" href="{i["file"]}">
        <span class="no">{n:02d}</span>
        <span class="main"><span class="t">{html.escape(i["title"])}</span><span class="s">{html.escape(i["sub"])}</span></span>
        <span class="side"><span class="h">学时 {i["hours"]} · {i["pages"]} 页</span><span class="bs">{"".join(badges)}</span></span>
      </a>''')
        rows.append(f'''
    <section class="grp{' examgrp' if is_exam else ''}" style="--c:{color}">
      <h2>{html.escape(proj)}<span class="cnt">{f"第 {lessons[0]}–{lessons[-1]} 次课" if len(lessons) > 1 else f"第 {lessons[0]} 次课"}</span></h2>
      {"".join(items)}
    </section>''')

    page = f'''<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>课程目录 · Windows 服务器配置与安全管理</title>
<link rel="stylesheet" href="assets/course.css">
<style>
 html,body{{margin:0;background:var(--bg);color:var(--text);font-family:var(--sans)}}
 .wrap{{max-width:1180px;margin:0 auto;padding:48px 40px 64px}}
 header .bar{{width:120px;height:6px;border-radius:3px;background:var(--accent);margin-bottom:22px}}
 header h1{{font-size:44px;margin:0 0 10px}}
 header p{{color:var(--muted);font-size:19px;margin:0}}
 .stats{{display:flex;gap:12px;flex-wrap:wrap;margin:22px 0 8px}}
 .stats span{{background:var(--surface2);border-radius:999px;padding:6px 16px;font-size:16px;color:var(--muted)}}
 .stats b{{color:var(--text)}}
 .legend{{color:var(--muted);font-size:15px;margin:6px 0 0}}
 .mod{{margin:40px 0 4px;font-size:15px;font-weight:700;letter-spacing:.2em;color:var(--c)}}
 .grp{{margin:14px 0 0;border-left:4px solid var(--c);background:var(--surface);border-radius:0 12px 12px 0;padding:14px 18px 10px}}
 .grp h2{{font-size:21px;margin:0 0 8px;display:flex;align-items:baseline;gap:14px}}
 .grp h2 .cnt{{font-size:14px;color:var(--muted);font-weight:400}}
 .examgrp{{background:linear-gradient(90deg,rgba(255,86,48,.12),var(--surface) 60%)}}
 a.lesson{{display:flex;align-items:center;gap:18px;padding:10px 12px;border-radius:10px;color:inherit;text-decoration:none;border-top:1px solid var(--line)}}
 a.lesson:first-of-type{{border-top:none}}
 a.lesson:hover{{background:var(--surface2)}}
 .no{{font-family:var(--mono);font-size:26px;font-weight:700;color:var(--c);width:46px;flex:none}}
 .main{{flex:1;min-width:0;display:flex;flex-direction:column;gap:3px}}
 .main .t{{font-size:20px;font-weight:700}}
 .main .s{{font-size:15px;color:var(--muted);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}}
 .side{{flex:none;display:flex;flex-direction:column;align-items:flex-end;gap:5px}}
 .side .h{{font-size:13px;color:var(--muted)}}
 .bs{{display:flex;gap:6px}}
 .ix-b{{font-size:12px;padding:2px 9px;border-radius:999px;background:var(--surface2);white-space:nowrap}}
 .ix-pop{{color:var(--accent)}} .ix-chk{{color:var(--green)}} .ix-lock{{color:var(--red)}}
 .lesson.locked{{display:flex;align-items:center;gap:18px;padding:10px 12px;border-radius:10px;border-top:1px solid var(--line);opacity:.72;cursor:default}}
 .lesson.locked:first-of-type{{border-top:none}}
 footer{{margin-top:40px;color:var(--muted);font-size:14px;border-top:1px solid var(--line);padding-top:14px}}
 @media print{{
   html,body{{background:#fff;color:#111}} .wrap{{padding:10mm 8mm}}
   .grp{{background:#f5f7fa;break-inside:avoid}} a.lesson{{border-color:#dde3ea}}
   .main .s,.side .h,header p,.stats span,.legend,footer{{color:#555}} .stats span,.ix-b{{background:#eef2f7}}
 }}
</style>
</head>
<body>
<div class="wrap">
  <header>
    <div class="bar"></div>
    <h1>Windows 服务器配置与安全管理</h1>
    <p>Windows Server 2022 · 红蓝对抗防御　|　已上完 第 1–22 次课（阶段考核不提供课件，持续更新中）</p>
    <div class="stats">
      <span><b>{total_pages}</b> 页幻灯片</span><span><b>{n_pop}</b> 课有详细步骤弹窗</span><span><b>{n_chk}</b> 课有检查脚本</span>
    </div>
    <p class="legend">点击课次打开课件（← → 翻页，S 打开讲者备注）。📋 = 任务页有「详细步骤 / 每项为什么」弹窗；🧪 = 配套检查脚本，课件最后一页可下载。后续课次会随教学进度持续更新。</p>
  </header>
  {"".join(rows)}
  <footer>本页由 make_index.py 根据各课件自动生成；仅包含已完成教学的课次。</footer>
</div>
</body>
</html>
'''
    open(os.path.join(HERE, "index.html"), "w", encoding="utf-8").write(page)
    print(f"index.html: {sum(len(l) for _,_,l in GROUPS)} 课, {total_pages} 页, 弹窗 {n_pop} 课, 检查脚本 {n_chk} 课")


if __name__ == "__main__":
    main()
