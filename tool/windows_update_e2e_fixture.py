import base64
import datetime
import hashlib
import json
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

root = (Path.cwd() / 'build' / 'windows-update-e2e' / 'profile').resolve()
if (root / 'preferences.json').exists():
    raise SystemExit('An integration profile already exists. Use a fresh test workspace; no files were changed.')
web = root / 'web'
web.mkdir(parents=True, exist_ok=True)
database = root / 'custom-database'
now = datetime.datetime.now()
date = now.strftime('%Y-%m-%d')
png = base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=')
image_path = f'days/{now.year}_image/{now.month:02}/{date}_Image01.png'
image = database / image_path
image.parent.mkdir(parents=True, exist_ok=True)
image.write_bytes(png)
day = database / 'days' / str(now.year) / f'{now.month:02}' / f'{date}.json'
day.parent.mkdir(parents=True, exist_ok=True)
day.write_text(json.dumps(dict(schemaVersion=1, date=date, entries=[dict(
    id='retained-entry', content='真实升级测试：已有数据库记录', createdAt=now.isoformat(), updatedAt=now.isoformat(), tagIds=[], completed=True,
    images=[dict(path=image_path, width=1, height=1, byteLength=len(png), sha256=hashlib.sha256(png).hexdigest(), mimeType='image/png')]
)]), ensure_ascii=False), encoding='utf-8')
preferences = dict(database_path=str(database), theme_preference='dark', font_scale='1.15', view_scale='0.9')
(root / 'preferences.json').write_text(json.dumps(preferences), encoding='utf-8')
draft = dict(markdown='**升级前未发送的草稿**\n\n第二段，中文与空行必须保留。', plannedDate=None, images=[dict(png=base64.b64encode(png).decode(), width=1, height=1)])
(root / 'pending-update-draft.json').write_text(json.dumps(draft, ensure_ascii=False), encoding='utf-8')
archive = web / 'update.zip'
archive_bytes = archive.read_bytes()
release = dict(tag_name='v0.1.0-preview.11', draft=False, prerelease=True, body='本机隔离的真实升级测试包，不连接 GitHub。', assets=[dict(
    name='PromptBox-preview-windows-x64.zip', state='uploaded', size=len(archive_bytes), digest='sha256:' + hashlib.sha256(archive_bytes).hexdigest(),
    browser_download_url='https://github.com/PraxisUnterwegs/PromptBox/releases/download/v0.1.0-preview.11/PromptBox-preview-windows-x64.zip'
)])
(web / 'releases.json').write_text(json.dumps([release]), encoding='utf-8')
before = dict(preferences=preferences, draft=draft, database={str(file.relative_to(database)): hashlib.sha256(file.read_bytes()).hexdigest() for file in database.rglob('*') if file.is_file()})
(root / 'before.json').write_text(json.dumps(before, ensure_ascii=False, indent=2), encoding='utf-8')

class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(web), **kwargs)

server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
(root / 'feed-port.txt').write_text(str(server.server_port), encoding='utf-8')
server.serve_forever()
