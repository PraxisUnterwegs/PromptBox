#!/bin/sh
set -eu
app_pid=$1
archive=$2
target=$3
work=$4
exec >> "$work/install.log" 2>&1
mount="$work/mount"
stage="$target.update-$(basename "$work")"
backup="$target.previous-$(basename "$work")"
moved=0
cleanup() {
  result=$?
  /usr/bin/hdiutil detach "$mount" -quiet || true
  if [ "$result" -ne 0 ]; then
    if [ "$moved" -eq 1 ] && [ ! -e "$target" ]; then /bin/mv "$backup" "$target" || true; fi
    /usr/bin/osascript -e 'display alert "PromptBox 更新失败" message "旧版本已保留。请查看更新临时目录中的 install.log；也可从 GitHub 下载并手动安装。"' || true
  fi
}
trap cleanup EXIT
test -d "$target/Contents/MacOS"
test ! -e "$stage"
test ! -e "$backup"
/bin/mkdir "$mount"
/usr/bin/hdiutil attach "$archive" -mountpoint "$mount" -nobrowse -readonly
test -d "$mount/PromptBox.app/Contents/MacOS"
/usr/bin/codesign --verify --deep --strict "$mount/PromptBox.app"
# Stage next to the installed app to verify write permission before moving it.
/usr/bin/ditto "$mount/PromptBox.app" "$stage"
while /bin/kill -0 "$app_pid" 2>/dev/null; do /bin/sleep 1; done
/bin/mv "$target" "$backup"
moved=1
if /bin/mv "$stage" "$target"; then
  /usr/bin/open "$target"
else
  /bin/mv "$backup" "$target"
  moved=0
  exit 1
fi
echo "Updated. Previous version retained at $backup"
