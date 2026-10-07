# Builds the GitHub wiki pages for stream-rooms and flavr-leftovers from the Markdown docs in both
# repositories, with links between them rewired to wiki page names and the manual screenshots copied.
#   python tools\build_wikis.py <work folder>
# The pages land in <work folder>\built\<repo>.wiki; copy them into a clone of
# https://github.com/sensokasucks/<repo>.wiki.git, commit and push (the wiki is a git repo).

import os, re, shutil, sys, glob
W = sys.argv[1]
def page_name(title): return re.sub(r'[^A-Za-z0-9]+', '-', title).strip('-')
def build(name, repo, root, pages, sidebar_title):
    out = os.path.join(W, "built", name); shutil.rmtree(out, ignore_errors=True); os.makedirs(out)
    srcmap = {os.path.normpath(src): page for page, src, *_ in pages}
    for page, src, *imgs in pages:
        text = open(os.path.join(root, src), encoding='utf-8', errors='replace').read()
        srcdir = os.path.dirname(src)
        def fix(m):
            label, target = m.group(1), m.group(2)
            if target.startswith(('http://', 'https://', '#', 'mailto:')): return m.group(0)
            path, _, anchor = target.partition('#')
            norm = os.path.normpath(os.path.join(srcdir, path)) if path else None
            if norm in srcmap: return f'[{label}]({srcmap[norm]}{"#"+anchor if anchor else ""})'
            if path and re.search(r'\.(png|jpg|jpeg|gif|webp)$', path, re.I): return f'[{label}](images/{os.path.basename(path)})'
            return f'[{label}](https://github.com/sensokasucks/{repo}/blob/HEAD/{norm.replace(os.sep, "/") if norm else ""}{"#"+anchor if anchor else ""})'
        text = re.sub(r'\[([^\]]*)\]\(([^)\s]+)\)', fix, text)
        text = re.sub(r'!\[([^\]]*)\]\(https://github\.com/[^)]*/blob/HEAD/[^)]*?/([^/)]+\.(?:png|jpg|jpeg|gif|webp))\)', r'![\1](images/\2)', text, flags=re.I)
        open(os.path.join(out, page + '.md'), 'w', encoding='utf-8', newline='\n').write(text)
        for d in imgs:
            os.makedirs(os.path.join(out, 'images'), exist_ok=True)
            for f in glob.glob(os.path.join(root, d, '*')):
                if os.path.isfile(f): shutil.copy(f, os.path.join(out, 'images', os.path.basename(f)))
    side = f"**{sidebar_title}**\n\n" + "\n".join(f"- [[{p.replace('-', ' ')}|{p}]]" for p, *_ in pages)
    open(os.path.join(out, '_Sidebar.md'), 'w', encoding='utf-8', newline='\n').write(side + "\n")
sr = "C:/Users/jonza/Documents/RedotHomeTheater/stream_rooms"
build("stream-rooms.wiki", "stream-rooms", sr, [("Home", "README.md"), ("Manual", "docs/manual/MANUAL.md", "docs/manual/images"),
    ("Room-Building-Guide", "docs/manual/ROOM_GUIDE.md"), ("Multiplayer-Notes", "docs/MULTIPLAYER.md"), ("Notes-for-Claude-Code", "CLAUDE.md")], "Stream Rooms")
fl = "G:/AI/claude/FlaVR_leftovers"
pages = [("Home", "README.md"), ("Stream-Core-Manual", "fridge-stream-core/docs/manual/MANUAL.md", "fridge-stream-core/docs/manual/images"),
         ("Release-Notes", "RELEASE_NOTES.md"), ("Git-Helpers", "GIT.md"), ("Stream-Core", "fridge-stream-core/README.md"),
         ("Stream-Core-Scripts", "fridge-stream-core/SCRIPTS.md"), ("Stream-Core-Changelog", "fridge-stream-core/CHANGELOG.md")]
for f in sorted(glob.glob(os.path.join(fl, "fridge-stream-core/docs/**/*.md"), recursive=True)):
    pages.append(("Stream-Core-" + page_name(os.path.splitext(os.path.basename(f))[0].replace('_', ' ').title()), os.path.relpath(f, fl).replace(os.sep, '/')))
for app in ["fridge-chat-credits", "fridge-minecraft", "fridge-factorio-stats", "fridge-granvir-stats", "fridge-reactive-image", "fridge-reactive-image-legacy"]:
    if os.path.exists(os.path.join(fl, app, "README.md")): pages.append((page_name(app.replace("fridge-", "").replace("-", " ").title()), f"{app}/README.md"))
for f in sorted(glob.glob(os.path.join(fl, "checklists/*.md"))):
    base = os.path.splitext(os.path.basename(f))[0]
    pages.append(("Checklists" if base in ("INDEX", "README") else "Checklist-" + page_name(base.replace('_', ' ').title()), f"checklists/{base}.md"))
seen = set(); pages = [p for p in pages if not (p[0] in seen or seen.add(p[0]))]
build("flavr-leftovers.wiki", "flavr-leftovers", fl, pages, "FlaVR Leftovers")
print("built")
